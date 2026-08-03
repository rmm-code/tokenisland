import Foundation

actor TelemetryCoordinator {
    private let repository: UsageRepository
    private var otlpReceiver: OTLPReceiver?
    private var proxyService: OpenAIProxyService?
    private var status = IngestionStatus.idle
    private var onStatusChange: (@Sendable (IngestionStatus) -> Void)?
    private var onEventsIngested: (@Sendable ([UsageEvent]) -> Void)?

    init(repository: UsageRepository) {
        self.repository = repository
    }

    func setCallbacks(
        onStatusChange: (@Sendable (IngestionStatus) -> Void)?,
        onEventsIngested: (@Sendable ([UsageEvent]) -> Void)?
    ) {
        self.onStatusChange = onStatusChange
        self.onEventsIngested = onEventsIngested
    }

    func start(settings: AppSettings) {
        stop()
        status = IngestionStatus(
            otlpHealth: settings.enableOTLPReceiver ? .starting : .stopped,
            proxyHealth: settings.enableOpenAIProxy ? .starting : .stopped,
            lastEventAt: nil,
            lastErrorMessage: nil,
            ingestedEventCount: 0
        )
        publishStatus()

        if settings.enableOTLPReceiver {
            do {
                let receiver = OTLPReceiver()
                try receiver.start(
                    port: settings.otlpPort,
                    storageOptions: settings.metadataStorageOptions
                ) { [repository] events in
                    try? await repository.insert(events)
                    await self.noteIngested(events)
                }
                otlpReceiver = receiver
                status.otlpHealth = .running
            } catch {
                status.otlpHealth = .failed
                status.lastErrorMessage = error.localizedDescription
            }
        }

        if settings.enableOpenAIProxy {
            do {
                let proxy = OpenAIProxyService()
                try proxy.start(
                    port: settings.proxyPort,
                    baseURL: settings.openAIBaseURL,
                    storageOptions: settings.metadataStorageOptions
                ) { [repository] events in
                    try? await repository.insert(events)
                    await self.noteIngested(events)
                }
                proxyService = proxy
                status.proxyHealth = .running
            } catch {
                status.proxyHealth = .failed
                status.lastErrorMessage = error.localizedDescription
            }
        }

        publishStatus()
    }

    func stop() {
        otlpReceiver?.stop()
        proxyService?.stop()
        otlpReceiver = nil
        proxyService = nil
    }

    private func noteIngested(_ events: [UsageEvent]) {
        guard !events.isEmpty else { return }
        status.lastEventAt = Date()
        status.ingestedEventCount += events.count
        status.lastErrorMessage = nil
        publishStatus()
        onEventsIngested?(events)
    }

    private func publishStatus() {
        onStatusChange?(status)
    }
}
