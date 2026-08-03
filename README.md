# Token Island

Every running AI coding session as a pixel pet in your Mac's notch — blue while it works,
green when it's done, orange when it's blocked on you. Approve permissions, answer
questions, and jump to the exact terminal without leaving the window you're in.

Native macOS app. Swift and SwiftUI, no Electron. Everything stays on your machine.

> **Status: pre-release.** The app is feature-complete for Claude Code and has a green test
> suite, but it is **not notarised yet**, so macOS will warn you on first launch (see
> [Installing](#installing)). There is no auto-updater. Treat it as a beta.

## What it does

- **A pet per session.** Four sprite species, colour-coded by state. You learn three
  colours once and stop checking terminals to find out whether something needs you.
- **Approve without switching.** Permission requests arrive in the notch with the command
  or diff attached. `⌃Y` allows, `⌃N` denies, `⌃A` allows that tool from then on.
- **Answer questions with one key.** When an agent asks something with options, they're
  numbered in the notch — press `⌃1`–`⌃9`.
- **Jump to the exact terminal.** Not the app: the specific window, tab and split pane the
  session is running in. Terminal.app, iTerm2, WezTerm and kitty are matched by TTY.
- **Session switcher.** `⌃G` for a HUD across every running session.
- **Usage limits.** Your 5-hour and 7-day windows with time-until-reset, read from your own
  account. Codex limits come from its own session files.
- **8-bit sound cues.** Three synthesised packs, generated at runtime — no audio files.

## Supported agents

| Agent | Support | What works |
| --- | --- | --- |
| **Claude Code** | Full | Live status, permission approvals, numbered questions, completion summaries, subagent rows, jump-to-terminal. |
| **Codex** | Monitoring | Live status, subagent rows, rate limits, jump. **No approvals** — Codex has no hook mechanism, so sessions are read from the files it already writes. |
| **Gemini CLI** | Experimental | Implemented against fixtures and never verified against a real session. Off by default. |

## Requirements

- macOS 14.0 Sonoma or later
- Apple Silicon or Intel (the app builds as a universal binary)
- A Mac with a notch is **not** required — on other Macs the strip appears at the top of
  the screen only while sessions are running

## Installing

No signed release yet. Build it from source:

```bash
git clone https://github.com/rmm-code/tokenisland.git
cd tokenisland
bash Scripts/build_app_bundle.sh
open .build/TokenIsland.app
```

`build_app_bundle.sh` produces a universal binary and signs it with a local self-signed
identity if one exists. Run `bash Scripts/create_signing_identity.sh` **once** first —
macOS ties Keychain and Accessibility grants to the code signature, so without a stable
identity every rebuild looks like a new app and re-asks for every permission.

Always launch the `.app` bundle rather than `swift run`; the permissions stick to the
bundle.

### The Gatekeeper warning

The app is not notarised (that needs a paid Apple Developer account), so macOS will refuse
to open it on first launch. Right-click the app → **Open** → **Open**. Building from source
yourself avoids the question entirely.

## How it works

```
Claude Code hook ──POST──> 127.0.0.1:47791 ──> HookRouter ──> SessionStore ──> notch UI
                                                              (pure reducer)
```

On setup, Token Island adds hook entries to `~/.claude/settings.json`, marker-tagged with
`#tokenisland-hook` so they can be found and removed, and backs the file up before the
first write. Those hooks post session events to a listener **bound to loopback only**.

Permission requests are *parked*: the hook stays open while the request waits in the notch,
and your verdict is returned as the hook's own stdout. Everything fails open — if Token
Island isn't running, your agents behave exactly as they would without it.

Codex and Gemini have no hook mechanism, so those sessions come from file watchers over the
session logs they already write.

## Privacy

No account, no cloud relay, no telemetry, no analytics. Session data never leaves the
machine. The only outbound request is optional: if you enable usage limits, the app reads
Anthropic's usage endpoint using the token already in your Keychain. It only reads.

## Development

```bash
swift build     # Swift 6, strict concurrency
swift test      # full suite — keep it green
```

House rules that matter:

- **No source file over 700 lines.** Split before it gets close.
- UI and state on `@MainActor`; services are actors or `@MainActor` classes.
- Adapters own all CLI-specific logic. Never write another tool's config outside an
  adapter, always marker-tag entries, and back up before the first write.
- Every `NSHostingView` sets `sizingOptions = []` — SwiftUI must never drive AppKit window
  frames, or macOS 26 hits a constraint loop and crashes.

`Docs/` carries the architecture notes, the execution plan and status log, and a
production-readiness audit (`Docs/QA_AUDIT.md`).

## Known limitations

- Not notarised; no auto-updater.
- Gemini support is unverified against real sessions.
- Codex sessions can't be approved from the notch, and Codex writes no exit record, so a
  finished session lingers longer than a Claude one.
- Multi-display and external-monitor behaviour is untested.
- No VoiceOver pass yet.
- English only.

## Contributing

Issues and pull requests are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md).

## Licence

[MIT](LICENSE).
