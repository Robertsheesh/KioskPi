#!/usr/bin/env bash
set -euo pipefail
FLAG="${XDG_RUNTIME_DIR:-/run/user/$UID}/kiosk.disabled"
mkdir -p "$(dirname "$FLAG")"
touch "$FLAG"

# Stop/Mask (runtime) user service if present
systemctl --user stop kiosk.service 2>/dev/null || true
systemctl --user mask --runtime kiosk.service 2>/dev/null || true
systemctl --user reset-failed kiosk.service 2>/dev/null || true

# Kill browsers
pkill -f chromium-browser 2>/dev/null || true
pkill -f '(^|/)chromium(\s|$)' 2>/dev/null || true

echo "Kiosk disabled until reboot."
