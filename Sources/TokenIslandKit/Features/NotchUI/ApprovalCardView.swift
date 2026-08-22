import SwiftUI

/// Approval prompt rendered under a session that is waiting on a permission
/// (or question). Approve/Deny wiring arrives with the approval round-trip
/// (P5); until handlers are provided the card offers jump-to-terminal.
struct ApprovalCardView: View {
    @EnvironmentObject private var approvalCenter: ApprovalCenter
    var session: AgentSession
    var onJump: (AgentSession) -> Void

    private var pendingApproval: PendingApproval? {
        approvalCenter.pendingApproval(forSessionID: session.id)
    }

    private var message: String {
        session.pendingApprovalMessage
            ?? session.pendingQuestionMessage
            ?? "Waiting for your approval"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(TITheme.warning)
                Text(message)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(TITheme.primaryText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let preview = session.pendingApprovalPreview {
                ToolPreviewView(preview: preview)
            }

            HStack(spacing: 8) {
                if let approval = pendingApproval {
                    approvalButton(title: "Deny", hint: "⌃N", prominent: false) {
                        approvalCenter.deny(id: approval.id)
                    }
                    approvalButton(title: "Allow", hint: "⌃Y", prominent: true) {
                        approvalCenter.approve(id: approval.id)
                    }
                    approvalButton(title: "Always", hint: "⌃A", prominent: false) {
                        approvalCenter.alwaysAllow(id: approval.id)
                    }
                } else {
                    // No held request to answer: either native-approval mode,
                    // or a Notification-driven prompt the CLI owns. Say which,
                    // so "Answer in terminal" does not read as a failure of the
                    // notch to offer the verdict buttons.
                    approvalButton(title: "Answer in terminal", hint: "⌃T", prominent: true) {
                        onJump(session)
                    }
                    if session.pendingApprovalSource == .terminalOnly {
                        Text("asked in its terminal")
                            .font(.system(size: 10))
                            .foregroundStyle(TITheme.tertiaryText)
                    }
                }
                Spacer()
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

    private func approvalButton(
        title: String,
        hint: String,
        prominent: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                Text(hint)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .opacity(0.6)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(prominent ? Color.white : Color.white.opacity(0.12))
            )
            .foregroundStyle(prominent ? Color.black : TITheme.primaryText)
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
    }
}
