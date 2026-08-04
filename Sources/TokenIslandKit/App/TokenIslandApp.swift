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

    public var body: some Scene {
        MenuBarExtra {
            MenuBarPopoverView()
                .environmentObject(appState)
                .preferredColorScheme(.dark)
        } label: {
            Label {
                Text(AppConstants.appName)
            } icon: {
                Image(nsImage: AppIconArt.menuBarIcon())
            }
        }
        .menuBarExtraStyle(.window)

        WindowGroup("TokenIsland Dashboard", id: "dashboard") {
            DashboardView()
                .environmentObject(appState)
                .preferredColorScheme(.dark)
                .frame(minWidth: 940, minHeight: 640)
                .task { await appState.start() }
        }
        .defaultSize(width: 1080, height: 720)

        Settings {
            SettingsView()
                .environmentObject(appState)
                .preferredColorScheme(.dark)
                .frame(width: 980, height: 700)
                .task { await appState.start() }
        }
    }
}
