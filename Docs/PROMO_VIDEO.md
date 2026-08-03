# Promo video — runbook

Social demo for X / Threads / LinkedIn, modelled on the hero video at
vibeisland.app/ai-coding-session-tracker. Deliverables: 16:9, 1:1, 9:16 with
burned-in captions.

Tooling lives in `Scripts/promo_scene.sh` (drives the scene) and
`Scripts/promo_export.sh` + `Scripts/promo_caption.swift` (cuts the exports).

## Ground rules

- **Sample repos only.** `payments-api`, `web-dashboard`, `mobile-app`,
  `infra-scripts`. No real client repos (admire-agency-portfolio, tarjimonchi,
  sifatly, oquvly, vitamentor) and no personal PDFs may appear in frame. Note
  `Scripts/dev_seed_sessions.sh` uses real repo names — it is **not** the promo
  script; use `promo_scene.sh`.
- **Shoot on a fresh Space**, never the working desktop.
- Only one app may answer approvals — quit the real Vibe Island if it is
  running (`pgrep -fi vibe`).

## Shoot order

1. Fresh Space; hide desktop icons:
   `defaults write com.apple.finder CreateDesktop false; killall Finder`
2. `bash Scripts/build_app_bundle.sh` then launch `.build/TokenIsland.app`
   (the user launches it — onboarding must be complete, and hook install
   writes marker-tagged entries into `~/.claude/settings.json`).
3. `./Scripts/promo_scene.sh setup` — opens four Terminal windows and seeds
   four working sessions. Off camera; grants Automation on first run.
4. Start the screen recording (⇧⌘5, or `screencapture -v take.mov` from the
   user's own terminal). **The user starts this, not Claude** — capture
   launched from Claude inherits Claude's TCC grant, which is the standing
   blocker below.
5. `./Scripts/promo_scene.sh run` — plays the beats with a lead-in. Press
   **⌃Y** when the approval card appears, **⌃2** when the question card does.
6. Stop recording. `./Scripts/promo_scene.sh teardown`, then restore icons:
   `defaults write com.apple.finder CreateDesktop true; killall Finder`
7. `./Scripts/promo_export.sh take.mov outputs/promo`

## Beat sheet (~30s)

| t | On screen | Caption |
|---|---|---|
| 0–4s | Collapsed notch, pets walking, 4 sessions | 4 AI agents. One notch. |
| 4–9s | Hover → panel, session cards | Blue = working. Green = done. Orange = needs you. |
| 9–16s | Approval card + Edit diff → ⌃Y | Approve changes without leaving your editor. |
| 16–22s | Question card, 3 options → ⌃2 | Answer questions with one keystroke. |
| 22–27s | Completion reveals, green pets | Know the moment it's done. |
| 27–30s | Usage pill `5h 34% \| 7d 2%` | Plus live usage limits. |

Timings are the export defaults; retime with `TI_BEATS=beats.txt` (one
`start|end|text` per line) against the real take.

## Payloads (confirmed in code)

- **Approval card with a diff** — `PermissionRequest`, `tool_name: "Edit"`,
  `tool_input.file_path` + `old_string` + `new_string` → `.editDiff`
  (`HookRouter.toolPreview`). `Bash` → command preview, `Write` → content.
  A `Notification` with `notification_type: "permission_prompt"` only turns
  the pet orange — it does **not** produce an answerable card.
- **Question card with numbered options** — `PreToolUse`,
  `tool_name: "AskUserQuestion"`, `tool_input.questions[0].question` +
  `.options[].label`, max 9 (`HookRouter.questionKind`). Clear it with a
  `PostToolUse` for the same tool (`SessionReducer`).

## Mechanism notes that shape the shoot

- `PermissionRequest` **parks the HTTP response** for up to 55s
  (`ApprovalCenter.holdTimeoutSeconds`) awaiting the notch verdict, then fails
  open. The scene script backgrounds that curl; never run it in the foreground.
- Sessions are bound to **real Terminal.app TTYs** (`X-TI-TTY` header). This
  is what makes ⌃1–9 real on camera: `answerQuestion` → `JumpService
  .focusForInput` → `TerminalDrivers.focusTerminalAppTab(ttyPath:)` → the
  digit is typed into that window. With a fake TTY the keystroke goes nowhere.
- Answering **collapses the notch** first (`interactionController
  .handleCollapse()`), so the panel closing is the expected on-camera result.
- The usage pill renders "Usage unavailable" without real data. Beat 6 needs
  the user signed in with `showUsageLimitsHeader` on — and it will show their
  real account percentages on camera.

## Current pipeline — fully synthetic Remotion

`promo/` renders the whole video in React. **There is no screen capture.** The
notch, pets, cards, terminals, menu bar and wallpaper are all components, so
the video re-renders at any size, can never leak personal data into frame, and
can show beats the live shoot could not (the ⌃2 keystroke landing in the
matching terminal — see "Not achieved" in the shoot log below).

Fidelity comes from the app's own source, not from eyeballing screenshots:

- `src/theme.ts` — colours from `TITheme.swift`, phase tints from
  `PetPalette.tint(for:)`, and the four species bitmaps transcribed verbatim
  from `PetSpecies.swift`. If those change in the app, change them here.
- `src/ui/Pet.tsx` — draws the bitmaps, 2-frame walk, `"2"/"Y"` highlight at
  55% like `PetView`.
- `src/ui/Desktop.tsx`, `Island.tsx`, `Cards.tsx`, `Scenes.tsx` — the desktop,
  notch shell and the four beats.
- `src/config.ts` — all content and timing: repos, prompts, summaries, the
  question and options, scene lengths, per-format framing.

Everything is composed on a virtual 1920×1200 stage and framed per format by
`Stage.tsx` using focus rectangles in stage coordinates.

### What the deliverable is

**16:9 only, full frame, one continuous take, no text.** `outputs/promo/v3/`.

Everything that reads as "assembled" was removed, because the target is
footage that looks like a real screen recording:

- **No captions, headline, tab bar, intro or outro.** The Monitor/Approve/Ask/
  Jump tabs and the headline/subtitle on vibeisland.app are controls on their
  *landing page*, sitting next to the video — not inside it. Baking them into
  the footage was a mistake.
- **No cuts.** `Take.tsx` is a single 33s timeline; the desktop keeps running
  while the island morphs between states. Hard cuts between beats are the
  clearest tell that a video was edited together.
- **No device mockup** — the desktop is the frame, edge to edge.
- **A cursor and a Dock.** The cursor travels on an eased curve; constant-speed
  linear motion is an immediate giveaway. The Dock fills the bottom third and
  is a strong authenticity cue.

Beat timings live in `T` in `config.ts`, in seconds.

### Getting the motion right

The design target is vibeisland.app's own hero (the user's capture of it is the
reference). What makes that read as "Mac" and an earlier flat-dark version not:

- **The wallpaper carries the look.** A black island on a dark grey desktop has
  nothing to sit against. `Wallpaper.tsx` draws Sequoia-style rays — and note
  conic-gradient stops are fractions of a full 360° turn, so with the origin on
  the bottom edge the palette must span **0–50%**; 0–100% puts three quarters
  of the ramp off-screen and yields a flat blue wash. Seam spacing is
  irregular on purpose — even spacing looks like a test pattern.
- **Depth, not clutter.** Background terminals are blurred and dimmed via
  `depth` so the island is unambiguously the subject.
- **Spring, not ease.** The island morph uses `spring()` (`useMorph`), tuned to
  settle in ~0.45s with a slight overshoot. An eased interpolation reads as a
  div resizing; the overshoot is what makes it feel native.
- **60fps.** The morph is the product; 30fps shows on it.
- **A steady camera.** No push-ins — a moving frame on top of a morphing island
  reads as busy. All motion comes from the island.
- **Chapter tabs + headline/subtitle**, as on the reference, so each scene is
  read as one of a set rather than a loose clip.

Two traps worth remembering:

- The island collapses to exactly the strip's size. It is opaque and painted
  after the strip, so when closed it **hides the pets completely** — mount it
  only while `island.visible`.
- Card content starts below the notch band, same constraint as the app.

```bash
cd promo
npx remotion studio                      # live preview
npx remotion render Promo-16x9 out.mp4 --codec h264 --crf 18
```

## Previous pipeline — Remotion over a screen capture

Kept for reference; the capture-based compositions were replaced by the
synthetic ones above.

```bash
cd promo
npx remotion studio                      # live preview while editing
npx remotion render Promo-16x9 out.mp4 --codec h264 --crf 18
```

Compositions: `Promo-16x9`, `Promo-1x1`, `Promo-9x16`. All three share one
component; everything format-specific lives in `src/config.ts`:

- `FORMATS[…].wide` / `.punch` — focus rectangles **in source pixels**. Scenes
  ease between them for the push-in. Width is what fills the canvas; the
  resulting band is clipped and placed via `placement` + `bandShift`. Never
  "cover" — covering a 1.54:1 desktop crops the top, and the notch is at y=0.
- `SCENES` — source in-point, scene length, and `playbackRate`.
- Square and vertical keep the same band height across `wide` and `punch`, so
  a push-in reads as a zoom rather than the frame resizing.

The capture goes in `promo/public/take.mp4` and **must be constant frame rate**
— `screencapture -v` writes VFR (a 47s file with 643 frames tagged 120fps),
which makes frame-accurate trimming unreliable:

```bash
ffmpeg -i take-4.mov -vf fps=30 -c:v libx264 -crf 18 -pix_fmt yuv420p -an promo/public/take.mp4
```

Measure the source windows before setting `sourceStart` — take-3 and take-4
differ, and reusing the older numbers silently frames the wrong moments. A
montage is the fastest way to find them:

```bash
ffmpeg -i public/take.mp4 -vf "select='eq(n,360)+eq(n,420)+eq(n,480)',crop=1400:400:800:0,scale=560:-2,tile=3x1" -frames:v 1 -vsync 0 montage.png
```

## Post-production — ffmpeg (previous, still works)

`promo_export.sh` handles crop, captions and the three encodes. Tunables:

- `TI_TRIM_START` / `TI_TRIM_DUR` — trim the master first.
- `TI_CROP_SQUARE` / `TI_CROP_VERT` — punch-in region in source pixels,
  `w:h:x:y`. Vertical formats punch in by default; a full desktop scaled to
  1080 wide leaves the notch panel unreadable on a phone. Retune these against
  the real capture — the defaults are percentage guesses.
- `TI_BEATS` — caption sheet.

Captions are composited as PNGs rendered by `promo_caption.swift`, because the
ffmpeg on this machine is built **without freetype/libass** — `drawtext` and
`subtitles` are both unavailable. Verified end to end against a synthetic
master; only the crop geometry still needs real footage.

## Shoot log — 2026-07-24, take 4 is the keeper

`outputs/promo/take-4.mov` (47s, 3024×1964) → `outputs/promo/final/`.
Export settings that produced it:

```bash
TI_TRIM_START=4 TI_TRIM_DUR=43 TI_BEATS=outputs/promo/beats.txt \
TI_CROP_VERT="1500:1250:762:0" TI_CROP_SQUARE="1900:1250:562:0" \
./Scripts/promo_export.sh outputs/promo/take-4.mov outputs/promo/final
```

**The "screencapture is TCC-blocked" diagnosis was wrong.** It was the Bash
sandbox. `screencapture` works normally with the sandbox disabled — Claude
can record the take itself, no user-side capture needed.

Four takes, three of them ruined by things in frame. What actually matters:

1. **Hide every other app, not just Claude's window.** Take 1 died because
   hiding Claude revealed ChatGPT and an editor full of real client code
   behind it. Snapshot the process names *before* hiding — iterating
   `every process whose visible is true` while hiding mutates the collection
   and errors midway (take 2).
2. **Drop this Claude Code session from the notch.** It otherwise shows up as
   a real session card with the user's prompt text in the title (take 2). Post
   a `SessionEnd` for the session id — TokenIsland is only an observer, so the
   real session is unaffected.
3. **Keep re-hiding Claude during the take.** It un-hides itself while a turn
   is still streaming and reappeared over the final beat (take 3). A 2s
   re-hide loop for the duration fixes it.
4. Reset the scene between takes (`teardown` → `setup` → `repaint`): panes are
   consumed and sessions end up completed, so a second take opens on three
   green sessions and a question pane past its prompt. `pkill -f
   'tokenisland-promo/pane-'` first or the windows refuse to close.
5. Also restore afterwards: Dock autohide, `CreateDesktop`, hidden apps.

The usage pill renders real data (`5h 19% | 7d 53%`), so the last beat is
filmable — it does show the account's true percentages.

Not achieved: ⌃2 never landed in the terminal, so the web-dashboard pane stays
at "Select an option:" while the notch card clears. The notch behaviour is
correct on camera; only the terminal-side payoff is missing. Claude cannot
press the keys itself — posting CGEvents needs Accessibility for the `claude`
CLI, which is not granted (a permission prompt appears if attempted).
