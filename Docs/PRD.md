# Product Requirements Document

## Vision

TokenIsland gives developers a premium, glanceable view of AI token usage across Claude, GPT, and Codex without requiring them to open vendor dashboards.

## User Problem

AI coding tools can consume significant tokens and cost during focused work. Developers need immediate visibility into current usage, provider split, source attribution, and cost without exposing prompt content.

## Goals

- Show live token usage in a compact notch-style surface.
- Provide a menu bar summary and detailed dashboard.
- Support Claude Code and GPT/Codex through OTLP and proxy-based ingestion.
- Store metadata locally with privacy-first defaults.
- Degrade gracefully when attribution is incomplete.

## Non-Goals

- Replacing provider billing dashboards.
- Capturing prompt text by default.
- Building a cloud sync service in the MVP.
- Implementing every vendor-specific telemetry schema before field validation.

## Core Features

- Compact and expanded notch overlay.
- Menu bar popover.
- Dashboard with overview, provider breakdown, recent requests, trends, and projects.
- Settings and onboarding.
- Local SQLite store.
- OTLP HTTP JSON receiver.
- OpenAI-compatible proxy.
- Notifications for daily thresholds.

## UX Principles

- Glanceable first, detailed on demand.
- Prefer direct toggles for two-state controls.
- Keep the visual hierarchy calm and dense enough for repeated daily use.
- Never store prompt or response text.

## Acceptance Criteria

- `swift build` succeeds.
- `swift test` succeeds.
- Menu bar extra is available.
- Notch overlay appears and can expand.
- Claude and GPT provider rows show icon, percent, tokens, and progress.
- Settings expose setup, privacy, notifications, and storage controls.
- Ingested telemetry is normalized and stored in SQLite.
