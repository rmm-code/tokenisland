import Foundation

/// One safe boundary for configuration reads and writes. An existing file
/// that cannot be decoded is an error, never an empty configuration.
struct HookSettingsFile {
    let url: URL
    private var fileManager: FileManager { .default }

    func read() throws -> [String: Any] {
        guard fileManager.fileExists(atPath: url.path) else { return [:] }
        let data = try Data(contentsOf: url)
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw AdapterFileError.unexpectedFormat(url.lastPathComponent)
        }
        guard let settings = object as? [String: Any] else {
            throw AdapterFileError.unexpectedFormat(url.lastPathComponent)
        }
        // A valid root object can still contain malformed hook collections.
        // Refuse to "repair" those by discarding unknown user configuration.
        if let value = settings["hooks"] {
            guard let hooks = value as? [String: Any],
                  hooks.values.allSatisfy({ $0 is [[String: Any]] })
            else { throw AdapterFileError.invalidHooks(url.lastPathComponent) }
            for entries in hooks.values {
                for entry in entries as? [[String: Any]] ?? [] {
                    if let nested = entry["hooks"], !(nested is [[String: Any]]) {
                        throw AdapterFileError.invalidHooks(url.lastPathComponent)
                    }
                }
            }
        }
        if let env = settings["env"], !(env is [String: Any]) {
            throw AdapterFileError.unexpectedFormat(url.lastPathComponent)
        }
        return settings
    }

    func write(_ settings: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    func backupIfNeeded() throws {
        let backupURL = url.appendingPathExtension("tokenisland-backup")
        guard fileManager.fileExists(atPath: url.path), !fileManager.fileExists(atPath: backupURL.path) else { return }
        try fileManager.copyItem(at: url, to: backupURL)
    }
}

enum AdapterFileError: Error, LocalizedError {
    case unexpectedFormat(String)
    case invalidHooks(String)

    var errorDescription: String? {
        switch self {
        case .unexpectedFormat(let file):
            "\(file) is not a valid JSON configuration. Your file was left unchanged; correct it and retry."
        case .invalidHooks(let file):
            "\(file) contains an invalid hooks section. Your file was left unchanged; correct it and retry."
        }
    }
}
