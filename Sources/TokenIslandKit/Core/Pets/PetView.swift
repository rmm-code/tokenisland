import SwiftUI

/// State → tint mapping shared by pets, cursor blocks, and status dots.
enum PetPalette {
    static func tint(for phase: SessionPhase) -> Color {
        switch phase {
        // Idle reads as "asleep": present, but clearly not one of the three
        // signal colors (blue working / green ready / orange needs you).
        case .idle: Color(red: 0.55, green: 0.60, blue: 0.70)
        case .working: Color(red: 0.38, green: 0.62, blue: 1.00)
        case .ready: Color(red: 0.38, green: 0.85, blue: 0.44)
        case .waitingApproval, .question: Color(red: 1.00, green: 0.72, blue: 0.30)
        case .error: Color(red: 1.00, green: 0.36, blue: 0.36)
        case .ended: Color.white.opacity(0.35)
        }
    }

    static func highlight(for phase: SessionPhase) -> Color {
        tint(for: phase).opacity(0.55)
    }
}

/// Nearest-neighbor pixel-art renderer for one pet frame. Pure drawing;
/// animation is driven by `AnimatedPetView`.
struct PetFrameView: View {
    var species: PetSpecies
    var frameIndex: Int
    var phase: SessionPhase
    var pixelSize: CGFloat
    var glow: Bool

    var body: some View {
        let frames = species.frames
        let frame = frames[frameIndex % frames.count]
        let grid = species.gridSize
        let tint = PetPalette.tint(for: phase)
        let highlight = PetPalette.highlight(for: phase)

        Canvas { context, _ in
            for (rowIndex, row) in frame.enumerated() {
                for (columnIndex, cell) in row.enumerated() where cell != 0 {
                    let rect = CGRect(
                        x: CGFloat(columnIndex) * pixelSize,
                        y: CGFloat(rowIndex) * pixelSize,
                        width: pixelSize,
                        height: pixelSize
                    )
                    context.fill(
                        Path(roundedRect: rect.insetBy(dx: pixelSize * 0.04, dy: pixelSize * 0.04), cornerRadius: pixelSize * 0.18),
                        with: .color(cell == 2 ? highlight : tint)
                    )
                }
            }
        }
        .frame(
            width: CGFloat(grid.columns) * pixelSize,
            height: CGFloat(grid.rows) * pixelSize
        )
        .shadow(color: glow ? tint.opacity(0.75) : .clear, radius: glow ? 2.5 : 0)
        .accessibilityHidden(true)
    }
}

/// Time-driven pet: flips frames at a low FPS, pausing under Reduce Motion
/// or when the session is no longer active.
struct AnimatedPetView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var species: PetSpecies
    var phase: SessionPhase
    var pixelSize: CGFloat = 2
    var glow: Bool = true

    private var animates: Bool {
        !reduceMotion && phase.isActive
    }

    var body: some View {
        if animates {
            TimelineView(.periodic(from: .now, by: 0.45)) { timeline in
                let tick = Int(timeline.date.timeIntervalSinceReferenceDate / 0.45)
                PetFrameView(
                    species: species,
                    frameIndex: tick,
                    phase: phase,
                    pixelSize: pixelSize,
                    glow: glow
                )
            }
        } else {
            PetFrameView(species: species, frameIndex: 0, phase: phase, pixelSize: pixelSize, glow: glow)
        }
    }
}

/// The blinking terminal-caret block that accompanies a pet on session cards.
struct CursorBlockView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var phase: SessionPhase
    var size: CGSize = CGSize(width: 5, height: 12)

    var body: some View {
        let tint = PetPalette.tint(for: phase)
        if reduceMotion || !phase.isActive {
            RoundedRectangle(cornerRadius: 1)
                .fill(tint)
                .frame(width: size.width, height: size.height)
                .accessibilityHidden(true)
        } else {
            TimelineView(.periodic(from: .now, by: 0.55)) { timeline in
                let visible = Int(timeline.date.timeIntervalSinceReferenceDate / 0.55) % 2 == 0
                RoundedRectangle(cornerRadius: 1)
                    .fill(tint.opacity(visible ? 1 : 0.25))
                    .frame(width: size.width, height: size.height)
            }
            .accessibilityHidden(true)
        }
    }
}

/// Pet + cursor pair used on session cards and in the collapsed strip.
struct SessionPetBadge: View {
    var session: AgentSession
    var pixelSize: CGFloat = 2
    var showCursor: Bool = true

    var body: some View {
        HStack(spacing: 4) {
            AnimatedPetView(
                species: PetSpecies.assigned(toSessionID: session.id),
                phase: session.phase,
                pixelSize: pixelSize
            )
            if showCursor {
                CursorBlockView(phase: session.phase, size: CGSize(width: pixelSize * 2.4, height: pixelSize * 5.6))
            }
        }
    }
}
