import SwiftUI

struct TokenIslandNotchView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var sessionStore: SessionStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var stateMachine: TokenIslandStateMachine
    var layout: TokenIslandWindowLayout
    let interactionController: NotchInteractionController
    @ObservedObject var usageLimits: UsageLimitsService
    let openSettings: () -> Void
    let onJump: (AgentSession) -> Void

    private var effectiveState: TokenIslandNotchState {
        appState.settings.pinExpandedNotch ? .expanded : stateMachine.state
    }

    private var wings: NotchWings {
        NotchWingMetrics.wings(
            sessionCount: sessionStore.sessions.count,
            label: sessionStore.stripDetailLabel,
            hovering: effectiveState == .hoverPeek,
            detailed: appState.settings.notchDetailedMode
        )
    }

    private var visibleSize: CGSize {
        layout.visibleSize(
            for: effectiveState,
            pinned: appState.settings.pinExpandedNotch,
            wings: wings,
            contentHeight: stateMachine.contentHeight(pinned: appState.settings.pinExpandedNotch)
        )
    }

    private var notchAnimation: Animation? {
        guard !reduceMotion else { return nil }
        let speed = min(max(appState.settings.animationSpeed, 0.45), 1.8)
        return .interactiveSpring(response: 0.42 / speed, dampingFraction: 0.80, blendDuration: 0.12)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Color.clear
                island
                    // Top-aligned: the island hangs off the top edge of the
                    // screen, so any content the frame can't hold has to
                    // overflow downward — never up, where it gets cut off.
                    .frame(width: visibleSize.width, height: visibleSize.height, alignment: .top)
                    .position(x: anchorX(in: proxy), y: visibleSize.height / 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.clear)
        .onPreferenceChange(IslandContentHeightKey.self) { height in
            stateMachine.reportRevealContentHeight(height)
        }
        .onPreferenceChange(PanelContentHeightKey.self) { height in
            stateMachine.reportPanelContentHeight(height)
        }
        .animation(notchAnimation, value: stateMachine.state)
        .animation(notchAnimation, value: visibleSize)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Agent sessions island")
    }

    private var island: some View {
        ZStack(alignment: .top) {
            TokenIslandNotchShape(
                topRadius: topRadius(for: effectiveState),
                bottomRadius: bottomRadius(for: effectiveState)
            )
            .fill(TokenIslandNotchFill(
                isTranslucent: appState.settings.useTranslucentNotchBackground,
                isTransparentFallback: !layout.hasHardwareNotch && appState.settings.fallbackHandlerIsTransparent
            ))
            .shadow(
                color: .black.opacity(shadowOpacity(for: effectiveState)),
                radius: shadowRadius(for: effectiveState),
                x: 0,
                y: effectiveState.isExpandedLayout ? 18 : 5
            )

            content
                .clipShape(TokenIslandNotchShape(
                    topRadius: topRadius(for: effectiveState),
                    bottomRadius: bottomRadius(for: effectiveState)
                ))
        }
        .contentShape(TokenIslandNotchShape(
            topRadius: topRadius(for: effectiveState),
            bottomRadius: bottomRadius(for: effectiveState)
        ))
        .onTapGesture {
            interactionController.handleClick()
        }
        .accessibilityAction {
            interactionController.handleClick()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch effectiveState {
        case .collapsed:
            CollapsedStripView(layout: layout, hovering: false)
        case .hoverPeek:
            CollapsedStripView(layout: layout, hovering: true)
        case .expanded:
            ExpandedPanelView(
                usageLimits: usageLimits,
                onCollapse: interactionController.handleCollapse,
                openSettings: openSettings,
                onJump: onJump
            )
        case .reveal(let kind, let sessionID):
            RevealCardView(
                kind: kind,
                topInset: layout.notchBandHeight,
                session: sessionStore.session(withID: sessionID) ?? sessionStore.focusedSession,
                onExpand: { stateMachine.expand() },
                onJump: onJump,
                openSettings: openSettings
            )
            // Take the card's own height, report it, then fill the island from
            // the top with it. Without the measurement the card was centered
            // in a short fixed frame and its first row fell off the screen.
            .fixedSize(horizontal: false, vertical: true)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: IslandContentHeightKey.self, value: proxy.size.height)
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        case .error(let message):
            TokenIslandErrorView(message: message, openSettings: openSettings)
        }
    }

    private func anchorX(in proxy: GeometryProxy) -> CGFloat {
        let centered = layout.anchorXInWindow + layout.centerOffset(for: effectiveState, wings: wings)
        return min(
            max(centered, visibleSize.width / 2),
            proxy.size.width - visibleSize.width / 2
        )
    }

    private func topRadius(for state: TokenIslandNotchState) -> CGFloat {
        state.isExpandedLayout ? 8 : 5
    }

    private func bottomRadius(for state: TokenIslandNotchState) -> CGFloat {
        switch state {
        case .collapsed:
            min(max(appState.settings.islandCornerRadius * 0.56, 14), 22)
        case .hoverPeek, .reveal:
            min(max(appState.settings.islandCornerRadius * 0.72, 18), 28)
        case .expanded, .error:
            min(max(appState.settings.islandCornerRadius, 22), 40)
        }
    }

    private func shadowOpacity(for state: TokenIslandNotchState) -> Double {
        switch state {
        case .collapsed:
            0.08
        case .hoverPeek, .reveal:
            min(max(appState.settings.shadowIntensity * 0.52, 0.12), 0.42)
        case .expanded, .error:
            min(max(appState.settings.shadowIntensity, 0.20), 0.78)
        }
    }

    private func shadowRadius(for state: TokenIslandNotchState) -> CGFloat {
        switch state {
        case .collapsed:
            5
        case .hoverPeek, .reveal:
            14
        case .expanded, .error:
            28
        }
    }
}

struct TokenIslandNotchFill: ShapeStyle {
    var isTranslucent: Bool = false
    var isTransparentFallback: Bool = false

    func resolve(in environment: EnvironmentValues) -> some ShapeStyle {
        let opacity = isTransparentFallback ? 0.42 : 1.0
        // Multiplied, not overridden: with both flags the old code drew a dark
        // band across the middle of an otherwise translucent bar.
        let midOpacity = isTranslucent ? opacity * 0.90 : opacity
        return LinearGradient(
            colors: [
                Color.black.opacity(opacity),
                Color(red: 0.020, green: 0.021, blue: 0.025).opacity(midOpacity),
                Color(red: 0.008, green: 0.009, blue: 0.011).opacity(opacity)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

struct TokenIslandNotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let top = min(topRadius, rect.width / 3, rect.height / 2)
        let bottom = min(bottomRadius, rect.width / 3, rect.height / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + top, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - top, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + top),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottom))
        path.addCurve(
            to: CGPoint(x: rect.maxX - bottom, y: rect.maxY),
            control1: CGPoint(x: rect.maxX, y: rect.maxY - bottom * 0.45),
            control2: CGPoint(x: rect.maxX - bottom * 0.45, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + bottom, y: rect.maxY))
        path.addCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - bottom),
            control1: CGPoint(x: rect.minX + bottom * 0.45, y: rect.maxY),
            control2: CGPoint(x: rect.minX, y: rect.maxY - bottom * 0.45)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + top))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + top, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}
