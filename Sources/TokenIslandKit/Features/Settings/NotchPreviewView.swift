import SwiftUI

/// Compact live preview for both collapsed-strip and session-card settings.
struct NotchPreviewView: View {
    var settings: AppSettings

    var body: some View {
        ZStack(alignment: .top) {
            Color(red: 0.09, green: 0.11, blue: 0.15)
            miniPanel
                .padding(.top, 24)
                .padding(.horizontal, 42)
            strip
        }
        .frame(height: 154)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        }
        .animation(.snappy(duration: 0.2), value: settings.notchDetailedMode)
        .animation(.snappy(duration: 0.2), value: settings.showAIModel)
        .animation(.snappy(duration: 0.2), value: settings.showAgentActivityDetail)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Live notch and session card preview")
    }

    private var strip: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                PetFrameView(species: .crab, frameIndex: 0, phase: .working, pixelSize: 1.7, glow: true)
                PetFrameView(species: .blob, frameIndex: 1, phase: .ready, pixelSize: 1.7, glow: true)
                if settings.notchDetailedMode {
                    Text("Working")
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(TITheme.secondaryText)
                        .lineLimit(1)
                }
            }
            Color.clear.frame(width: 74)
            Text("2")
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(TITheme.primaryText)
        }
        .padding(.horizontal, 12)
        .frame(height: 26)
        .background(
            Color.black,
            in: UnevenRoundedRectangle(
                bottomLeadingRadius: 10,
                bottomTrailingRadius: 10,
                style: .continuous
            )
        )
    }

    private var miniPanel: some View {
        HStack(alignment: .top, spacing: 10) {
            PetFrameView(species: .crab, frameIndex: 0, phase: .working, pixelSize: 2, glow: true)
                .frame(width: 31, height: 31)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(previewTitle)
                        .font(.system(size: previewFontSize, weight: .semibold))
                        .foregroundStyle(TITheme.primaryText)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if settings.showAIModel {
                        Text("Sonnet 5")
                            .font(.system(size: max(8, previewFontSize - 2), weight: .medium))
                            .foregroundStyle(TITheme.secondaryText)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 4))
                    }
                }
                if settings.showAgentActivityDetail {
                    Label("Reading Sources/SessionStore.swift", systemImage: "doc.text.magnifyingglass")
                        .font(.system(size: max(8, previewFontSize - 2)))
                        .foregroundStyle(PetPalette.tint(for: .working))
                        .lineLimit(1)
                }
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.06))
                    .frame(height: min(30, max(14, settings.completionCardHeight * 0.2)))
                    .overlay(alignment: .leading) {
                        Text("Agent output appears here")
                            .font(.system(size: max(8, previewFontSize - 2)))
                            .foregroundStyle(TITheme.tertiaryText)
                            .padding(.horizontal, 7)
                    }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 114, alignment: .topLeading)
        .background(
            Color.black,
            in: UnevenRoundedRectangle(
                bottomLeadingRadius: 12,
                bottomTrailingRadius: 12,
                style: .continuous
            )
        )
    }

    private var previewTitle: String {
        var parts: [String] = []
        if settings.showProjectName { parts.append("counter") }
        parts.append("Fix model display")
        if settings.showWorktree { parts.append("main") }
        return parts.joined(separator: " · ")
    }

    private var previewFontSize: CGFloat {
        CGFloat(min(12, max(8, settings.contentFontSize * 0.85)))
    }
}
