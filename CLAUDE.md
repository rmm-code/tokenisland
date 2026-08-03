# TokenIsland — CLAUDE.md

A native macOS 14+ notch app (Vibe Island-style): every running AI CLI session shows as
an animated **pixel pet** in the notch — blue working, green ready, orange needs you.
Hover opens a panel of live session cards; approvals, questions, and jumps to the exact
terminal all happen from the notch. Session data stays local; optional usage-limit
refreshes contact the configured provider directly.

The repo started as "TokenIsland", a token-usage counter — it was pivoted (2026-07-16)
into this agent monitor. The reference app being recreated is **Vibe Island**
(vibeisland.app); reference screenshots/recording live in `island/` (do not modify).

## Commands

```bash
swift build                     # build (Swift 6, strict concurrency)
swift test                      # full suite — MUST stay green (150 tests)
bash Scripts/build_app_bundle.sh    # signed .app → .build/TokenIsland.app  ← run the app THIS way
bash Scripts/create_signing_identity.sh  # one-time: stable identity (see below)
./Scripts/dev_seed_sessions.sh  # demo sessions via curl (no real claude needed)
```

**macOS permissions are tied to the code signature.** Ad-hoc signing gives the app no
stable identity, so every rebuild reads as a new app and Keychain "Always Allow" grants
plus Accessibility/Automation approvals are all asked for again. `create_signing_identity.sh`
makes a local self-signed identity once; the build script uses it automatically
(or `TOKENISLAND_SIGN_IDENTITY`).

Always launch via the bundle, not `swift run` — macOS permissions (Accessibility,
Automation) stick to the bundle identity. Never launch the app yourself without the
user: integrations activate only after onboarding finishes, and Claude hook setup can
write marker-tagged entries into `~/.claude/settings.json`.

## Rules

- **No source file over 700 lines.** Split before it gets close.
- `swift build` + `swift test` green after every change; rebuild the bundle when handing
  back to the user (they test immediately).
- UI/state on `@MainActor`; services as `actor`s or `@MainActor` classes.
- Adapters own all CLI-specific logic; never write another tool's config outside an
  adapter, always marker-tag our entries (`#tokenisland-hook`) and back up before first
  write.
- SwiftUI must NEVER drive AppKit window frames: every `NSHostingView` we create sets
  `sizingOptions = []` (macOS 26 constraint-loop crash — see Status/Gotchas).

## Architecture (Sources/TokenIslandKit/)

Event flow: CLI hooks → `HookServer` (127.0.0.1:47791) → `HookRouter` decode →
`SessionStore.apply` (pure `SessionReducer`) → notch UI. Codex/Gemini have no hooks —
file watchers feed the same store.

- `Core/Sessions/` — `AgentSession` model, `SessionEvent`, reducer, `SessionStore`
  (single source of session truth; reveal/sound/removal callbacks).
- `Core/Hooks/` — localhost receiver + Claude payload decoding. `PermissionRequest`
  events can be **parked** awaiting a notch verdict (`ApprovalCenter`), answered as
  hook stdout (`hookSpecificOutput.permissionDecision`). Fail-open everywhere.
- `Core/Adapters/` — `ClaudeCodeAdapter` (full: hook install into
  `~/.claude/settings.json`), `CodexAdapter`/`GeminiAdapter` (file-watch),
  and `AdapterRegistry`. Do not advertise another CLI until it emits real sessions.
- `Core/Codex/`, `Core/Gemini/` — 2s poll watchers over local session files.
- `Core/Jump/` — click-to-jump: custom URL rules → TTY-exact drivers (Terminal.app,
  iTerm2 via AppleScript; WezTerm via CLI; kitty via remote control) → AX title-marker
  scan (`TitleMarkerService` stamps "claude — <slug>" via hook `terminalSequence`) →
  app activation. `KeyInjection` types question answers (⌃1–9).
- `Core/Approvals/` — parked-approval registry; ⌃Y/⌃N/⌃A/⌃B.
- `Core/Pets/` — pixel sprites (4 species, 2-frame walk), Canvas renderer, state tints.
- `Core/Windowing/` — the notch overlay: full-width transparent strip window
  (`statusBar+8`), hardware-notch geometry (+ symmetric wings so expansion is centered),
  state machine (collapsed/hover→expanded/reveal), **mouse-poll hover sentinel** (11 Hz —
  AppKit hover events are unreliable for non-key overlay windows), ⌃G switcher HUD.
- `Core/UsageLimits/` — Claude OAuth usage endpoint (read-only) + Codex `rate_limits`
  from session JSONL; rendered as the panel-header pill (`5h 34% | 7d 2%`, icon click
  cycles provider).
- `Core/Audio/` — synthesized 8-bit cues (3 packs), no audio assets.
- `Features/NotchUI/` — strip, session cards, completion (LiteMarkdown), approval
  (diff preview), question cards, reveal, switcher HUD.
- `Features/Settings/` — sidebar window (General/Integrations/Notifications/Display/
  Sound/Usage/Shortcuts/Labs/Pass/About). Panes bind via
  `SettingsPaneBindingProviding` keypath helpers into `AppState.settings`.
- `Features/Onboarding/` — 5 steps ending in the boarding pass. Fixed 760×640 window;
  steps scroll.
- Legacy usage counter (OTLP receiver/proxy, dashboard, SQLite) still exists, demoted
  to Labs — don't delete without asking.

## Docs

- `Docs/PLAN.md` — execution plan + status log (keep updating it).
- `Docs/PROMO_VIDEO.md` — promo-video runbook (scene scripts, beats, exports).
- `Docs/VIBE_ISLAND_BLUEPRINT.md` — the reference app's full UI/mechanism spec.
- `island/` — reference screenshots + screen recording (source of design truth).

## Status & gotchas (2026-07-25)

- Phases P0–P12 + parity rounds done; 150/150 tests green.
- **Subagents**: Claude's fan-out tool is `Agent` (older builds: `Task`). Inner tool calls
  carry no parent marker in hook payloads — per-agent activity comes from
  `<session>/subagents/agent-<id>.jsonl` + `.meta.json` (its `toolUseId` is our row id).
  A background spawn's PostToolUse means *launched*, not finished; `SubagentStop`'s
  `agent_id` settles it. Codex: `source.subagent.thread_spawn` rollouts are rows on the
  parent card, `source.subagent.other` ("guardian") rollouts are machinery — never cards.
- **Session titles come from transcript sidecar records**, not `summary` (current Claude
  Code writes zero of those): `custom-title` / `last-prompt`, one per turn, small enough to
  land in the 256KB tail where the conversation records are giant tool results. Transcript
  refresh retries while `title == nil`, not just while `model == nil`.
- **The overlay window covers the menu bar and the top of the frontmost window**, so the
  click rect (`islandRect`) is the island's exact bounds; only the hover rect (`hoverRect`,
  sentinel-only) gets a margin. Padding the click rect eats the user's menu-bar clicks.
- **No-notch displays**: the strip only appears when there are sessions (an empty one is a
  black tab over the menu bar, not a notch). Geometry is testable without hardware via
  `layout(screenFrame:hardwareNotchSize:headerBaseHeight:settings:)`.
- **Never give notch content a fixed height it can outgrow.** SwiftUI `.frame(height:)`
  centers oversized content, and the island hangs off the top of the screen, so the
  overflow lands outside the window and the card's first row is destroyed. Reveals and the
  expanded panel measure their content and size to it (top-aligned; `revealHeight(fitting:)`
  / `panelHeight(fitting:)`), so Max Panel Height is a scroll threshold, not a size. The
  window's hit rect must be fed the same height or the lower half stops clicking. Measure
  the *natural* subview (card via `.fixedSize`, list inside the ScrollView) — never a view
  that stretches to the frame, or the measurement feeds itself.
- Card content starts below `layout.notchBandHeight` (notch height + 2, from the hardware,
  not the tunable `headerHeight`) — the physical notch cuts through anything in that band.
- Settings capability audit complete: visible controls have runtime consumers;
  placeholder updater/IDE/SSH/screen-sharing/Auto Mode controls were removed. Passive
  Codex/Gemini monitoring has real toggles. First launch has no hook/listener/notification
  side effects until onboarding completes; legacy OTLP and threshold alerts default off.
- Model display is provider-aware for current Claude/Codex/Gemini IDs, including
  Anthropic Bedrock/Vertex wrappers. Gemini model changes propagate from chat records;
  Claude retries transcript model discovery on the first tool event.
- **Windows/UI on macOS 26**: two crash classes fixed — (1) hosting-view-driven window
  resize loops ("more Update Constraints passes than views"): fixed windows +
  `sizingOptions = []`; (2) key-window flips during display cycles: always defer with
  `DispatchQueue.main.async`. An uncaught-exception logger writes
  `~/Library/Application Support/TokenIsland/last-exception.log` — read it first when
  debugging any crash.
- Hooks apply to NEW Claude sessions only (snapshot at session start).
- The real Vibe Island's hooks may still be installed on this machine
  (`~/.vibe-island`, entries in `~/.claude/settings.json`, `~/.gemini/settings.json`) —
  both apps can watch sessions, but only ONE should answer approvals.
- Gemini adapter is fixture-tested but unvalidated against real local data (this
  machine has no Gemini CLI session history); the real Vibe Island integrates Gemini
  via hooks in `~/.gemini/settings.json` — a hook-based upgrade is the natural next step.
- Still open: real-session verification by the user (approvals ⌃Y/⌃N, questions ⌃1–9,
  ⌃G switcher, live Codex run), per-provider daily/monthly usage charts, SSH Remote.
- Provider icon on colored tiles must use `ProviderIconView(whiteTemplate: true)`
  (orange-on-orange Claude mark is invisible otherwise). SVG gotcha: NSImage renders
  provider SVGs as blobs unless arc flags are space-separated.
