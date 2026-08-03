import Foundation

/// Tails Codex CLI rollout files (`~/.codex/sessions/**/rollout-*.jsonl`)
/// and turns appended lines into normalized `SessionEvent`s. Codex has no
/// hook mechanism, so this is a 2s poll: per file we keep a byte offset and
/// only read new data. State lives on the main actor; file IO runs off it.
@MainActor
final class CodexSessionWatcher {
    typealias EventHandler = @Sendable (SessionEvent) -> Void

    private struct FileState {
        var offset: UInt64
        var sessionID: String
        var cwd: String?
        var model: String? = nil
        var announced = false
        /// Between task_started and task_complete: agent messages are
        /// commentary, not the turn's final answer.
        var inTask = false
        var pendingAgentMessage: String?
        /// Set when this rollout is a subagent thread rather than a
        /// conversation: it becomes a row on its parent's card, not a card.
        var thread: CodexThreadInfo?
        var subagentAnnounced = false
    }

    /// Newly appended (complete) lines of one file, parsed off-main.
    private struct FileBatch: Sendable {
        var path: String
        var fileStem: String
        var isFirstSight: Bool
        var newOffset: UInt64
        var records: [CodexRolloutRecord]
    }

    private let sessionsDirectory: URL
    private let pollInterval: TimeInterval
    /// Only files modified inside this window are tracked at all.
    private let recencyWindow: TimeInterval = 48 * 3600
    /// A first-seen file whose newest line is older than this is tracked
    /// silently (offset only) — stale history shouldn't surface a session.
    private let catchUpMaxAge: TimeInterval = 7200
    /// Shorter ceiling for a rollout whose last turn already finished. Codex
    /// writes no exit record, so "completed, then quiet" is the only signal
    /// that a run is over — without this, replaying at launch resurrected
    /// finished runs as live cards for the full `catchUpMaxAge`, and the user
    /// saw Codex sessions on the notch with no Codex running.
    private let completedReplayMaxAge: TimeInterval = 300
    private let onEvent: EventHandler
    private var fileStates: [String: FileState] = [:]
    private var pollTask: Task<Void, Never>?

    init(
        sessionsDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions", isDirectory: true),
        pollInterval: TimeInterval = 2,
        onEvent: @escaping EventHandler
    ) {
        self.sessionsDirectory = sessionsDirectory
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
        let batches = await Self.collectBatches(
            directory: sessionsDirectory,
            knownOffsets: fileStates.mapValues(\.offset),
            recencyWindow: recencyWindow
        )
        for batch in batches {
            apply(batch)
        }
    }

    // MARK: - Event mapping (main actor)

    private func apply(_ batch: FileBatch) {
        var state = fileStates[batch.path]
            ?? FileState(offset: 0, sessionID: "codex-" + batch.fileStem)
        var records = batch.records

        if batch.isFirstSight {
            // Absorb identity even when the history is too stale to replay.
            // Only the FIRST meta is this file's own: a subagent rollout forks
            // its parent's transcript, so later metas are the parent's copies.
            var sawMeta = false
            for record in records {
                switch record.event {
                case .sessionMeta(let id, let cwd, let thread):
                    guard !sawMeta else { break }
                    sawMeta = true
                    if let id, !id.isEmpty { state.sessionID = "codex-" + id }
                    if let cwd, !cwd.isEmpty { state.cwd = cwd }
                    state.thread = thread
                case .turnContext(let cwd, let model):
                    if let cwd, !cwd.isEmpty { state.cwd = cwd }
                    if let model, !model.isEmpty { state.model = model }
                default:
                    break
                }
            }
            let age = records.compactMap(\.timestamp).max().map { Date().timeIntervalSince($0) }
            let isFinishedHistory = age.map {
                $0 > completedReplayMaxAge && Self.endsOnCompletedTurn(records)
            } ?? false
            if let age, age > catchUpMaxAge || isFinishedHistory {
                records = []
            } else {
                records = Self.coalesceCatchUp(records)
            }
        }

        // Machinery threads (Codex's guardian reviewers) are not sessions and
        // not subagent rows — without this each one became its own card
        // showing the guardian's internal assessment prompt.
        if state.thread?.isInternalWorker == true {
            state.offset = batch.newOffset
            fileStates[batch.path] = state
            return
        }

        if state.thread?.isSubagent == true {
            applySubagentThread(records, state: &state, fileStem: batch.fileStem)
            state.offset = batch.newOffset
            fileStates[batch.path] = state
            return
        }

        for record in records {
            emit(record, state: &state)
        }
        state.offset = batch.newOffset
        fileStates[batch.path] = state
    }

    /// A fan-out thread reports to its parent's card: one row when it starts,
    /// settled when its own task completes. Its turns stay out of the parent's
    /// activity — they are the subagent's work, not the main agent's.
    private func applySubagentThread(
        _ records: [CodexRolloutRecord],
        state: inout FileState,
        fileStem: String
    ) {
        guard let thread = state.thread, let parentID = thread.parentThreadID, !parentID.isEmpty else {
            return
        }
        let parentSessionID = "codex-" + parentID
        let rowID = state.sessionID.isEmpty ? fileStem : state.sessionID

        func send(_ kind: SessionEventKind, timestamp: Date?) {
            let context = SessionEventContext(
                sessionID: parentSessionID,
                agent: .codex,
                cwd: state.cwd,
                model: state.model,
                timestamp: timestamp ?? Date()
            )
            onEvent(SessionEvent(context: context, kind: kind))
        }

        if !state.subagentAnnounced {
            state.subagentAnnounced = true
            send(
                .preTool(
                    toolName: "Agent",
                    detail: nil,
                    toolUseID: rowID,
                    subagentLabel: thread.label ?? "Subagent"
                ),
                timestamp: records.compactMap(\.timestamp).first
            )
        }

        let label = thread.label ?? "Subagent"
        for record in records {
            switch record.event {
            case .taskComplete:
                send(.postTool(toolName: "Agent", toolUseID: rowID), timestamp: record.timestamp)

            case .taskStarted:
                // Re-announcing an existing row updates it in place.
                send(
                    .preTool(toolName: "Agent", detail: "working…", toolUseID: rowID, subagentLabel: label),
                    timestamp: record.timestamp
                )

            case .agentMessage(let text):
                send(
                    .preTool(
                        toolName: "Agent",
                        detail: SessionReducer.condense(text, limit: 44),
                        toolUseID: rowID,
                        subagentLabel: label
                    ),
                    timestamp: record.timestamp
                )

            default:
                break
            }
        }
    }

    /// A first-seen file is history, not a live stream: replaying every turn
    /// would fire a completion reveal per line. Keep only the identity, the
    /// last prompt, and enough state to reconstruct the latest turn.
    private static func coalesceCatchUp(_ records: [CodexRolloutRecord]) -> [CodexRolloutRecord] {
        var meta: CodexRolloutRecord?
        var turnContext: CodexRolloutRecord?
        var lastUser: CodexRolloutRecord?
        var taskStarted: CodexRolloutRecord?
        var agentMessage: CodexRolloutRecord?
        var taskComplete: CodexRolloutRecord?
        for record in records {
            switch record.event {
            case .sessionMeta:
                if meta == nil { meta = record }
            case .turnContext:
                turnContext = record
            case .userMessage:
                lastUser = record
                taskStarted = nil
                agentMessage = nil
                taskComplete = nil
            case .taskStarted:
                taskStarted = record
                agentMessage = nil
                taskComplete = nil
            case .agentMessage:
                agentMessage = record
            case .taskComplete:
                taskComplete = record
            case .tokenCount:
                break
            }
        }

        let turnState: [CodexRolloutRecord]
        if let taskComplete {
            turnState = [taskComplete]
        } else if let taskStarted {
            turnState = [taskStarted, agentMessage].compactMap { $0 }
        } else {
            turnState = [agentMessage].compactMap { $0 }
        }
        return [meta, turnContext, lastUser].compactMap { $0 } + turnState
    }

    private func emit(_ record: CodexRolloutRecord, state: inout FileState) {
        switch record.event {
        case .sessionMeta(let id, let cwd, let thread):
            // Never rename a session the store already knows about.
            if !state.announced, let id, !id.isEmpty { state.sessionID = "codex-" + id }
            if let cwd, !cwd.isEmpty { state.cwd = cwd }
            if state.thread == nil { state.thread = thread }
            announceIfNeeded(&state, timestamp: record.timestamp)

        case .turnContext(let cwd, let model):
            if let cwd, !cwd.isEmpty { state.cwd = cwd }
            if let model, !model.isEmpty { state.model = model }
            announceIfNeeded(&state, timestamp: record.timestamp)

        case .userMessage(let text):
            announceIfNeeded(&state, timestamp: record.timestamp)
            send(.userPrompt(prompt: text), state: state, timestamp: record.timestamp)

        case .taskStarted:
            announceIfNeeded(&state, timestamp: record.timestamp)
            state.inTask = true
            send(
                .preTool(toolName: "Codex", detail: "working…", toolUseID: nil, subagentLabel: nil),
                state: state,
                timestamp: record.timestamp
            )

        case .agentMessage(let text):
            announceIfNeeded(&state, timestamp: record.timestamp)
            if state.inTask {
                state.pendingAgentMessage = text
            } else {
                // No task framing (older CLIs): an agent message ends the turn.
                send(.stop(lastAssistantMessage: text), state: state, timestamp: record.timestamp)
            }

        case .taskComplete(let lastAgentMessage):
            announceIfNeeded(&state, timestamp: record.timestamp)
            let message = lastAgentMessage ?? state.pendingAgentMessage
            state.inTask = false
            state.pendingAgentMessage = nil
            send(.stop(lastAssistantMessage: message), state: state, timestamp: record.timestamp)

        case .tokenCount:
            break // Usage heartbeat; session state is driven by task/message events.
        }
    }

    /// True when the rollout's last turn-lifecycle record is a completion, so
    /// nothing was in flight when writing stopped. `tokenCount` and message
    /// records are ignored: a completed turn still trails a usage heartbeat.
    nonisolated static func endsOnCompletedTurn(_ records: [CodexRolloutRecord]) -> Bool {
        for record in records.reversed() {
            switch record.event {
            case .taskComplete: return true
            case .taskStarted, .userMessage: return false
            default: continue
            }
        }
        return false
    }

    private func announceIfNeeded(_ state: inout FileState, timestamp: Date?) {
        guard !state.announced else { return }
        state.announced = true
        send(.sessionStart(source: "codex"), state: state, timestamp: timestamp)
    }

    private func send(_ kind: SessionEventKind, state: FileState, timestamp: Date?) {
        let context = SessionEventContext(
            sessionID: state.sessionID,
            agent: .codex,
            cwd: state.cwd,
            model: state.model,
            timestamp: timestamp ?? Date()
        )
        onEvent(SessionEvent(context: context, kind: kind))
    }

    // MARK: - File IO (off main: nonisolated async runs on the global executor)

    private nonisolated static func collectBatches(
        directory: URL,
        knownOffsets: [String: UInt64],
        recencyWindow: TimeInterval
    ) async -> [FileBatch] {
        // Hop through a synchronous helper: directory enumeration is
        // unavailable in async contexts, and this async frame already runs
        // on the global executor, keeping the IO off the main actor.
        collectBatchesSync(
            directory: directory,
            knownOffsets: knownOffsets,
            recencyWindow: recencyWindow
        )
    }

    private nonisolated static func collectBatchesSync(
        directory: URL,
        knownOffsets: [String: UInt64],
        recencyWindow: TimeInterval
    ) -> [FileBatch] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let cutoff = Date().addingTimeInterval(-recencyWindow)
        var batches: [FileBatch] = []
        for case let url as URL in enumerator
        where url.pathExtension == "jsonl" && url.lastPathComponent.hasPrefix("rollout-") {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            guard let modified = values?.contentModificationDate, modified >= cutoff else { continue }

            let path = url.path
            let size = UInt64(values?.fileSize ?? 0)
            let isFirstSight = knownOffsets[path] == nil
            var offset = knownOffsets[path] ?? 0
            if size < offset { offset = 0 } // truncated/rewritten — start over
            guard size > offset else { continue }
            if let batch = readBatch(url: url, path: path, isFirstSight: isFirstSight, from: offset) {
                batches.append(batch)
            }
        }
        return batches
    }

    private nonisolated static func readBatch(
        url: URL,
        path: String,
        isFirstSight: Bool,
        from offset: UInt64
    ) -> FileBatch? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard (try? handle.seek(toOffset: offset)) != nil,
              let data = try? handle.readToEnd(), !data.isEmpty
        else { return nil }

        // Hold back a trailing partial line until its newline lands.
        guard let lastNewline = data.lastIndex(of: UInt8(ascii: "\n")) else { return nil }
        let records = CodexRolloutParser.records(fromLines: data[data.startIndex..<lastNewline])
        return FileBatch(
            path: path,
            fileStem: url.deletingPathExtension().lastPathComponent,
            isFirstSight: isFirstSight,
            newOffset: offset + UInt64(lastNewline - data.startIndex + 1),
            records: records
        )
    }
}
