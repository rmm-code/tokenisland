import Foundation
@testable import TokenIslandKit
import XCTest

/// `pixelSize` is per-pixel, so a species' on-screen footprint is its grid
/// times that size. A species drawn on a bigger grid is simply a bigger pet —
/// which is how the crab ended up rendering at nearly twice the width of every
/// other species in the panel.
final class PetSpriteTests: XCTestCase {
    func testAllSpeciesShareAComparableFootprint() {
        let extents = PetSpecies.allCases.map { species -> (PetSpecies, Int, Int) in
            let grid = species.gridSize
            return (species, grid.columns, grid.rows)
        }
        let widths = extents.map(\.1)
        let heights = extents.map(\.2)

        // Half again as wide as the narrowest species is the most a pet may be
        // before it visually dominates a row of them.
        let describe = extents.map { "\($0.0.rawValue) \($0.1)x\($0.2)" }.joined(separator: ", ")
        XCTAssertLessThanOrEqual(
            Double(widths.max() ?? 0) / Double(widths.min() ?? 1), 1.5,
            "pet widths are out of balance: \(describe)"
        )
        XCTAssertLessThanOrEqual(
            Double(heights.max() ?? 0) / Double(heights.min() ?? 1), 1.5,
            "pet heights are out of balance: \(describe)"
        )
    }

    func testEveryFrameIsRectangularAndMatchesItsSpeciesGrid() {
        for species in PetSpecies.allCases {
            let grid = species.gridSize
            XCTAssertFalse(species.frames.isEmpty, "\(species.rawValue) has no frames")
            for (index, frame) in species.frames.enumerated() {
                XCTAssertEqual(frame.count, grid.rows, "\(species.rawValue) frame \(index) row count")
                for (rowIndex, row) in frame.enumerated() {
                    // A short row silently shifts every pixel after it.
                    XCTAssertEqual(
                        row.count, grid.columns,
                        "\(species.rawValue) frame \(index) row \(rowIndex) is ragged"
                    )
                }
            }
        }
    }

    /// Two frames that are identical read as a frozen pet, not a walking one.
    func testEverySpeciesActuallyAnimates() {
        for species in PetSpecies.allCases {
            let frames = species.frames
            XCTAssertGreaterThanOrEqual(frames.count, 2, "\(species.rawValue) needs a second frame")
            XCTAssertNotEqual(frames[0], frames[1], "\(species.rawValue) frames are identical")
        }
    }

    func testSpeciesAssignmentIsStablePerSession() {
        let id = "sess-1234-abcd"
        XCTAssertEqual(PetSpecies.assigned(toSessionID: id), PetSpecies.assigned(toSessionID: id))
    }
}
