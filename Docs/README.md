# TokenIsland

TokenIsland is a native macOS agent-session monitor. It places live Claude Code, Codex, and other supported CLI sessions in the MacBook notch so you can see progress, answer approvals, and jump back to the correct terminal window.

## Features

- Hardware-notch overlay with live session pets and expanded agent cards.
- Claude Code hook integration with inline approval controls.
- Click-to-jump support for terminals and supported IDEs.
- Optional Claude and Codex subscription-usage display.
- Native onboarding, settings, notifications, and launch-at-login support.
- Local-first session and usage storage.

## Requirements

- macOS 14.6 or later for the intended deployment target.
- Xcode / Swift toolchain capable of Swift Package Manager builds.
- Claude Code, Codex, or another supported agent CLI.

## Run Locally

Build and launch the signed app bundle. Do not use `swift run`: macOS attaches Accessibility and Automation permissions to the app's bundle identity.

```bash
bash Scripts/build_app_bundle.sh
open .build/TokenIsland.app
```

## Architecture

The executable target is intentionally tiny. `TokenIslandKit` owns session adapters, persistence, hooks, AppKit windowing, approvals, and SwiftUI features. The primary runtime path is:

1. App boot creates `AppEnvironment`.
2. `AppState` prepares storage, adapters, hooks, and session state.
3. Agent hooks send lifecycle and permission events to the local hook server.
4. `SessionReducer` updates the in-memory session store.
5. SwiftUI and AppKit surfaces render sessions and route user actions.

## Current Status

The Vibe Island-style agent monitor is implemented and unit tested. See `VIBE_ISLAND_BLUEPRINT.md` for the product specification and `HANDOFF.md` for current verification notes and known gaps.
