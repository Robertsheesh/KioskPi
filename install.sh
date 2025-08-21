#!/usr/bin/env bash
set -euo pipefail

# Disable flag (clears on reboot)
FLAG="${XDG_RUNTIME_DIR:-/run/user/$UID}/kiosk.disabled"
[ -e "$FLAG" ] && exit 0

BROWSER="$(command -v chromium-browser || command -v chromium)"

# Kill any existing Chromium
pkill -f chromium-browser 2>/dev/null || true
pkill -f '(^|/)chromium(\s|$)' 2>/dev/null || true
sleep 0.5

# Anti-blank + hide cursor (works under X11; harmless on Wayland)
xset -dpms s off s noblank 2>/dev/null || true
unclutter -idle 1 -root 2>/dev/null &

# Launch kiosk (wrapper page)
exec setsid "$BROWSER" \
  --kiosk --start-fullscreen \
  --noerrdialogs --disable-infobars --disable-session-crashed-bubble \
  --no-first-run --disable-translate \
  file://"$HOME"/kiosk.html \
  >/dev/null 2>&1
