# TokenIsland — production readiness audit

Audited 2026-08-03 against the built bundle, a running instance, and the source.
Every claim below was verified by running something, not by reading code alone.

## Verdict

**Not ready to ship to other people yet.** The app itself is in good shape — 169/169
tests green, no crash logs, 85 MB idle, no TODOs, no hardcoded secrets. What is missing
is everything between "works on my Mac" and "a stranger can install it": a distributable
signature, and a repo.

Nothing found is deep or architectural. The blockers are packaging and distribution.

## Platform support (answers: which Macs, which OS)

| | Status |
|---|---|
| **Apple Silicon** | Supported. |
| **Intel** | Now supported — was NOT before this audit (see B2). |
| **Minimum OS** | macOS 14.0 Sonoma. Was inconsistent (see B3). |
| **Notch required?** | No. On non-notch Macs the strip appears only when sessions exist. |

## Blockers — must fix before distributing

### B1. Not signed for distribution, not notarized — **open**
`codesign` reports `Signature=adhoc`, `TeamIdentifier=not set`. `spctl -a -t exec`
returns **rejected**. On anyone else's Mac, Gatekeeper refuses to open it; macOS 15+
makes the right-click-Open workaround deliberately hard to find.

Requires an Apple Developer Program membership ($99/yr), then:
- sign with a **Developer ID Application** certificate,
- add `--options runtime` (hardened runtime — required for notarization),
- add an entitlements file,
- `notarytool submit` + `stapler staple`,
- ship a `.dmg` or `.zip`.

This cannot be done from here — it needs the Apple account.

### B2. Intel Macs could not run the app — **fixed in this audit**
`swift build -c release` builds host-arch only, so building on Apple Silicon produced an
**arm64-only** binary. Verified: `lipo -info` reported `Non-fat file … arm64`.
`Scripts/build_app_bundle.sh` now passes `--arch x86_64 --arch arm64`; the bundle is
`x86_64 arm64`. `TOKENISLAND_HOST_ONLY=1` keeps the fast path while iterating.

### B3. Minimum-OS mismatch — **fixed in this audit**
`Package.swift` declared `.macOS(.v14)` while `Info.plist` said `LSMinimumSystemVersion
14.6`, silently locking out every 14.0–14.5 Mac. Now both say 14.0.

### B4. No repository — **open**
There is no `.git`, no `LICENSE`, no `README`, no `.gitignore`. Required before any
open-source plan. No secrets found in the tree, so history starts clean.

### B5. No update mechanism — **open**
No Sparkle, no appcast. Every update means the user manually re-downloading. Fine for a
first release; needed soon after.

## Security

### S1. Hook server was reachable from the LAN — **fixed in this audit**
`NWListener` was created with plain `NWParameters.tcp`, which binds **every interface**.
The log line claimed `127.0.0.1`; `lsof` showed `*:47791`. Verified exploitable: a POST
from this Mac's own LAN address `192.168.0.151:47791` returned **HTTP 200**.

Impact: on shared Wi-Fi, anyone could inject fake sessions and — because the hook server
parks `PermissionRequest` events for the user to approve from the notch — **forge
approval prompts**, inviting the user to approve an action they never initiated.

Fixed with `requiredInterfaceType = .loopback`. Re-verified after the fix: LAN address
**refused**, `127.0.0.1` still **200**. `LocalHTTPServerBindingTests` covers both the
parameters and a real end-to-end LAN probe.

### S2. Egress is limited and matches a "fully local" claim — **verified**
Only three hosts appear in source: `127.0.0.1`, `api.anthropic.com/api/oauth/usage`
(read-only usage, user's own OAuth token), and `api.openai.com` (a default value in
legacy proxy settings, not called on the default path). OTLP receiver defaults **off**.
No analytics, no telemetry.

### S3. Credential handling — **verified sound**
The Claude token is read from the user's own Keychain, never written anywhere, held in
memory for the process lifetime, and dropped on 401/403. Automatic refreshes are
forbidden from showing a Keychain prompt; a declined prompt is never re-asked that run.

## Code health

- **169/169 tests green.** No crash reports; `last-exception.log` absent.
- **85.5 MB RSS idle, 0.2% CPU** — under the "under 100 MB" claim.
- **No TODO/FIXME/HACK anywhere** in `Sources` or `Tests`.
- **No hardcoded secrets.**
- **700-line rule:** all sources pass (largest `AppSettings.swift`, 526).
  `Tests/…/SessionReducerTests.swift` is 775 — the one violation, worth splitting.
- **Accessibility:** 27 annotations across the UI. Not audited with VoiceOver.
- **Localization:** none — English only, strings hardcoded.

## Known gaps (functional, not blocking)

- **Gemini** is fixture-tested only; never validated against real local data. The real
  Vibe Island uses hooks in `~/.gemini/settings.json` — a hook-based upgrade is the
  natural next step. Do not advertise Gemini until it emits real sessions here.
- **Real-session verification by the user is still outstanding**: approvals ⌃Y/⌃N,
  questions ⌃1–9, ⌃G switcher, a live Codex run.
- **SSH Remote** and per-provider daily/monthly usage charts are unimplemented.
- **Codex/Gemini sessions have no exit signal**, so finished ones linger until the 2 h
  idle cleanup where Claude's vanish in 8 s. Partly addressed 2026-08-01.
- **Multi-display / external monitor** behaviour untested.
- Only **Claude** is fully wired (hooks). Codex/Gemini are file-watchers.

## Suggested order

1. B4 (git + LICENSE + README) — unblocks everything else.
2. B1 (Developer ID + notarization) — the real gate on other people using this.
3. Real-session verification of approvals/questions/jump.
4. B5 (Sparkle) before the second release.
5. Split `SessionReducerTests.swift`; VoiceOver pass.
