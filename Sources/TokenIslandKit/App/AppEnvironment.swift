import Foundation

@MainActor
final class AppEnvironment {
    /// Set by the executable before the environment is built (Sparkle lives
    /// there, so the library never links the framework).
    nonisolated(unsafe) static var updateInstaller: (() -> Void)?

    let appState: AppState
    let repository: UsageRepository
    let settingsStore: SettingsStore
    let telemetryCoordinator: TelemetryCoordinator
    let sessionStore: SessionStore
    let hookServer: HookServer
    let adapterRegistry: AdapterRegistry
    let titleMarkerService: TitleMarkerService
    let approvalCenter: ApprovalCenter
    let usageLimits: UsageLimitsService
    let updateChecker: UpdateChecker
    /// Single deterministic opener for settings/dashboard windows — SwiftUI's
    /// scene-based actions are unreliable for accessory apps.
    private(set) lazy var windowRouter = AppWindowRouter(appState: appState)
    let codexSessionWatcher: CodexSessionWatcher
    let geminiSessionWatcher: GeminiSessionWatcher

    private init(
        appState: AppState,
        repository: UsageRepository,
        settingsStore: SettingsStore,
        telemetryCoordinator: TelemetryCoordinator,
        sessionStore: SessionStore,
        hookServer: HookServer,
        adapterRegistry: AdapterRegistry,
        titleMarkerService: TitleMarkerService,
        approvalCenter: ApprovalCenter,
        usageLimits: UsageLimitsService,
        updateChecker: UpdateChecker,
        codexSessionWatcher: CodexSessionWatcher,
        geminiSessionWatcher: GeminiSessionWatcher
    ) {
        self.appState = appState
        self.repository = repository
        self.settingsStore = settingsStore
        self.telemetryCoordinator = telemetryCoordinator
        self.sessionStore = sessionStore
        self.hookServer = hookServer
        self.adapterRegistry = adapterRegistry
        self.titleMarkerService = titleMarkerService
        self.approvalCenter = approvalCenter
        self.usageLimits = usageLimits
        self.updateChecker = updateChecker
        self.codexSessionWatcher = codexSessionWatcher
        self.geminiSessionWatcher = geminiSessionWatcher
    }

    static func production() -> AppEnvironment {
        let supportURL = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent(AppConstants.appName, isDirectory: true)
            ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(AppConstants.appName)

        let repository = UsageRepository(
            databaseURL: supportURL.appendingPathComponent(AppConstants.databaseFileName)
        )
        let settingsStore = SettingsStore()
        let telemetryCoordinator = TelemetryCoordinator(repository: repository)
        let sessionStore = SessionStore()
        let titleMarkerService = TitleMarkerService()
        let adapterRegistry = AdapterRegistry(hookPort: AppConstants.defaultHookPort)
        let approvalCenter = ApprovalCenter()
        let usageLimits = UsageLimitsService()
        let updateChecker = UpdateChecker()
        // The executable injects Sparkle here when the framework is embedded;
        // without it the checker falls back to opening the release page.
        updateChecker.installHandler = AppEnvironment.updateInstaller

        // Codex has no hooks — a rollout-file watcher feeds the same store.
        let codexSessionWatcher = CodexSessionWatcher { event in
            Task { @MainActor in
                sessionStore.apply(event)
            }
        }

        // Gemini has no hooks either — its per-project session artifacts
        // are watched the same way.
        let geminiSessionWatcher = GeminiSessionWatcher { event in
            Task { @MainActor in
                sessionStore.apply(event)
            }
        }

        let hookServer = HookServer { event in
            // Apply the event; PermissionRequest may be parked for a verdict
            // or auto-answered from an earlier Always-Allow/Bypass.
            enum ApprovalRoute { case none, hold(String), autoAllow }
            let route = await MainActor.run { () -> ApprovalRoute in
                sessionStore.apply(event)
                guard case .permissionRequest = event.kind else { return .none }
                if approvalCenter.shouldAutoAllow(event: event) {
                    sessionStore.clearApprovalPending(sessionID: event.context.sessionID)
                    return .autoAllow
                }
                guard approvalCenter.shouldHold(event: event) else { return .none }
                return .hold(approvalCenter.register(event: event))
            }

            switch route {
            case .autoAllow:
                return HookResponses.permission(.allow, reason: "Always allowed from the notch", agent: event.context.agent)
            case .hold(let holdID):
                let decision = await approvalCenter.wait(id: holdID)
                await MainActor.run {
                    sessionStore.clearApprovalPending(sessionID: event.context.sessionID)
                }
                return HookResponses.permission(decision, reason: "Decided from the notch", agent: event.context.agent)
            case .none:
                break
            }

            return await MainActor.run { () -> String? in
                guard let session = sessionStore.session(withID: event.context.sessionID) else {
                    return nil
                }
                guard let payload = titleMarkerService.responsePayload(for: event, session: session) else {
                    return nil
                }
                return HookResponses.serialize(payload)
            }
        }

        sessionStore.onSessionRemoved = { sessionID in
            titleMarkerService.forget(sessionID: sessionID)
            approvalCenter.dropPending(forSessionID: sessionID)
        }

        // Subagent transcripts live beside the parent session's; reading them
        // is the only way to know what a specific agent is doing right now.
        sessionStore.onSubagentRefreshNeeded = { session in
            guard let path = session.transcriptPath else { return }
            let sessionID = session.id
            Task.detached(priority: .utility) {
                let activities = SubagentActivityReader.read(sessionTranscriptPath: path)
                guard !activities.isEmpty else { return }
                await MainActor.run {
                    sessionStore.applySubagentActivity(sessionID: sessionID, activities: activities)
                }
            }
        }

        sessionStore.onTranscriptRefreshNeeded = { session in
            let sessionID = session.id
            let projectPath = session.projectPath
            // Worktree branch (Display → Show Worktree) rides the same
            // off-main refresh.
            Task.detached(priority: .utility) {
                let branch = GitBranchReader.branch(forRepositoryAt: projectPath)
                await MainActor.run {
                    sessionStore.applyWorktreeBranch(sessionID: sessionID, branch: branch)
                }
            }
            guard let path = session.transcriptPath else { return }
            Task.detached(priority: .utility) {
                guard let digest = TranscriptReader.digest(atPath: path) else { return }
                await MainActor.run {
                    sessionStore.applyTranscriptDigest(
                        sessionID: sessionID,
                        title: digest.title,
                        lastPrompt: digest.lastUserPrompt,
                        tldr: digest.lastAssistantText.map { SessionReducer.condense($0, limit: 180) },
                        completionText: digest.lastAssistantText.map { String($0.prefix(2000)) },
                        model: digest.model
                    )
                }
            }
        }

        let appState = AppState(
            repository: repository,
            settingsStore: settingsStore,
            telemetryCoordinator: telemetryCoordinator,
            notificationService: NotificationService(),
            launchAtLoginService: LaunchAtLoginService(),
            sessionStore: sessionStore,
            hookServer: hookServer,
            adapterRegistry: adapterRegistry,
            titleMarkerService: titleMarkerService,
            approvalCenter: approvalCenter,
            codexSessionWatcher: codexSessionWatcher,
            geminiSessionWatcher: geminiSessionWatcher
        )
        return AppEnvironment(
            appState: appState,
            repository: repository,
            settingsStore: settingsStore,
            telemetryCoordinator: telemetryCoordinator,
            sessionStore: sessionStore,
            hookServer: hookServer,
            adapterRegistry: adapterRegistry,
            titleMarkerService: titleMarkerService,
            approvalCenter: approvalCenter,
            usageLimits: usageLimits,
            updateChecker: updateChecker,
            codexSessionWatcher: codexSessionWatcher,
            geminiSessionWatcher: geminiSessionWatcher
        )
    }
}
