#!/usr/bin/env bash
# install.sh — installs Muezzin as an Omarchy plugin for the current user.
# Copies this folder into ~/.config/omarchy/plugins/<id>/ and enables it.
#
# Usage: ./install.sh [--yes]
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ID="io.github.aadaz.muezzin"
DEST="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/${PLUGIN_ID}"
ASSUME_YES=false
[[ "${1:-}" == "--yes" ]] && ASSUME_YES=true

echo "==> Muezzin Omarchy plugin installer"
echo "    id:   ${PLUGIN_ID}"
echo "    into: ${DEST}"
echo
echo "Note: plugins run unsandboxed inside omarchy-shell. This one only:"
echo "  - runs bin/muezzin_core.py (config + prayer-time fetch from api.aladhan.com)"
echo "  - runs notify-send and mpv for reminders/Adhan"
if [[ "$ASSUME_YES" != "true" ]]; then
  read -r -p "Continue? [y/N] " reply
  [[ "$reply" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 1; }
fi

command -v jq >/dev/null 2>&1 || { echo "Missing dependency: jq"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "Missing dependency: python3"; exit 1; }

echo "==> Copying plugin files to ${DEST}"
mkdir -p "$DEST"
cp -a "$SELF_DIR"/. "$DEST"/

echo "==> Validating manifest"
if command -v omarchy >/dev/null 2>&1; then
  omarchy plugin validate "$DEST" || { echo "Manifest validation failed."; exit 1; }
else
  echo "  (omarchy CLI not found — skipping validate; will check manually below)"
fi

python3 - "$DEST/manifest.json" <<'PY'
import json, sys, pathlib
p = pathlib.Path(sys.argv[1])
d = json.loads(p.read_text())
required = ["schemaVersion","id","name","version","author","kinds","entryPoints"]
missing = [k for k in required if k not in d]
assert not missing, f"manifest missing: {missing}"
for kind, rel in d["entryPoints"].items():
    assert not pathlib.Path(rel).is_absolute(), f"{kind} entry point must be relative"
    assert (p.parent / rel).exists(), f"{kind} entry point missing on disk: {rel}"
print("  manifest OK:", d["id"], "kinds:", d["kinds"])
PY

echo "==> Enabling plugin"
if command -v omarchy >/dev/null 2>&1; then
  omarchy plugin enable "$PLUGIN_ID" --yes 2>/dev/null || omarchy plugin enable "$PLUGIN_ID" || true
else
  echo "  omarchy CLI not found."
  echo "  Do this manually: open Setup > Plugins, or run:"
  echo "    omarchy plugin enable $PLUGIN_ID"
  echo "  Then place it on your bar (default section: right), e.g.:"
  echo "    omarchy bar put $PLUGIN_ID --section right"
fi

echo
echo "==> Done. Next steps:"
echo "  1. Reload/restart the shell if the widget does not appear: omarchy-restart-shell"
echo "  2. Click the 🕌 widget to open settings and set your city/country/method."
echo "  3. Remove anytime with:  omarchy plugin remove $PLUGIN_ID"
