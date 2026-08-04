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
swift test                      # full suite — MUST stay green (207 tests)
bash Scripts/build_app_bundle.sh    # signed .app → .build/TokenIsland.app
bash Scripts/run.sh             # build + relaunch  ← run the app THIS way
bash Scripts/release.sh 0.2.1   # sign → notarize → staple → dmg + zip + appcast
./Scripts/dev_seed_sessions.sh  # demo sessions via curl (no real claude needed)
bash Scripts/clean_desktop.sh   # hide desktop icons + Dock for recording
```

**Never run the app with `swift run`.** That binary is ad-hoc signed with a per-build
identifier, so macOS sees a brand-new app every time and re-asks for Keychain,
Accessibility and Automation forever. Only the bundle carries the stable identity.
Never launch it *for* the user without being asked: integrations activate after
onboarding, and hook install writes marker-tagged entries into other CLIs' configs.

**macOS permissions are tied to the code signature.** The build script picks
Developer ID → Apple Development → local self-signed → ad-hoc, in that order; grants
survive rebuilds only from the first two. `Scripts/create_signing_identity.sh` makes a
local identity for machines with no Apple certificate.

## Releasing

`Scripts/release.sh <version>` is the whole pipeline and refuses to produce something
Gatekeeper would reject. It needs, one time per machine: a **Developer ID Application**
certificate (Apple Development cannot ship — notarization refuses it) and
`xcrun notarytool store-credentials TokenIslandNotary` (app-specific password — the
user's to enter, never ours).

- **Hardened runtime + `Scripts/TokenIsland.entitlements`** — required for notarization;
  without `com.apple.security.automation.apple-events` a notarized build's click-to-jump
  dies silently.
- **Two artifacts, two jobs.** `.zip` is what Sparkle installs; `.dmg` (with an
  `/Applications` symlink) is the website download — an app launched from a downloaded zip
  is App-Translocated, which breaks in-place updates. The DMG needs *its own* notarization
  ticket. A fixed-name `TokenIsland.dmg` copy keeps `/releases/latest/download/…` working.
- **`sign_update` emits `sparkle:edSignature` AND `length`.** Emitting our own `length`
  too produced a duplicate attribute → invalid XML → every parser read the feed as empty
  while the app cheerfully reported "up to date". `ReleasePipelineTests` round-trips the
  script's own appcast through `UpdateChecker` so writer and reader cannot drift.
- Feed: `SUFeedURL` → `releases/latest/download/appcast.xml` on the public repo. Private
  repos 404 for anonymous fetches, which is silent — the check just never finds anything.

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

Event flow: CLI hooks → `HookServer` (`127.0.0.1:47791/hook/<source>`) → dialect decode →
`SessionStore.apply` (pure `SessionReducer`) → notch UI. Codex has no hooks — a rollout
watcher feeds the same store.

- `Core/Sessions/` — `AgentSession` model, `SessionEvent`, reducer, `SessionStore`
  (single source of session truth; reveal/sound/removal callbacks).
- `Core/Hooks/` — localhost receiver + **three payload dialects**: `HookRouter` (Claude
  Code and its derivatives), `CursorHookRouter` (`preToolUse`, `beforeShellExecution`,
  `conversation_id`, `workspace_roots`), `GeminiHookRouter` (`BeforeTool`/`AfterAgent`,
  snake_case tool names). `PermissionRequest` events are **parked** awaiting a notch verdict
  (`ApprovalCenter`); the answer must be in the shape that CLI reads — Claude
  `hookSpecificOutput.permissionDecision`, Cursor `permission`, Gemini `decision` — or it
  reads as "no opinion" and the CLI prompts in its own terminal. Fail-open everywhere.
- `Core/Adapters/` — most agent CLIs are Claude Code derivatives with the same hook
  vocabulary and config shape, so they are **data, not code**: `HookFamilyCLI` describes
  each (route, config path, dialect, binaries), `HookConfigBuilder` is the single
  merge/strip/state implementation (`ClaudeHookCommand` delegates to it), and
  `HookFamilyAdapter` serves all of them. Roster: Claude Code, Qwen, Qoder, Trae,
  CodeBuddy, Droid, Copilot, Cursor, Gemini + `CodexAdapter` (file-watch). Copilot reads a
  hooks *directory*, so we own one file there instead of merging. Do not advertise a CLI
  whose real config shape has not been verified on a machine that has it installed.
- `Core/Codex/` — 2s poll watcher over rollout JSONL. `source.subagent.thread_spawn`
  threads become subagent rows on the parent's card; `source.subagent.other` ("guardian")
  threads are machinery and must never surface (104 of 197 files on the dev machine).
- `Core/Updates/` — `UpdateChecker` + `AppcastParser`: Sparkle-format feed, checked on
  launch and hourly (rate-limited 6h, gated by `autoCheckForUpdates`), surfaced as the
  menu-bar banner and the About card. Sparkle itself is linked by the **executable only**
  (`SparkleUpdaterBridge`), injected through `TokenIslandLaunch.setUpdateInstaller`, so the
  library stays framework-free and `swift test` needs no embedded framework.
- `Core/Transcripts/` — `TranscriptReader` (title/prompt/model; reads `custom-title` /
  `last-prompt` sidecars) and `SubagentActivityReader` (per-agent live tool call from
  `<session>/subagents/agent-<id>.jsonl`).
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
  from session JSONL; rendered as the panel-header pill. Windows are **discovered**, not
  hardcoded, so per-model caps appear automatically (`5h 33% | 7d 55% | 7d Fable 12%`);
  `*_opus` is suppressed because Claude does not meter it. The access token is cached for
  the process lifetime — every Keychain read is a password prompt.
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

## Status & gotchas (2026-08-04)

- Phases P0–P12 + parity rounds done; **207/207 tests green**. Distribution is live:
  Developer ID + notarized + stapled, Sparkle in-place updates, DMG + zip published to
  GitHub Releases on a public repo, feed verified against the real published appcast.
- **10 CLI integrations** (was 3): the Claude-family ones are descriptors, not adapters.
  Vibe Island lists 26 — the remaining gap is mostly more descriptors plus terminals.
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
- Card content starts below `layout.notchBandHeight` (**exactly** the notch height — it is a
  hardware measurement, not a design margin) and reveal rows use 4pt padding, so the first
  row sits ~36pt down. That is the floor: the physical notch slices anything above it.
  The reveal band carries the panel's actions (sound, settings) so it reads as the notch
  rather than as dead space.
- **Prompts and titles are sanitized** (`SessionText.sanitizedPrompt`): agents inject
  `<system-reminder>`, `<task-notification>`, slash-command envelopes and
  `[Image: …]` placeholders into the same user turn. A turn made only of injected content
  keeps the previous title instead of becoming one.
- Markdown renders in the card's TLDR line (`LiteMarkdownText`), not raw `**bold**`.
- Settings capability audit stands: **every visible control must have a runtime consumer**
  (`SettingsCapabilityTests` enforces it). "Auto check for updates" was removed as a dead
  toggle and is back only because `UpdateChecker` now consumes it; the IDE/SSH/screen-
  sharing/Auto Mode placeholders are still gone. Passive
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
- Still open: watch a 0.2.0 install update itself (last unproven link in the Sparkle
  chain); the terminal-jump matrix (4 precise drivers vs the reference's 20+, no tmux, no
  IDE extensions); SSH Remote; licensing; localization; per-provider usage charts.
- The **welcome/setup walkthrough** is one-shot on first launch — Settings → General →
  "Show Welcome Guide" replays it (`AppWindowRouter.openWelcomeGuide`).
- Provider icon on colored tiles must use `ProviderIconView(whiteTemplate: true)`
  (orange-on-orange Claude mark is invisible otherwise). SVG gotcha: NSImage renders
  provider SVGs as blobs unless arc flags are space-separated.
