import SwiftUI

enum TITheme {
    static let background = Color(red: 0.045, green: 0.048, blue: 0.055)
    static let panel = Color.white.opacity(0.08)
    static let panelStroke = Color.white.opacity(0.14)
    static let primaryText = Color.white.opacity(0.94)
    static let secondaryText = Color.white.opacity(0.64)
    static let tertiaryText = Color.white.opacity(0.42)
    static let warning = Color(red: 1.00, green: 0.74, blue: 0.32)
    static let danger = Color(red: 1.00, green: 0.34, blue: 0.36)
    static let blue = Color(red: 0.37, green: 0.62, blue: 1.0)

    static let cornerRadius: CGFloat = 18
    static let compactCornerRadius: CGFloat = 24
    static let controlRadius: CGFloat = 8
}

extension View {
    func tiPanel(cornerRadius: CGFloat = TITheme.cornerRadius) -> some View {
        background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(TITheme.panelStroke, lineWidth: 1)
            }
    }

    func tiButtonStyle() -> some View {
        buttonStyle(.plain)
            .contentShape(Rectangle())
    }
}
