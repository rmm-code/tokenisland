import SwiftUI

/// Dark inner card showing the finished turn: prompt header + response
/// excerpt. Rendered under a ready session card and inside reveals.
struct CompletionCardView: View {
    @EnvironmentObject private var appState: AppState
    var session: AgentSession
    /// Explicit override for compact contexts (reveals); otherwise derived
    /// from Settings → Display → Completion Card Height.
    var lineLimit: Int?
    @State private var isExpanded: Bool

    init(
        session: AgentSession,
        lineLimit: Int? = nil,
        initiallyExpanded: Bool = true
    ) {
        self.session = session
        self.lineLimit = lineLimit
        _isExpanded = State(initialValue: initiallyExpanded)
    }

    private var effectiveLineLimit: Int {
        if let lineLimit { return lineLimit }
        // ~13pt per monospaced line at the default font size.
        return max(2, Int(appState.settings.completionCardHeight / 13))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Text("You:")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(TITheme.tertiaryText)
                    Text(session.lastUserPrompt ?? session.displayTitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(TITheme.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 8)
                    Text("Done")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(TITheme.tertiaryText)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(TITheme.tertiaryText)
                        .frame(width: 14, height: 14)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "Collapse completed response" : "Expand completed response")

            if isExpanded,
               let text = session.completionText ?? session.completionTLDR {
                Divider()
                    .overlay(Color.white.opacity(0.08))
                LiteMarkdownText(text: text, size: 11)
                    .foregroundStyle(TITheme.primaryText.opacity(0.88))
                    .lineLimit(effectiveLineLimit)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.black.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
    }
}
