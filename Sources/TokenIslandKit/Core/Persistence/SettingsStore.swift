import Foundation

final class SettingsStore {
    private let defaults: UserDefaults
    private let key = "TokenIsland.AppSettings.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> AppSettings {
        guard let data = defaults.data(forKey: key) else {
            return .defaults
        }
        do {
            let decoder = JSONDecoder()
            return try decoder.decode(AppSettings.self, from: data)
        } catch {
            AppLog.app.error("Failed to decode settings: \(error.localizedDescription)")
            return .defaults
        }
    }

    func save(_ settings: AppSettings) {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(settings)
            defaults.set(data, forKey: key)
        } catch {
            AppLog.app.error("Failed to encode settings: \(error.localizedDescription)")
        }
    }
}
