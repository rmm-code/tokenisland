# Contributing

Thanks for taking a look. This is a small, opinionated codebase — reading the rules below
first will save you a review round.

## Getting set up

```bash
swift build
swift test                            # must stay green
bash Scripts/create_signing_identity.sh   # once — see below
bash Scripts/build_app_bundle.sh
open .build/TokenIsland.app
```

macOS ties Keychain and Accessibility grants to the code signature. Without a stable local
identity, every rebuild reads as a brand-new app and re-asks for every permission, which
makes testing miserable. Run `create_signing_identity.sh` once.

Always test the `.app` bundle, not `swift run` — permissions stick to the bundle.

### Testing without a real agent

```bash
./Scripts/dev_seed_sessions.sh
```

This drives the whole notch UX — pets, cards, approvals, completion reveals — against the
local hook server, so you don't need a live `claude` run to work on the UI.

## House rules

- **No source file over 700 lines.** Split before it gets close.
- `swift build` and `swift test` green after every change. No exceptions.
- UI and state live on `@MainActor`. Services are `actor`s or `@MainActor` classes.
- **Adapters own all CLI-specific logic.** Never write another tool's config from outside an
  adapter. Always marker-tag entries we add (`#tokenisland-hook`) and back the file up
  before the first write — this is somebody's real editor config.
- **SwiftUI must never drive AppKit window frames.** Every `NSHostingView` we create sets
  `sizingOptions = []`; without it macOS 26 hits a constraint loop and crashes.
- **Never give notch content a fixed height it can outgrow.** SwiftUI centres oversized
  content, and since the island hangs off the top of the screen the overflow lands
  off-screen and destroys the first row. Measure content and size to it.
- Fail open. If Token Island is broken or not running, the user's agents must behave
  exactly as they would without it.

## Tests

Tests are the specification here, and several encode bugs that were expensive to find —
please don't delete one to make a change pass. If a test is wrong, say so in the PR and
explain why.

Prefer a test that would have caught the bug over a test that restates the implementation.

## Pull requests

- Keep the diff focused. Unrelated cleanups belong in their own PR.
- Say what you verified and how. "Tests pass" is weaker than "seeded an approval and
  confirmed ⌃Y returns the verdict as hook stdout".
- Match the surrounding code's comment density and naming. Comments here explain *why*,
  especially where the code looks odd because a platform bug forced it.
- UI changes: include a before/after screenshot.

## Reporting bugs

Include your macOS version, Mac model (Apple Silicon or Intel), which agent CLI and
version, and whether the app was built from source or downloaded.

If the app crashed, attach
`~/Library/Application Support/TokenIsland/last-exception.log` — an uncaught-exception
logger writes it, and it's the first thing to read for any crash.

## Security

Please don't open a public issue for a security problem. Report it privately through
GitHub's security advisories on this repository.
