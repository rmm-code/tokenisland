import Foundation

enum OTLPNormalizerError: Error, LocalizedError {
    case invalidJSON

    var errorDescription: String? {
        switch self {
        case .invalidJSON:
            "The telemetry payload was not valid JSON."
        }
    }
}

struct OTLPNormalizer {
    private let costEstimator = TokenCostEstimator()
    private let sanitizer = MetadataSanitizer()

    func events(from data: Data, defaultSource: String, storePromptText: Bool) throws -> [UsageEvent] {
        try events(
            from: data,
            defaultSource: defaultSource,
            storageOptions: UsageMetadataStorageOptions(
                storePromptText: storePromptText,
                storeSourceApp: true,
                storeProjectPath: true,
                storeRawMetadataJSON: true
            )
        )
    }

    func events(from data: Data, defaultSource: String, storageOptions: UsageMetadataStorageOptions) throws -> [UsageEvent] {
        guard !data.isEmpty else { return [] }
        let object = try JSONSerialization.jsonObject(with: data, options: [])
        var candidates: [[String: Any]] = []
        collectCandidates(from: object, inherited: [:], into: &candidates)

        var seen: Set<String> = []
        return candidates.compactMap { map in
            guard let event = event(
                from: map,
                originalObject: object,
                defaultSource: defaultSource,
                storageOptions: storageOptions
            ) else {
                return nil
            }
            let key = event.requestID ?? "\(event.timestamp.timeIntervalSince1970)-\(event.provider.rawValue)-\(event.model)-\(event.totalTokens)"
            guard !seen.contains(key) else { return nil }
            seen.insert(key)
            return event
        }
    }

    private func collectCandidates(from object: Any, inherited: [String: Any], into candidates: inout [[String: Any]]) {
        if let dictionary = object as? [String: Any] {
            var context = inherited
            context.merge(flatten(dictionary), uniquingKeysWith: { _, new in new })

            if let resource = dictionary["resource"] as? [String: Any] {
                context.merge(attributeMap(from: resource["attributes"]), uniquingKeysWith: { _, new in new })
                context.merge(flatten(resource), uniquingKeysWith: { _, new in new })
            }
            context.merge(attributeMap(from: dictionary["attributes"]), uniquingKeysWith: { _, new in new })

            if let body = dictionary["body"] {
                let decodedBody = decodeOTelValue(body)
                if let bodyDictionary = decodedBody as? [String: Any] {
                    context.merge(flatten(bodyDictionary), uniquingKeysWith: { _, new in new })
                } else if let bodyString = decodedBody as? String,
                          let bodyData = bodyString.data(using: .utf8),
                          let bodyObject = try? JSONSerialization.jsonObject(with: bodyData) {
                    context.merge(flatten(bodyObject), uniquingKeysWith: { _, new in new })
                } else {
                    context["body"] = decodedBody
                }
            }

            if looksLikeUsage(context) {
                candidates.append(context)
            }

            for (key, value) in dictionary where key != "attributes" && key != "resource" && key != "body" {
                collectCandidates(from: value, inherited: context, into: &candidates)
            }
        } else if let array = object as? [Any] {
            for item in array {
                collectCandidates(from: item, inherited: inherited, into: &candidates)
            }
        }
    }

    private func event(
        from map: [String: Any],
        originalObject: Any,
        defaultSource: String,
        storageOptions: UsageMetadataStorageOptions
    ) -> UsageEvent? {
        let inputTokens = intValue(map, keys: [
            "input_tokens",
            "prompt_tokens",
            "usage.prompt_tokens",
            "usage.input_tokens",
            "gen_ai.usage.input_tokens",
            "llm.usage.prompt_tokens",
            "anthropic.usage.input_tokens"
        ])
        let outputTokens = intValue(map, keys: [
            "output_tokens",
            "completion_tokens",
            "usage.completion_tokens",
            "usage.output_tokens",
            "gen_ai.usage.output_tokens",
            "llm.usage.completion_tokens",
            "anthropic.usage.output_tokens"
        ])
        let cacheReadTokens = intValue(map, keys: [
            "cache_read_tokens",
            "cache_read_input_tokens",
            "usage.cache_read_tokens",
            "usage.cache_read_input_tokens",
            "anthropic.usage.cache_read_input_tokens"
        ])
        let cacheWriteTokens = intValue(map, keys: [
            "cache_write_tokens",
            "cache_creation_tokens",
            "cache_creation_input_tokens",
            "usage.cache_write_tokens",
            "usage.cache_creation_input_tokens",
            "anthropic.usage.cache_creation_input_tokens"
        ])

        guard inputTokens + outputTokens + cacheReadTokens + cacheWriteTokens > 0 else {
            return nil
        }

        let model = stringValue(map, keys: [
            "model",
            "request.model",
            "response.model",
            "gen_ai.request.model",
            "gen_ai.response.model",
            "llm.request.model",
            "llm.response.model"
        ]) ?? "unknown-model"

        let provider = AIProvider.infer(from: stringValue(map, keys: [
            "provider",
            "gen_ai.provider.name",
            "gen_ai.system",
            "llm.provider",
            "source",
            "source_app",
            "service.name",
            "name",
            "app",
            "model"
        ]), model: model)

        let sourceApp = stringValue(map, keys: [
            "source_app",
            "source",
            "service.name",
            "telemetry.sdk.name",
            "process.executable.name",
            "app"
        ]) ?? fallbackSource(provider: provider, defaultSource: defaultSource)

        let suppliedCost = decimalValue(map, keys: [
            "estimated_cost_usd",
            "cost_usd",
            "usage.cost_usd",
            "claude_code.cost.usage",
            "gen_ai.usage.cost_usd"
        ])

        let cost = suppliedCost ?? costEstimator.estimate(
            provider: provider,
            model: model,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheReadTokens: cacheReadTokens,
            cacheWriteTokens: cacheWriteTokens
        )

        let projectName = stringValue(map, keys: ["project_name", "project.name", "workspace.name", "repository.name"])
        let projectPath = stringValue(map, keys: ["project_path", "project.path", "workspace.path", "cwd"])

        return UsageEvent(
            timestamp: timestamp(from: map) ?? Date(),
            provider: provider,
            sourceApp: storageOptions.storeSourceApp ? sourceApp : "Source hidden",
            projectName: storageOptions.storeProjectPath ? projectName : nil,
            projectPath: storageOptions.storeProjectPath ? projectPath : nil,
            model: model,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheReadTokens: cacheReadTokens,
            cacheWriteTokens: cacheWriteTokens,
            estimatedCostUSD: cost,
            requestID: stringValue(map, keys: ["request_id", "request.id", "gen_ai.request.id", "spanId", "traceId", "id"]),
            latencyMS: intValue(map, keys: ["latency_ms", "duration_ms", "gen_ai.response.latency_ms"]),
            sessionID: stringValue(map, keys: ["session_id", "session.id", "conversation_id"]),
            rawMetadataJSON: storageOptions.storeRawMetadataJSON
                ? sanitizer.metadataJSONString(from: originalObject, storePromptText: storageOptions.storePromptText)
                : nil
        )
    }

    private func looksLikeUsage(_ map: [String: Any]) -> Bool {
        let tokenKeys = [
            "input_tokens", "output_tokens", "prompt_tokens", "completion_tokens",
            "cache_read_tokens", "cache_write_tokens", "cache_creation_tokens",
            "gen_ai.usage.input_tokens", "gen_ai.usage.output_tokens",
            "usage.prompt_tokens", "usage.completion_tokens"
        ]
        return tokenKeys.contains { map[$0] != nil }
    }

    private func flatten(_ object: Any, prefix: String? = nil) -> [String: Any] {
        if let dictionary = object as? [String: Any] {
            return dictionary.reduce(into: [String: Any]()) { result, element in
                let key = prefix.map { "\($0).\(element.key)" } ?? element.key
                let decoded = decodeOTelValue(element.value)
                if decoded is [String: Any] || decoded is [Any] {
                    result.merge(flatten(decoded, prefix: key), uniquingKeysWith: { _, new in new })
                } else {
                    result[key] = decoded
                    result[element.key] = decoded
                }
            }
        }
        if let array = object as? [Any] {
            return [prefix ?? "array": array.map(decodeOTelValue)]
        }
        return [prefix ?? "value": decodeOTelValue(object)]
    }

    private func attributeMap(from attributesObject: Any?) -> [String: Any] {
        guard let attributes = attributesObject as? [[String: Any]] else { return [:] }
        return attributes.reduce(into: [String: Any]()) { result, attribute in
            guard let key = attribute["key"] as? String else { return }
            result[key] = decodeOTelValue(attribute["value"] as Any)
        }
    }

    private func decodeOTelValue(_ value: Any) -> Any {
        guard let dictionary = value as? [String: Any] else { return value }
        if let value = dictionary["stringValue"] { return value }
        if let value = dictionary["intValue"] { return numberLikeValue(value) }
        if let value = dictionary["doubleValue"] { return numberLikeValue(value) }
        if let value = dictionary["boolValue"] { return value }
        if let arrayValue = dictionary["arrayValue"] as? [String: Any],
           let values = arrayValue["values"] as? [Any] {
            return values.map(decodeOTelValue)
        }
        if let kvList = dictionary["kvlistValue"] as? [String: Any],
           let values = kvList["values"] as? [[String: Any]] {
            return values.reduce(into: [String: Any]()) { result, item in
                guard let key = item["key"] as? String else { return }
                result[key] = decodeOTelValue(item["value"] as Any)
            }
        }
        return dictionary
    }

    private func numberLikeValue(_ value: Any) -> Any {
        if let string = value as? String {
            if let integer = Int(string) { return integer }
            if let double = Double(string) { return double }
        }
        return value
    }

    private func intValue(_ map: [String: Any], keys: [String]) -> Int {
        for key in keys {
            guard let value = map[key] else { continue }
            if let int = value as? Int { return int }
            if let int64 = value as? Int64 { return Int(int64) }
            if let double = value as? Double { return Int(double) }
            if let string = value as? String, let int = Int(string) { return int }
        }
        return 0
    }

    private func decimalValue(_ map: [String: Any], keys: [String]) -> Decimal? {
        for key in keys {
            guard let value = map[key] else { continue }
            if let decimal = value as? Decimal { return decimal }
            if let double = value as? Double { return Decimal(double) }
            if let int = value as? Int { return Decimal(int) }
            if let string = value as? String, let decimal = Decimal(string: string) { return decimal }
        }
        return nil
    }

    private func stringValue(_ map: [String: Any], keys: [String]) -> String? {
        for key in keys {
            guard let value = map[key] else { continue }
            if let string = value as? String, !string.isEmpty { return string }
            if let number = value as? NSNumber { return number.stringValue }
        }
        return nil
    }

    private func timestamp(from map: [String: Any]) -> Date? {
        if let unixNanoString = stringValue(map, keys: ["timeUnixNano", "startTimeUnixNano"]),
           let unixNano = Double(unixNanoString) {
            return Date(timeIntervalSince1970: unixNano / 1_000_000_000)
        }
        if let unixNano = map["timeUnixNano"] as? Double ?? map["startTimeUnixNano"] as? Double {
            return Date(timeIntervalSince1970: unixNano / 1_000_000_000)
        }
        if let unixSeconds = map["timestamp"] as? Double {
            return Date(timeIntervalSince1970: unixSeconds)
        }
        if let timestampString = stringValue(map, keys: ["timestamp", "time", "created_at"]) {
            if let seconds = Double(timestampString) {
                return Date(timeIntervalSince1970: seconds)
            }
            return ISO8601DateFormatter().date(from: timestampString)
        }
        return nil
    }

    private func fallbackSource(provider: AIProvider, defaultSource: String) -> String {
        switch provider {
        case .claude:
            defaultSource.isEmpty ? "Generic Claude Source" : defaultSource
        case .gpt:
            defaultSource.isEmpty ? "Generic OpenAI Source" : defaultSource
        case .gemini:
            defaultSource.isEmpty ? "Generic Gemini Source" : defaultSource
        case .unknown:
            defaultSource.isEmpty ? "Unknown Source" : defaultSource
        }
    }
}
