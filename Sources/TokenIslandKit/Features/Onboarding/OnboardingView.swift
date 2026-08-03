import SwiftUI

/// Five-step centered onboarding: hero → accessibility → detected tools →
/// notch tour → boarding pass. Mirrors the reference flow (minus pricing).
struct OnboardingView: View {
    @EnvironmentObject private var appState: AppState
    @State private var step: OnboardingStep = .welcome
    @State private var accessibilityGranted = WindowLocator.hasAccessibilityPermission
    var onFinish: (() -> Void)?

    init(onFinish: (() -> Void)? = nil) {
        self.onFinish = onFinish
    }

    var body: some View {
        VStack(spacing: 0) {
            // Steps scroll inside the fixed window (the window must never
            // resize to content — macOS 26 layout-loop crash); short steps
            // center via the min-height container.
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    content
                        .frame(maxWidth: 520)
                        .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity, minHeight: 470)
            }
            footer
        }
        .padding(.horizontal, 26)
        .padding(.top, 14)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TITheme.background)
        .onAppear {
            appState.adapterRegistry.refreshStatuses()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome: welcome
        case .jump: jump
        case .allSet: allSet
        case .tour: tour
        case .boardingPass: boardingPass
        }
    }

    // MARK: - Steps

    private var welcome: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                PetFrameView(species: .crab, frameIndex: 0, phase: .working, pixelSize: 5, glow: true)
                PetFrameView(species: .blob, frameIndex: 1, phase: .ready, pixelSize: 5, glow: true)
                PetFrameView(species: .runner, frameIndex: 0, phase: .waitingApproval, pixelSize: 5, glow: true)
            }
            .padding(.bottom, 6)
            Text("All your AI agents, one notch.")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(TITheme.primaryText)
            Text("Every Claude Code session shows up as a pixel pet in your notch — see who's working, who's done, and who needs you, without switching windows.")
                .font(.system(size: 13))
                .foregroundStyle(TITheme.secondaryText)
                .multilineTextAlignment(.center)
        }
    }

    private var jump: some View {
        VStack(spacing: 16) {
            Image(systemName: "cursorarrow.rays")
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(TITheme.blue)
            Text("Click to jump back.")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(TITheme.primaryText)
            Text("Click any session and land in the exact terminal tab where that agent is running. macOS requires the Accessibility permission for this.")
                .font(.system(size: 13))
                .foregroundStyle(TITheme.secondaryText)
                .multilineTextAlignment(.center)

            HStack(spacing: 8) {
                Image(systemName: accessibilityGranted ? "checkmark.seal.fill" : "exclamationmark.shield")
                    .foregroundStyle(accessibilityGranted ? PetPalette.tint(for: .ready) : TITheme.warning)
                Text(accessibilityGranted ? "Accessibility access granted" : "Accessibility access needed")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(TITheme.primaryText)
                if !accessibilityGranted {
                    Button("Grant…") {
                        WindowLocator.requestAccessibilityPermission()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            .padding(12)
            .tiPanel(cornerRadius: 12)
            .task {
                // Poll while this step is visible; the system prompt is async.
                while !Task.isCancelled {
                    accessibilityGranted = WindowLocator.hasAccessibilityPermission
                    try? await Task.sleep(for: .seconds(1))
                }
            }
        }
    }

    private var allSet: some View {
        VStack(spacing: 14) {
            Text("Tools Detected")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(TITheme.primaryText)
            Text("TokenIsland found the supported agents on this Mac. Their integrations activate when setup finishes. Claude usage loads automatically when macOS permits silent credential access; the notch never opens an authentication prompt.")
                .font(.system(size: 13))
                .foregroundStyle(TITheme.secondaryText)
                .multilineTextAlignment(.center)

            VStack(spacing: 0) {
                Text("AI AGENTS")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(TITheme.tertiaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 6)
                // The roster is long (~20 CLIs) — it scrolls inside a fixed
                // box so the step header and Next stay visible.
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 0) {
                        ForEach(appState.adapterRegistry.entries) { entry in
                            HStack(spacing: 8) {
                                Image(systemName: entry.status.isActive ? "checkmark" : "circle.dashed")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(entry.status.isActive ? PetPalette.tint(for: .ready) : TITheme.tertiaryText)
                                Text(entry.adapter.displayName)
                                    .font(.system(size: 12.5, weight: .medium))
                                    .foregroundStyle(TITheme.primaryText)
                                Spacer()
                                Text(entry.status.label)
                                    .font(.system(size: 11))
                                    .foregroundStyle(entry.status.isActive ? TITheme.secondaryText : TITheme.warning)
                            }
                            .padding(.vertical, 5)
                            .padding(.trailing, 6)
                        }
                    }
                }
                .frame(height: 205)
                Divider().overlay(Color.white.opacity(0.08)).padding(.vertical, 8)
                Toggle(isOn: launchAtLoginBinding) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Launch at Login")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(TITheme.primaryText)
                        Text("Start automatically when you log in")
                            .font(.system(size: 11))
                            .foregroundStyle(TITheme.tertiaryText)
                    }
                }
                .toggleStyle(.switch)
            }
            .padding(14)
            .tiPanel(cornerRadius: 14)

            Text("Claude hooks apply to new sessions after setup finishes; Codex and Gemini use passive local monitoring.")
                .font(.system(size: 11))
                .foregroundStyle(TITheme.tertiaryText)
        }
    }

    private var tour: some View {
        VStack(spacing: 14) {
            Text("Meet your pets")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(TITheme.primaryText)

            VStack(alignment: .leading, spacing: 10) {
                tourRow(phase: .idle, text: "Grey — open at its prompt, waiting for you to type")
                tourRow(phase: .working, text: "Blue — the agent is working (Reading, Writing, Running)")
                tourRow(phase: .ready, text: "Green — done and waiting for you; the completion pops from the notch")
                tourRow(phase: .waitingApproval, text: "Orange — needs an approval; answer with ⌃Y / ⌃N right in the notch")
            }
            .padding(16)
            .tiPanel(cornerRadius: 14)

            VStack(alignment: .leading, spacing: 6) {
                Text("Hover the notch for a status peek · click to open the panel")
                Text("Click a session to jump to its terminal · esc collapses")
            }
            .font(.system(size: 12))
            .foregroundStyle(TITheme.secondaryText)
        }
    }

    private func tourRow(phase: SessionPhase, text: String) -> some View {
        HStack(spacing: 10) {
            PetFrameView(species: .crab, frameIndex: 0, phase: phase, pixelSize: 2.6, glow: true)
            Text(text)
                .font(.system(size: 12.5))
                .foregroundStyle(TITheme.primaryText)
        }
    }

    private var boardingPass: some View {
        VStack(spacing: 16) {
            BoardingPassCard()
            Text("Welcome aboard")
                .font(.system(size: 24, weight: .bold, design: .monospaced))
                .foregroundStyle(TITheme.primaryText)
            Text("Run claude in any terminal, then watch the notch.")
                .font(.system(size: 12.5))
                .foregroundStyle(TITheme.secondaryText)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 12) {
            Button {
                advance()
            } label: {
                Text(step.buttonTitle)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 36)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(.white))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)

            HStack(spacing: 6) {
                ForEach(OnboardingStep.allCases) { item in
                    Circle()
                        .fill(item == step ? Color.white : Color.white.opacity(0.25))
                        .frame(width: 6, height: 6)
                }
            }
        }
        .padding(.bottom, 4)
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { appState.settings.launchAtLogin },
            set: { newValue in appState.updateSettings { $0.launchAtLogin = newValue } }
        )
    }

    private func advance() {
        if let next = step.next {
            withAnimation(.snappy(duration: 0.24)) { step = next }
        } else {
            appState.completeOnboarding()
            onFinish?()
        }
    }
}

/// Pixel-art boarding pass (reference "Welcome aboard" card): dithered dot
/// field, pet, EXPLORER / LANDED rows.
struct BoardingPassCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                DitherFieldView()
                    .frame(height: 130)
                PetFrameView(species: .runner, frameIndex: 0, phase: .waitingApproval, pixelSize: 4, glow: true)
            }
            .clipped()

            VStack(alignment: .leading, spacing: 7) {
                Text("EXPLORER")
                    .font(.system(size: 21, weight: .heavy, design: .monospaced))
                    .foregroundStyle(Color(red: 0.91, green: 0.45, blue: 0.95))
                Text("BOARDING_PASS")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(TITheme.tertiaryText)
                    .padding(.bottom, 5)
                passRow(label: "STATUS", value: "LANDED", highlighted: true)
                passRow(label: "JOINED", value: Date.now.formatted(.dateTime.day(.twoDigits).month(.twoDigits).year()), highlighted: false)
                passRow(label: "ACCESS", value: "FULL", highlighted: false)
            }
            .padding(16)

            HStack {
                Text("TOKEN ISLAND ▪ V1")
                Spacer()
                Text("WELCOME ABOARD")
            }
            .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
            .foregroundStyle(TITheme.tertiaryText)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .frame(width: 320)
        .background(Color(red: 0.075, green: 0.06, blue: 0.14))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(red: 0.45, green: 0.42, blue: 0.85).opacity(0.55), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: Color(red: 0.35, green: 0.3, blue: 0.9).opacity(0.35), radius: 22, y: 10)
    }

    private func passRow(label: String, value: String, highlighted: Bool) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(TITheme.tertiaryText)
                .frame(width: 52, alignment: .leading)
            Text(">")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(TITheme.tertiaryText)
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(highlighted ? Color.black : Color(red: 0.75, green: 0.72, blue: 0.98))
                .padding(.horizontal, highlighted ? 6 : 0)
                .padding(.vertical, highlighted ? 1.5 : 0)
                .background(highlighted ? Color(red: 0.91, green: 0.45, blue: 0.95) : Color.clear)
        }
    }
}

/// Deterministic dithered "world map" dot field (no assets).
struct DitherFieldView: View {
    var body: some View {
        Canvas { context, size in
            let cell: CGFloat = 7
            var seed: UInt64 = 0x9E37_79B9
            func random() -> Double {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                return Double((seed >> 33) & 0xFFFF) / 65_535.0
            }
            let columns = Int(size.width / cell)
            let rows = Int(size.height / cell)
            for row in 0..<rows {
                for column in 0..<columns {
                    let value = random()
                    // Denser at the edges, sparse center (leaves room for the pet).
                    let dx = abs(Double(column) / Double(columns) - 0.5)
                    let dy = abs(Double(row) / Double(rows) - 0.5)
                    let edgeBoost = (dx + dy)
                    guard value < 0.16 + edgeBoost * 0.55 else { continue }
                    let isPlus = value < 0.05
                    let x = CGFloat(column) * cell
                    let y = CGFloat(row) * cell
                    let color = Color(
                        red: 0.30 + value * 0.35,
                        green: 0.36 + value * 0.28,
                        blue: 0.85
                    ).opacity(0.30 + value * 0.7)
                    if isPlus {
                        context.fill(Path(CGRect(x: x + 1.5, y: y, width: 1.6, height: 4.6)), with: .color(color))
                        context.fill(Path(CGRect(x: x, y: y + 1.5, width: 4.6, height: 1.6)), with: .color(color))
                    } else {
                        context.fill(Path(CGRect(x: x + 1.6, y: y + 1.6, width: 1.8, height: 1.8)), with: .color(color))
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}
