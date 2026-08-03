import XCTest
@testable import TokenIslandKit

final class NotificationServiceTests: XCTestCase {
    func testUserNotificationsAreDisabledForSwiftRunExecutable() {
        let swiftRunURL = URL(fileURLWithPath: "/tmp/TokenIsland/.build/arm64-apple-macosx/debug")

        XCTAssertFalse(NotificationService.canUseUserNotifications(bundleURL: swiftRunURL, bundleIdentifier: nil))
    }

    func testUserNotificationsAreEnabledForAppBundle() {
        let appURL = URL(fileURLWithPath: "/Applications/TokenIsland.app")

        XCTAssertTrue(NotificationService.canUseUserNotifications(bundleURL: appURL, bundleIdentifier: "com.tokenisland.app"))
    }
}
