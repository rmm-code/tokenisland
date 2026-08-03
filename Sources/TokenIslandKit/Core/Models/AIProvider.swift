import Foundation
import SwiftUI

enum AIProvider: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case claude
    case gpt
    case gemini
    case unknown

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude:
            "Claude"
        case .gpt:
            "OpenAI / Codex"
        case .gemini:
            "Gemini"
        case .unknown:
            "Unknown"
        }
    }

    var systemImage: String {
        switch self {
        case .claude:
            "c.circle.fill"
        case .gpt:
            "sparkles"
        case .gemini:
            "diamond.fill"
        case .unknown:
            "questionmark.circle"
        }
    }

    var tint: Color {
        switch self {
        case .claude:
            Color(red: 0.94, green: 0.45, blue: 0.24)
        case .gpt:
            Color(red: 0.22, green: 0.78, blue: 0.58)
        case .gemini:
            Color(red: 0.38, green: 0.61, blue: 0.96)
        case .unknown:
            Color(red: 0.62, green: 0.67, blue: 0.74)
        }
    }

    static func infer(from value: String?, model: String? = nil) -> AIProvider {
        let normalized = value?.lowercased() ?? ""
        if normalized.contains("claude") || normalized.contains("anthropic") {
            return .claude
        }
        if normalized.contains("gpt") || normalized.contains("openai") || normalized.contains("codex") {
            return .gpt
        }
        if normalized.contains("gemini") || normalized.contains("google") || normalized.contains("gcp") {
            return .gemini
        }
        if let model, model.caseInsensitiveCompare(value ?? "") != .orderedSame {
            return infer(from: model)
        }
        return .unknown
    }
}
