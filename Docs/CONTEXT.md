# Context

TokenIsland is a macOS 14.6+ utility for local AI token visibility. It should feel like a polished menu bar/notch utility, not a marketing app.

## Product Intent

Show Claude and GPT/Codex token usage in a compact overlay, menu bar popover, and dashboard. Privacy-first metadata storage is core to the product.

## Architectural Rules

- No monolith files over 700 lines.
- `TokenIslandKit` owns all reusable app code.
- `AppState` owns UI-facing state on the main actor.
- `TokenIslandStateMachine` owns only the notch overlay state and must not be replaced with scattered booleans.
- `TokenIslandWindowController` creates the island outside SwiftUI scenes using a transparent full-width `TokenIslandWindow`.
- `TokenIslandNotchView` is the only notch surface that should draw visible pixels; the AppKit host window must remain clear.
- `UsageRepository` owns persistence.
- `TelemetryCoordinator` starts/stops ingestion services.
- `OTLPNormalizer` owns schema inference.
- `UsageAggregator` owns derived summaries.

## Coding Conventions

- SwiftUI views should stay small and focused.
- Use native controls: toggles, segmented pickers, steppers, text fields, and icon buttons.
- Use AppKit only where SwiftUI cannot handle windowing/notch behavior.
- Notch geometry must come from `NSScreen` safe areas and auxiliary top areas; do not hardcode one screen size.
- If no hardware notch exists, use the top-center fallback island.
- Never store prompt or response text. Debug payload storage must remain sanitized and off by default.

## UI Expectations

- Dark premium utility style.
- Thin provider progress bars.
- Claude and GPT rows are visible by default but configurable in Island settings.
- The notch island should visually attach to the notch as a black custom shape. No visible rectangular host window, gray outline, or debug border is acceptable.
- Idle state must visually read as a black native/inactive notch first. No token count UI, provider rows, icons, or progress line should appear until hover, click, or a live activity.
- Hover should reveal the compact counter preview smoothly; click should expand to the full TokenIsland panel.
- Claude and Codex provider icons should use the bundled SVG files, not SF Symbol substitutes.
- Empty, idle, partial, and error states should be explicit.

## Integration Assumptions

- OTLP HTTP JSON is supported first.
- Proxy captures standard OpenAI response `usage` objects.
- Missing attribution degrades to generic source labels.
