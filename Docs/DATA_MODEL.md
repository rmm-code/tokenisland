# Data Model

## `usage_events`

| Field | Type | Notes |
| --- | --- | --- |
| `id` | TEXT | UUID primary key |
| `timestamp` | REAL | Unix seconds |
| `provider` | TEXT | `claude`, `gpt`, `unknown` |
| `source_app` | TEXT | Claude Code, Codex CLI, IDE, generic source |
| `project_name` | TEXT | Optional |
| `project_path` | TEXT | Optional |
| `model` | TEXT | Vendor model identifier or `unknown-model` |
| `input_tokens` | INTEGER | Prompt/input tokens |
| `output_tokens` | INTEGER | Completion/output tokens |
| `cache_read_tokens` | INTEGER | Cache read tokens |
| `cache_write_tokens` | INTEGER | Cache creation/write tokens |
| `total_tokens` | INTEGER | Computed total |
| `estimated_cost_usd` | REAL | Supplied or estimated cost |
| `request_id` | TEXT | Optional trace/request id |
| `latency_ms` | INTEGER | Optional latency |
| `session_id` | TEXT | Optional session id |
| `raw_metadata_json` | TEXT | Sanitized by default |

## `daily_aggregates`

Reserved for materialized rollups by day, provider, model, and project path.

## Settings

`AppSettings` is stored in `UserDefaults` as JSON. It includes onboarding state, overlay preferences, OTLP/proxy ports, privacy mode, thresholds, launch-at-login, and debug mode.

## Migration Notes

Migration version 1 creates `schema_migrations`, `usage_events`, indexes, and `daily_aggregates`. Future migrations should be additive and recorded by version.
