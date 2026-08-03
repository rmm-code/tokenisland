import AppKit
import SwiftUI

struct ProviderIconView: View {
    var provider: AIProvider
    var size: CGFloat = 28
    /// Renders the glyph as a white silhouette (template) — for colored
    /// tiles like the usage pill, where the orange-on-orange Claude mark
    /// would otherwise disappear.
    var whiteTemplate: Bool = false

    var body: some View {
        Group {
            if let image = ProviderIconAsset.image(for: provider) {
                if whiteTemplate {
                    Image(nsImage: image)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(.white)
                } else {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                }
            } else {
                fallbackIcon
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var fallbackIcon: some View {
        Image(systemName: provider.systemImage)
            .font(.system(size: size * 0.72, weight: .semibold))
            .foregroundStyle(provider.tint)
    }
}

@MainActor
private enum ProviderIconAsset {
    private static let claudeImage = loadSVG(named: "claude-ai-icon")
    private static let codexImage = loadSVG(named: "codex_dark")

    static func image(for provider: AIProvider) -> NSImage? {
        switch provider {
        case .claude:
            return claudeImage
        case .gpt:
            return codexImage
        case .gemini:
            return nil
        case .unknown:
            return nil
        }
    }

    private static func loadSVG(named name: String) -> NSImage? {
        guard let url = Bundle.module.url(forResource: name, withExtension: "svg")
            ?? Bundle.module.url(
                forResource: name,
                withExtension: "svg",
                subdirectory: "ProviderIcons"
            )
        else {
            return nil
        }
        return NSImage(contentsOf: url)
    }
}
