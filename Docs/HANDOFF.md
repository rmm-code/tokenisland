# Handoff

Current product: **Vibe Island-style agent session monitor** (pivot landed
2026-07-16). Spec of record: `VIBE_ISLAND_BLUEPRINT.md`. Execution plan and
phase status: `PLAN.md` (P0–P12 plus capability audit).

## What works (built + unit-tested, needs on-machine verification)

- **Session spine** — Claude Code hooks POST to `127.0.0.1:47791`;
  `SessionReducer` (tested) turns them into `AgentSession`s in `SessionStore`.
- **Hook auto-install** — completing onboarding runs `AdapterRegistry.autoConfigure()`:
  marker-tagged entries merged into `~/.claude/settings.json`
  (one-time backup at `settings.json.tokenisland-backup`; uninstall from
  Settings → Integrations). Hooks apply to NEW claude sessions only.
- **Notch UI** — pets in the collapsed strip (blue/green/orange = working/
  ready/approval), hover peek, expanded session cards, completion cards,
  approval cards, dwell-based auto-reveals. Hover and click open the full panel.
- **Click-to-jump** — Terminal.app/iTerm2 exact-tab via AppleScript TTY match
  (Automation permission prompts on first use), AX title-marker scan
  otherwise (Accessibility permission), app activation as last resort.
  Titles become `claude — <task-slug>` via hook `terminalSequence`.
- **Notch approvals** — PreToolUse calls for write-ish tools are parked
  (permission-mode aware) until Allow/Deny/Always/Bypass or a 55s fail-open;
  ⌃Y/⌃N/⌃A/⌃B/⌃T shortcuts while the panel is open. Labs → native approvals
  toggle short-circuits everything.
- **Sound** — synthesized 8-bit cues (start/complete/error/approval).
- **Onboarding** — 5 steps ending in the pixel boarding pass.
- **Usage limits header** — opening the panel refreshes automatically from the
  credentials file, cached quota values, or a Keychain query configured with
  interaction disabled. It cannot display a password prompt. Activating an
  unavailable Claude value is the only path that may request Keychain access.
- **Settings** — sidebar window (General / Integrations / Notifications /
  Display / Sound / Usage / Shortcuts / Labs / Pass / About). Every visible
  control has runtime behavior; legacy OTLP/proxy lives under Labs and defaults off.
- **Agent coverage** — Claude hooks plus passive Codex and Gemini file watchers.
  Settings exposes real monitoring toggles and model chips support current provider IDs.

## How to run / verify

```bash
swift build && swift test          # all tests green expected
bash Scripts/build_app_bundle.sh   # creates .build/TokenIsland.app
open .build/TokenIsland.app        # always launch the signed app bundle
./Scripts/dev_seed_sessions.sh     # fake two sessions; full notch UX demo
```

Real-session check: launch app → grant Accessibility when prompted → open a
NEW `claude` session in Terminal → pet appears (blue), Stop turns it green
with a completion reveal; `Bash` tool calls under default permissions raise
the approval card.

First launch does not install hooks, start listeners, or request notification
permission before onboarding completes. Finishing onboarding can install hooks into
`~/.claude/settings.json` (reversible; backup kept). Accessibility is requested from
onboarding; Automation is only requested by an exact terminal jump. Automatic Claude usage refresh
forbids Keychain interaction UI; explicit retry is the only path that may ask
for read-only access when macOS has not already granted it.

## Known gaps / next

- Validate Gemini watcher behavior against a real Gemini CLI recording; fixture coverage is green.
- Additional agents, SSH Remote, and IDE extensions are intentionally absent until
  they can emit real sessions end-to-end.
- PreToolUse holds can't see Claude Code's own allow-rules; rare 55s stalls
  on auto-allowed write tools — mitigated by Always/Bypass and Labs native
  mode.
- Transcript JSONL format is officially unstable; reader is defensive and
  secondary (Stop hook carries the completion text).
- Old unsupported setting keys remain decode-only for migration compatibility and
  are not exposed in Settings.
- Bundle/product rename (TokenIsland → final name) deliberately deferred.
