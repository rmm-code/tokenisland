# PLAN — Rebuild `counter` (TokenIsland) into a Vibe Island-style agent monitor

**This is the single authoritative execution plan.** Deep product/mechanism spec lives in
[VIBE_ISLAND_BLUEPRINT.md](VIBE_ISLAND_BLUEPRINT.md). Reference material: `island/` media,
https://vibeisland.app/ai-coding-session-tracker/ .

Status legend: `[ ]` todo · `[x]` done · `[~]` in progress · `[!]` blocked (stop & ask user).

---

## 0. Ground rules

1. **No source file may exceed 700 lines.** Split by responsibility before it gets close.
2. `swift build` must pass at the end of every phase; `swift test` for the phases that add
   logic. The app must stay launchable throughout (pivot, not teardown).
3. Local-only: no cloud calls except the (later) usage-limit endpoints. Hooks talk to a
   localhost HTTP server.
4. Swift 6 strict concurrency: UI/state on `@MainActor`, stores/services as `actor`s.
5. Existing OTLP/proxy pipeline is **kept but demoted** (default off, Labs) — token/cost
   accounting later re-attaches to sessions via transcripts.
6. Naming: product surface stays `TokenIsland` for now (bundle/product rename is a final
   cosmetic step, not worth churn mid-build).

## 1. What we are building (one paragraph)

Every running AI CLI session shows as a **pixel pet** in the notch strip (blue=working,
green=ready/attention, orange=waiting approval) with a session count; hover widens the
strip with a status word; click expands a panel of **session cards** (project · title,
live tool activity, agent/terminal chips, elapsed time, completion TLDR, subagents);
completions/approvals **auto-reveal**; clicking a card **jumps** to the exact terminal
window; approvals can be answered from the notch. Settings become a sidebar window with
General / Integrations / Notifications / Display / Sound / Usage / Shortcuts / Labs /
About (+ SSH Remote, Pass placeholders). Details: blueprint §2.

## 2. Target module tree (new code under `Sources/TokenIslandKit/`)

```
Core/Sessions/     SessionModels.swift        // AgentSession, SessionState, ActivityKind, chips
                   SessionEvent.swift         // normalized inbound event (one enum, versioned)
                   SessionStore.swift         // @MainActor ObservableObject; reduce + publish
                   SessionReducer.swift       // pure event→session transitions (unit-tested)
Core/Hooks/        HookServer.swift           // localhost HTTP receiver on 127.0.0.1:47791
                   HookRouter.swift           // path → CLI kind → SessionEvent (decoding)
Core/Adapters/     CLIAdapter.swift           // protocol + AdapterStatus (active/needsAuth/…)
                   AdapterRegistry.swift      // roster, detect-all, auto-configure
                   ClaudeCodeAdapter.swift    // ~/.claude/settings.json hook install/repair
                   ClaudeHookCommand.swift    // builds the curl one-liner hook commands
Core/Transcripts/  TranscriptReader.swift     // JSONL tail: title/prompt/TLDR/model/usage
Core/Jump/         JumpService.swift          // resolve session → app/window, activate
                   WindowLocator.swift        // AX title-marker scan (needs AX permission)
Core/Pets/         PetSpecies.swift           // bitmaps (crab, blob, ghost, runner…)
                   PetView.swift              // Canvas nearest-neighbor renderer + glow
                   PetAnimator.swift          // TimelineView 2–4 fps frame driver
Features/NotchUI/  (rewrite) CollapsedStripView, ExpandedPanelView, SessionCardView,
                   CompletionCardView, ApprovalCardView, PanelHeaderView
Features/Settings/ (rewrite as sidebar) one pane file per page
Tests/             SessionReducerTests, ClaudeHookInstallTests, TranscriptReaderTests,
                   HookServerTests
```

## 3. Phases

### P0 — Session spine (models, reducer, store, hook server)  `[x]`
- [x] `SessionModels` / `SessionEvent`: states `working / ready / waitingApproval /
      question / error / ended`; activity line (tool + target); agent kind; terminal hint;
      startedAt / lastEventAt; project (cwd basename) + worktree; model name.
- [x] `SessionReducer` (pure, tested): SessionStart→working; UserPromptSubmit→working(+prompt);
      PreToolUse/PostToolUse→activity; Notification(permission)→waitingApproval;
      Notification(idle)→ready(idle); Stop→ready(+completion); SubagentStart/Stop→subagent rows;
      SessionEnd→ended (drop after grace); unknown-session events synthesize a session (Codex-style
      no-close CLIs get the 2h idle cleanup later).
- [x] `HookServer` on `127.0.0.1:47791` reusing `LocalHTTPServer`; `POST /hook/claude`
      (+`/hook/generic` for future CLIs); replies `{}` fast; forwards decoded events to store.
- [x] `SessionStore`: ordered sessions, focused session, counts by state; Combine-published.
- [x] Wire into `AppEnvironment`/`AppState` alongside existing telemetry (untouched).
- Acceptance: `swift test` green for reducer; `curl` a SessionStart/Stop pair against a
  debug-run server flips a session working→ready.

### P1 — Claude Code adapter (real sessions appear)  `[x]` *(hook install runs at first user launch)*
- [x] Detect `~/.claude` + `claude` binary; status surfaced for Integrations pane.
- [x] Hook install: merge marker-tagged (`__tokenisland`) entries into
      `~/.claude/settings.json` for SessionStart, UserPromptSubmit, PreToolUse, PostToolUse,
      Notification, Stop, SubagentStop, SessionEnd, PreCompact. Command = `curl` one-liner
      posting stdin JSON to the hook server (3s timeout, fail-open). Idempotent; repair;
      clean uninstall; never touch user's own hooks. Backup file on first write.
- [x] `TranscriptReader`: session title (first user prompt, cleaned), last prompt, last
      assistant TLDR (first ~2 lines), model, per-message usage (tokens) when present —
      read lazily on card render / Stop events, not continuously.
- [x] Session titles for terminal binding groundwork: SessionStart hook also emits
      `\e]0;⛯<sid8>\a` marker to `/dev/tty` (behind a settings flag, default on).
- Acceptance: with hooks installed, a real `claude` run in Terminal produces a live session
  (working→ready with TLDR). (needs user-side run — verify at first launch)

### P2 — Notch UI rewrite (pets in strip, session cards)  `[x]` *(visual pass at first launch)*
- [x] State machine: `collapsed / hoverPeek / expanded / autoReveal(kind)`; hover peek
      re-enabled behind settings (matches reference), ESC collapse, dwell timer (5s default)
      for completion/approval reveals.
- [x] `CollapsedStripView`: left wing = one pet per session (cap 3 + overflow dot), right
      wing = count; Detailed mode adds status word + "N sessions" on hover.
- [x] `ExpandedPanelView`: header (usage-limits placeholder text now, gear, sound toggle, ×),
      session cards list (focused-first, `Show all N sessions`), completion card, approval
      card (buttons render; wiring lands in P5).
- [x] `SessionCardView` per blueprint §2.3 (chips: agent, terminal, elapsed; activity line;
      status line; optional subagent rows).
- Acceptance: simulated sessions (debug seed) render all states; animations respect
  reduce-motion.

### P3 — Pixel pets  `[x]`
- [x] `PetSpecies`: 4 species × 2-frame idle/walk bitmaps (~10×7 logical px) as int grids;
      deterministic species assignment per session id.
- [x] `PetView`: Canvas nearest-neighbor with per-state tint (blue/green/orange/red) +
      glow (shadow) + blinking cursor block companion in cards.
- [x] `PetAnimator`: TimelineView-driven 2 fps frame flip, paused under reduce-motion.
- Acceptance: strip + cards show animated pets; species stable across refreshes.

### P4 — Click-to-jump  `[x]` *(needs AX grant at first launch)*
- [x] `WindowLocator`: AX scan of on-screen windows for the `⛯<sid8>` title marker;
      permission state surfaced (Integrations/General row + onboarding step later).
- [x] `JumpService`: marker hit → focus window (AXRaise + app activate); fallback chain:
      terminal-hint app (Terminal/iTerm/Ghostty/VS Code/Cursor by bundle id) → cwd match in
      window titles. Click session card → jump; `^T` from panel.
- Acceptance: click lands on the right Terminal.app/iTerm/Ghostty window in a 2-session
  test. (needs user-side AX grant — verify at first launch)

### P5 — Approvals from the notch  `[x]` *(retargeted to the PermissionRequest hook after inspecting the reference app's real config; verify on a live session)*
- [x] Hook contract verified twice: docs research (claude-code-guide agent) + the
      reference app's real `~/.claude/settings.json` found on this machine. Approvals ride
      the dedicated **PermissionRequest** hook (fires only when Claude Code would prompt;
      reference parks it with timeout 86400). PreToolUse stays fire-and-forget telemetry.
      `CLAUDE_CODE_DISABLE_TERMINAL_TITLE=1` env (also from the reference config) protects
      our title markers. Hold ≤85s (curl cap 90s), no-decision → empty output → native
      terminal prompt; fail-open everywhere.
- [x] `ApprovalCenter` actor: pending request registry keyed by (session, tool-call id);
      card Approve/Deny/Always-Allow(session-scoped)/Bypass responses resolve the hook's
      long-poll; timeout auto-`ask`; "Use Native Claude Code Approvals" toggle short-circuits.
- [x] Only escalate to card when Claude Code would actually prompt: heuristic = tool not in
      session's seen-approved set AND not read-only (Read/Glob/Grep/WebFetch auto-`ask`
      passthrough silently) — mirrors reference "auto-reviewed requests are always silent".
- [x] Shortcuts while expanded: ^Y approve, ^N deny, ^A always, ^B bypass, ^1-9 options,
      esc collapse.
- Acceptance: `Bash(touch /tmp/x)` under default permissions pauses in terminal, card
  appears, ^Y approves and the command runs. (verify at first launch)

### P6 — Settings v2 (sidebar) + AppSettings v2  `[x]`
- [x] `AppSettings` v2: new keys per blueprint §2.5 with decode-defaults (hover 0.15s,
      dwell 5s, idle cleanup 2h, panel 560×640, font 11, Clean/Detailed, display target,
      session-card toggles, sound toggles/volume, usage header prefs, shortcut enables,
      Labs flags incl. `useNativeClaudeApprovals`, `useAutoModeInsteadOfBypass`,
      OTLP/proxy demoted default-off). Old keys keep decoding (no data loss).
- [x] Sidebar window: General / Integrations / Notifications / Display / Sound / Usage /
      Shortcuts / Labs / About + disabled SSH Remote & Pass placeholder rows. One pane file
      each, reusing `SettingsSupportViews` rows; every control itemized in blueprint §2.5
      present and bound (SSH/Pass content excluded from v1 scope).
- [x] Integrations pane: adapter rows with live status (Active / Needs setup / Not found +
      Install/Repair buttons), AX permission row, hook-server port, auto-configure toggle,
      "Disable Claude Code native terminal title" toggle.
- Acceptance: every toggle/slider persists across relaunch and drives behavior where the
  backend exists.

### P7 — Sound + onboarding  `[x]`
- [x] `SoundBank`: 8-bit square/triangle synth (AVAudioEngine, generated buffers, no
      assets) for session-start / complete / error / approval / acknowledge / context-limit
      / idle-reminder; volume + per-event enable; quiet-scene suppression (screen locked,
      Focus via NSWorkspace where available, recording flag manual).
- [x] Onboarding rewrite (5 steps): hero → AX permission → detected agents & terminals
      ("All Set") → notch tour (skip pricing) → boarding-pass "Welcome aboard" (pixel art,
      local-only identity), Start Vibing.
- Acceptance: sounds audible under toggle control; onboarding completes and installs hooks.

### P8 — Usage limits header + cleanup  `[x]` *(limits need the user's Claude subscription at runtime)*
- [x] `UsageLimitsService`: Claude OAuth usage endpoint via Keychain/`~/.claude/.credentials.json`
      token (read-only, feature-flagged, hides header on any failure); Codex JSONL
      `rate_limits` parser stub for later. Header shows `5h X% · reset | 7d Y% · reset`.
- [x] Demote OTLP/proxy fully to Labs (off by default), keep dashboard reachable from
      Settings→Usage; delete root-level duplicate SVGs (`claude-ai-icon.svg`, `codex_dark.svg`,
      `codex_light.svg`, `openai.svg`) after confirming bundled copies remain.
- [x] Docs refresh: ARCHITECTURE/HANDOFF/CHANGELOG entries for the pivot.
- Acceptance: header renders real percentages on a machine with an active Claude
  subscription; build + tests green. (needs user account — verify at first launch)

## 4. Verification strategy

- Per phase: `swift build` + targeted `swift test`.
- Hook-path integration test: launch `HookServer` in-test on an ephemeral port, POST real
  captured Claude hook payload fixtures, assert store state.
- Manual smoke script `Scripts/dev_seed_sessions.sh`: curl a scripted event sequence
  (start → tools → notification → stop) so the full notch UX is demoable **without** a
  real Claude run.
- Real-world check (user-assisted at the end): install hooks, run `claude` in Terminal +
  VS Code, confirm pet states, completion reveal, jump, approval.

## 5. Stop-and-ask triggers (per user instruction)

- AX permission or hook install behaving differently on the user's machine than designed.
- Claude Code hook contract mismatch discovered at runtime (payload shape drift).
- Any phase acceptance failing twice after fixes → stop, report, ask.
- Anything requiring the user's accounts/credentials (usage limits P8) → ask before touching.

## 6. Out of scope for this pass

SSH Remote, IDE extensions (VS Code/Cursor plugin binaries), Codex/Gemini/long-tail
adapters (structure ready, one reference adapter shipped), session switcher HUD (^G cycle
— shortcut reserved), Sparkle updater, licensing/Pass economy, app rename/bundle id.

---
*Maintained by Claude; update checkboxes as phases land. Blueprint stays the spec of record.*


## Phase 2 — video-parity completion (P9–P12)

### P9 — Codex adapter (sessions for the 2nd agent)  `[x]`
- [x] `CodexSessionWatcher`: poll `~/.codex/sessions/**/rollout-*.jsonl` (2s tail reader,
      newest files) → normalized SessionEvents (agent `.codex`): session_meta→sessionStart,
      user/agent messages→userPrompt/stop(+last message), token_count→activity heartbeat.
      No close signal → existing idle cleanup. Gated by `enableCodexMonitoring`.
- [x] `CodexAdapter` replaces the detect-only entry: status Active when watcher runs.
- [x] Jump fallback: cwd/title match + app activation (no TTY available from files).

### P10 — Questions & option answering (⌃1–9)  `[x]`
- [x] Detect Claude `AskUserQuestion` (PreToolUse tool_input questions/options) →
      QuestionCard in panel/reveal with option buttons.
- [x] Answering: focus the session's terminal (JumpService), then inject the option
      digit + Return via CGEvent (needs the existing AX permission). ⌃1–9 shortcuts.
- [x] Fallback button "Answer in terminal" when injection unavailable.

### P11 — Session switcher (⌃G)  `[x]`
- [x] Global ⌃G cycles a switcher HUD over sessions (⌘Tab-style); releasing ⌃ jumps
      to the highlighted session. ⌃⇧G reverse. Uses global event monitor (AX-granted).

### P12 — Settings/UI parity rows  `[x]`
- [x] Display: live strip + card preview, display-target picker
      (Built-in / Main / Pointer Display), and one fullscreen tri-state in General.
- [x] Notifications: direct subagent-completion toggle and Blocked Launcher Apps list
      (drop sessions from selected launcher apps).
- [x] Sound: pack picker (Chip / Soft) driving SoundBank timbre.
- [x] Pass page: boarding-pass card (reuse onboarding art) with local stats.
- [x] Integrations: managed Claude hooks, passive Codex/Gemini monitor toggles, and
      Custom Jump Rules (`jump-rules.json`: bundle id → URL template consulted by JumpService).
- Out of scope still: SSH Remote (v2), sound marketplace, licensing.

---

## Status log

- **2026-07-16** — P0–P8 implemented; `swift build` clean, **40/40 tests green**
  (reducer, hook install/merge, router, approval center, state machine, HTTP-level
  hook-server integration). Fixed a real fragmentation bug in `LocalHTTPServer`
  (multi-segment HTTP bodies) caught by the integration test.
- Settings subagent died mid-P6 (session limit); panes finished in the main session.
- **Deliberately not done by Claude:** launching the app. Integrations activate only
  after onboarding finishes; Claude hook setup then writes marker-tagged entries into
  `~/.claude/settings.json` (approval interception + terminal-title env) —
  the permission system correctly required that the user run and review this themselves.
  See HANDOFF.md “How to run / verify”.
- **Coexistence note:** this machine already has the real Vibe Island's hooks +
  statusline installed. Both apps can observe sessions simultaneously, but only one
  should answer approvals — quit Vibe Island while testing ours, or enable
  Labs → “Use Native Claude Code Approvals” in ours.
- **2026-07-16 (Phase 2)** — P9–P12 landed via three parallel subagents (Codex adapter
  validated against real local rollouts; questions ⌃1–9 with CGEvent injection; ⌃G
  switcher HUD; Display preview/target, blocked launchers, sound packs, Pass page,
  jump-rules file). Integrated tree: `swift build` clean, **51/51 tests green**.
- **2026-07-17 (Phase 3)** — parity round via three parallel subagents, all landed:
  Gemini CLI adapter (file-watching, fixture-tested; NOTE: the real Vibe Island
  integrates Gemini via hooks in ~/.gemini/settings.json — hook-based upgrade is a
  natural follow-up), approval-card diff/command previews + LiteMarkdown completion
  cards, WezTerm/kitty pane-exact jump drivers (Warp has no public API), pixel-crab
  menu-bar/app icon, Arcade sound pack. Reference-style inline usage header with
  provider cycling; symmetric notch wings (centered expansion). Integrated:
  `swift build` clean, **67/67 tests green**, bundle carries AppIcon.icns.
  Remaining: real-session verification (user), per-provider usage charts, SSH Remote.
- **2026-07-19 (capability audit)** — removed unsupported visible updater, IDE extension,
  SSH Remote, screen-sharing quiet mode, Auto Mode, detect-only agent roster, and duplicate
  fullscreen controls. First launch now defers hooks/listeners/watchers/notification access
  until onboarding completion; reset preserves onboarding; OTLP and threshold alerts default
  off; non-telemetry settings no longer restart ingestion. Added real Codex/Gemini watcher
  toggles, cost-threshold control, live settings preview, current OTel provider semantics,
  provider-aware model formatting, Gemini model propagation/switching, and first-tool Claude
  model refresh. **95/95 tests green**; signed bundle rebuilt.
- **2026-07-24 (reveal card top-clipping)** — auto-reveals (completion, approval, question)
  were drawn in a fixed `revealSize.height` (132pt) island frame while the real cards measure
  181–269pt. SwiftUI centers oversized content inside a fixed frame, so every reveal spilled
  above the window's top edge — the screen's top edge — and lost its first row; the hit rect
  used the same 132pt, leaving the buttons at the bottom of a tall card unclickable. Reveals
  now measure their own content (`IslandContentHeightKey` → `stateMachine.revealContentHeight`)
  and the island *and* the hit rect size to it, clamped to `[revealSize.height, maxIslandHeight]`,
  top-aligned so any residual overflow goes downward. Card content also starts below
  `layout.notchBandHeight` (= notch height + 2, sized from the hardware rather than the
  tunable `headerHeight`) so the physical notch stops cutting through the session row while
  the gap stays tight. Review pass caught two more: the reveal ceiling was `expandedHeight`,
  so Display → Max Panel Height at 300 would have truncated a tall approval card — the window
  is now sized for `max(panel, revealCeiling)`; and the notch-clearance test was tautological,
  replaced with one that fails when the clearance follows the preference instead of the
  hardware. Known and accepted: the hit rect snaps to the new height while the island springs
  into it (~0.4s), the same rect-leads-animation behaviour every expand already had.
  Then the same treatment for the **expanded panel**, which was a fixed `expandedSize.height`
  slab (560pt) no matter how few sessions it held: `PanelContentHeightKey` reports
  `PanelHeaderView.height` (34, now fixed) + the natural height of the list inside the
  ScrollView, and `panelHeight(fitting:)` clamps it to `[120, expandedSize.height]` — so Max
  Panel Height becomes the scroll threshold instead of the size. Measured: 0 sessions 184pt,
  2 sessions 162pt, 4 sessions 284pt. The empty state reports a constant (it is Spacer-padded
  and would otherwise measure its own stretched frame — a layout loop).
  **110/110 tests green**; signed bundle rebuilt.
- **2026-07-25 (recording review vs Vibe Island v1.0.42)** — reviewed a 64s screen recording
  of the live app plus vibeisland.app's feature page and full changelog. Two real bugs found
  and fixed: (1) session titles and "You:" lines showed harness-injected content
  (`counter · [Image: original 2556x1580, displayed at…`, `You: <task-notification> <task-id>…`)
  — new `SessionText.sanitizedPrompt` strips injected `<…>` blocks and attachment
  placeholders on both the hook and transcript paths, and a turn made only of injected
  content no longer becomes a title (their v1.0.40 fixed the same class); (2) the card's TLDR
  line rendered raw markdown (`**What it was:**`) — now goes through `LiteMarkdownText` like
  the reference. Confirmed live in the recording: the panel is content-sized. Parity gap
  noted, not closed: their Detailed strip shows the session title in the pill
  ("fix auth bug"), ours shows only a status word. **116/116 tests green**; bundle rebuilt.
  Gap list vs v1.0.42 (for prioritisation, none started): 26 agents vs our 3; 20+ terminals
  and IDE extensions vs our 4 precise drivers + AX fallback; SSH Remote; localization;
  Sparkle updates/licensing/device management; custom sound files; Silence Rules by prompt
  text; Quiet Hours; pill right-click menu; multi-question wizard; Plan Review feedback +
  Auto Mode; session recap; Glance mode; Codex approvals from the notch; Kimi/GLM/DeepSeek
  usage; diagnostics export; complete uninstall.
- **2026-07-25 (parity + two audits)** — Detailed strip now shows the session title
  (`stripDetailLabel`, title-first with a status-word fallback), capped at
  `NotchWingMetrics.labelWidthCap` so long titles truncate instead of stretching the pill.
  Two read-only subagent audits then found, and this round fixed:
  **Titles** — `TranscriptReader` only understood `{"type":"summary"}`, and current Claude
  Code writes none (verified: 0 summary vs 125 `custom-title` records in a live transcript);
  the tail window holds only tool results, and single records exceed it. Now reads
  `custom-title` / `last-prompt` sidecars (summary kept for older CLIs), `.sessionStart`
  requests a refresh, and the refresh gates widened from `model == nil` to
  `model == nil || title == nil` — one successful model lookup used to disable the retry
  forever. Verified against the real transcripts on this machine. New `TranscriptReaderTests`.
  **Windowing** — click target was inflated to ~354×66pt over the menu bar and the frontmost
  window's toolbar: split into `islandRect` (clicks, exact bounds) and `hoverRect` (sentinel,
  generous). On no-notch displays: the idle strip no longer draws a black tab over the menu
  bar, the 170pt notch gap is gone from the bar, and bar height finally comes from
  `fallbackHandlerHeight`. Added a screen-parameter observer and pointer-display follow (the
  geometry was never recomputed on display changes), "Main Display" now means the primary
  screen rather than `NSScreen.main` (the key-window screen — self-pinning, since the overlay
  takes key for approvals), a nil layout no longer re-shows a stale window, and translucent ×
  transparent fill multiplies instead of overriding. Geometry split into a pure
  `layout(screenFrame:hardwareNotchSize:headerBaseHeight:settings:)` so the fallback is
  testable on a notched Mac; new `FallbackGeometryTests`. **133/133 tests green**; bundle
  rebuilt. Still open from the audits: non-notch displays get no `.canJoinAllSpaces`
  (island vanishes on other Spaces — needs a real multi-display test before changing window
  collection behaviour); fallback handler settings have no Settings UI;
  `hideLiveActivitiesOnNonNotchedScreens` is dead; ⌃G HUD ignores `displayTarget`.
- **2026-07-25 (reveal band)** — the notch band above a reveal read as dead space because it
  was empty. It now carries the panel's actions (sound toggle + settings), right-aligned
  clear of the notch, and the session row sits directly under it with no extra spacing —
  first row at ~42pt, ~10pt clear of a 32pt notch, which is as tight as the hardware allows.
  Reveal cards are 6pt shorter than before while showing more. Same rhythm as the expanded
  panel, matching the reference's reveal (speaker + gear in the band).
- **2026-07-25 (subagents, end to end)** — subagent detection was dead: it matched only
  `tool_name == "Task"` and current Claude Code names the fan-out tool `Agent` (verified: 3
  `Agent` spawns, 0 `Task`, in this project's own transcript). Fixed, then closed the five
  gaps behind it. **Reveals** list agents compactly (3 + "+N more"); the panel lists them all
  with a running count. **Live activity per agent** comes from the subagent transcripts Claude
  Code writes at `<session>/subagents/agent-<id>.jsonl` + `.meta.json`, whose `toolUseId`
  matches our row id exactly — hook payloads for a subagent's inner tool calls carry no parent
  marker, so this is the only precise source (`SubagentActivityReader`, polled every 2s only
  while agents are in flight, ages ticking on a 1 Hz timeline). **Cap** now keeps every running
  agent and trims only finished ones. **Settling** is exact: `SubagentStop` carries `agent_id`;
  and a *background* spawn returns from its tool call at launch (`status: "async_launched"`),
  which we were reading as completion — those rows now stay running until their agent stops.
  **Codex** subagents work from the rollout files: `source.subagent.thread_spawn` threads become
  rows on their parent's card (label from `agent_nickname`/`agent_path`, settled on the child's
  `task_complete`, progress from its agent messages), and `source.subagent.other = "guardian"`
  threads are dropped — on this machine 104 of 197 rollouts are guardians, each of which used to
  surface as its own Codex card showing an internal review prompt. Also fixed: the first-sight
  prepass took the *last* `session_meta`, which in a forked subagent rollout is the parent's
  replayed copy. Classifier over the real corpus: 55 user / 38 fan-out / 104 guardian / 0
  unparsed. **Gemini: not implementable** — the CLI is not installed here, `~/.gemini/tmp` does
  not exist, and the Gemini hook vocabulary has no subagent event; nothing to key on.
  **150/150 tests green**; bundle rebuilt.
- **2026-07-27 (CLI families: 3 integrations → 9)** — most agent CLIs are Claude Code
  derivatives: verified on this machine that `~/.qwen`, `~/.qoder`, `~/.trae`,
  `~/.codebuddy`, `~/.factory` (Droid) and `~/.copilot` all register the *same* hook
  vocabulary and the same `{"hooks": {Event: [{"hooks": [{"type":"command", …}]}]}}` shape our
  `HookRouter` already decodes. So they became data, not code: `HookFamilyCLI` describes each
  (route, config path, binaries, config style), `HookConfigBuilder` is the single merge/strip/
  state implementation (Claude Code's `ClaudeHookCommand` now delegates to it), and
  `HookFamilyAdapter` is one adapter for all of them. The hook server accepts `/hook/<source>`
  and tags the session's agent from the route. Copilot reads a hooks *directory*, so we own
  `tokenisland.json` there — nothing shared to merge. Safety cover: install only adds our
  marker-tagged entries beside another monitor's, backs the file up first (once), uninstall
  restores it to their entries alone, and a moved port reports repairable. Roster now Claude
  Code, Qwen, Qoder, Trae, CodeBuddy, Droid, Copilot, Codex, Gemini — all six new ones detect
  as "Needs setup" here, i.e. installed but not yet hooked. **179/179 tests green**.
  Then both remaining dialects landed, written against each CLI's published hooks reference
  rather than guesswork: **Cursor** (`CursorHookRouter` — `conversation_id`/`session_id`,
  `workspace_roots` array, `beforeSubmitPrompt`, `preToolUse`, and its *separate*
  `beforeShellExecution`/`beforeMCPExecution`/`beforeReadFile` approval gates, `subagentStart`
  with `tool_call_id`, `afterAgentResponse`) and **Gemini CLI** (`GeminiHookRouter` —
  `BeforeAgent`/`AfterAgent` with `prompt`/`prompt_response`, `BeforeTool` as the approval
  gate, snake_case tool names normalised to `Bash`/`Read`/`Edit`…). Approvals now answer in
  the shape each CLI reads — Claude `hookSpecificOutput.permissionDecision`, Cursor
  `permission`, Gemini `decision` — routed by the event's agent; sending the wrong shape reads
  as "no opinion" and the CLI prompts in its own terminal. New `SessionEventKind
  .assistantMessage` records agent text without ending the turn (Cursor reports it separately
  from `stop`). Roster is now 10: Claude Code, Qwen, Qoder, Trae, CodeBuddy, Droid, Cursor,
  Gemini CLI, Copilot, Codex. Also: the welcome/setup walkthrough could only ever be seen once
  — added Settings → General → **Show Welcome Guide** (`AppWindowRouter.openWelcomeGuide`).
  **191/191 tests green**; bundle rebuilt.
  Then update delivery: `UpdateChecker` + `AppcastParser` read a **Sparkle-format appcast**
  (deliberately — the same feed works unchanged when Sparkle's installer is dropped in), pick
  the highest version above the running one, and publish it. Checked on launch and hourly,
  rate-limited to 6h, gated by the `autoCheckForUpdates` setting — which was a dead toggle
  removed in the capability audit and is now back *with* a consumer (the test that banned it
  now asserts the consumer exists). UI: an "Update available — x.y.z" banner in the menu bar
  popover, and an Updates card in About (state, Download, Check now). A build with no
  `SUFeedURL` reports "no release feed" rather than claiming to be up to date.
  **200/200 tests green**.
  Then the release pipeline itself: the bundle now signs with the **hardened runtime** plus a
  `com.apple.security.automation.apple-events` entitlement (without it a notarized build's
  click-to-jump dies silently), takes its version from `TOKENISLAND_VERSION`, and carries
  `SUFeedURL` → the repo's `releases/latest/download/appcast.xml`. `Scripts/release.sh` does
  build → verify signature and entitlement → `ditto` zip → `notarytool submit --wait` →
  `stapler staple` → re-zip with the staple → emit `appcast.xml` → print the `gh release create`
  line. It refuses to run without a Developer ID certificate and explains how to make one, and
  warns rather than pretends when no notary profile exists. `ReleasePipelineTests` round-trips
  the script's own appcast heredoc through `UpdateChecker`, so the writer and the reader cannot
  drift, and pins the distribution requirements (runtime, entitlement, timestamp, staple).
  **204/204 tests green**.
  The user then created a **Developer ID Application** certificate and stored a notary
  profile, so the chain closed the same day: v0.2.0 built, notarized (Apple: Accepted),
  stapled, published to GitHub Releases, repo made public, and the live feed verified by
  feeding the real published appcast through `UpdateChecker` (0.1.0 → offers 0.2.0; 0.2.0 →
  offers nothing).
- **2026-08-04 (Sparkle: updates install themselves)** — Sparkle 2.9.5 via SwiftPM, linked by
  the **executable only** so `swift test` never needs an embedded framework; the library
  exposes one seam (`TokenIslandLaunch.setUpdateInstaller`) that `main.swift` fills with
  `SparkleUpdaterBridge`, and `UpdateChecker.installOrOpenDownload()` uses it when present,
  falling back to opening the release page when it is not. The build script embeds
  `Sparkle.framework` in `Contents/Frameworks` and signs **inside-out** — XPC services,
  Autoupdate and Updater.app individually, then the framework, then the app — because `--deep`
  would re-stamp nested code with the app's identifier and break notarization. `SUPublicEDKey`
  is in the plist; `release.sh` runs `sign_update` and splices `sparkle:edSignature` into the
  enclosure, so Sparkle refuses anything not signed by the private key in the release
  machine's keychain. Verified: app launches with `@rpath/Sparkle.framework` resolved, v0.2.1
  notarized + stapled + signed, `spctl` accepted. `ReleasePipelineTests` now also pins the
  embedding, the inside-out signing, and the presence of the signature.
  **205/205 tests green**. Remaining: publish v0.2.1 and watch a 0.2.0 install update itself
  (the last unproven link), then the terminal-jump matrix.
- **2026-08-01 (idle sessions no longer read as "working")** — opening or resuming a CLI
  showed up as a blue, actively-working agent: `SessionReducer` set `phase = .working` on
  every `SessionStart`, and `synthesizeSession` defaulted the same way. With several
  Claude Code windows merely *open*, the panel claimed several agents were mid-task and
  sorted them above sessions that had genuinely finished. Added a distinct
  `SessionPhase.idle` ("open at its prompt, nothing running", grey — deliberately not one
  of the three signal colors) and mapped `SessionStart` to it. The one exception is
  `source == "compact"`: auto-compaction is the only SessionStart that fires mid-turn, so
  that alone stays `.working`, and `PreCompact` now says `.working` outright instead of
  falling through. `SessionStart` also clears stale `activity`, so a resumed session stops
  advertising the tool it was running when it ended. Idle is `isActive == false`, sorts
  below `.ready` (a result to read outranks an untouched window), and the collapsed strip
  no longer says "Ready" when nothing has run — it falls back to the lead session's own
  word. Card body reads "Waiting for your prompt" with the previous prompt dimmed beneath.
  **153/153 tests green**; bundle rebuilt.
- **2026-08-01 (usage pill: reset countdowns actually render)** — the pill showed
  `5h 58% | 7d 55%` and never the reset time, even though `UsageLimitsSnapshot` already
  carried `fiveHourResetsAt`/`sevenDayResetsAt` and `usageSegment` already rendered a
  countdown when present. Root cause was the parse: `/api/oauth/usage` returns
  `"resets_at": "2026-04-11T07:00:00.528743+00:00"` — microsecond precision — and
  `ISO8601DateFormatter()` parses no fractional seconds by default (and only three digits
  even with `.withFractionalSeconds`), so every window's date came back nil. Confirmed
  against the cached snapshot on this machine, which held percentages and no dates at all.
  `parseTimestamp` now tries fractional, then plain, then strips an over-long fraction and
  retries; `resets_in_seconds` is accepted as a relative fallback. Also fixed in the same
  parser: `utilization` is already 0–100, but a `value <= 1` branch rescaled it, so a
  genuine 1% window rendered as a red 100%. The decode moved out of the network path into
  `snapshot(fromUsageJSON:fetchedAt:)` so the real response shape (including a null
  `seven_day_opus`) is covered by tests. Pill now reads `5h 58% ↻2h14m | 7d 55% ↻3d4h`,
  ticking on a 60s `TimelineView` so it does not freeze while the panel is open, with a
  tooltip giving the wall-clock reset time. **158/158 tests green**; bundle rebuilt.
  Not verified live: the panel refreshes usage only in its `.task`, so a real fetch needs
  the user to open the panel (and approve the Keychain read).
- **2026-08-01 (pet sizes balanced)** — the crab rendered nearly twice the width of every
  other species. `pixelSize` is per-pixel, so a species' footprint is its grid times that
  size, and the crab was drawn at 11x8 against blob 6x6, runner 5x6, bit 5x5 — at 2.4pt
  that is 26.4x19.2 next to 14.4x14.4. Redrew the crab as a 7x7 invader (antennae, eyes,
  two-frame walking legs) rather than scaling it down in the renderer, which would have
  blurred its details while the chunky species stayed crisp. Verified on screen: crab ink
  is now ~1.1x the blob, down from ~1.83x. New `PetSpriteTests` holds the line — max/min
  grid extent must stay within 1.5x, frames must be rectangular and match their declared
  grid, and every species must have two distinct frames. **162/162 tests green.**
  Also confirmed live in the same capture that the usage-reset fix works against the real
  account: the pill now reads `5h 76% ↻1h16m | 7d 57% ↻5h26m`.
- **2026-08-01 (icon art decoupled from the pet sprite)** — rebalancing the crab pet also
  redrew the menu-bar and app icons: `AppIconArt` rendered `PetSpecies.crab.frames[0]`, so
  the two were the same bitmap. They have different jobs — the icon is a lone glyph in a
  square tile and wants the wide detailed silhouette; the pet has to sit in a row beside
  three other species. `AppIconArt.iconFrame` now owns the original 11x8 invader outright,
  and `AppIconArtTests` asserts it stays 11x8 and unequal to the pet frame so this cannot
  silently happen again. Menu-bar icon verified restored on screen. **163/163 tests green.**
- **2026-08-01 (finished Codex runs no longer resurrect)** — a Codex card ("tmp · Say only:
  pong", 58m) sat on the notch with no Codex process running. Not seeded data: a real
  rollout at `~/.codex/sessions/2026/08/01/rollout-…019fbd94….jsonl` whose last record is
  `task_complete`. Cause: Codex has no hooks and writes no exit record, so the watcher's
  only first-sight guard was age — `catchUpMaxAge` 2h — and every relaunch replayed the
  finished run as a live session, which the store then held for `idleCleanupSeconds` (2h).
  Added `completedReplayMaxAge` (300s): on first sight, a rollout whose last turn-lifecycle
  record is a completion AND which has been quiet longer than that is absorbed silently
  (offset + identity only). `endsOnCompletedTurn` scans in reverse and ignores trailing
  `tokenCount`/message heartbeats, so a real completed turn is recognised. Still surfaces:
  a just-finished run (inside the grace, so completion cards still appear), an older run
  with a turn in flight, and the same file if it comes back to life — it announces then.
  Verified by running the watcher over a copy of the real rollout: 0 events emitted.
  **167/167 tests green.**
- **2026-08-03 (production-readiness audit)** — full audit in `Docs/QA_AUDIT.md`.
  Verdict: app is healthy (169/169 green, 85.5 MB idle, 0.2% CPU, no TODOs, no secrets,
  no crash logs); the blockers are packaging, not architecture. Fixed during the audit:
  (1) **hook server was reachable from the LAN** — `NWListener` with plain
  `NWParameters.tcp` binds every interface, so a POST from this Mac's LAN address
  returned HTTP 200; anyone on shared Wi-Fi could inject sessions and forge approval
  prompts. Now `requiredInterfaceType = .loopback`, re-verified LAN-refused /
  loopback-200, covered by `LocalHTTPServerBindingTests` incl. a real LAN probe.
  (2) **Intel Macs could not run the app** — release builds were host-arch only
  (`lipo`: `Non-fat … arm64`); the bundle script now builds `x86_64 arm64`.
  (3) **min-OS mismatch** — `Package.swift` said 14.0, `Info.plist` said 14.6.
  Still open and needing the Apple account: Developer ID signing + notarization
  (`spctl` currently **rejected**, signature ad-hoc). Also open: no git repo/LICENSE/
  README, no updater. **169/169 tests green.**
- **2026-08-03 (marketing site)** — `Website/index.html`, single self-contained file, no
  build step, no external requests (GitHub Pages / Vercel ready). Structure follows the
  reference site's shape; all copy, art and identity are original — no competitor text,
  testimonials or "trusted by" logos were reused. Palette is the app's own state language
  (`#6BB8FF` working / `#61D970` ready / `#FF9F45` needs-you) on `#0A0D14`, the exact tile
  colour from `AppIconArt`. Signature element is a working notch replica: the pets are the
  real `PetSpecies` bitmaps, flipping frames every 450ms like `AnimatedPetView`, cycling
  collapsed → panel → approval-with-diff → done. `prefers-reduced-motion` holds a single
  explanatory frame instead. Claims are limited to what the audit verified — Claude Code
  full, Codex monitoring-only, Gemini experimental — and the Gatekeeper warning is
  disclosed in the FAQ rather than hidden.
  Fixed while building: notch panel overflowed the stage and covered the next section
  (stage now clips and reserves height); session card titles collapsed to zero width on
  narrow screens because the tags are `flex:none` and took no shrink.
  Verified: no horizontal overflow at 375px (`scrollWidth == innerWidth`, zero offending
  elements), titles render, full-page renders checked at 1440px.
- **2026-08-03 (site redesign from a real reference audit)** — the first site read flat next
  to vibeisland.app. Extracted their actual design tokens from the live stylesheet rather
  than eyeballing screenshots (`Website/REFERENCE_AUDIT.md`): `#111111` neutral base (ours
  was blue-black), `rgba(255,255,255,.08)` translucent borders, `--max-w:820px` (ours was
  1080 — the main reason ours sprawled), h1 32px/400 in a bitmap font (ours 64px/800, so
  ours shouted and the mockup didn't carry the page), 13px understated buttons, and a
  three-layer atmosphere (dot matrix + noise grain .15 + god rays .24, plus per-card
  `feTurbulence` grain at .04 `mix-blend-mode:overlay`).
  Three agents each built a full variant (kept in `Website/variants/`); the merged result
  is `Website/index.html`: variant C's left-aligned trace layout with the state-coloured
  wire, the live 4×3 sprite sheet and the real `settings.json` hook entry; plus B's honest
  facts band ("No testimonials here — nobody but us has run it yet", including a
  `Not notarised yet →` chip), B's in-flow notch (removes the old `overflow:hidden`
  clipping hack) and B's accessible Monitor/Approve/Ask/Jump tablist; plus A's 5×7 bitmap
  font drawn as SVG rects — the same technique as the pets, so no font licence and no
  network — used only for the wordmark and the `03` count, headings stay sans.
  **Pet colours corrected to the Swift source**: `#619EFF` / `#61D970` / `#FFB84D` with
  highlight = tint at 0.55 alpha (`PetView.swift`). The old page had invented `#6BB8FF`,
  `#FF9F45` and pastel highlights.
  Verified independently: zero external requests, no webfonts, `scrollWidth ===
  clientWidth` at 375/390/768/1440 (measured in sized iframes — headless `--window-size`
  clamps near 500px and misreports mobile), 4 tabs → 4 distinct DOM states with the right
  attachment each, roving tabindex correct (one selected, one tabbable, Arrow/Home move
  focus), no pixel type in headings, heading order with no skipped levels.
- **2026-08-03 (repository scaffolded and pushed)** — `git init` → `rmm-code/tokenisland`
  (private, `main`). Added `.gitignore`, MIT `LICENSE`, `README.md`, `CONTRIBUTING.md` and
  a GitHub Actions CI workflow (build + test on macos-14, plus a job that builds the
  universal binary and asserts `lipo` reports both slices — the exact bug that shipped an
  Intel-incompatible app). Initial commit: 179 files, 1.2 MB.
  Excluded by `.gitignore`, all confirmed absent on the remote: `island/` (337 MB of the
  reference app's screenshots and recording — not ours to redistribute, and over GitHub's
  file limit), `promo/` (738 MB, has its own nested `.git` and node_modules — would have
  become a broken submodule), `outputs/` (276 MB of debug captures), `.build/` (1.1 GB),
  `Website/` (per the user, tracked separately), and `Docs/VIBE_ISLAND_BLUEPRINT.md`.
  Verified before pushing: no secrets, no files >200 KB, and no staged file referencing
  `/Users/mardonjon`. Commit authored and committed as the user with no attribution
  trailers, per their request.
  **Open before flipping the repo public:** `CLAUDE.md` is tracked and still describes the
  project as a recreation of Vibe Island and points at the (now untracked) `island/`
  reference folder — that framing should be rewritten first.
- **2026-08-03 (site notch made faithful to the real thing)** — the mockup was a stylised
  panel: a uniform black block covering the whole menu bar, with text-only provider tags.
  Fixed three things against the source rather than by eye.
  (1) **Silhouette.** On a real Mac only the camera housing interrupts the menu bar and the
  panel hangs below it, so the shape is narrow-above-wide. `.notch` now starts below the
  24px menu bar and a `::before` bridges up through it at the hardware width (measured
  118px tab vs 256px panel). This also matches why `notchBandHeight` exists in
  `TokenIslandScreenGeometry`: content drawn in that band is physically cut.
  (2) **Real provider marks.** The Claude and Codex SVG paths are extracted straight out of
  `Sources/TokenIslandKit/Resources/ProviderIcons/` into inline `<symbol>`s, so the site
  can't drift from what the app ships. Claude keeps its own `#D97757`; Codex is the white
  template mark. Verified rendered fill is `rgb(217,119,87)`.
  (3) **Usage header** now leads with the provider mark and carries the reset countdown
  (`5h 62%  7d 18%   resets in 1h 12m`), matching the panel-header pill.
  Verified: 4/4 marks render non-zero, both symbols resolve, panel sits flush under the
  menu bar, no overflow at 375/768/1440.
  **Correction (same day):** the narrow-above-wide silhouette above was wrong. The island
  is an overlay window that *covers* the menu bar (see the Status notes), so the black
  starts at y=0 and the menu bar reads either side of it — no step. Reverted to a single
  flush-topped panel and capped its width at `min(68%,470px)`; at 86% it swallowed the
  whole bar on a narrow stage and stopped reading as a notch. Measured: flush at top and
  118-174px of menu bar visible on both sides at 768/1100/1440. Wallpaper rebuilt from
  diffuse radial blobs into swept SVG ribbons — the blobs read as "a gradient", the
  ribbons read as a desktop, which is what makes the black island pop.
  **Note:** capturing the real notch for reference was abandoned — warping the cursor into
  it triggers the user-initiated usage refresh, which raises a Keychain password prompt.
  The prompt was left untouched and cancelled by quitting the app; the captures (which also
  held unrelated private content) were deleted. Don't automate hover over the notch.
- **2026-08-04 (site panel ported from the app instead of guessed)** — the mockup had an
  invented pets-and-label strip row inside the *open* panel. That row is the COLLAPSED
  state; `PanelHeaderView` shows a usage pill, a close button, then sound and settings
  pushed right, and nothing else. Rebuilt the site panel against the real sources rather
  than by eye:
  `PanelHeaderView` — 34pt row, padding 10/14/4; usage pill on `rgba(255,255,255,.07)` at
  radius 7, provider mark on a 17x17 tile at radius 4.5 filled `rgb(.85,.35,.13)` = #D9591F,
  segments `5h 62% ↻1h12m | 7d 18% ↻4d6h` at 10.5pt mono with the `|` at white 25%.
  `SessionChip` — 10.5pt semibold, padding 7/3, radius 6; the Claude chip is #E89957 on
  #4D3019, everything else white .72 on white .10.
  `SessionCardView` — pet in a 44pt centred column, 12pt gap, 14pt bold title, rows flat on
  black with the white-6% fill as hover/focus rather than a permanent card.
  Verified: tile renders `rgb(217,89,31)`, Claude chip `rgb(77,48,25)`/`rgb(232,153,87)`,
  pet column 44px, strip gone, no JS errors, 4 tabs → 4 distinct states, pets still flipping
  2 frames on the 450ms cadence, no overflow at 375/768/1440, menu bar visible both sides.
  **Measurement note:** the crab's two frames have identical markup length, and 1000ms is
  ~2 flips (same parity), so both `innerHTML.length` and a single 1s before/after comparison
  read as "frozen" when the animation is fine. Sample several times at sub-cadence intervals
  and compare content.
- **2026-08-04 (site demo starts closed, hover opens it)** — the mockup sat permanently
  expanded, which skipped the actual interaction and left no reason for it to be open.
  The island now starts COLLAPSED (232px: walking pets, lead session, count — the strip
  that belongs to that state) and expands to 470px on real `:hover`/`:focus-within`, the
  same declaration block the scene buttons drive via `.open`. A drawn pointer walks up into
  the island when the demo opens it unattended, and yields to `opacity:0` the moment a real
  pointer enters the stage, so an auto-opened panel reads as "something hovered it".
  Reduced motion holds it open with no pointer choreography.
  Bug found and fixed on the way: the open rule set `.phead{display:block}`, which killed
  its flex layout so the spacer stopped pushing sound/settings to the right edge — now
  `flex` for the header and `block` for the list.
  Verified in a fresh frame: closed at load (232px, strip visible, pointer shown), open
  after the pointer arrives (470px, strip hidden), header `display:flex` with icons 14/31px
  off the right edge, a scene click opens it and renders that scene, hover rule present,
  no overflow at 375/768/1440.
- **2026-08-04 (island expansion now uses the app's actual spring)** — the web mockup eased
  open with `cubic-bezier(.32,.72,0,1)` over 340ms, which is why it felt unlike macOS.
  `TokenIslandNotchView.notchAnimation` is
  `.interactiveSpring(response: 0.42, dampingFraction: 0.80, blendDuration: 0.12)` applied
  to BOTH `state` and `visibleSize` — an underdamped spring, and a cubic-bezier is
  monotonic so it structurally cannot express the settle.
  Sampled the damped-oscillator solution (w0 = 2pi/0.42 = 14.96 rad/s, zeta = 0.80,
  wd = 8.976) into a 49-stop CSS `linear()`: 577ms to settle, peak 1.0152 at 60% of the
  duration, non-monotonic. Also ported the per-state geometry from
  `topRadius`/`bottomRadius`/`shadowRadius`/`shadowOpacity` at the shipped defaults
  (islandCornerRadius 32, shadowIntensity 0.58): collapsed 5/17.9px with
  `0 5px 10px rgba(0,0,0,.08)`, open 8/32px with `0 18px 50px rgba(0,0,0,.58)`, all three
  properties riding the same spring. Added `overflow:hidden` to match the app's
  `.clipShape(TokenIslandNotchShape)`, so the panel is revealed by the island growing over
  it rather than appearing beside it.
  Token clash caught: `--spring` was already defined (and redefined *after* mine) for
  button/card micro-interactions, so the island's spring lost the cascade — renamed to
  `--island-spring`/`--island-dur`.
  Verified: easing resolves to `linear(0 0%, 0.0147 2.08%, ...)`, duration 0.577s, closed
  232px / open 470px with the right radii and shadows, chips stay on one 24px row in all
  three cards, zero external refs.
  **Measurement note:** headless `--virtual-time-budget` freezes CSS transitions partway, so
  a still can catch the island at collapsed width with open content — that is the harness,
  not a layout bug. And `requestAnimationFrame` is throttled in an offscreen iframe, so the
  curve cannot be sampled that way; assert on the resolved `linear()` stops instead.
- **2026-08-04 (site deployed to the VPS)** — the marketing site now lives in its own repo,
  `rmm-code/tokenisland-web` (private), rather than in this one; `Website/` stays untracked
  here. `variants/` and `REFERENCE_AUDIT.md` are gitignored out of it — the audit is
  research on a competitor's site and has no business in a publishable repo.
  Server: 79.143.176.109, Ubuntu 24.04, nginx, **~20 live client sites**. Surveyed
  read-only first. Key hazard found: there is **no `default_server`**, so the bare IP is
  answered by whichever vhost loads first — a careless config here would hijack traffic for
  every other site. The vhost is therefore named-only (`tokenisland.uz www.tokenisland.uz`)
  and explicitly not a default; `nginx -t` was run before any reload, and the reload was
  graceful.
  Deploy path: the server already had working `gh` auth, so it clones the private repo
  directly — no new credentials were put on the box. Update with
  `ssh root@79.143.176.109 'cd /var/www/tokenisland && git pull --ff-only'`.
  Verified after reload: tokenisland.uz -> HTTP 200 / 77939 bytes with the right title,
  `/.git/config` -> 403, and sifatly/taomly/eiuedu/anorjon/tesol/texn/mardonjon.me all
  still answering 301 as before, with the bare IP still NOT serving our site.
  **Still outstanding:** `tokenisland.uz` resolves to Cloudflare (104.21.83.172 /
  172.67.179.62), not the VPS, so it is not publicly live yet. Repoint the A record to
  79.143.176.109, then `certbot --nginx -d tokenisland.uz -d www.tokenisland.uz`
  (certbot 2.9.0 is installed).
- **2026-08-04 (HTTPS fixed — the 443 half of the default_server hazard)** — after DNS was
  pointed at the VPS, `http://tokenisland.uz` served the site correctly but
  `https://tokenisland.uz` returned 307 -> /login showing **Sifatly's Next.js app**. Not a
  Cloudflare problem: the deployed vhost only had `listen 80`, and Cloudflare proxies to the
  origin on 443, where nginx found no server block for the host and fell through to the
  first-loaded HTTPS vhost. Same default_server hazard identified during the survey, missed
  on the 443 side. Confirmed by hitting the origin directly with `--resolve` (also 307), which
  ruled Cloudflare out.
  Fixed with `certbot --nginx -d tokenisland.uz` (apex only — `www` has no DNS record, so
  including it would have failed HTTP-01). Vhost backed up to
  `/root/tokenisland.uz.vhost.bak.*` first.
  Verified: origin:443 -> 200/77939, public https -> 200/77939 with the right title,
  0 hits for "sifatly" in the served HTML, cert CN=tokenisland.uz valid to 2026-11-02, and
  sifatly/taomly/eiuedu/anorjon/tesol/texn/mardonjon.me all still 200 over HTTPS.
  **Lesson:** on a multi-site box, a new vhost must cover BOTH 80 and 443 before DNS is
  pointed, or the domain silently serves someone else's app over TLS.
  Outstanding: no `www.tokenisland.uz` DNS record (Cloudflare flags it); add the record then
  re-run certbot with `-d tokenisland.uz -d www.tokenisland.uz` if www is wanted.
- **2026-08-04 (SEO pass + ru/uz localisation)** — audited against the checklist the user
  supplied. Was already fine: original content, one h1 with no skipped levels, clean URLs,
  mobile-friendly (no overflow 375–1440), no keyword cannibalisation, no orphan pages.
  **Biggest risk checked and cleared:** JS crawlability. Comparing raw HTML against the
  `--dump-dom` render showed only 58 JS-only words, all demo-mockup strings; every heading
  and all real copy is static.
  Fixed: title 70 → 52 chars, description 191 → 157, plus canonical, og:url/image/site_name/
  locale, Twitter summary_large_image, robots meta, and a 4-entry hreflang set. JSON-LD
  `@graph` with SoftwareApplication + Person (E-A-T) + WebSite + FAQPage, the FAQ generated
  from the real `<details>` so schema can't drift. Added robots.txt, sitemap.xml with
  per-URL hreflang, and og.png rendered from the actual hero.
  Localisation is **build-time, not JS** — `/`, `/ru/`, `/uz/` are separate crawlable URLs
  with a real `<a href>` switcher. `build.py` masks script/style/pre/code and the
  diff/hook/terminal blocks before substitution, so code is never translated; verified the
  ru/uz builds have byte-identical `<script>` blocks and identical tag counts to the source.
  Two bugs of mine caught by verification: keys are stored stripped while the document
  indents its text nodes, so exact-match replacement silently left the lede and the CTA in
  English (fixed with a whitespace-tolerant pattern); and `build.py`/`i18n.json` were
  publicly fetchable — `Disallow` is advisory, so they are now `deny all` in nginx (403).
  Cloudflare **prepends its own managed robots.txt** (AI content-signals) but keeps our
  rules and the Sitemap line — checked, not a problem.
  Live: / /ru/ /uz/ /robots.txt /sitemap.xml /og.png all 200; build inputs 403; and
  sifatly/taomly/eiuedu/tesol/mardonjon.me all still 200.
  Outstanding: no `www` DNS record; Cloudflare SSL mode should be Full (strict) now the
  origin has a real cert; backlinks and keyword-volume research need tools I don't have.

- **2026-10-01 (integration reliability fixes after code audit)** — reproduced the
  incorrect Claude PermissionRequest response schema, Cursor/Gemini installation
  schemas, malformed-config overwrite, mixed-group ownership loss, restart opt-out
  loss, and native-mode allowlist override. Corrected verdict serialization and
  introduced per-dialect profiles plus shared strict configuration file handling.
  Integration switches now persist disable/re-enable intent and update errors/status
  immediately. Native mode releases parked calls; timeout leaves a terminal-waiting
  card; resolving one of several requests preserves the remaining request's preview.
  Cursor/Gemini tool gates monitor activity without parking every ordinary tool call;
  approvals stay in their native CLI. Gemini selects a single source and drops cards
  from a previous source on switches. HTTP tests use the production event handler.
  Split the pre-existing 775-line reducer/router test file at its class boundary.
  Validation: 238 tests pass, including real localhost round trips and fixture-only
  config changes. Universal release bundle builds for arm64/x86_64. Local signing
  verification passes outside the sandbox. No app launch or real CLI config edits.
  Evidence/report: local `outputs/bug-reproducer-report.md` and evidence JSON.
  Live third-party CLI behavior, VoiceOver, and a visual walkthrough remain unverified.

- **2026-10-05 (usage limits freshness audit and fix)** — the installed app showed
  the exact percentages from a September 17 snapshot (5h 1%, weekly 49%), with
  overdue resets rendered as “soon”. Reproduced stale restoration, expired reset
  wording, relative reset anchoring, and stale Codex records via focused tests.
  Removed the account-independent persisted usage cache and process-lifetime
  credential token. Added typed fetch/access failures, bounded rotation retry,
  request deduplication, automatic visible-panel polling, wake/reset handling,
  provider-directed Retry-After, and explicit Refresh/Connect controls. Old values
  are hidden on failures, age expiry, and reset boundaries. Current Keychain login
  wins over legacy files; automated paths remain noninteractive. Decoder shows
  every valid reported model window and validates numbers/aliases. Split network,
  credentials, decoding, service policy, and header presentation into cohesive files.
  Validation: 269 workspace tests passed, including mock HTTP, clock and credential
  cases. Signed universal v0.2.3 installed with user approval. The live API returned
  401 for the old CLI login; Claude Code's own read-only /usage startup renewed it
  after explicit workspace-trust approval. TokenIsland then received HTTP 200 and
  displayed live 5h 39%, weekly 14%, with future reset dates. A live edge case led
  to per-window expiry filtering so an expired optional limit cannot hide valid
  primary limits. Expiry metadata supports seconds/ms; the server decides whether
  a credential is accepted. No model prompt was sent and no token was logged.
