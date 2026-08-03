import Foundation
import XCTest

final class InteractionSafetyTests: XCTestCase {
    func testQuestionAnswerRequiresExactSessionFocusBeforeTyping() throws {
        let jumpSource = try sourceFile(
            "Sources/TokenIslandKit/Core/Jump/JumpService.swift"
        )
        let injectionSource = try sourceFile(
            "Sources/TokenIslandKit/Core/Jump/KeyInjection.swift"
        )
        let controllerSource = try sourceFile(
            "Sources/TokenIslandKit/Core/Windowing/TokenIslandWindowController.swift"
        )
        let inputFocus = try sourceSection(
            jumpSource,
            beginningWith: "func focusForInput",
            endingBefore: "func jump"
        )
        let answerQuestion = try sourceSection(
            controllerSource,
            beginningWith: "private func answerQuestion",
            endingBefore: "/// ⌣Y approve"
        )

        XCTAssertTrue(
            jumpSource.contains("enum JumpResult"),
            "JumpService must distinguish exact session focus from app-only activation"
        )
        XCTAssertTrue(
            jumpSource.contains("case exactSession") && jumpSource.contains("case applicationOnly"),
            "Jump results need separate exact-session and app-only outcomes"
        )
        XCTAssertNotNil(
            answerQuestion.range(
                of: #"guard\s+jumpService\.focusForInput\(to:\s*session\)\s+else\s*\{\s*return\s*\}"#,
                options: .regularExpression
            ),
            "Question answers must not inject keystrokes unless the exact terminal session was focused"
        )
        XCTAssertFalse(inputFocus.contains("JumpRules"))
        XCTAssertFalse(inputFocus.contains("projectName"))
        XCTAssertFalse(inputFocus.contains("app.activate"))
        XCTAssertFalse(
            injectionSource.contains("Task.sleep"),
            "Digit and Return must be emitted as one immediate operation after exact focus is established"
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

    private func sourceSection(
        _ source: String,
        beginningWith startMarker: String,
        endingBefore endMarker: String
    ) throws -> String {
        guard let start = source.range(of: startMarker) else {
            throw TestSourceError.missingMarker(startMarker)
        }
        let end = source.range(
            of: endMarker,
            range: start.upperBound..<source.endIndex
        )?.lowerBound ?? source.endIndex
        return String(source[start.lowerBound..<end])
    }

    private enum TestSourceError: Error {
        case missingMarker(String)
    }
}
