import Foundation

struct MetadataSanitizer {
    private let sensitiveFragments = [
        "prompt",
        "message",
        "messages",
        "content",
        "input",
        "completion",
        "text"
    ]

    func sanitizedJSONObject(_ object: Any, storePromptText: Bool) -> Any {
        guard !storePromptText else { return object }
        if let dictionary = object as? [String: Any] {
            return dictionary.reduce(into: [String: Any]()) { result, element in
                let key = element.key.lowercased()
                if sensitiveFragments.contains(where: { key.contains($0) }) {
                    result[element.key] = "[redacted]"
                } else {
                    result[element.key] = sanitizedJSONObject(element.value, storePromptText: storePromptText)
                }
            }
        }
        if let array = object as? [Any] {
            return array.map { sanitizedJSONObject($0, storePromptText: storePromptText) }
        }
        return object
    }

    func metadataJSONString(from object: Any, storePromptText: Bool) -> String? {
        let sanitized = sanitizedJSONObject(object, storePromptText: storePromptText)
        guard JSONSerialization.isValidJSONObject(sanitized),
              let data = try? JSONSerialization.data(withJSONObject: sanitized, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return string
    }
}
