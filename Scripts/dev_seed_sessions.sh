#!/usr/bin/env bash
# Simulates two Claude Code sessions against the local hook server so the
# whole notch UX (pets, cards, reveals, approvals) can be demoed without a
# real claude run. Usage: ./Scripts/dev_seed_sessions.sh [port]
set -euo pipefail

PORT="${1:-47791}"
URL="http://127.0.0.1:${PORT}/hook/claude"

post() {
  curl -s -m 3 -X POST "$URL" \
    -H "Content-Type: application/json" \
    -H "X-TI-Term: Apple_Terminal" \
    -H "X-TI-TTY: /dev/ttys009" \
    --data-binary "$1" > /dev/null
  echo "→ $2"
}

SID_A="demo-aaaa-1111-2222-333344445555"
SID_B="demo-bbbb-6666-7777-888899990000"

echo "Seeding demo sessions against ${URL}"

post "{\"session_id\":\"$SID_A\",\"hook_event_name\":\"SessionStart\",\"source\":\"startup\",\"cwd\":\"$HOME/Desktop/vitamentor\",\"transcript_path\":\"/tmp/demo-a.jsonl\"}" "A: SessionStart"
sleep 1
post "{\"session_id\":\"$SID_A\",\"hook_event_name\":\"UserPromptSubmit\",\"prompt\":\"Order vitamins flow for miniapp\",\"cwd\":\"$HOME/Desktop/vitamentor\"}" "A: UserPromptSubmit"
sleep 1
post "{\"session_id\":\"$SID_A\",\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Read\",\"tool_use_id\":\"t1\",\"tool_input\":{\"file_path\":\"$HOME/Desktop/vitamentor/src/checkout.ts\"},\"cwd\":\"$HOME/Desktop/vitamentor\"}" "A: PreToolUse Read"
sleep 2

post "{\"session_id\":\"$SID_B\",\"hook_event_name\":\"SessionStart\",\"source\":\"startup\",\"cwd\":\"$HOME/Desktop/counter\",\"transcript_path\":\"/tmp/demo-b.jsonl\"}" "B: SessionStart"
sleep 1
post "{\"session_id\":\"$SID_B\",\"hook_event_name\":\"UserPromptSubmit\",\"prompt\":\"Fix unsupported content type error\",\"cwd\":\"$HOME/Desktop/counter\"}" "B: UserPromptSubmit"
sleep 1
post "{\"session_id\":\"$SID_B\",\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Task\",\"tool_use_id\":\"t2\",\"tool_input\":{\"description\":\"Search API endpoints\",\"subagent_type\":\"Explore\"},\"cwd\":\"$HOME/Desktop/counter\"}" "B: PreToolUse Task (subagent)"
sleep 2

post "{\"session_id\":\"$SID_A\",\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Read\",\"tool_use_id\":\"t1\"}" "A: PostToolUse"
post "{\"session_id\":\"$SID_A\",\"hook_event_name\":\"Notification\",\"notification_type\":\"permission_prompt\",\"message\":\"Claude needs your permission to use Bash\"}" "A: permission notification (approval card + orange pet)"
sleep 4

post "{\"session_id\":\"$SID_A\",\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Bash\",\"tool_use_id\":\"t3\",\"tool_input\":{\"command\":\"npm test\"}}" "A: approval resolved, Bash running"
sleep 2
post "{\"session_id\":\"$SID_B\",\"hook_event_name\":\"SubagentStop\"}" "B: SubagentStop"
post "{\"session_id\":\"$SID_B\",\"hook_event_name\":\"Stop\",\"last_assistant_message\":\"**TLDR**: This isn't from your project at all — it's a bug in the SDK version pin. I updated the dependency and the error is gone.\"}" "B: Stop (completion reveal, green pet)"
sleep 3
post "{\"session_id\":\"$SID_A\",\"hook_event_name\":\"Stop\",\"last_assistant_message\":\"Done. I rebuilt the miniapp checkout as a multi-step wizard matching your screenshots, and verified every step in a headless browser.\"}" "A: Stop"
sleep 2

echo "Demo sessions live. Remove them by quitting the app or:"
echo "  curl -s -X POST $URL -H 'Content-Type: application/json' --data '{\"session_id\":\"$SID_A\",\"hook_event_name\":\"SessionEnd\",\"reason\":\"exit\"}'"
echo "  curl -s -X POST $URL -H 'Content-Type: application/json' --data '{\"session_id\":\"$SID_B\",\"hook_event_name\":\"SessionEnd\",\"reason\":\"exit\"}'"
