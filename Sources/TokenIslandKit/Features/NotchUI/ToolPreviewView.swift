import SwiftUI

/// Structured preview rendered inside an approval card: dark monospaced
/// command block for Bash, a red/green diff for Edit, path + content for
/// Write. Compact and non-scrolling — capped height, clipped overflow.
struct ToolPreviewView: View {
    var preview: ToolCallPreview

    /// Max lines shown per diff side / code block.
    private static let maxLines = 6
    private static let maxHeight: CGFloat = 120

    var body: some View {
        Group {
            switch preview.kind {
            case .bashCommand(let command):
                codeBlock(command)
            case .editDiff(let path, let old, let new):
                VStack(alignment: .leading, spacing: 4) {
                    pathCaption(path)
                    diffBlock(old: old, new: new)
                }
            case .writeFile(let path, let content):
                VStack(alignment: .leading, spacing: 4) {
                    pathCaption(path)
                    codeBlock(content)
                }
            case .generic(let detail):
                codeBlock(detail)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxHeight: Self.maxHeight, alignment: .top)
        .clipped()
    }

    // MARK: - Pieces

    private func pathCaption(_ path: String) -> some View {
        Text(path)
            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
            .foregroundStyle(TITheme.tertiaryText)
            .lineLimit(1)
            .truncationMode(.middle)
    }

    /// Compact SetupCommandBox-style block (dark, monospaced, no copy row).
    private func codeBlock(_ text: String) -> some View {
        Text(Self.clamp(text, lines: Self.maxLines))
            .font(.system(size: 10.5, design: .monospaced))
            .foregroundStyle(TITheme.primaryText.opacity(0.9))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.38), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
    }

    /// Naive old-then-new diff: strips lines the two blocks share at their
    /// edges, then shows removals ("-") above additions ("+").
    private func diffBlock(old: String, new: String) -> some View {
        let (removed, added) = Self.diffLines(old: old, new: new)
        return VStack(alignment: .leading, spacing: 1) {
            ForEach(Array(removed.enumerated()), id: \.offset) { _, line in
                diffLine(line, marker: "-", tint: TITheme.danger)
            }
            ForEach(Array(added.enumerated()), id: \.offset) { _, line in
                diffLine(line, marker: "+", tint: PetPalette.tint(for: .ready))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(4)
        .background(Color.black.opacity(0.38), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func diffLine(_ line: String, marker: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 5) {
            Text(marker)
                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                .foregroundStyle(tint)
            Text(line.isEmpty ? " " : line)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(TITheme.primaryText.opacity(0.9))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
        .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 3, style: .continuous))
    }

    // MARK: - Helpers

    /// Trims common leading/trailing lines so only the changed core shows,
    /// each side capped at `maxLines` with an ellipsis marker.
    static func diffLines(old: String, new: String) -> (removed: [String], added: [String]) {
        var oldLines = old.components(separatedBy: "\n")
        var newLines = new.components(separatedBy: "\n")
        while let first = oldLines.first, first == newLines.first,
              oldLines.count > 1 || newLines.count > 1 {
            oldLines.removeFirst()
            newLines.removeFirst()
        }
        while let last = oldLines.last, last == newLines.last,
              oldLines.count > 1 || newLines.count > 1 {
            oldLines.removeLast()
            newLines.removeLast()
        }
        func capped(_ lines: [String]) -> [String] {
            let visible = lines.filter { !(lines.count == 1 && $0.isEmpty) }
            guard visible.count > maxLines else { return visible }
            return Array(visible.prefix(maxLines - 1)) + ["… \(visible.count - maxLines + 1) more lines"]
        }
        return (capped(oldLines), capped(newLines))
    }

    /// Caps a text block at `lines` lines, appending an overflow marker.
    static func clamp(_ text: String, lines: Int) -> String {
        let all = text.components(separatedBy: "\n")
        guard all.count > lines else { return text }
        return all.prefix(lines).joined(separator: "\n") + "\n… \(all.count - lines) more lines"
    }
}
