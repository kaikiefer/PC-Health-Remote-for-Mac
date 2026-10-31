# Pulse Link identity

An orange telemetry pulse inside an open cyan/orange circuit ring. It continues
the desktop HUD's identity without using the Flipper dolphin, Marvel characters,
or third-party logos. PC Health Remote remains the working product name until
the publisher confirms the release name and completes name/rights checks.

- `logo-mark.svg`: transparent, editable vector mark.
- `logo-lockup.svg`: dark horizontal wordmark, editable SVG text.
- `logo-mark.png`: 1024 px transparent export, generated from native drawing.
- `logo-lockup.png`: 1600 × 400 dark wordmark export.
- `app-icon-1024.png`: desktop icon master.

Palette: midnight `#060b11`, signal cyan `#3bdef5`, Flipper-inspired orange
`#ff7d2e`, pale foreground `#dbeff5`, muted text `#7b9eaf`. Keep clear space of
at least 10% of the mark width. Do not describe the product as an official Flipper
or Apple app. The mark was drawn using native vector/CoreGraphics code, not
generated from a third-party logo. SVG and PNG ring/tick styling differ slightly
to suit their renderers.

Rebuild exports with `scripts/prepare-assets.sh`. Fonts in the editable SVG
lockup use Menlo with a generic monospace fallback; final PNG text is rendered
with Menlo. Store icon assets are provided in `Assets/Assets.xcassets`.
