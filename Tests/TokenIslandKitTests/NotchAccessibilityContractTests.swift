import Foundation
import XCTest

final class NotchAccessibilityContractTests: XCTestCase {
    func testClickableNotchSurfacesExposeDefaultAccessibilityActions() throws {
        let notchSource = try sourceFile(
            "Sources/TokenIslandKit/Features/NotchUI/TokenIslandNotchView.swift"
        )
        let sessionCardSource = try sourceFile(
            "Sources/TokenIslandKit/Features/NotchUI/SessionCardView.swift"
        )

        XCTAssertTrue(
            notchSource.contains(".accessibilityAction") &&
                notchSource.contains("interactionController.handleClick()"),
            "The notch's click interaction must also be available to assistive technologies"
        )
        XCTAssertTrue(
            sessionCardSource.contains(".accessibilityAction") &&
                sessionCardSource.contains("onJump(session)"),
            "Session rows marked as buttons must expose a default accessibility action"
        )
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func sourceFile(_ relativePath: String) throws -> String {
        try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}
