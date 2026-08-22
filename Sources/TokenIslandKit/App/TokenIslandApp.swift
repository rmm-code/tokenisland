import SwiftUI

/// The one seam the executable needs. Sparkle is linked there, not here, so
/// the library stays framework-free and testable — the app hands its installer
/// in before the environment is built.
public enum TokenIslandLaunch {
    @MainActor
    public static func setUpdateInstaller(_ handler: @escaping () -> Void) {
        AppEnvironment.updateInstaller = handler
    }
}

public struct TokenIslandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState: AppState
    private let environment: AppEnvironment

    public init() {
        let environment = AppEnvironment.production()
        self.environment = environment
        _appState = StateObject(wrappedValue: environment.appState)
        AppDelegate.environment = environment
    }

    /// Only the Settings scene lives here. The menu bar icon is an
    /// `NSStatusItem` (`StatusItemController`) so a click can open the
    /// dashboard directly instead of a popover, and the dashboard window is
    /// opened by `AppWindowRouter` — a `WindowGroup` would also open itself at
    /// launch, which an accessory app must not do.
    public var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(appState)
                .preferredColorScheme(.dark)
                .frame(width: 980, height: 700)
                .task { await appState.start() }
        }
    }
}
