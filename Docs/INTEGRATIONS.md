# Integrations

## Setup and controls

Finish onboarding, then open Settings → Integrations. Hook integrations have one
enable switch per agent. Disabling an integration removes only Token Island's
commands and saves the choice across restarts. Automatic setup never reconnects an
agent you explicitly disabled. Re-enable it to reconnect.

Restart running CLI sessions after installing or repairing hooks: some CLIs snapshot
their configuration when the session starts. Codex is monitored from local rollout
files and has a separate monitoring switch; it does not support notch approvals.

## Hook contracts

- Claude Code and its derivatives use grouped hook entries. Claude's
  `PermissionRequest` verdict is `hookSpecificOutput.decision.behavior`, with
  `decision.message` on denial. This differs from the `PreToolUse` response format.
- Cursor uses lowercase event names and flat command entries in a version-1
  `hooks.json`. Its tool gates read `permission`; prompt submission reads `continue`.
  A transport failure exits 3 so Cursor's native permission policy can proceed.
  Successful observational responses use the valid schema for their event. Tool
  gates are monitored without parking the call or adding an approval policy.
- Gemini uses `BeforeAgent`, `AfterAgent`, `BeforeTool`, `AfterTool`, and
  `PreCompress`. Matchers are regexes, and hook timeouts are milliseconds. Verdicts
  use `decision` and `reason`, but ordinary tool gates are monitored without
  overriding native approvals. Passive Gemini monitoring is a fallback when the
  managed hook integration is unavailable, avoiding two sources for the same session.

Contracts checked against the official references on 2026-10-01:
[Claude](https://code.claude.com/docs/en/hooks#permissionrequest-decision-control),
[Cursor](https://cursor.com/docs/hooks),
[Gemini](https://geminicli.com/docs/hooks/reference/).

## Configuration safety

Existing invalid JSON, non-object roots, malformed hook collections, and invalid
environment sections are refused before writing. The original file remains unchanged.
The first successful shared-file installation creates a `.tokenisland-backup` copy.
Writes are atomic. Repair and removal operate on individual marker-tagged commands,
preserving foreign commands and matcher metadata even inside mixed groups. Upgrades
remove old Token Island commands before installing the current dialect's entries.

## Approvals and troubleshooting

Notch approval cards are used for Claude-family `PermissionRequest` events. Cursor
and Gemini hooks run for ordinary tools, so they update activity without asking for
an extra confirmation. Answer their permission prompts in the native CLI.

- Native approvals mode releases parked requests without granting permission and
  clears remembered Always-Allow/Bypass choices.
- A timed-out request stays marked as waiting in the terminal. Use the terminal
  action to continue; the app does not claim the agent resumed working.
- Other apps' approval hooks appear as a conflict warning. Coordinate which monitor
  answers requests rather than removing another application's commands automatically.
- Connect, Repair, or Retry runs setup for that agent. Errors are shown in full.
- The local hook endpoint is `127.0.0.1:47791`; `GET /health` checks its availability.

## Optional legacy usage sources

Session monitoring does not require OTLP or the OpenAI-compatible proxy. Both default
off and are available in Settings → Labs.

For OpenTelemetry JSON exporters, use `OTEL_EXPORTER_OTLP_PROTOCOL=http/json` and
`OTEL_EXPORTER_OTLP_ENDPOINT=http://127.0.0.1:4318`. The receiver accepts `/v1/traces`,
`/v1/metrics`, and `/v1/logs`.

OpenAI-compatible clients can use the optional local proxy at
`http://127.0.0.1:8787/v1`; keep credentials in the client's environment. The proxy
forwards requests and parses response usage metadata. This legacy path is separate
from Codex session monitoring.
