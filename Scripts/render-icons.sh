#!/bin/bash
# Render Design/*.svg into the PNGs in the asset catalog. Re-run after editing an SVG.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
ASSETS="TrayFold/Resources/Assets.xcassets"
render() { swift Scripts/render-icon.swift "$@"; }

# App icon: every point size at 1x and 2x (so 512@2x is 1024 px).
for size in 16 32 128 256 512; do
  render Design/AppIcon.svg "$ASSETS/AppIcon.appiconset/AppIcon-$size.png" "$size"
  render Design/AppIcon.svg "$ASSETS/AppIcon.appiconset/AppIcon-$size@2x.png" $((size * 2))
done

# Menu bar glyph: 18 pt tall, so 18 px at 1x and 36 px at 2x (Retina).
render Design/MenuBarIcon.svg "$ASSETS/MenuBarIcon.imageset/MenuBarIcon.png" 18
render Design/MenuBarIcon.svg "$ASSETS/MenuBarIcon.imageset/MenuBarIcon@2x.png" 36
