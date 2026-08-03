import Foundation
import os

enum AppLog {
    static let app = Logger(subsystem: AppConstants.bundleIdentifier, category: "app")
    static let persistence = Logger(subsystem: AppConstants.bundleIdentifier, category: "persistence")
    static let telemetry = Logger(subsystem: AppConstants.bundleIdentifier, category: "telemetry")
    static let proxy = Logger(subsystem: AppConstants.bundleIdentifier, category: "proxy")
    static let windowing = Logger(subsystem: AppConstants.bundleIdentifier, category: "windowing")
}
