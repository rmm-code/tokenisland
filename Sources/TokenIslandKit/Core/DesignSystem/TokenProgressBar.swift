import SwiftUI

struct TokenProgressBar: View {
    var value: Double
    var tint: Color
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.10))
                Capsule()
                    .fill(tint)
                    .frame(width: max(0, min(1, value)) * proxy.size.width)
            }
        }
        .frame(height: height)
        .accessibilityLabel("Usage percentage")
        .accessibilityValue(AppFormatters.percent(value))
    }
}
