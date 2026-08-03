# Architecture Decisions

## 2026-07-05: Swift Package With Library Core

Decision: Use a Swift Package with a tiny `TokenIsland` executable and a `TokenIslandKit` library.

Reason: This keeps the product code testable and avoids fragile hand-authored Xcode project files in a greenfield workspace.

## 2026-07-05: Direct SQLite

Decision: Use SQLite through a small wrapper instead of adding an ORM dependency.

Reason: The schema is small, local, and stable enough for direct SQL. This minimizes dependencies and keeps migrations explicit.

## 2026-07-05: OTLP HTTP JSON First

Decision: Implement OTLP HTTP JSON ingestion before protobuf/gRPC.

Reason: It is buildable without additional dependencies and provides a clear local integration path. Protobuf/gRPC support is deferred to v1 hardening.

## 2026-07-05: Transparent Top-Strip Notch Window

Decision: implement a NotchDrop-style transparent full-width top-strip `NSWindow` instead of a small visible `NSPanel`.

Reason: the small-panel approach can expose a rectangular host artifact around the island. A full-width clear host window lets SwiftUI draw the only visible pixels, so there is no AppKit border, gray outline, titlebar, or panel shadow to leak into screenshots.

Geometry: `TokenIslandScreenGeometry` checks `NSScreen.safeAreaInsets.top`, `auxiliaryTopLeftArea`, and `auxiliaryTopRightArea`. If the auxiliary areas are present, notch width is `screen.frame.width - leftAuxiliaryWidth - rightAuxiliaryWidth`, and the SwiftUI island anchors to the top center of the host strip.

Fallback: when notch geometry is unavailable, the same transparent top-strip window uses a virtual notch size and centers the island at the top of the active or built-in display.

Interaction: `TokenIslandHostingView` limits hit testing to the visible island rect so the full-width transparent window does not unnecessarily block the menu bar.

## 2026-07-05: Dedicated Notch State Machine

Decision: use `TokenIslandStateMachine` for `idleBlack`, `hoverPreview`, `expanded`, `activeRequest`, `peek`, `notConfigured`, and `error`.

Reason: The notch interaction is a product surface with transient behavior, not a single expanded boolean. A state machine keeps hover, click, swipe, active-request, peek, setup, and error transitions coherent and prevents dashboard/setup state from leaking into the overlay.

Update: idle is its own black-only state, not the compact counter. This prevents TokenIsland from reading as an always-open widget before the user interacts with the notch.

## 2026-07-05: Metadata-Only Default

Decision: Redact prompt-like and response-like fields from raw telemetry and keep prompt/response text storage disabled.

Reason: The product promise is privacy-first usage visibility. TokenIsland is a token usage monitor, not a prompt/archive tool.

## 2026-07-05: Top-Tab TokenIsland Settings

Decision: Replace the sidebar settings view with a top icon-tab preferences window organized as General, Gestures, Live Activities, Island, Sources, Privacy, and About.

Reason: The settings surface now matches the product's actual control groups: notch behavior, token counter display, source configuration, and privacy. Unrelated generic notch-widget categories such as calendar, media, tray, and drop area are intentionally excluded.
