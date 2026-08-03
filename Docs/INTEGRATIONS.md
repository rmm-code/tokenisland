# Integrations

## Claude Code

Preferred setup is OTLP HTTP JSON:

```bash
export OTEL_EXPORTER_OTLP_ENDPOINT=http://127.0.0.1:4318
export OTEL_EXPORTER_OTLP_PROTOCOL=http/json
```

TokenIsland accepts common OpenTelemetry paths such as `/v1/traces`, `/v1/metrics`, and `/v1/logs`.

## GPT / Codex

Use OTLP when the client supports it. For OpenAI-compatible HTTP clients, enable the local proxy and set:

```bash
export OPENAI_BASE_URL=http://127.0.0.1:8787/v1
```

Keep normal credentials in the client environment. TokenIsland forwards requests to the configured upstream URL and parses response usage metadata.

## Supported Fields

The normalizer recognizes common fields including:

- `gen_ai.system`
- `gen_ai.request.model`
- `gen_ai.response.model`
- `gen_ai.usage.input_tokens`
- `gen_ai.usage.output_tokens`
- `usage.prompt_tokens`
- `usage.completion_tokens`
- `cache_read_input_tokens`
- `cache_creation_input_tokens`
- `cost_usd`

## Troubleshooting

- Check Settings -> Advanced for service health.
- Confirm the configured port is not already in use.
- Send `GET /health` to the OTLP or proxy port.
- If source/project data is missing, verify the emitting tool includes those attributes.
- If proxy requests fail, verify upstream base URL and client credentials.
