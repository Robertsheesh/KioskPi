#!/usr/bin/env bash
set -euo pipefail

# --- Detect who we're installing for (login user) ---
TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
FILES_DIR="$REPO_DIR/files"

echo "Installing KioskPi for user: $TARGET_USER (home: $TARGET_HOME)"
echo "Using files from: $FILES_DIR"

# --- Packages (Chromium only; Wayland friendly) ---
sudo apt update
sudo apt install -y chromium-browser || sudo apt install -y chromium

# Try xbindkeys only if present (helps on X11; harmless on Wayland if missing)
sudo apt install -y xbindkeys || true

# --- Ensure config dirs exist ---
mkdir -p "$TARGET_HOME/.config/systemd/user" "$TARGET_HOME/.config/autostart"

# --- Copy payload files into the user's home ---
install -m 0755 "$FILES_DIR/start-kiosk.sh"      "$TARGET_HOME/start-kiosk.sh"
install -m 0755 "$FILES_DIR/disable-kiosk.sh"    "$TARGET_HOME/disable-kiosk.sh"
install -m 0644 "$FILES_DIR/kiosk.html"          "$TARGET_HOME/kiosk.html"
install -m 0644 "$FILES_DIR/kiosk.service"       "$TARGET_HOME/.config/systemd/user/kiosk.service"

# X11-only hotkey bits (won't hurt if unused)
if command -v xbindkeys >/dev/null 2>&1; then
  install -m 0644 "$FILES_DIR/.xbindkeysrc"        "$TARGET_HOME/.xbindkeysrc"
  install -m 0644 "$FILES_DIR/xbindkeys.desktop"   "$TARGET_HOME/.config/autostart/xbindkeys.desktop"
fi

# Optional nightly reboot at 03:00
if [ -f "$FILES_DIR/kiosk-reboot.cron" ] && [ ! -f /etc/cron.d/kiosk-reboot ]; then
  sudo install -m 0644 "$FILES_DIR/kiosk-reboot.cron" /etc/cron.d/kiosk-reboot
fi

# --- Wayfire (Wayland) hotkey: Shift+Alt+Enter to disable kiosk ---
# Adds/updates ~/.config/wayfire.ini to enable 'command' plugin and bind our script.
WAYFIRE_INI="$TARGET_HOME/.config/wayfire.ini"
if [ -f /etc/xdg/wayfire/wayfire.ini ]; then
  mkdir -p "$TARGET_HOME/.config"
  [ -f "$WAYFIRE_INI" ] || cp /etc/xdg/wayfire/wayfire.ini "$WAYFIRE_INI"

  # Ensure 'command' plugin is listed under [core]
  if grep -q '^\s*plugins\s*=' "$WAYFIRE_INI"; then
    sed -i 's/^\(\s*plugins\s*=\s*.*\)\bcommand\b\{0,1\}\(.*\)$/\1 command\2/' "$WAYFIRE_INI"
  else
    printf '[core]\nplugins = command\n' >> "$WAYFIRE_INI"
  fi

  # Ensure [command] section exists
  grep -q '^\[command\]' "$WAYFIRE_INI" || printf '\n[command]\n' >> "$WAYFIRE_INI"

  # Append a binding for Shift+Alt+Enter -> disable-kiosk.sh
  IDX=$(grep -Eo '^binding_[0-9]+' "$WAYFIRE_INI" | sed 's/binding_//' | sort -n | tail -1)
  IDX=${IDX:-"-1"}; IDX=$((IDX+1))
  printf 'binding_%d = <shift> <alt> KEY_ENTER\ncommand_%d = %s/disable-kiosk.sh\n' \
    "$IDX" "$IDX" "$TARGET_HOME" >> "$WAYFIRE_INI"
fi

# --- Ownership fixes (very important) ---
sudo chown -R "$TARGET_USER:$TARGET_USER" \
  "$TARGET_HOME/start-kiosk.sh" \
  "$TARGET_HOME/disable-kiosk.sh" \
  "$TARGET_HOME/kiosk.html" \
  "$TARGET_HOME/.config"

# --- Enable user lingering & the kiosk service ---
sudo loginctl enable-linger "$TARGET_USER"
sudo -u "$TARGET_USER" systemctl --user daemon-reload
sudo -u "$TARGET_USER" systemctl --user unmask kiosk.service 2>/dev/null || true
sudo -u "$TARGET_USER" systemctl --user enable --now kiosk.service

echo
echo "Install complete."
echo "If Chromium didn't pop up yet, check:"
echo "  systemctl --user status kiosk.service"
echo "  journalctl --user -u kiosk.service -e"
echo "Hotkey to disable kiosk (Wayland/Wayfire): Shift+Alt+Enter"
