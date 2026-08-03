import Foundation

enum PrivacyMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case metadataOnly
    case storePrompts

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .metadataOnly:
            "Metadata only"
        case .storePrompts:
            "Legacy prompt storage"
        }
    }
}

enum FullscreenOverlayMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case never
    case notchedScreens
    case always

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .never:
            "Never"
        case .notchedScreens:
            "On notched screens"
        case .always:
            "Always"
        }
    }
}

enum CompactWidthMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case tight
    case balanced
    case wide

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tight:
            "Tight"
        case .balanced:
            "Balanced"
        case .wide:
            "Wide"
        }
    }

    var widthDelta: CGFloat {
        switch self {
        case .tight:
            -34
        case .balanced:
            0
        case .wide:
            46
        }
    }
}

struct UsageMetadataStorageOptions: Equatable, Sendable {
    var storePromptText: Bool
    var storeSourceApp: Bool
    var storeProjectPath: Bool
    var storeRawMetadataJSON: Bool

    static let defaults = UsageMetadataStorageOptions(
        storePromptText: false,
        storeSourceApp: true,
        storeProjectPath: true,
        storeRawMetadataJSON: false
    )
}

struct AppSettings: Codable, Equatable, Sendable {
    var hasCompletedOnboarding: Bool
    var showNotchOverlay: Bool
    var expandOnHover: Bool
    /// Detailed strip mode shows a status word next to the pets (reference:
    /// Display → Clean vs Detailed).
    var notchDetailedMode: Bool
    /// When true, clicking a session card won't switch to its terminal.
    var disableClickToJump: Bool

    // MARK: Session monitor v2 (Vibe Island parity)

    /// Auto-hide the strip when there are no active sessions.
    var autoHideWhenNoSessions: Bool
    /// Skip auto-expand when the session's own terminal is frontmost.
    var smartSuppression: Bool
    /// Seconds a completion/warning reveal stays open (ESC closes sooner).
    var autoRevealDwellSeconds: Double
    /// Close reveals when clicking anywhere outside the panel.
    var dismissRevealOnOutsideClick: Bool
    /// Hours before sessions without a close signal are dropped.
    var idleCleanupHours: Double
    /// Install hooks for newly detected CLIs automatically.
    var autoConfigureNewCLIs: Bool
    /// Own the terminal title with our session marker (jump precision).
    var enableTitleMarkers: Bool
    /// Session card fields.
    var showProjectName: Bool
    var showWorktree: Bool
    var showAIModel: Bool
    var showSubagents: Bool
    var showAgentActivityDetail: Bool
    /// Panel sizing.
    var contentFontSize: Double
    var completionCardHeight: Double
    var maxPanelHeight: Double
    var maxPanelWidth: Double
    /// Sounds.
    var soundEnabled: Bool
    var soundVolume: Double
    var soundSessionStart: Bool
    var soundTaskComplete: Bool
    var soundTaskError: Bool
    var soundApprovalNeeded: Bool
    var soundTaskAcknowledge: Bool
    var soundContextLimit: Bool
    var soundIdleReminder: Bool
    /// Quiet scenes: no auto-expand/sound while active.
    var quietWhenScreenLocked: Bool
    var quietWhenScreenSharing: Bool
    /// Labs.
    var useNativeClaudeApprovals: Bool
    var useAutoModeInsteadOfBypass: Bool
    var approvalHoldSeconds: Double
    /// Usage limits header.
    var showUsageLimitsHeader: Bool
    var usageDisplayValueRemaining: Bool
    /// Phase-2 parity (P9–P12).
    var enableCodexMonitoring: Bool
    var enableGeminiMonitoring: Bool
    /// "builtin" | "main" | "focus" — which display hosts the island.
    var displayTarget: String
    /// "immediately" | "withMainAgent" | "never" — subagent completion reveals.
    var subagentNotificationMode: String
    /// Bundle identifiers whose launched sessions are dropped.
    var blockedLauncherApps: [String]
    /// "chip" | "soft" — SoundBank timbre.
    var soundPack: String
    var pinExpandedNotch: Bool
    var fullscreenOverlayMode: FullscreenOverlayMode
    var preventCloseOnMouseLeave: Bool
    var lockWhileInteracting: Bool
    var enableHaptics: Bool
    var contentPadding: Double
    var notchWidthAdjustment: Double
    var notchHeightAdjustment: Double
    var enableNonNotchFallback: Bool
    var fallbackHandlerWidth: Double
    var fallbackHandlerHeight: Double
    var fallbackHandlerIsTransparent: Bool
    var demoMode: Bool
    var allowHoverGestures: Bool
    var enableVerticalGestures: Bool
    var enableHorizontalGestures: Bool
    var invertHorizontalGestures: Bool
    var enableClickToExpand: Bool
    var hoverOpenDelayMS: Int
    var mouseLeaveCloseDelayMS: Int
    var enableLiveActivities: Bool
    var hideLiveActivitiesOnNonNotchedScreens: Bool
    var liveActivityInactivityTimeoutSeconds: Int
    var enableInteractiveActivities: Bool
    var enableQuickPeek: Bool
    var unhideAutomatically: Bool
    var showRequestCompletionActivity: Bool
    var showThresholdAlerts: Bool
    var showErrorAlerts: Bool
    var showSourceConnectionAlerts: Bool
    var showActiveRequestInFullscreen: Bool
    var showRequestCompletedInFullscreen: Bool
    var showErrorAlertsInFullscreen: Bool
    var showThresholdAlertsInFullscreen: Bool
    var showDailySummaryInFullscreen: Bool
    var showCompactProviderIcons: Bool
    var showCompactTotalTokens: Bool
    var showCompactProgressLine: Bool
    var showCompactActiveIndicator: Bool
    var showCompactCost: Bool
    var compactWidthMode: CompactWidthMode
    var showHoverProviderSplit: Bool
    var showHoverTodayTotals: Bool
    var showHoverActiveRequestPreview: Bool
    var showHoverRecentRequestSummary: Bool
    var showExpandedProviderRows: Bool
    var showExpandedTokenPercentages: Bool
    var showExpandedEstimatedCost: Bool
    var showExpandedRecentRequests: Bool
    var showExpandedCurrentSource: Bool
    var showExpandedSettingsShortcut: Bool
    var showExpandedQuickActions: Bool
    var showClaudeProviderRow: Bool
    var showGPTProviderRow: Bool
    var showProviderPercentages: Bool
    var showProviderTokenTotals: Bool
    var showProviderProgressLines: Bool
    var showModelNameWhenActive: Bool
    var preferRoundButtons: Bool
    var useTranslucentNotchBackground: Bool
    var shadowIntensity: Double
    var islandCornerRadius: Double
    var animationSpeed: Double
    var enableClaudeTracking: Bool
    var enableGPTCodexTracking: Bool
    var useCodexTelemetry: Bool
    var useOpenAIProxySource: Bool
    var preferTelemetryOverProxy: Bool
    var mergeDuplicateEvents: Bool
    var trackSourceApp: Bool
    var trackProjectPath: Bool
    var enableDebugPayloadStorage: Bool
    var storeProjectPathIfAvailable: Bool
    var storeSourceAppIfAvailable: Bool
    var autoCheckForUpdates: Bool
    var enableOTLPReceiver: Bool
    var otlpPort: UInt16
    var enableOpenAIProxy: Bool
    var proxyPort: UInt16
    var openAIBaseURL: URL
    var privacyMode: PrivacyMode
    var dailyTokenThreshold: Int
    var dailyCostThresholdUSD: Decimal
    var enableThresholdNotifications: Bool
    var launchAtLogin: Bool
    var debugMode: Bool

    static let defaults = AppSettings(
        hasCompletedOnboarding: false,
        showNotchOverlay: true,
        expandOnHover: true,
        notchDetailedMode: true,
        disableClickToJump: false,
        autoHideWhenNoSessions: false,
        smartSuppression: true,
        autoRevealDwellSeconds: 5,
        dismissRevealOnOutsideClick: false,
        idleCleanupHours: 2,
        autoConfigureNewCLIs: true,
        enableTitleMarkers: true,
        showProjectName: true,
        showWorktree: true,
        showAIModel: true,
        showSubagents: true,
        showAgentActivityDetail: true,
        contentFontSize: 11,
        completionCardHeight: 80,
        maxPanelHeight: 560,
        maxPanelWidth: 640,
        soundEnabled: true,
        soundVolume: 0.3,
        soundSessionStart: true,
        soundTaskComplete: true,
        soundTaskError: true,
        soundApprovalNeeded: true,
        soundTaskAcknowledge: false,
        soundContextLimit: true,
        soundIdleReminder: false,
        quietWhenScreenLocked: true,
        quietWhenScreenSharing: false,
        useNativeClaudeApprovals: false,
        useAutoModeInsteadOfBypass: false,
        approvalHoldSeconds: 55,
        showUsageLimitsHeader: true,
        usageDisplayValueRemaining: false,
        enableCodexMonitoring: true,
        enableGeminiMonitoring: true,
        displayTarget: "builtin",
        subagentNotificationMode: "withMainAgent",
        blockedLauncherApps: [],
        soundPack: "chip",
        pinExpandedNotch: false,
        fullscreenOverlayMode: .notchedScreens,
        preventCloseOnMouseLeave: false,
        lockWhileInteracting: true,
        enableHaptics: false,
        contentPadding: 17,
        notchWidthAdjustment: 0,
        notchHeightAdjustment: 0,
        enableNonNotchFallback: true,
        fallbackHandlerWidth: 170,
        fallbackHandlerHeight: 34,
        fallbackHandlerIsTransparent: false,
        demoMode: false,
        allowHoverGestures: true,
        enableVerticalGestures: true,
        enableHorizontalGestures: true,
        invertHorizontalGestures: false,
        enableClickToExpand: true,
        hoverOpenDelayMS: 50,
        mouseLeaveCloseDelayMS: 420,
        enableLiveActivities: true,
        hideLiveActivitiesOnNonNotchedScreens: false,
        liveActivityInactivityTimeoutSeconds: 4,
        enableInteractiveActivities: true,
        enableQuickPeek: true,
        unhideAutomatically: true,
        showRequestCompletionActivity: true,
        showThresholdAlerts: true,
        showErrorAlerts: true,
        showSourceConnectionAlerts: true,
        showActiveRequestInFullscreen: true,
        showRequestCompletedInFullscreen: true,
        showErrorAlertsInFullscreen: true,
        showThresholdAlertsInFullscreen: true,
        showDailySummaryInFullscreen: false,
        showCompactProviderIcons: true,
        showCompactTotalTokens: true,
        showCompactProgressLine: true,
        showCompactActiveIndicator: true,
        showCompactCost: false,
        compactWidthMode: .balanced,
        showHoverProviderSplit: true,
        showHoverTodayTotals: true,
        showHoverActiveRequestPreview: true,
        showHoverRecentRequestSummary: false,
        showExpandedProviderRows: true,
        showExpandedTokenPercentages: true,
        showExpandedEstimatedCost: true,
        showExpandedRecentRequests: true,
        showExpandedCurrentSource: true,
        showExpandedSettingsShortcut: true,
        showExpandedQuickActions: true,
        showClaudeProviderRow: true,
        showGPTProviderRow: true,
        showProviderPercentages: true,
        showProviderTokenTotals: true,
        showProviderProgressLines: true,
        showModelNameWhenActive: true,
        preferRoundButtons: true,
        useTranslucentNotchBackground: false,
        shadowIntensity: 0.58,
        islandCornerRadius: 32,
        animationSpeed: 1,
        enableClaudeTracking: true,
        enableGPTCodexTracking: true,
        useCodexTelemetry: true,
        useOpenAIProxySource: false,
        preferTelemetryOverProxy: true,
        mergeDuplicateEvents: true,
        trackSourceApp: true,
        trackProjectPath: true,
        enableDebugPayloadStorage: false,
        storeProjectPathIfAvailable: true,
        storeSourceAppIfAvailable: true,
        autoCheckForUpdates: true,
        enableOTLPReceiver: false,
        otlpPort: AppConstants.defaultOTLPPort,
        enableOpenAIProxy: false,
        proxyPort: AppConstants.defaultProxyPort,
        openAIBaseURL: URL(string: "https://api.openai.com")!,
        privacyMode: .metadataOnly,
        dailyTokenThreshold: 2_000_000,
        dailyCostThresholdUSD: 25,
        enableThresholdNotifications: false,
        launchAtLogin: false,
        debugMode: false
    )

    var storesPromptText: Bool {
        false
    }

    var metadataStorageOptions: UsageMetadataStorageOptions {
        UsageMetadataStorageOptions(
            storePromptText: storesPromptText,
            storeSourceApp: trackSourceApp && storeSourceAppIfAvailable,
            storeProjectPath: trackProjectPath && storeProjectPathIfAvailable,
            storeRawMetadataJSON: enableDebugPayloadStorage || debugMode
        )
    }
}

extension AppSettings {
    init(from decoder: Decoder) throws {
        let defaults = AppSettings.defaults
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hasCompletedOnboarding = container.decode(.hasCompletedOnboarding, default: defaults.hasCompletedOnboarding)
        showNotchOverlay = container.decode(.showNotchOverlay, default: defaults.showNotchOverlay)
        expandOnHover = container.decode(.expandOnHover, default: defaults.expandOnHover)
        notchDetailedMode = container.decode(.notchDetailedMode, default: defaults.notchDetailedMode)
        disableClickToJump = container.decode(.disableClickToJump, default: defaults.disableClickToJump)
        autoHideWhenNoSessions = container.decode(.autoHideWhenNoSessions, default: defaults.autoHideWhenNoSessions)
        smartSuppression = container.decode(.smartSuppression, default: defaults.smartSuppression)
        autoRevealDwellSeconds = container.decode(.autoRevealDwellSeconds, default: defaults.autoRevealDwellSeconds)
        dismissRevealOnOutsideClick = container.decode(.dismissRevealOnOutsideClick, default: defaults.dismissRevealOnOutsideClick)
        idleCleanupHours = container.decode(.idleCleanupHours, default: defaults.idleCleanupHours)
        autoConfigureNewCLIs = container.decode(.autoConfigureNewCLIs, default: defaults.autoConfigureNewCLIs)
        enableTitleMarkers = container.decode(.enableTitleMarkers, default: defaults.enableTitleMarkers)
        showProjectName = container.decode(.showProjectName, default: defaults.showProjectName)
        showWorktree = container.decode(.showWorktree, default: defaults.showWorktree)
        showAIModel = container.decode(.showAIModel, default: defaults.showAIModel)
        showSubagents = container.decode(.showSubagents, default: defaults.showSubagents)
        showAgentActivityDetail = container.decode(.showAgentActivityDetail, default: defaults.showAgentActivityDetail)
        contentFontSize = container.decode(.contentFontSize, default: defaults.contentFontSize)
        completionCardHeight = container.decode(.completionCardHeight, default: defaults.completionCardHeight)
        maxPanelHeight = container.decode(.maxPanelHeight, default: defaults.maxPanelHeight)
        maxPanelWidth = container.decode(.maxPanelWidth, default: defaults.maxPanelWidth)
        soundEnabled = container.decode(.soundEnabled, default: defaults.soundEnabled)
        soundVolume = container.decode(.soundVolume, default: defaults.soundVolume)
        soundSessionStart = container.decode(.soundSessionStart, default: defaults.soundSessionStart)
        soundTaskComplete = container.decode(.soundTaskComplete, default: defaults.soundTaskComplete)
        soundTaskError = container.decode(.soundTaskError, default: defaults.soundTaskError)
        soundApprovalNeeded = container.decode(.soundApprovalNeeded, default: defaults.soundApprovalNeeded)
        soundTaskAcknowledge = container.decode(.soundTaskAcknowledge, default: defaults.soundTaskAcknowledge)
        soundContextLimit = container.decode(.soundContextLimit, default: defaults.soundContextLimit)
        soundIdleReminder = container.decode(.soundIdleReminder, default: defaults.soundIdleReminder)
        quietWhenScreenLocked = container.decode(.quietWhenScreenLocked, default: defaults.quietWhenScreenLocked)
        quietWhenScreenSharing = container.decode(.quietWhenScreenSharing, default: defaults.quietWhenScreenSharing)
        useNativeClaudeApprovals = container.decode(.useNativeClaudeApprovals, default: defaults.useNativeClaudeApprovals)
        useAutoModeInsteadOfBypass = container.decode(.useAutoModeInsteadOfBypass, default: defaults.useAutoModeInsteadOfBypass)
        approvalHoldSeconds = container.decode(.approvalHoldSeconds, default: defaults.approvalHoldSeconds)
        showUsageLimitsHeader = container.decode(.showUsageLimitsHeader, default: defaults.showUsageLimitsHeader)
        usageDisplayValueRemaining = container.decode(.usageDisplayValueRemaining, default: defaults.usageDisplayValueRemaining)
        enableCodexMonitoring = container.decode(.enableCodexMonitoring, default: defaults.enableCodexMonitoring)
        enableGeminiMonitoring = container.decode(.enableGeminiMonitoring, default: defaults.enableGeminiMonitoring)
        displayTarget = container.decode(.displayTarget, default: defaults.displayTarget)
        subagentNotificationMode = container.decode(.subagentNotificationMode, default: defaults.subagentNotificationMode)
        blockedLauncherApps = container.decode(.blockedLauncherApps, default: defaults.blockedLauncherApps)
        soundPack = container.decode(.soundPack, default: defaults.soundPack)
        pinExpandedNotch = container.decode(.pinExpandedNotch, default: defaults.pinExpandedNotch)
        fullscreenOverlayMode = container.decode(.fullscreenOverlayMode, default: defaults.fullscreenOverlayMode)
        preventCloseOnMouseLeave = container.decode(.preventCloseOnMouseLeave, default: defaults.preventCloseOnMouseLeave)
        lockWhileInteracting = container.decode(.lockWhileInteracting, default: defaults.lockWhileInteracting)
        enableHaptics = container.decode(.enableHaptics, default: defaults.enableHaptics)
        contentPadding = container.decode(.contentPadding, default: defaults.contentPadding)
        notchWidthAdjustment = container.decode(.notchWidthAdjustment, default: defaults.notchWidthAdjustment)
        notchHeightAdjustment = container.decode(.notchHeightAdjustment, default: defaults.notchHeightAdjustment)
        enableNonNotchFallback = container.decode(.enableNonNotchFallback, default: defaults.enableNonNotchFallback)
        fallbackHandlerWidth = container.decode(.fallbackHandlerWidth, default: defaults.fallbackHandlerWidth)
        fallbackHandlerHeight = container.decode(.fallbackHandlerHeight, default: defaults.fallbackHandlerHeight)
        fallbackHandlerIsTransparent = container.decode(.fallbackHandlerIsTransparent, default: defaults.fallbackHandlerIsTransparent)
        demoMode = container.decode(.demoMode, default: defaults.demoMode)
        allowHoverGestures = container.decode(.allowHoverGestures, default: defaults.allowHoverGestures)
        enableVerticalGestures = container.decode(.enableVerticalGestures, default: defaults.enableVerticalGestures)
        enableHorizontalGestures = container.decode(.enableHorizontalGestures, default: defaults.enableHorizontalGestures)
        invertHorizontalGestures = container.decode(.invertHorizontalGestures, default: defaults.invertHorizontalGestures)
        enableClickToExpand = container.decode(.enableClickToExpand, default: defaults.enableClickToExpand)
        hoverOpenDelayMS = container.decode(.hoverOpenDelayMS, default: defaults.hoverOpenDelayMS)
        // Migration: 140ms was the pre-pivot default — snap it to the new
        // instant-feeling default once.
        if hoverOpenDelayMS == 140 { hoverOpenDelayMS = 50 }
        mouseLeaveCloseDelayMS = container.decode(.mouseLeaveCloseDelayMS, default: defaults.mouseLeaveCloseDelayMS)
        enableLiveActivities = container.decode(.enableLiveActivities, default: defaults.enableLiveActivities)
        hideLiveActivitiesOnNonNotchedScreens = container.decode(.hideLiveActivitiesOnNonNotchedScreens, default: defaults.hideLiveActivitiesOnNonNotchedScreens)
        liveActivityInactivityTimeoutSeconds = container.decode(.liveActivityInactivityTimeoutSeconds, default: defaults.liveActivityInactivityTimeoutSeconds)
        enableInteractiveActivities = container.decode(.enableInteractiveActivities, default: defaults.enableInteractiveActivities)
        enableQuickPeek = container.decode(.enableQuickPeek, default: defaults.enableQuickPeek)
        unhideAutomatically = container.decode(.unhideAutomatically, default: defaults.unhideAutomatically)
        showRequestCompletionActivity = container.decode(.showRequestCompletionActivity, default: defaults.showRequestCompletionActivity)
        showThresholdAlerts = container.decode(.showThresholdAlerts, default: defaults.showThresholdAlerts)
        showErrorAlerts = container.decode(.showErrorAlerts, default: defaults.showErrorAlerts)
        showSourceConnectionAlerts = container.decode(.showSourceConnectionAlerts, default: defaults.showSourceConnectionAlerts)
        showActiveRequestInFullscreen = container.decode(.showActiveRequestInFullscreen, default: defaults.showActiveRequestInFullscreen)
        showRequestCompletedInFullscreen = container.decode(.showRequestCompletedInFullscreen, default: defaults.showRequestCompletedInFullscreen)
        showErrorAlertsInFullscreen = container.decode(.showErrorAlertsInFullscreen, default: defaults.showErrorAlertsInFullscreen)
        showThresholdAlertsInFullscreen = container.decode(.showThresholdAlertsInFullscreen, default: defaults.showThresholdAlertsInFullscreen)
        showDailySummaryInFullscreen = container.decode(.showDailySummaryInFullscreen, default: defaults.showDailySummaryInFullscreen)
        showCompactProviderIcons = container.decode(.showCompactProviderIcons, default: defaults.showCompactProviderIcons)
        showCompactTotalTokens = container.decode(.showCompactTotalTokens, default: defaults.showCompactTotalTokens)
        showCompactProgressLine = container.decode(.showCompactProgressLine, default: defaults.showCompactProgressLine)
        showCompactActiveIndicator = container.decode(.showCompactActiveIndicator, default: defaults.showCompactActiveIndicator)
        showCompactCost = container.decode(.showCompactCost, default: defaults.showCompactCost)
        compactWidthMode = container.decode(.compactWidthMode, default: defaults.compactWidthMode)
        showHoverProviderSplit = container.decode(.showHoverProviderSplit, default: defaults.showHoverProviderSplit)
        showHoverTodayTotals = container.decode(.showHoverTodayTotals, default: defaults.showHoverTodayTotals)
        showHoverActiveRequestPreview = container.decode(.showHoverActiveRequestPreview, default: defaults.showHoverActiveRequestPreview)
        showHoverRecentRequestSummary = container.decode(.showHoverRecentRequestSummary, default: defaults.showHoverRecentRequestSummary)
        showExpandedProviderRows = container.decode(.showExpandedProviderRows, default: defaults.showExpandedProviderRows)
        showExpandedTokenPercentages = container.decode(.showExpandedTokenPercentages, default: defaults.showExpandedTokenPercentages)
        showExpandedEstimatedCost = container.decode(.showExpandedEstimatedCost, default: defaults.showExpandedEstimatedCost)
        showExpandedRecentRequests = container.decode(.showExpandedRecentRequests, default: defaults.showExpandedRecentRequests)
        showExpandedCurrentSource = container.decode(.showExpandedCurrentSource, default: defaults.showExpandedCurrentSource)
        showExpandedSettingsShortcut = container.decode(.showExpandedSettingsShortcut, default: defaults.showExpandedSettingsShortcut)
        showExpandedQuickActions = container.decode(.showExpandedQuickActions, default: defaults.showExpandedQuickActions)
        showClaudeProviderRow = container.decode(.showClaudeProviderRow, default: defaults.showClaudeProviderRow)
        showGPTProviderRow = container.decode(.showGPTProviderRow, default: defaults.showGPTProviderRow)
        showProviderPercentages = container.decode(.showProviderPercentages, default: defaults.showProviderPercentages)
        showProviderTokenTotals = container.decode(.showProviderTokenTotals, default: defaults.showProviderTokenTotals)
        showProviderProgressLines = container.decode(.showProviderProgressLines, default: defaults.showProviderProgressLines)
        showModelNameWhenActive = container.decode(.showModelNameWhenActive, default: defaults.showModelNameWhenActive)
        preferRoundButtons = container.decode(.preferRoundButtons, default: defaults.preferRoundButtons)
        useTranslucentNotchBackground = container.decode(.useTranslucentNotchBackground, default: defaults.useTranslucentNotchBackground)
        shadowIntensity = container.decode(.shadowIntensity, default: defaults.shadowIntensity)
        islandCornerRadius = container.decode(.islandCornerRadius, default: defaults.islandCornerRadius)
        animationSpeed = container.decode(.animationSpeed, default: defaults.animationSpeed)
        enableClaudeTracking = container.decode(.enableClaudeTracking, default: defaults.enableClaudeTracking)
        enableGPTCodexTracking = container.decode(.enableGPTCodexTracking, default: defaults.enableGPTCodexTracking)
        useCodexTelemetry = container.decode(.useCodexTelemetry, default: defaults.useCodexTelemetry)
        useOpenAIProxySource = container.decode(.useOpenAIProxySource, default: defaults.useOpenAIProxySource)
        preferTelemetryOverProxy = container.decode(.preferTelemetryOverProxy, default: defaults.preferTelemetryOverProxy)
        mergeDuplicateEvents = container.decode(.mergeDuplicateEvents, default: defaults.mergeDuplicateEvents)
        trackSourceApp = container.decode(.trackSourceApp, default: defaults.trackSourceApp)
        trackProjectPath = container.decode(.trackProjectPath, default: defaults.trackProjectPath)
        enableDebugPayloadStorage = container.decode(.enableDebugPayloadStorage, default: defaults.enableDebugPayloadStorage)
        storeProjectPathIfAvailable = container.decode(.storeProjectPathIfAvailable, default: defaults.storeProjectPathIfAvailable)
        storeSourceAppIfAvailable = container.decode(.storeSourceAppIfAvailable, default: defaults.storeSourceAppIfAvailable)
        autoCheckForUpdates = container.decode(.autoCheckForUpdates, default: defaults.autoCheckForUpdates)
        enableOTLPReceiver = container.decode(.enableOTLPReceiver, default: defaults.enableOTLPReceiver)
        otlpPort = container.decode(.otlpPort, default: defaults.otlpPort)
        enableOpenAIProxy = container.decode(.enableOpenAIProxy, default: defaults.enableOpenAIProxy)
        proxyPort = container.decode(.proxyPort, default: defaults.proxyPort)
        openAIBaseURL = container.decode(.openAIBaseURL, default: defaults.openAIBaseURL)
        privacyMode = container.decode(.privacyMode, default: defaults.privacyMode)
        dailyTokenThreshold = container.decode(.dailyTokenThreshold, default: defaults.dailyTokenThreshold)
        dailyCostThresholdUSD = container.decode(.dailyCostThresholdUSD, default: defaults.dailyCostThresholdUSD)
        enableThresholdNotifications = container.decode(.enableThresholdNotifications, default: defaults.enableThresholdNotifications)
        launchAtLogin = container.decode(.launchAtLogin, default: defaults.launchAtLogin)
        debugMode = container.decode(.debugMode, default: defaults.debugMode)
    }
}

private extension KeyedDecodingContainer {
    func decode<Value: Decodable>(_ key: Key, default defaultValue: Value) -> Value {
        (try? decodeIfPresent(Value.self, forKey: key)) ?? defaultValue
    }
}
