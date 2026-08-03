import Foundation

/// Reads a repository's current branch without spawning git: `.git/HEAD`
/// (following the `gitdir:` pointer for worktrees). Cheap enough to run on
/// every transcript refresh; nil for non-repos.
enum GitBranchReader {
    static func branch(forRepositoryAt path: String) -> String? {
        guard !path.isEmpty else { return nil }
        let fileManager = FileManager.default
        var gitURL = URL(fileURLWithPath: path).appendingPathComponent(".git")

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: gitURL.path, isDirectory: &isDirectory) else {
            return nil
        }
        if !isDirectory.boolValue {
            // Worktree checkout: `.git` is a file "gitdir: /main/.git/worktrees/x".
            guard let contents = try? String(contentsOf: gitURL, encoding: .utf8),
                  let range = contents.range(of: "gitdir:")
            else { return nil }
            let target = contents[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            gitURL = URL(
                fileURLWithPath: target,
                relativeTo: URL(fileURLWithPath: path)
            ).standardizedFileURL
        }

        let headURL = gitURL.appendingPathComponent("HEAD")
        guard let head = try? String(contentsOf: headURL, encoding: .utf8) else { return nil }
        let trimmed = head.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.hasPrefix("ref: ") {
            return trimmed.components(separatedBy: "/").last
        }
        // Detached HEAD — short commit hash.
        return trimmed.isEmpty ? nil : String(trimmed.prefix(7))
    }
}
