#!/usr/bin/env bash
# Replaces the seeded demo sessions with REAL Claude Code sessions.
#
# The fake scene (promo_scene.sh) posts hook payloads directly at the app. This
# one creates three small scratch repos and runs the actual `claude` CLI in the
# three on-screen terminals, so every card in the notch comes from a real
# session: a real permission request with the diff Claude actually proposes, a
# real question, a real completion summary.
#
#   ./Scripts/promo_real_scene.sh repos    # create ~/code/{payments-api,…}
#   ./Scripts/promo_real_scene.sh launch   # run claude in the 3 windows
#   ./Scripts/promo_real_scene.sh clean    # remove the scratch repos
#
# Trade-offs vs the seeded scene, worth knowing before filming:
#   - it spends real usage on the user's account
#   - beats are non-deterministic: timing, wording and the diff vary per run,
#     and Claude may not always choose to ask a question
#   - permissions must stay ON (no --dangerously-skip-permissions), because the
#     permission prompt IS the approval beat
set -euo pipefail

ROOT="${TI_DEMO_ROOT:-$HOME/code}"
STATE_DIR="${TI_PROMO_STATE:-${TMPDIR:-/tmp}/tokenisland-promo}"
STATE="${STATE_DIR}/scene.env"

# ---------------------------------------------------------------- repos

cmd_repos() {
  mkdir -p "$ROOT"

  # payments-api — the approval beat. handleEvent has no retry, so "add retry
  # handling" produces a real, small, readable Edit diff.
  mkdir -p "$ROOT/payments-api/src/webhooks"
  cat > "$ROOT/payments-api/package.json" <<'JSON'
{
  "name": "payments-api",
  "version": "1.0.0",
  "type": "module",
  "scripts": { "test": "node --test" }
}
JSON
  cat > "$ROOT/payments-api/src/webhooks/stripe.ts" <<'TS'
import type { StripeEvent } from "../types.js";

/** Dispatches a verified Stripe event to its handler. */
export async function handleEvent(event: StripeEvent): Promise<void> {
  switch (event.type) {
    case "payment_intent.succeeded":
      await markPaid(event.data.object.id);
      break;
    case "charge.refunded":
      await markRefunded(event.data.object.id);
      break;
    default:
      break;
  }
}

export async function receiveWebhook(event: StripeEvent): Promise<void> {
  await handleEvent(event);
}

async function markPaid(id: string): Promise<void> {
  await fetch(`/internal/orders/${id}/paid`, { method: "POST" });
}

async function markRefunded(id: string): Promise<void> {
  await fetch(`/internal/orders/${id}/refunded`, { method: "POST" });
}
TS
  cat > "$ROOT/payments-api/src/types.ts" <<'TS'
export type StripeEvent = {
  id: string;
  type: string;
  data: { object: { id: string } };
};
TS

  # web-dashboard — the question beat. Several caching strategies are equally
  # defensible here, which is what gets Claude to ask rather than assume.
  mkdir -p "$ROOT/web-dashboard/src/api"
  cat > "$ROOT/web-dashboard/package.json" <<'JSON'
{
  "name": "web-dashboard",
  "version": "1.0.0",
  "type": "module"
}
JSON
  cat > "$ROOT/web-dashboard/src/api/analytics.ts" <<'TS'
import { db } from "../db.js";

/** Aggregates pageviews per day. Hits the database on every request. */
export async function getAnalytics(range: string) {
  const rows = await db.query(
    "SELECT day, count(*) FROM pageviews WHERE day > $1 GROUP BY day",
    [range],
  );
  return rows.map((r) => ({ day: r.day, views: Number(r.count) }));
}
TS
  cat > "$ROOT/web-dashboard/src/db.ts" <<'TS'
export const db = {
  async query(_sql: string, _params: unknown[]): Promise<any[]> {
    return [];
  },
};
TS

  # mobile-app — the completion beat. A keychain read on the main thread during
  # launch is a real, recognisable cold-start bug.
  mkdir -p "$ROOT/mobile-app/Sources/App"
  cat > "$ROOT/mobile-app/Sources/App/AppDelegate.swift" <<'SWIFT'
import UIKit

final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Reads the keychain before the scene phase has been set up.
        let token = Keychain.read("session-token")!
        Session.shared.restore(token: token)
        return true
    }
}

enum Keychain {
    static func read(_ key: String) -> String? { nil }
}

final class Session {
    static let shared = Session()
    func restore(token: String) {}
}
SWIFT

  echo "Created:"
  echo "  $ROOT/payments-api      (approval beat — real Edit diff)"
  echo "  $ROOT/web-dashboard     (question beat)"
  echo "  $ROOT/mobile-app        (completion beat)"
}

# ---------------------------------------------------------------- launch

# Opens a Terminal window running $1, applies the dark profile, tiles it, and
# echoes its window id. Opening our own windows (rather than reusing the seeded
# scene's) keeps this independent of promo_scene.sh.
open_window() {
  local cmd="$1" bounds="$2"
  local wid
  # Bind `front window` to a variable ONCE and reuse it. Re-evaluating
  # `front window` for each statement raced the new window coming forward and
  # applied the theme, the bounds and the id read to whichever window happened
  # to be frontmost — all three launches came back with the same id.
  wid=$(osascript <<OSA
tell application "Terminal"
  do script "${cmd//\"/\\\"}"
  delay 0.9
  set w to front window
  set current settings of w to settings set "Pro"
  delay 0.2
  set bounds of w to {${bounds}}
  return id of w
end tell
OSA
)
  echo "$wid"
}

cmd_launch() {
  mkdir -p "$STATE_DIR"
  # Launched through the wrapper so the inherited CLAUDE_* environment is
  # stripped — otherwise the new sessions start in child-session mode with
  # transcript saving off.
  local L
  L="$(cd "$(dirname "$0")" && pwd)/promo_claude_launch.sh"

  local w1 w2 w3
  w1=$(open_window "'$L' '$ROOT/payments-api' 'Add retry handling with exponential backoff to handleEvent in src/webhooks/stripe.ts. Keep it small.'" "50,110,740,540")
  w2=$(open_window "'$L' '$ROOT/web-dashboard' 'I want to cache the analytics endpoint in src/api/analytics.ts. Ask me which caching strategy you should use before you write any code.'" "772,110,1462,540")
  w3=$(open_window "'$L' '$ROOT/mobile-app' 'This app crashes on cold start. Read Sources/App/AppDelegate.swift, explain the cause, and fix it.'" "330,580,1180,930")

  echo "REAL_WIDS=\"$w1 $w2 $w3\"" > "${STATE_DIR}/real.env"

  echo
  echo "Three real Claude sessions launched (windows $w1 $w2 $w3)."
  echo "Permission prompts appear in the notch — that IS the approval beat."
}

# Closes the real-session windows. Kills by window, never by command pattern —
# a pkill on the claude command line also matches the shell that launched it
# and takes the whole window down.
cmd_stop() {
  [ -f "${STATE_DIR}/real.env" ] || { echo "No real scene running." >&2; exit 0; }
  # shellcheck disable=SC1090
  . "${STATE_DIR}/real.env"
  for wid in $REAL_WIDS; do
    osascript -e "tell application \"Terminal\" to close (every window whose id is ${wid})" >/dev/null 2>&1 || true
  done
  rm -f "${STATE_DIR}/real.env"
  echo "Closed the real-session windows."
}

cmd_clean() {
  rm -rf "$ROOT/payments-api" "$ROOT/web-dashboard" "$ROOT/mobile-app"
  echo "Removed the three scratch repos from $ROOT"
}

case "${1:-}" in
  repos)  cmd_repos ;;
  stop)   cmd_stop ;;
  launch) cmd_launch ;;
  clean)  cmd_clean ;;
  *) sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
