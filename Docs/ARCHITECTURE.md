# Architecture

## Targets

- `TokenIsland`: executable target with `main.swift`.
- `TokenIslandKit`: reusable app/library target containing all product code.
- `TokenIslandKitTests`: tests for normalization and aggregation.

## Layers

- `App`: app entry, environment construction, main state, launch at login, notifications.
- `Core/Models`: provider, usage event, settings, summary, ingestion status.
- `Core/Persistence`: SQLite wrapper, migrations, repository.
- `Core/Telemetry`: OTLP normalization, metadata sanitization, cost estimation.
- `Core/Proxy`: OpenAI-compatible proxy service.
- `Core/Networking`: small local HTTP server.
- `Core/Windowing`: transparent AppKit notch host window, notch geometry, interaction controller, and state machine.
- `Core/DesignSystem`: shared colors and reusable SwiftUI components.
- `Features`: notch UI, menu bar, dashboard, settings, onboarding.
- `Services`: aggregation and telemetry coordination.

## Ingestion Design

The OTLP receiver listens for HTTP JSON payloads and accepts traces, metrics, logs, and generic JSON usage responses. The normalizer recursively extracts OpenTelemetry attributes and common OpenAI/Anthropic usage fields into `UsageEvent`.

Unsupported schemas are ignored rather than stored incorrectly. Missing source attribution becomes `Generic Claude Source`, `Generic OpenAI Source`, or `Unknown Source`.

## Proxy Design

The proxy accepts OpenAI-compatible HTTP requests, forwards them to the configured upstream base URL, returns the original response, and parses standard response `usage` metadata. Streaming support is a future hardening task.

## Database Design

SQLite stores normalized request events in `usage_events`. `daily_aggregates` exists for future materialized aggregation. Migrations are tracked in `schema_migrations`.

## Notch Overlay System

The notch UI is not a SwiftUI `WindowGroup` and is no longer a small visible panel. `AppDelegate` creates `TokenIslandWindowController`, which owns:

- `TokenIslandWindow`: a full-width transparent top-strip `NSWindow`, borderless, clear, no AppKit shadow, status-bar level plus offset, all-spaces/fullscreen auxiliary behavior.
- `TokenIslandScreenGeometry`: reads `NSScreen.frame`, `safeAreaInsets`, `auxiliaryTopLeftArea`, and `auxiliaryTopRightArea`; when auxiliary top areas reveal a camera gap, the SwiftUI island anchors to that top-center notch geometry.
- `TokenIslandStateMachine`: owns `idleBlack`, `hoverPreview`, `expanded`, `activeRequest`, `peek`, `notConfigured`, and `error` states plus pointer presence and horizontal section selection.
- `NotchInteractionController`: handles hover preview delay, mouse-leave close delay, click expansion, scroll/swipe expansion, horizontal section switching, and Escape collapse.
- `TokenIslandHostingView`: restricts hit testing to the actual visible island rect so the transparent full-width window does not block the menu bar unnecessarily.
- `TokenIslandNotchView`: SwiftUI content hosted inside the transparent strip. It draws the only visible black notch shape and hosts idle/hover/expanded/active/peek/setup/error content.

On Macs without notch geometry, the same transparent top strip uses a configurable virtual top-center notch size and renders the same black island shape when fallback is enabled.

Idle is intentionally not the compact counter. The default visible state is `idleBlack`, which draws no usage content. Hover transitions to `hoverPreview`; click transitions to `expanded`; mouse leave collapses to `idleBlack` after the configured delay unless pinned or prevented by settings. Active requests and completion peeks return to `idleBlack` or `hoverPreview` depending on pointer presence.

The settings window is a SwiftUI preferences surface with top icon tabs. `SettingsDetailView` only dispatches to focused panes so the settings implementation stays split by responsibility: General, Gestures, Live Activities, Island, Sources, Privacy, and About.

## State Management

`AppState` is the main-actor source of truth for app data: loaded settings, current summary, ingestion status, and errors. The notch expansion and transient activity lifecycle are owned by `TokenIslandStateMachine`, not by dashboard/setup state. Background services report into `TelemetryCoordinator`, which inserts events through the repository and asks `AppState` to refresh.

## Fallback Strategies

- No notch: use the same panel as a top-center island with a compact notch-like bridge.
- No telemetry configured: idle remains a black notch; click can open setup-required content.
- Partial telemetry: store available fields and label unknown source/project/model values.
- Launch-at-login outside a bundle: report the ServiceManagement error without crashing.
