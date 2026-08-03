#!/usr/bin/env bash
# Launches a clean `claude` session for the promo shoot.
#
#   promo_claude_launch.sh <dir> <prompt>
#
# Terminals opened from inside a Claude Code session inherit ~20 CLAUDE_*
# environment variables — including CLAUDE_CODE_CHILD_SESSION, which puts the
# new session into child mode ("Transcript saving is off") and stops it
# behaving like a normal top-level session. Every one of them is stripped here
# so the session TokenIsland observes is a genuine standalone run.
set -euo pipefail

DIR="$1"
PROMPT="$2"

# Build -u flags for every CLAUDE* variable currently exported.
UNSET_FLAGS=()
while IFS= read -r name; do
  UNSET_FLAGS+=(-u "$name")
done < <(env | awk -F= '/^CLAUDE/ {print $1}')

cd "$DIR"
clear
exec env "${UNSET_FLAGS[@]}" claude "$PROMPT"
