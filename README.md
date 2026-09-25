# TrayFold

A Windows-style system tray for the macOS menu bar, built for MacBooks with a notch.

> **Status: planning.** No code yet. The product spec lives in [`.claude/PRPs/prds/trayfold.prd.md`](.claude/PRPs/prds/trayfold.prd.md).

## The problem

On a notched MacBook, macOS quietly hides menu bar icons that don't fit beside the notch. No overflow arrow, no hint. The app is running, but you can't see or click it.

Existing fixes either reveal hidden icons back into the same cramped bar, cost money, or need the **Screen Recording** permission to draw icons in a separate panel.

## The idea

- TrayFold adds a small divider to your menu bar. **⌘-drag** any icon to the left of it and it folds away.
- Click the TrayFold chevron: a popup grid shows everything folded away.
- Click an entry: TrayFold briefly unfolds that icon and opens its real menu.

## Principles

- **Accessibility permission only** by default. No Screen Recording, no capture indicator.
- **Live icons are optional.** An off-by-default toggle; only that toggle asks for Screen Recording.
- **No network.** No updater, no telemetry, no analytics.
- **Small and dependency-free.** Native Swift / SwiftUI, easy to read and audit.

## Requirements

- macOS 26 (Tahoe) on Apple silicon.
- macOS 27 ships its own overflow button; support there is not guaranteed.

## License

[MIT](LICENSE)
