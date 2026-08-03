#!/usr/bin/env bash
# Drives the promo-video scene: opens real Terminal.app windows, binds seeded
# Claude sessions to their real TTYs, and fires each beat on demand so the
# capture can be cut precisely.
#
# Binding to real TTYs matters: ⌃1–9 and "Answer in terminal" go through
# JumpService.focusForInput → TerminalDrivers.focusTerminalAppTab(ttyPath:),
# so the injected keystroke actually lands in the matching window on camera.
#
#   ./Scripts/promo_scene.sh setup      # terminals + sessions (TI_PANES=3 for three)
#   ./Scripts/promo_scene.sh seed       # re-seed sessions after launching the app
#   ./Scripts/promo_scene.sh run        # THE TAKE — beats only, after setup
#   ./Scripts/promo_scene.sh approval   # PermissionRequest w/ Edit diff (parks 55s)
#   ./Scripts/promo_scene.sh question   # AskUserQuestion w/ 3 options
#   ./Scripts/promo_scene.sh answered   # clears the question card after ⌃2
#   ./Scripts/promo_scene.sh finish     # Stop → completion reveals
#   ./Scripts/promo_scene.sh teardown   # SessionEnd + close windows
#   ./Scripts/promo_scene.sh all        # setup + run (unattended rehearsal)
#
# Sample repo names only — the user's real client repos must never be in frame.
set -euo pipefail

PORT="${TI_PORT:-47791}"
URL="http://127.0.0.1:${PORT}/hook/claude"
STATE_DIR="${TI_PROMO_STATE:-${TMPDIR:-/tmp}/tokenisland-promo}"
STATE="${STATE_DIR}/scene.env"

# Four demo sessions. Fixed IDs so every subcommand addresses the same session.
SID_PAY="promo-pay-1111-2222-333344445555"   # payments-api  → approval beat
SID_WEB="promo-web-2222-3333-444455556666"   # web-dashboard → question beat
SID_MOB="promo-mob-3333-4444-555566667777"   # mobile-app    → completion beat
SID_INF="promo-inf-4444-5555-666677778888"   # infra-scripts → subagent beat

# ---------------------------------------------------------------- helpers

# POST a hook payload. $2 is the TTY the session is bound to, $3 a log label.
post() {
  local body="$1" tty="$2" label="$3"
  curl -s -m 5 -X POST "$URL" \
    -H "Content-Type: application/json" \
    -H "X-TI-Term: Apple_Terminal" \
    -H "X-TI-TTY: ${tty}" \
    --data-binary "$body" > /dev/null || true
  echo "→ ${label}"
}

# PermissionRequest parks the HTTP response for up to 55s (ApprovalCenter
# .holdTimeoutSeconds) waiting for the notch verdict — never run it in the
# foreground or the scene script stalls mid-shoot.
post_parked() {
  local body="$1" tty="$2" label="$3"
  curl -s -m 70 -X POST "$URL" \
    -H "Content-Type: application/json" \
    -H "X-TI-Term: Apple_Terminal" \
    -H "X-TI-TTY: ${tty}" \
    --data-binary "$body" > "${STATE_DIR}/approval-response.json" 2>/dev/null &
  echo "→ ${label} (parked, pid $!)"
}

require_state() {
  [ -f "$STATE" ] || { echo "No scene state. Run: $0 setup" >&2; exit 1; }
  # shellcheck disable=SC1090
  . "$STATE"
}

# ---------------------------------------------------------------- terminals

# Painters are written to files and run as `bash <file>` — inlining them into
# the AppleScript would let AppleScript's own string escaping eat the ANSI
# sequences. Each sets its window title via OSC 0 so teardown can find it.
#
# This is set dressing for the windows behind the notch; the notch itself
# shows real app state driven by the hook events below.
write_painter() {
  local name="$1" repo="$2" prompt="$3"
  cat > "${STATE_DIR}/pane-${name}.sh" <<PAINT
#!/usr/bin/env bash
printf '\033]0;claude — ${repo}\007'
clear
printf '\033[38;5;208m✳\033[0m \033[1mclaude\033[0m \033[2m·\033[0m \033[36m${repo}\033[0m\n\n'
printf '\033[2m>\033[0m ${prompt}\n\n'
sleep 3600
PAINT
}

# The web-dashboard window ends at a real numbered prompt so the digit typed
# by the notch (⌃2 → KeyInjection.typeOption) visibly selects an option.
write_question_painter() {
  cat > "${STATE_DIR}/pane-web.sh" <<'PAINT'
#!/usr/bin/env bash
printf '\033]0;claude — web-dashboard\007'
clear
printf '\033[38;5;208m✳\033[0m \033[1mclaude\033[0m \033[2m·\033[0m \033[36mweb-dashboard\033[0m\n\n'
printf '\033[2m>\033[0m Add caching to the analytics endpoint\n\n'
printf '\033[33m?\033[0m \033[1mWhich caching strategy should I use?\033[0m\n\n'
printf '  \033[2m1.\033[0m Redis with a 60s TTL\n'
printf '  \033[2m2.\033[0m In-memory LRU per instance\n'
printf '  \033[2m3.\033[0m No cache — measure first\n\n'
printf '\033[2m  Select an option:\033[0m '
read -r choice
case "$choice" in
  1) label='Redis with a 60s TTL' ;;
  2) label='In-memory LRU per instance' ;;
  3) label='No cache — measure first' ;;
  *) label="$choice" ;;
esac
printf '\n\033[32m⏺\033[0m %s\n\n' "$label"
printf '\033[2m⏺\033[0m Edit src/api/analytics.ts\n'
sleep 3600
PAINT
}

# Opens a Terminal window running the painter at $1 and echoes "tty|window_id".
# The window id is recorded so teardown can close exactly the windows this
# script opened — matching on the title would also catch the user's own real
# Claude sessions, which TitleMarkerService stamps "claude — <slug>" too.
open_window() {
  local script_path="$1" bounds="$2"
  osascript <<OSA
tell application "Terminal"
  set newTab to do script "bash '${script_path}'"
  delay 0.4
  set bounds of front window to {${bounds}}
  return (tty of newTab) & "|" & (id of front window)
end tell
OSA
}

# ---------------------------------------------------------------- beats

# Seeds the demo sessions into a running app. Split out of cmd_setup so the
# scene can be re-seeded after TokenIsland starts — the terminals outlive a
# restart of the app, but the sessions do not.
seed_sessions() {
  # Bring all four to working (blue pets) — this is the opening frame.
  post "{\"session_id\":\"$SID_PAY\",\"hook_event_name\":\"SessionStart\",\"source\":\"startup\",\"cwd\":\"$HOME/code/payments-api\",\"transcript_path\":\"/tmp/promo-pay.jsonl\"}" "$TTY_PAY" "payments-api: start"
  post "{\"session_id\":\"$SID_WEB\",\"hook_event_name\":\"SessionStart\",\"source\":\"startup\",\"cwd\":\"$HOME/code/web-dashboard\",\"transcript_path\":\"/tmp/promo-web.jsonl\"}" "$TTY_WEB" "web-dashboard: start"
  post "{\"session_id\":\"$SID_MOB\",\"hook_event_name\":\"SessionStart\",\"source\":\"startup\",\"cwd\":\"$HOME/code/mobile-app\",\"transcript_path\":\"/tmp/promo-mob.jsonl\"}" "$TTY_MOB" "mobile-app: start"
  [ -n "$TTY_INF" ] && post "{\"session_id\":\"$SID_INF\",\"hook_event_name\":\"SessionStart\",\"source\":\"startup\",\"cwd\":\"$HOME/code/infra-scripts\",\"transcript_path\":\"/tmp/promo-inf.jsonl\"}" "$TTY_INF" "infra-scripts: start"

  post "{\"session_id\":\"$SID_PAY\",\"hook_event_name\":\"UserPromptSubmit\",\"prompt\":\"Add retry handling to the Stripe webhook\",\"cwd\":\"$HOME/code/payments-api\"}" "$TTY_PAY" "payments-api: prompt"
  post "{\"session_id\":\"$SID_WEB\",\"hook_event_name\":\"UserPromptSubmit\",\"prompt\":\"Add caching to the analytics endpoint\",\"cwd\":\"$HOME/code/web-dashboard\"}" "$TTY_WEB" "web-dashboard: prompt"
  post "{\"session_id\":\"$SID_MOB\",\"hook_event_name\":\"UserPromptSubmit\",\"prompt\":\"Fix the crash on cold start\",\"cwd\":\"$HOME/code/mobile-app\"}" "$TTY_MOB" "mobile-app: prompt"
  [ -n "$TTY_INF" ] && post "{\"session_id\":\"$SID_INF\",\"hook_event_name\":\"UserPromptSubmit\",\"prompt\":\"Audit the Terraform state drift\",\"cwd\":\"$HOME/code/infra-scripts\"}" "$TTY_INF" "infra-scripts: prompt"

  post "{\"session_id\":\"$SID_PAY\",\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Read\",\"tool_use_id\":\"p1\",\"tool_input\":{\"file_path\":\"$HOME/code/payments-api/src/webhooks/stripe.ts\"},\"cwd\":\"$HOME/code/payments-api\"}" "$TTY_PAY" "payments-api: Read"
  post "{\"session_id\":\"$SID_WEB\",\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Grep\",\"tool_use_id\":\"w1\",\"tool_input\":{\"pattern\":\"analytics\"},\"cwd\":\"$HOME/code/web-dashboard\"}" "$TTY_WEB" "web-dashboard: Grep"
  post "{\"session_id\":\"$SID_MOB\",\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Bash\",\"tool_use_id\":\"m1\",\"tool_input\":{\"command\":\"xcodebuild test -scheme App\"},\"cwd\":\"$HOME/code/mobile-app\"}" "$TTY_MOB" "mobile-app: Bash"
  [ -n "$TTY_INF" ] && post "{\"session_id\":\"$SID_INF\",\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Task\",\"tool_use_id\":\"i1\",\"tool_input\":{\"description\":\"Diff live state vs plan\",\"subagent_type\":\"Explore\"},\"cwd\":\"$HOME/code/infra-scripts\"}" "$TTY_INF" "infra-scripts: subagent"

}

cmd_seed() {
  require_state
  seed_sessions
  echo
  echo "Sessions seeded."
}

cmd_setup() {
  mkdir -p "$STATE_DIR"
  # TI_PANES=3 drops the infra-scripts window and tiles the remaining three
  # as two-up over one — a calmer frame than a 2x2 grid.
  local panes="${TI_PANES:-4}"
  echo "Opening ${panes} demo terminals (Automation permission prompt may appear)…"

  write_painter pay payments-api  'Add retry handling to the Stripe webhook'
  write_question_painter
  write_painter mob mobile-app    'Fix the crash on cold start'
  write_painter inf infra-scripts 'Audit the Terraform state drift'

  local r_pay r_web r_mob r_inf="" t_inf=""
  if [ "$panes" -le 3 ]; then
    r_pay=$(open_window "${STATE_DIR}/pane-pay.sh" "50,110,740,540")
    r_web=$(open_window "${STATE_DIR}/pane-web.sh" "772,110,1462,540")
    r_mob=$(open_window "${STATE_DIR}/pane-mob.sh" "330,580,1180,930")
  else
    r_pay=$(open_window "${STATE_DIR}/pane-pay.sh" "60,120,760,520")
    r_web=$(open_window "${STATE_DIR}/pane-web.sh" "800,120,1500,520")
    r_mob=$(open_window "${STATE_DIR}/pane-mob.sh" "60,560,760,960")
    r_inf=$(open_window "${STATE_DIR}/pane-inf.sh" "800,560,1500,960")
    t_inf="${r_inf%%|*}"
  fi

  local t_pay="${r_pay%%|*}" t_web="${r_web%%|*}" t_mob="${r_mob%%|*}"
  local wids="${r_pay##*|} ${r_web##*|} ${r_mob##*|}"
  [ -n "$r_inf" ] && wids="${wids} ${r_inf##*|}"

  cat > "$STATE" <<STATE
TTY_PAY="${t_pay}"
TTY_WEB="${t_web}"
TTY_MOB="${t_mob}"
TTY_INF="${t_inf}"
WIDS="${wids}"
STATE
  echo "TTYs: pay=${t_pay} web=${t_web} mob=${t_mob} inf=${t_inf:-none}"

  # shellcheck disable=SC2034
  TTY_PAY="$t_pay" TTY_WEB="$t_web" TTY_MOB="$t_mob" TTY_INF="$t_inf"
  seed_sessions

  echo
  echo "Scene is live: ${panes} working sessions. Next: $0 approval"
}

# Repaints the four windows. Resizing or minimising a Terminal window after
# its painter has run leaves the content scrolled out of view, so re-run this
# after any window juggling and before the take.
#
# This writes display output to the TTY device — it does not send input to
# the shell (the panes are parked in sleep / read).
repaint_pane() {
  local tty="$1" repo="$2" prompt="$3"
  {
    printf '\033[2J\033[H'
    printf '\033[38;5;208m✳\033[0m \033[1mclaude\033[0m \033[2m·\033[0m \033[36m%s\033[0m\n\n' "$repo"
    printf '\033[2m>\033[0m %s\n\n' "$prompt"
  } > "$tty" 2>/dev/null || echo "   (could not write ${tty})"
}

cmd_repaint() {
  require_state
  repaint_pane "$TTY_PAY" "payments-api"  "Add retry handling to the Stripe webhook"
  repaint_pane "$TTY_MOB" "mobile-app"    "Fix the crash on cold start"
  [ -n "${TTY_INF:-}" ] && repaint_pane "$TTY_INF" "infra-scripts" "Audit the Terraform state drift"
  # The web pane is parked at a live `read`; redraw the whole question so the
  # digit typed by the notch still lands on a visible prompt.
  {
    printf '\033[2J\033[H'
    printf '\033[38;5;208m✳\033[0m \033[1mclaude\033[0m \033[2m·\033[0m \033[36mweb-dashboard\033[0m\n\n'
    printf '\033[2m>\033[0m Add caching to the analytics endpoint\n\n'
    printf '\033[33m?\033[0m \033[1mWhich caching strategy should I use?\033[0m\n\n'
    printf '  \033[2m1.\033[0m Redis with a 60s TTL\n'
    printf '  \033[2m2.\033[0m In-memory LRU per instance\n'
    printf '  \033[2m3.\033[0m No cache — measure first\n\n'
    printf '\033[2m  Select an option:\033[0m '
  } > "$TTY_WEB" 2>/dev/null || echo "   (could not write ${TTY_WEB})"
  echo "→ repainted 4 panes"
}

# Beat 3 — approval card with a real diff preview. Edit → ToolCallPreview
# .editDiff(path:old:new:), per HookRouter.toolPreview.
cmd_approval() {
  require_state
  local body
  body=$(cat <<JSON
{"session_id":"$SID_PAY","hook_event_name":"PermissionRequest","tool_name":"Edit","tool_use_id":"p-approve-1",
 "cwd":"$HOME/code/payments-api",
 "tool_input":{"file_path":"$HOME/code/payments-api/src/webhooks/stripe.ts",
 "old_string":"  await handleEvent(event)","new_string":"  await withRetry(3, () => handleEvent(event))"}}
JSON
)
  post_parked "$body" "$TTY_PAY" "payments-api: PermissionRequest (Edit diff → approval card, orange pet)"
  echo "   Card is up for ≤55s. Approve with ⌃Y (or ⌃N deny) while recording."
}

# Beat 4 — question card with numbered options. PreToolUse + AskUserQuestion,
# per HookRouter.questionKind (max 9 options).
cmd_question() {
  require_state
  local body
  body=$(cat <<JSON
{"session_id":"$SID_WEB","hook_event_name":"PreToolUse","tool_name":"AskUserQuestion","tool_use_id":"w-ask-1",
 "cwd":"$HOME/code/web-dashboard",
 "tool_input":{"questions":[{"question":"Which caching strategy should I use?",
 "options":[{"label":"Redis with a 60s TTL"},{"label":"In-memory LRU per instance"},{"label":"No cache — measure first"}]}]}}
JSON
)
  post "$body" "$TTY_WEB" "web-dashboard: AskUserQuestion (question card, ⌃1–3)"
  echo "   Press ⌃2 while recording — the notch focuses ${TTY_WEB} and types it."
}

# Fired after the ⌃2 keystroke lands, so the card clears the way a real
# session would (SessionReducer clears .question on AskUserQuestion PostToolUse).
cmd_answered() {
  require_state
  post "{\"session_id\":\"$SID_WEB\",\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"AskUserQuestion\",\"tool_use_id\":\"w-ask-1\"}" "$TTY_WEB" "web-dashboard: question answered"
  post "{\"session_id\":\"$SID_WEB\",\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Edit\",\"tool_use_id\":\"w2\",\"tool_input\":{\"file_path\":\"$HOME/code/web-dashboard/src/api/analytics.ts\"},\"cwd\":\"$HOME/code/web-dashboard\"}" "$TTY_WEB" "web-dashboard: back to work"
}

# Beat 5 — completion reveals (green pets).
cmd_finish() {
  require_state
  post "{\"session_id\":\"$SID_INF\",\"hook_event_name\":\"SubagentStop\"}" "$TTY_INF" "infra-scripts: SubagentStop"
  post "{\"session_id\":\"$SID_MOB\",\"hook_event_name\":\"Stop\",\"last_assistant_message\":\"Fixed the cold-start crash — the keychain read now happens after the scene phase, not in \`applicationDidFinishLaunching\`. Added a regression test.\"}" "$TTY_MOB" "mobile-app: done"
  sleep 3
  post "{\"session_id\":\"$SID_PAY\",\"hook_event_name\":\"Stop\",\"last_assistant_message\":\"Stripe webhook now retries 3× with exponential backoff, and duplicate deliveries are deduped by event id.\"}" "$TTY_PAY" "payments-api: done"
  sleep 3
  post "{\"session_id\":\"$SID_INF\",\"hook_event_name\":\"Stop\",\"last_assistant_message\":\"Found 4 drifted resources — two security groups and both NAT gateways. Wrote the plan to \`drift-report.md\`.\"}" "$TTY_INF" "infra-scripts: done"
}

cmd_teardown() {
  require_state
  for sid in "$SID_PAY" "$SID_WEB" "$SID_MOB" "$SID_INF"; do
    post "{\"session_id\":\"$sid\",\"hook_event_name\":\"SessionEnd\",\"reason\":\"exit\"}" "/dev/null" "end ${sid:0:9}"
  done
  # Close by recorded window id only — never by title. The user's own real
  # Claude sessions carry "claude — <slug>" titles and must not be touched.
  for wid in ${WIDS:-}; do
    osascript -e "tell application \"Terminal\" to close (every window whose id is ${wid})" 2>/dev/null || true
  done
  rm -f "$STATE"
  echo "Scene torn down. Restore desktop icons if you hid them:"
  echo "  defaults write com.apple.finder CreateDesktop true; killall Finder"
}

# The take. Run `setup` first (off camera), start the screen recording, then
# run this — beats only, on beat-sheet timing, with a lead-in so the first
# seconds of the capture are the calm 4-agent opening frame.
#
# Recording is started by the user, not from here: screen capture launched by
# this process inherits the calling app's TCC grant, which is exactly what has
# been failing. ⇧⌘5, or `screencapture -v take.mov` from their own terminal.
cmd_run() {
  require_state
  local lead="${TI_LEAD_IN:-6}"
  echo "Lead-in ${lead}s — hover the notch now, let the pets walk."
  sleep "$lead"
  cmd_approval
  echo "   … ⌃Y to approve (10s)"; sleep 10
  cmd_question
  echo "   … ⌃2 to answer (8s)";   sleep 8
  cmd_answered; sleep 4
  cmd_finish
  echo
  echo "Take complete — stop the recording. Teardown: $0 teardown"
}

# Unattended rehearsal — opens the scene and runs every beat end to end.
cmd_all() {
  cmd_setup; sleep 6
  cmd_run
}

case "${1:-}" in
  setup)    cmd_setup ;;
  seed)     cmd_seed ;;
  repaint)  cmd_repaint ;;
  run)      cmd_run ;;
  approval) cmd_approval ;;
  question) cmd_question ;;
  answered) cmd_answered ;;
  finish)   cmd_finish ;;
  teardown) cmd_teardown ;;
  all)      cmd_all ;;
  *) sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
