import SwiftUI

/// Multiple-choice question card for Claude's `AskUserQuestion`: the question
/// text plus numbered option buttons. Tapping an option (or ⌃1–9) focuses the
/// session's terminal and types the digit; "Answer in terminal" is the
/// fallback when injection is unavailable or the options didn't decode.
struct QuestionCardView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    var session: AgentSession
    var onJump: (AgentSession) -> Void

    private var message: String {
        session.pendingQuestionMessage ?? "Claude has a question"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "questionmark.bubble.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(TITheme.warning)
                Text(message)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(TITheme.primaryText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !session.questionOptions.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(session.questionOptions.enumerated()), id: \.offset) { index, label in
                        optionButton(number: index + 1, label: label)
                    }
                }
            }

            HStack(spacing: 8) {
                if !session.questionOptions.isEmpty {
                    Text("⌃1–9")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(TITheme.tertiaryText)
                }
                Spacer()
                fallbackButton
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(TITheme.warning.opacity(0.09))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(TITheme.warning.opacity(0.30), lineWidth: 1)
        )
    }

    private func optionButton(number: Int, label: String) -> some View {
        Button {
            sessionStore.onAnswerQuestion?(session, number)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(number)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(TITheme.warning)
                Text("· \(label)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(TITheme.primaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.white.opacity(0.10))
            )
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .accessibilityLabel("Option \(number): \(label)")
    }

    private var fallbackButton: some View {
        Button {
            onJump(session)
        } label: {
            HStack(spacing: 5) {
                Text("Answer in terminal")
                    .font(.system(size: 11, weight: .semibold))
                Text("⌃T")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .opacity(0.6)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.white.opacity(0.12)))
            .foregroundStyle(TITheme.primaryText)
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
    }
}
