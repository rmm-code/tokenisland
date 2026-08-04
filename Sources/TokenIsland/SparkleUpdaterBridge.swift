import Sparkle
import TokenIslandKit

/// Owns Sparkle's updater and hands the app an install action.
///
/// Sparkle lives in the executable, not in TokenIslandKit: the library stays
/// framework-free so `swift test` runs without an embedded Sparkle.framework,
/// and the app injects the capability at launch.
@MainActor
final class SparkleUpdaterBridge {
    private let controller: SPUStandardUpdaterController

    init() {
        // Sparkle does its own scheduled checks; ours drive the notch banner,
        // so background checking is left to the app's own poller and Sparkle
        // only runs when the user asks to install.
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        controller.updater.automaticallyChecksForUpdates = false
    }

    /// Presents Sparkle's download/verify/relaunch flow.
    func install() {
        controller.updater.checkForUpdates()
    }
}
