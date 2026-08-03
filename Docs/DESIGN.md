# Design

## UI Principles

- Dark, premium, restrained.
- Dense but readable utility layout.
- Thin provider bars instead of bulky progress widgets.
- Icons in controls where the command is clear.
- Avoid extra navigation layers for simple toggles.

## Component System

- `MetricCard`: dashboard summary metric.
- `ProviderIconView`: monochrome provider icon treatment.
- `ProviderUsageRow`: provider name, icon, percent, bar, tokens, and cost.
- `RecentRequestRow`: compact request metadata row.
- `StatusBadge`: service health indicator.
- `TokenProgressBar`: thin horizontal usage line.
- `SettingsCard` and `SettingsRow`: settings layout.
- Settings panes: top icon tabs for General, Gestures, Live Activities, Island, Sources, Privacy, and About.

## Spacing and Typography

Panels use 18 px padding and 14-18 px section gaps. Dashboard headings use large title scale; compact notch uses small rounded numeric type. Text in compact controls is capped with `lineLimit` and scaling where needed.

## Color Intent

The base palette is dark neutral with distinct accents:

- Claude: warm orange.
- GPT: green.
- Utility blue: neutral action accent.
- Warning: amber.
- Danger: red.

Provider icons use bundled SVG files for Claude and Codex. Codex is drawn on a light disc because the supplied SVG path is dark.

## Notch Behavior

The overlay is a transparent full-width top-strip `TokenIslandWindow`, not a small visible panel. The AppKit window itself has no background, no border, no titlebar, no AppKit shadow, and no visible rectangle.

`TokenIslandScreenGeometry` anchors the SwiftUI island to the real hardware camera gap when `safeAreaInsets.top` and the auxiliary top-left/top-right areas indicate a notch. If those areas are unavailable, the island falls back to a virtual top-center notch.

Only `TokenIslandNotchView` draws visible pixels. It uses a custom black shape with small top radii, rounder bottom corners, and SwiftUI-owned shadow. No gray stroke or outer debug outline is drawn.

States:

- Idle black: default state. Draws only the native-looking black notch/handler with no token count, rows, icons, or usage text.
- Hover preview: 45-64 px high compact counter preview shown after hover delay, with configurable provider icons, today total/cost, active indicator, and thin split line.
- Expanded: 740-900 px wide drop-down panel connected to the top notch bridge.
- Active request: transient pulse-style usage card when a new event arrives.
- Peek: completion card for roughly four seconds after an event.
- Not configured: setup actions when no sources are enabled.
- Error: attention state with settings action.

Expanded sections switch horizontally through Overview, Providers, Recent, and Setup. Provider rows use stronger typography and thin progress lines.

## Settings Design

Settings use a top icon-tab preferences layout rather than a sidebar. The tabs are TokenIsland-specific:

- General: startup, fullscreen behavior, hover safety, geometry tuning, non-notch fallback, demo mode, reset.
- Gestures: hover preview, click expand, vertical open/close, horizontal section switching, open/close delays.
- Live Activities: active request, completion peek, alert visibility, inactivity timeout, fullscreen event preferences.
- Island: compact/hover/expanded content controls, provider row controls, shadow/corner/animation tuning.
- Sources: Claude OTLP, GPT/Codex telemetry/proxy, copy commands, connection status, source preferences, diagnostics.
- Privacy: metadata-only storage, debug payload storage, project/source metadata, export/delete, no prompt/response text storage.
- About: app identity, version/build info, update preference, documentation/privacy/support/changelog links.

## Interaction States

- Idle: black notch only; no usage content is visible until hover, click, or a live activity.
- Hover: opens smoothly into compact preview using spring animation.
- Mouse leave: closes back to idle black after the configured delay unless pinned or prevented by settings.
- Empty: configured but idle messaging appears only inside hover/expanded content.
- Loading: state tracked in `AppState`.
- Partial data: unknown provider/source labels remain visible.
- Error: advanced settings and app state expose the message.

## Accessibility

Rows combine related labels for VoiceOver. Controls use native SwiftUI buttons, toggles, steppers, segmented pickers, and text fields. Notch animations respect reduced-motion settings, and the panel stays non-activating during hover/open interactions.
