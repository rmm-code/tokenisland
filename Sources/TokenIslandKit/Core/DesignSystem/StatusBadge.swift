import SwiftUI

struct StatusBadge: View {
    var title: String
    var health: ServiceHealth

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(TITheme.secondaryText)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.08), in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(health.rawValue)")
    }

    private var color: Color {
        switch health {
        case .running:
            .green
        case .starting:
            TITheme.warning
        case .degraded:
            .orange
        case .failed:
            TITheme.danger
        case .stopped:
            TITheme.tertiaryText
        }
    }
}
