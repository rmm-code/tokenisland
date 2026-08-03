# Changelog

## 2026-07-16 — Vibe Island pivot

The app is now an **agent session monitor** (Vibe Island-style): live AI CLI
sessions in the notch with pixel pets, click-to-jump, and notch approvals.
Spec: `Docs/VIBE_ISLAND_BLUEPRINT.md` · plan: `Docs/PLAN.md`.

- Added session spine: `SessionModels`/`SessionEvent`/`SessionReducer` (pure,
  tested), `SessionStore` (MainActor source of truth), idle cleanup.
- Added `HookServer` on `127.0.0.1:47791` + `HookRouter` decoding Claude Code
  hook payloads (typed `notification_type`, `last_assistant_message`,
  `permission_mode`).
- Added `ClaudeCodeAdapter`: auto-installs marker-tagged hooks into
  `~/.claude/settings.json` (backup + idempotent merge + clean uninstall) for
  SessionStart/UserPromptSubmit/PreToolUse/PostToolUse/Notification/Stop/
  SubagentStop/PreCompact/SessionEnd; `AdapterRegistry` roster/auto-configure.
- Added `TranscriptReader` fallback (title/TLDR/model) — primary completion
  text comes from the Stop hook.
- Rewrote the notch UI: collapsed strip with per-session pixel pets + count,
  hover peek (status word), expanded session-card panel, completion cards,
  approval cards, auto-reveals with dwell; state machine now
  collapsed/hoverPeek/expanded/reveal/error.
- Added pixel pets: 4 species × 2-frame bitmaps, nearest-neighbor Canvas
  renderer with glow, state tints (blue working / green ready / orange
  approval), blinking cursor block; reduce-motion aware.
- Added click-to-jump: terminal-title session markers ("claude — <slug>") via
  hook `terminalSequence`, TTY-precise AppleScript drivers (Terminal.app,
  iTerm2), AX title scan (`WindowLocator`), app-activation fallback.
- Added notch approvals: blocking PreToolUse round-trip (`ApprovalCenter`,
  permission-mode-aware holds, 55s fail-open), Allow/Deny/Always buttons,
  ⌃Y/⌃N/⌃A/⌃B/⌃T panel shortcuts.
- Added 8-bit synthesized `SoundBank` (no assets) with per-event toggles and
  screen-locked quiet scene.
- Rebuilt onboarding: hero → Accessibility → All Set (detected CLIs) → pet
  tour → pixel boarding pass.
- Added `UsageLimitsService` (read-only Claude OAuth usage; header hides on
  any failure) and panel-header display with Used/Remaining preference.
- AppSettings v2: ~30 new session-monitor keys with decode-defaults; settings
  window rebuilt as a sidebar (General/Integrations/Notifications/Display/
  Sound/Usage/Shortcuts/Labs/About + placeholders).
- Removed obsolete token-counter notch views; deleted duplicate root SVGs;
  OTLP/proxy demoted to Labs (legacy sources).

## 2026-07-05

- Added bundled Claude and Codex SVG icon resources and updated provider icon rendering to use those files instead of SF Symbol placeholders.
- Fixed provider icon rendering to load SwiftPM-flattened SVG resources from the bundle root and render the raw Claude/Codex SVG artwork without custom circular badges.
- Updated packaged `.app` creation to copy the `TokenIsland_TokenIslandKit.bundle` resource bundle so provider SVGs are available outside `swift run`.
- Changed the default notch state to `idleBlack`, so idle shows only a black native-looking notch/handler with no token count UI until hover/click/live activity.
- Fixed SQLite startup execution so row-returning statements such as `PRAGMA journal_mode = WAL` do not surface “another row available” as an app error.
- Fixed `swift run TokenIsland` startup by skipping UserNotifications setup outside a packaged `.app` bundle.
- Added `hoverPreview` as the compact counter state with configurable hover and mouse-leave delays.
- Added a top-icon-tab settings window with General, Gestures, Live Activities, Island, Sources, Privacy, and About panes.
- Added settings-backed controls for notch geometry, non-notch fallback sizing/transparency, gestures, live activities, compact/expanded island content, provider rows, source setup/status, privacy, and app info.
- Updated privacy behavior so prompt/response text storage remains disabled; debug payload storage is separate and off by default.
- Replaced the small visible notch panel with a NotchDrop-style transparent full-width top-strip `TokenIslandWindow`.
- Added `TokenIslandHostingView` hit testing so only the visible island rect is interactive while the transparent strip passes through outside clicks.
- Added `TokenIslandNotchView` and `TokenIslandNotchShape`; the SwiftUI black island is now the only visible notch surface, with no outer stroke or AppKit window shadow.
- Replaced stale `NotchPanel`/`NotchWindowController`/`NotchScreenGeometry`/`NotchStateMachine` files with TokenIsland-named equivalents.
- Replaced the old two-state notch SwiftUI views with idle black, hover preview, expanded, active request, peek, setup-required, and error island views.
- Added hardware notch detection using `safeAreaInsets`, `auxiliaryTopLeftArea`, and `auxiliaryTopRightArea`, with top-center fallback.
- Added hover delay behavior, scroll/swipe expand-collapse, horizontal section switching, and pin support.
- Updated menu bar controls for show/hide island, pin/unpin, connection status, dashboard/settings, and quit.
- Created Swift Package project with `TokenIsland` executable and `TokenIslandKit` library.
- Added usage models, app settings, ingestion status, and provider summaries.
- Added SQLite persistence, migrations, repository, and JSON export/delete operations.
- Added OTLP HTTP JSON receiver, local HTTP server, OpenAI-compatible proxy scaffold, metadata sanitizer, and cost estimator.
- Added app state, settings persistence, threshold notifications, and launch-at-login service.
- Added AppKit notch overlay with top-center fallback geometry.
- Added SwiftUI menu bar popover, dashboard, settings, and onboarding.
- Added design system components for provider rows, progress bars, metric cards, recent request rows, empty states, and status badges.
- Added unit tests for provider aggregation and OTLP span normalization.
- Verified `swift build` and `swift test`.
