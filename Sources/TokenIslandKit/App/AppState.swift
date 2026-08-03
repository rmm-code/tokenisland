import Combine
import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var summary: UsageSummary = .empty
    @Published private(set) var ingestionStatus: IngestionStatus = .idle
    @Published private(set) var isLoading = true
    @Published var settings: AppSettings
    @Published var errorMessage: String?

    private let repository: UsageRepository
    private let settingsStore: SettingsStore
    private let telemetryCoordinator: TelemetryCoordinator
    private let notificationService: NotificationService
    private let launchAtLoginService: LaunchAtLoginService
    let sessionStore: SessionStore
    let adapterRegistry: AdapterRegistry
    let titleMarkerService: TitleMarkerService
    let approvalCenter: ApprovalCenter
    private let codexSessionWatcher: CodexSessionWatcher
    private let geminiSessionWatcher: GeminiSessionWatcher
    private let hookServer: HookServer
    private var refreshTask: Task<Void, Never>?
    private var hasStarted = false
    private var integrationsActive = false

    init(
        repository: UsageRepository,
        settingsStore: SettingsStore,
        telemetryCoordinator: TelemetryCoordinator,
        notificationService: NotificationService,
        launchAtLoginService: LaunchAtLoginService,
        sessionStore: SessionStore,
        hookServer: HookServer,
        adapterRegistry: AdapterRegistry,
        titleMarkerService: TitleMarkerService,
        approvalCenter: ApprovalCenter,
        codexSessionWatcher: CodexSessionWatcher,
        geminiSessionWatcher: GeminiSessionWatcher
    ) {
        self.repository = repository
        self.settingsStore = settingsStore
        self.telemetryCoordinator = telemetryCoordinator
        self.notificationService = notificationService
        self.launchAtLoginService = launchAtLoginService
        self.sessionStore = sessionStore
        self.hookServer = hookServer
        self.adapterRegistry = adapterRegistry
        self.titleMarkerService = titleMarkerService
        self.approvalCenter = approvalCenter
        self.codexSessionWatcher = codexSessionWatcher
        self.geminiSessionWatcher = geminiSessionWatcher
        self.settings = settingsStore.load()
    }

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        applyDerivedSettings(settings)
        adapterRegistry.refreshStatuses()
        do {
            try await repository.prepare()
            await telemetryCoordinator.setCallbacks(
                onStatusChange: { [weak self] status in
                    Task { @MainActor in
                        self?.ingestionStatus = status
                    }
                },
                onEventsIngested: { [weak self] _ in
                    Task { @MainActor in
                        await self?.refresh()
                    }
                }
            )
            if settings.hasCompletedOnboarding {
                await activateRuntimeIntegrations()
            }
            await refresh()
            startRefreshLoop()
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    func refresh() async {
        do {
            summary = try await repository.summary()
            isLoading = false
            errorMessage = nil
            if settings.hasCompletedOnboarding {
                await notificationService.evaluateThresholds(summary: summary, settings: settings)
            }
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    func updateSettings(_ update: (inout AppSettings) -> Void) {
        var next = settings
        update(&next)
        persistSettings(next)
    }

    func resetSettings() {
        var defaults = AppSettings.defaults
        defaults.hasCompletedOnboarding = settings.hasCompletedOnboarding
        persistSettings(defaults)
    }

    /// Pushes settings-derived knobs into the session services.
    private func applyDerivedSettings(_ settings: AppSettings) {
        sessionStore.idleCleanupSeconds = max(600, settings.idleCleanupHours * 3600)
        approvalCenter.useNativeApprovals = settings.useNativeClaudeApprovals
        approvalCenter.holdTimeoutSeconds = min(85, max(10, settings.approvalHoldSeconds))
        titleMarkerService.isEnabled = settings.enableTitleMarkers
        if integrationsActive, settings.enableCodexMonitoring {
            codexSessionWatcher.start()
        } else {
            codexSessionWatcher.stop()
        }
        if integrationsActive, settings.enableGeminiMonitoring {
            geminiSessionWatcher.start()
        } else {
            geminiSessionWatcher.stop()
        }
    }

    private func persistSettings(_ next: AppSettings) {
        let previous = settings
        if previous.launchAtLogin != next.launchAtLogin {
            do {
                try launchAtLoginService.setEnabled(next.launchAtLogin)
            } catch {
                errorMessage = error.localizedDescription
                return
            }
        }
        settings = next
        settingsStore.save(next)
        applyDerivedSettings(next)
        Task {
            if integrationsActive, telemetryConfigurationChanged(from: previous, to: next) {
                await telemetryCoordinator.start(settings: next)
            }
            if integrationsActive,
               !previous.enableThresholdNotifications,
               next.enableThresholdNotifications {
                await notificationService.requestAuthorizationIfNeeded()
            }
            await refresh()
        }
    }

    func completeOnboarding() {
        guard !settings.hasCompletedOnboarding else { return }
        updateSettings { $0.hasCompletedOnboarding = true }
        Task {
            await activateRuntimeIntegrations()
        }
    }

    private func activateRuntimeIntegrations() async {
        guard !integrationsActive else { return }
        integrationsActive = true
        do {
            try hookServer.start()
        } catch {
            errorMessage = "Hook server failed to start: \(error.localizedDescription)"
        }
        applyDerivedSettings(settings)
        if settings.autoConfigureNewCLIs {
            adapterRegistry.autoConfigure()
        } else {
            adapterRegistry.refreshStatuses()
        }
        await telemetryCoordinator.start(settings: settings)
        if settings.enableThresholdNotifications {
            await notificationService.requestAuthorizationIfNeeded()
        }
    }

    private func telemetryConfigurationChanged(from old: AppSettings, to new: AppSettings) -> Bool {
        old.enableOTLPReceiver != new.enableOTLPReceiver
            || old.otlpPort != new.otlpPort
            || old.enableOpenAIProxy != new.enableOpenAIProxy
            || old.proxyPort != new.proxyPort
            || old.openAIBaseURL != new.openAIBaseURL
            || old.metadataStorageOptions != new.metadataStorageOptions
    }

    func deleteAllUsage() async {
        do {
            try await repository.deleteAllUsage()
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func exportUsageData(to url: URL) async {
        do {
            let data = try await repository.exportEventsJSON()
            try data.write(to: url, options: .atomic)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startRefreshLoop() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                await self?.refresh()
            }
        }
    }
}
