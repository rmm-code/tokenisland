import Foundation

/// Watches Gemini CLI per-project session artifacts under
/// `~/.gemini/tmp/<project-hash>/` and turns changes into normalized
/// `SessionEvent`s. Two sources feed the same store:
///
/// - `chats/*.json` — full session recordings (user + model + tool calls),
///   the primary source when the CLI writes them.
/// - `logs.json` — prompt-only history, a fallback for sessions with no
///   recording (older CLIs). Sessions covered by a recording are suppressed.
///
/// Unlike Codex rollouts these are whole-JSON documents rewritten in place,
/// so instead of byte offsets we keep a per-file message watermark and only
/// re-parse when the size/mtime fingerprint changes. State lives on the main
/// actor; file IO runs off it. Gemini has no hook mechanism here — this is
/// the same 2s poll posture as `CodexSessionWatcher`.
@MainActor
final class GeminiSessionWatcher {
    typealias EventHandler = @Sendable (SessionEvent) -> Void

    /// Cards fall back to this project path when the CLI gives us none
    /// (Gemini keys project dirs by sha256(cwd), which is not reversible),
    /// so they read "gemini · <title>".
    static let fallbackProjectPath = "gemini"

    private struct Fingerprint: Equatable, Sendable {
        var size: UInt64
        var modified: Date
    }

    private struct ChatFileState {
        var sessionID: String
        var cwd: String?
        var model: String?
        var announced = false
        /// Messages fully consumed; the message at this index (if present)
        /// is the trailing, still-mutating one.
        var consumedMessages = 0
        var trailingToolCallsEmitted = 0
        var trailingAnswerEmitted = false
        /// Commentary from an intermediate model message, promoted to the
        /// turn's answer if the turn ends without a better one.
        var pendingModelText: String?
    }

    private struct LogsFileState {
        var consumedEntries = 0
    }

    private struct ChatBatch: Sendable {
        var path: String
        var fileStem: String
        var isFirstSight: Bool
        var modified: Date
        var fingerprint: Fingerprint
        var record: GeminiSessionRecord
    }

    private struct LogsBatch: Sendable {
        var path: String
        var isFirstSight: Bool
        var modified: Date
        var fingerprint: Fingerprint
        var entries: [GeminiPromptEntry]
    }

    private struct ScanResult: Sendable {
        var chats: [ChatBatch] = []
        var logs: [LogsBatch] = []
    }

    private let rootDirectory: URL
    private let pollInterval: TimeInterval
    /// Only files modified inside this window are tracked at all.
    private let recencyWindow: TimeInterval = 48 * 3600
    /// A first-seen file whose newest activity is older than this is tracked
    /// silently — stale history shouldn't surface a session.
    private let catchUpMaxAge: TimeInterval = 7200
    private let onEvent: EventHandler

    private var fingerprints: [String: Fingerprint] = [:]
    private var chatStates: [String: ChatFileState] = [:]
    private var logsStates: [String: LogsFileState] = [:]
    /// Raw session IDs seen in chat recordings — suppresses the logs.json
    /// fallback for sessions that have the richer stream.
    private var chatCoveredSessionIDs: Set<String> = []
    private var announcedLogSessionIDs: Set<String> = []
    private var pollTask: Task<Void, Never>?

    init(
        rootDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gemini/tmp", isDirectory: true),
        pollInterval: TimeInterval = 2,
        onEvent: @escaping EventHandler
    ) {
        self.rootDirectory = rootDirectory
        self.pollInterval = pollInterval
        self.onEvent = onEvent
    }

    deinit {
        pollTask?.cancel()
    }

    var isRunning: Bool { pollTask != nil }

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.pollOnce()
                try? await Task.sleep(for: .seconds(self.pollInterval))
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// One scan pass; exposed for tests (the timer loop just calls this).
    func pollOnce() async {
        let result = await Self.collectBatches(
            root: rootDirectory,
            fingerprints: fingerprints,
            recencyWindow: recencyWindow
        )
        // Recordings first so their session IDs suppress logs.json fallback
        // entries arriving in the same pass.
        for batch in result.chats {
            applyChat(batch)
        }
        for batch in result.logs {
            applyLogs(batch)
        }
    }

    // MARK: - Chat recordings (main actor)

    private func applyChat(_ batch: ChatBatch) {
        fingerprints[batch.path] = batch.fingerprint
        if let rawID = batch.record.sessionID, !rawID.isEmpty {
            chatCoveredSessionIDs.insert(rawID)
        }

        var state = chatStates[batch.path]
            ?? ChatFileState(sessionID: "gemini-" + (batch.record.sessionID ?? batch.fileStem))
        // Never rename a session the store already knows about.
        if !state.announced, let rawID = batch.record.sessionID, !rawID.isEmpty {
            state.sessionID = "gemini-" + rawID
        }
        if let cwd = batch.record.cwd, !cwd.isEmpty {
            state.cwd = cwd
        }
        let messages = batch.record.messages
        if state.consumedMessages > messages.count {
            state.consumedMessages = messages.count // file replaced/truncated
        }

        if batch.isFirstSight {
            let newest = batch.record.lastUpdated
                ?? messages.last?.timestamp
                ?? batch.modified
            if Date().timeIntervalSince(newest) > catchUpMaxAge {
                state.model = messages.compactMap(\.model).last ?? state.model
                state.consumedMessages = messages.count // track silently
            } else {
                emitCatchUp(&state, messages: messages)
            }
        } else {
            processIncrementally(&state, messages: messages)
        }
        chatStates[batch.path] = state
    }

    /// A first-seen recording is history, not a live stream: replaying every
    /// turn would fire a completion reveal per message. Keep the identity,
    /// the last prompt, and the last turn state.
    private func emitCatchUp(_ state: inout ChatFileState, messages: [GeminiMessage]) {
        guard !messages.isEmpty else { return }
        state.model = messages.compactMap(\.model).last ?? state.model
        announceIfNeeded(&state, timestamp: messages.first?.timestamp)
        if let lastUser = messages.last(where: { $0.role == .user }),
           let text = lastUser.text, !text.isEmpty {
            send(.userPrompt(prompt: text), state: state, timestamp: lastUser.timestamp)
        }
        state.consumedMessages = messages.count
        guard let last = messages.last, last.role == .model else { return }

        // The trailing model message stays partial so later mutation
        // (tool completion, final answer) can still end the turn.
        state.consumedMessages = messages.count - 1
        state.trailingToolCallsEmitted = last.toolCalls.count
        let hasOpenTools = last.toolCalls.contains { !$0.isTerminal }
        if !hasOpenTools, let text = last.text, !text.isEmpty {
            send(.stop(lastAssistantMessage: text), state: state, timestamp: last.timestamp)
            state.trailingAnswerEmitted = true
        } else {
            send(
                .preTool(toolName: "Gemini", detail: "working…", toolUseID: nil, subagentLabel: nil),
                state: state,
                timestamp: last.timestamp
            )
            state.trailingAnswerEmitted = false
        }
    }

    private func processIncrementally(_ state: inout ChatFileState, messages: [GeminiMessage]) {
        let partialIndex = state.consumedMessages
        var index = state.consumedMessages
        while index < messages.count {
            let message = messages[index]
            if let model = message.model, !model.isEmpty {
                state.model = model
            }
            let isPartialRevisit = index == partialIndex
            let toolsEmitted = isPartialRevisit ? state.trailingToolCallsEmitted : 0
            var answerEmitted = isPartialRevisit ? state.trailingAnswerEmitted : false
            let isLast = index == messages.count - 1

            switch message.role {
            case .user:
                announceIfNeeded(&state, timestamp: message.timestamp)
                if let text = message.text, !text.isEmpty {
                    send(.userPrompt(prompt: text), state: state, timestamp: message.timestamp)
                }
                state.pendingModelText = nil

            case .model:
                announceIfNeeded(&state, timestamp: message.timestamp)
                for call in message.toolCalls.dropFirst(toolsEmitted) {
                    send(
                        .preTool(toolName: call.name, detail: call.detail, toolUseID: nil, subagentLabel: nil),
                        state: state,
                        timestamp: message.timestamp
                    )
                }
                if isLast {
                    let hasOpenTools = message.toolCalls.contains { !$0.isTerminal }
                    if !answerEmitted, !hasOpenTools, let text = message.text, !text.isEmpty {
                        send(.stop(lastAssistantMessage: text), state: state, timestamp: message.timestamp)
                        state.pendingModelText = nil
                        answerEmitted = true
                    }
                    // Stay partial: content/tool calls may still be appended.
                    state.consumedMessages = index
                    state.trailingToolCallsEmitted = message.toolCalls.count
                    state.trailingAnswerEmitted = answerEmitted
                    return
                }
                // A model message not followed by another model message ends
                // its turn; between model messages, text is commentary.
                if messages[index + 1].role == .model {
                    if let text = message.text, !text.isEmpty {
                        state.pendingModelText = text
                    }
                } else if !answerEmitted {
                    let text = message.text.flatMap { $0.isEmpty ? nil : $0 } ?? state.pendingModelText
                    send(.stop(lastAssistantMessage: text), state: state, timestamp: message.timestamp)
                    state.pendingModelText = nil
                } else {
                    state.pendingModelText = nil
                }

            case .other:
                break
            }

            index += 1
            state.consumedMessages = index
            state.trailingToolCallsEmitted = 0
            state.trailingAnswerEmitted = false
        }
    }

    // MARK: - logs.json fallback (main actor)

    private func applyLogs(_ batch: LogsBatch) {
        fingerprints[batch.path] = batch.fingerprint
        var state = logsStates[batch.path] ?? LogsFileState()
        let entries = batch.entries
        defer {
            state.consumedEntries = entries.count
            logsStates[batch.path] = state
        }

        if batch.isFirstSight {
            // Coalesce history to the most recent prompt, if it's fresh.
            guard let last = entries.last else { return }
            let newest = last.timestamp ?? batch.modified
            guard Date().timeIntervalSince(newest) <= catchUpMaxAge else { return }
            emitLogEntry(last)
            return
        }
        let start = min(state.consumedEntries, entries.count)
        for entry in entries[start...] {
            emitLogEntry(entry)
        }
    }

    private func emitLogEntry(_ entry: GeminiPromptEntry) {
        guard !chatCoveredSessionIDs.contains(entry.sessionID) else { return }
        let sessionID = "gemini-" + entry.sessionID
        if !announcedLogSessionIDs.contains(entry.sessionID) {
            announcedLogSessionIDs.insert(entry.sessionID)
            sendRaw(
                .sessionStart(source: "gemini"),
                sessionID: sessionID,
                cwd: nil,
                model: nil,
                timestamp: entry.timestamp
            )
        }
        sendRaw(
            .userPrompt(prompt: entry.text),
            sessionID: sessionID,
            cwd: nil,
            model: nil,
            timestamp: entry.timestamp
        )
    }

    // MARK: - Emit helpers

    private func announceIfNeeded(_ state: inout ChatFileState, timestamp: Date?) {
        guard !state.announced else { return }
        state.announced = true
        send(.sessionStart(source: "gemini"), state: state, timestamp: timestamp)
    }

    private func send(_ kind: SessionEventKind, state: ChatFileState, timestamp: Date?) {
        sendRaw(kind, sessionID: state.sessionID, cwd: state.cwd, model: state.model, timestamp: timestamp)
    }

    private func sendRaw(
        _ kind: SessionEventKind,
        sessionID: String,
        cwd: String?,
        model: String?,
        timestamp: Date?
    ) {
        let context = SessionEventContext(
            sessionID: sessionID,
            agent: .gemini,
            cwd: cwd ?? Self.fallbackProjectPath,
            model: model,
            timestamp: timestamp ?? Date()
        )
        onEvent(SessionEvent(context: context, kind: kind))
    }

    // MARK: - File IO (off main: nonisolated async runs on the global executor)

    private nonisolated static func collectBatches(
        root: URL,
        fingerprints: [String: Fingerprint],
        recencyWindow: TimeInterval
    ) async -> ScanResult {
        // Hop through a synchronous helper: directory enumeration is
        // unavailable in async contexts, and this async frame already runs
        // on the global executor, keeping the IO off the main actor.
        collectBatchesSync(root: root, fingerprints: fingerprints, recencyWindow: recencyWindow)
    }

    private nonisolated static func collectBatchesSync(
        root: URL,
        fingerprints: [String: Fingerprint],
        recencyWindow: TimeInterval
    ) -> ScanResult {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return ScanResult() }

        let cutoff = Date().addingTimeInterval(-recencyWindow)
        var result = ScanResult()
        for case let url as URL in enumerator where url.pathExtension == "json" {
            let isLogs = url.lastPathComponent == "logs.json"
            let isChat = !isLogs && url.deletingLastPathComponent().lastPathComponent == "chats"
            guard isLogs || isChat else { continue }

            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            guard let modified = values?.contentModificationDate, modified >= cutoff else { continue }
            let fingerprint = Fingerprint(size: UInt64(values?.fileSize ?? 0), modified: modified)
            let path = url.path
            let known = fingerprints[path]
            guard known != fingerprint else { continue }
            // Mid-write documents fail to parse; the unchanged fingerprint
            // makes the next poll retry them.
            guard let data = try? Data(contentsOf: url), !data.isEmpty else { continue }

            if isLogs {
                result.logs.append(LogsBatch(
                    path: path,
                    isFirstSight: known == nil,
                    modified: modified,
                    fingerprint: fingerprint,
                    entries: GeminiLogParser.promptEntries(fromLogsData: data)
                ))
            } else if let record = GeminiLogParser.sessionRecord(fromChatData: data) {
                result.chats.append(ChatBatch(
                    path: path,
                    fileStem: url.deletingPathExtension().lastPathComponent,
                    isFirstSight: known == nil,
                    modified: modified,
                    fingerprint: fingerprint,
                    record: record
                ))
            }
        }
        return result
    }
}
