import Foundation

/// Pixel-art creature species. Each species is a set of 2-frame bitmaps on a
/// small logical grid; `1` = body pixel, `2` = highlight pixel. Species are
/// assigned per session (stable across refreshes) so a session keeps its pet.
enum PetSpecies: String, CaseIterable, Sendable {
    case crab
    case blob
    case runner
    case bit

    /// Deterministic assignment from a session identifier.
    static func assigned(toSessionID id: String) -> PetSpecies {
        let all = PetSpecies.allCases
        var hash: UInt64 = 5381
        for byte in id.utf8 {
            hash = (hash &* 33) &+ UInt64(byte)
        }
        return all[Int(hash % UInt64(all.count))]
    }

    /// Animation frames as pixel rows. All frames within a species share the
    /// same grid size.
    var frames: [[[UInt8]]] {
        switch self {
        case .crab: Self.crabFrames
        case .blob: Self.blobFrames
        case .runner: Self.runnerFrames
        case .bit: Self.bitFrames
        }
    }

    var gridSize: (columns: Int, rows: Int) {
        let frame = frames[0]
        return (frame.first?.count ?? 1, frame.count)
    }

    // MARK: - Bitmaps

    /// Invader with antennae and walking legs — the reference app's signature
    /// silhouette. Drawn on a 7x7 grid so it sits at the same visual size as
    /// its siblings: `pixelSize` is per-pixel, so a wider grid is a bigger pet,
    /// and at 11x8 this one rendered nearly twice the width of every other
    /// species. Shrinking it in the renderer instead would have blurred its
    /// details while the chunky species stayed crisp.
    private static let crabFrames: [[[UInt8]]] = [
        parse([
            "..1.1..",
            ".11111.",
            "1121211",
            "1111111",
            ".11111.",
            ".1...1.",
            "1.....1"
        ]),
        parse([
            "..1.1..",
            ".11111.",
            "1121211",
            "1111111",
            ".11111.",
            "..1.1..",
            ".1...1."
        ])
    ]

    /// Small round ghost/blob.
    private static let blobFrames: [[[UInt8]]] = [
        parse([
            ".1111.",
            "122221",
            "121121",
            "122221",
            "111111",
            "1.11.1"
        ]),
        parse([
            ".1111.",
            "122221",
            "121121",
            "122221",
            "111111",
            ".1..1."
        ])
    ]

    /// Tiny biped runner.
    private static let runnerFrames: [[[UInt8]]] = [
        parse([
            ".111.",
            ".121.",
            "11111",
            ".111.",
            ".1.1.",
            "1...1"
        ]),
        parse([
            ".111.",
            ".121.",
            "11111",
            ".111.",
            ".11..",
            "..11."
        ])
    ]

    /// Square bug with blinking core.
    private static let bitFrames: [[[UInt8]]] = [
        parse([
            "1.1.1",
            ".111.",
            "11211",
            ".111.",
            "1.1.1"
        ]),
        parse([
            ".1.1.",
            "11111",
            "1.2.1",
            "11111",
            ".1.1."
        ])
    ]

    /// "." → empty, "1" → body, "2"/"Y" → highlight.
    private static func parse(_ rows: [String]) -> [[UInt8]] {
        rows.map { row in
            row.map { character in
                switch character {
                case "1": 1
                case "2", "Y": 2
                default: 0
                }
            }
        }
    }
}
