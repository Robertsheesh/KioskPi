#!/usr/bin/env bash
set -euo pipefail

# ===== Detect user & paths =====
TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "==> Installing Kiosk for user: $TARGET_USER (home: $TARGET_HOME)"

# ===== Packages =====
echo "==> Installing Chromium"
sudo apt update
# Works whether package name is chromium-browser or chromium
sudo apt install -y chromium-browser || sudo apt install -y chromium

# Ensure we boot to a graphical target (Desktop)
sudo systemctl set-default graphical.target || true

# ===== Create needed dirs =====
mkdir -p "$TARGET_HOME/.config/systemd/user" "$TARGET_HOME/.config/autostart"

# ===== Write kiosk.html (the wrapper page) =====
cat > "$TARGET_HOME/kiosk.html" <<'HTML'
<!doctype html>
<html lang="en"><meta charset="utf-8" />
<title>Kiosk</title>
<style>
  html,body{margin:0;height:100%;background:#000;overflow:hidden}
  iframe{width:100%;height:100%;border:0;display:block;background:#000}
  ::-webkit-scrollbar{display:none}
  body{cursor:default} body.hide-cursor{cursor:none}
</style>
<body>
<script>
  // >>> CHANGE THIS if you need a different page:
  const URL_TO_LOAD = "https://ahola-infotv.azurewebsites.net/display/3";
  const REFRESH_MS = 120000, HIDE_CURSOR_AFTER_MS = 2000;

  const frame=document.createElement('iframe'); document.body.appendChild(frame);
  function reload(){ const sep = URL_TO_LOAD.includes('?')?'&':'?'; frame.src = URL_TO_LOAD + sep + 't=' + Date.now(); }
  reload(); setInterval(reload, REFRESH_MS);

  let t; function arm(){ document.body.classList.remove('hide-cursor'); clearTimeout(t);
    t=setTimeout(()=>document.body.classList.add('hide-cursor'),HIDE_CURSOR_AFTER_MS); }
  ['mousemove','mousedown','touchstart','keydown'].forEach(e=>document.addEventListener(e,arm,{passive:true}));
  arm();
</script>
</body></html>
HTML

# ===== Write start-kiosk.sh (launcher) =====
cat > "$TARGET_HOME/start-kiosk.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

# Do not start if disabled for this boot
FLAG="${XDG_RUNTIME_DIR:-/run/user/$UID}/kiosk.disabled"
[ -e "$FLAG" ] && exit 0

BROWSER="$(command -v chromium-browser || command -v chromium)"

# Kill any existing Chromium instances
pkill -f chromium-browser 2>/dev/null || true
pkill -f '(^|/)chromium(\s|$)' 2>/dev/null || true
sleep 0.5

# Prefer Wayland on Bookworm; harmless if it falls back
EXTRA_FLAGS="--ozone-platform=wayland"

# Prevent blanking under X11 (no effect on Wayland)
xset -dpms s off s noblank 2>/dev/null || true

# Launch kiosk
exec setsid "$BROWSER" \
  --kiosk --start-fullscreen \
  --noerrdialogs --disable-infobars --disable-session-crashed-bubble \
  --no-first-run --disable-translate \
  $EXTRA_FLAGS \
  file://"$HOME"/kiosk.html \
  >/dev/null 2>&1
SH
chmod +x "$TARGET_HOME/start-kiosk.sh"

# ===== Write disable-kiosk.sh (hotkey target) =====
cat > "$TARGET_HOME/disable-kiosk.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
FLAG="${XDG_RUNTIME_DIR:-/run/user/$UID}/kiosk.disabled"
mkdir -p "$(dirname "$FLAG")"; touch "$FLAG"

# Stop/Mask (runtime) user service if present
systemctl --user stop kiosk.service 2>/dev/null || true
systemctl --user mask --runtime kiosk.service 2>/dev/null || true
systemctl --user reset-failed kiosk.service 2>/dev/null || true

# Kill browsers
pkill -f chromium-browser 2>/dev/null || true
pkill -f '(^|/)chromium(\s|$)' 2>/dev/null || true
echo "Kiosk disabled until reboot."
SH
chmod +x "$TARGET_HOME/disable-kiosk.sh"

# ===== User systemd service (robust autostart) =====
cat > "$TARGET_HOME/.config/systemd/user/kiosk.service" <<'UNIT'
[Unit]
Description=Chromium Kiosk (User)
Wants=graphical-session.target
After=graphical-session.target
ConditionPathExists=!%t/kiosk.disabled

[Service]
Type=simple
ExecStart=%h/start-kiosk.sh
Restart=always
RestartSec=3

[Install]
WantedBy=default.target
UNIT

# ===== Desktop autostart (second trigger; Wayfire/LXQt) =====
cat > "$TARGET_HOME/.config/autostart/kiosk.desktop" <<DESK
[Desktop Entry]
Type=Application
Name=Kiosk
Exec=$TARGET_HOME/start-kiosk.sh
X-GNOME-Autostart-enabled=true
DESK

# ===== Wayfire (Wayland) hotkey: Shift+Alt+Enter => disable-kiosk =====
WAYFIRE_INI="$TARGET_HOME/.config/wayfire.ini"
if [ -f /etc/xdg/wayfire/wayfire.ini ]; then
  mkdir -p "$TARGET_HOME/.config"
  [ -f "$WAYFIRE_INI" ] || cp /etc/xdg/wayfire/wayfire.ini "$WAYFIRE_INI"
  # Ensure 'command' plugin present
  if grep -q '^\s*plugins\s*=' "$WAYFIRE_INI"; then
    # add 'command' if missing
    sed -i 's/^\(\s*plugins\s*=\s*.*\)\bcommand\b\{0,1\}\(.*\)$/\1 command\2/' "$WAYFIRE_INI"
  else
    printf '[core]\nplugins = command\n' >> "$WAYFIRE_INI"
  fi
  # Ensure [command] section
  grep -q '^\[command\]' "$WAYFIRE_INI" || printf '\n[command]\n' >> "$WAYFIRE_INI"
  # Append binding Shift+Alt+Enter
  IDX=$(grep -Eo '^binding_[0-9]+' "$WAYFIRE_INI" | sed 's/binding_//' | sort -n | tail -1)
  IDX=${IDX:-"-1"}; IDX=$((IDX+1))
  printf 'binding_%d = <shift> <alt> KEY_ENTER\ncommand_%d = %s/disable-kiosk.sh\n' \
    "$IDX" "$IDX" "$TARGET_HOME" >> "$WAYFIRE_INI"
fi

# ===== Nightly reboot at 03:00 =====
if [ ! -f /etc/cron.d/kiosk-reboot ]; then
  echo '0 3 * * * root /sbin/shutdown -r now' | sudo tee /etc/cron.d/kiosk-reboot >/dev/null
fi

# ===== Ownership and enablement =====
sudo chown -R "$TARGET_USER:$TARGET_USER" \
  "$TARGET_HOME/kiosk.html" \
  "$TARGET_HOME/start-kiosk.sh" \
  "$TARGET_HOME/disable-kiosk.sh" \
  "$TARGET_HOME/.config"

# Allow user services to run without an active TTY after boot
sudo loginctl enable-linger "$TARGET_USER"

# Enable and start the user service now
sudo -u "$TARGET_USER" systemctl --user daemon-reload
sudo -u "$TARGET_USER" systemctl --user unmask kiosk.service 2>/dev/null || true
sudo -u "$TARGET_USER" systemctl --user enable --now kiosk.service

echo "==> Install complete."
echo "   - Kiosk should launch now if you're in the desktop session."
echo "   - It will auto-launch on every login."
echo "   - Hotkey to disable until reboot: Shift + Alt + Enter"
echo "   - Logs:  systemctl --user status kiosk.service"
echo "            journalctl --user -u kiosk.service -e"
