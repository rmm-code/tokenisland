# Privacy

## Stored By Default

- Provider.
- Model.
- Token counts.
- Cache token counts.
- Estimated cost.
- Source app label.
- Project name/path when emitted.
- Request/session identifiers when emitted.
- Latency.
- Sanitized raw metadata.

## Not Stored By Default

Prompt-like fields are redacted from raw metadata by default. The sanitizer removes values from keys containing terms such as prompt, messages, content, input, completion, and text.

## Privacy Modes

- Metadata only: default and recommended.
- Store prompt text: explicit opt-in for users who need raw debugging data.

## Deletion and Export

Settings -> Data & Storage can export JSON or delete all usage data. Deleting usage data preserves app settings.

## Network Behavior

TokenIsland stores data locally. The optional proxy forwards user API requests only to the configured upstream base URL.
