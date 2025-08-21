#!/usr/bin/env bash
set -euo pipefail

# ---- Detect the target login user (who will run the kiosk) ----
TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
echo "Installing for user: $TARGET_USER (home: $TARGET_HOME)"

# ---- Packages ----
sudo apt update
sudo apt install -y chromium-browser unclutter xbindkeys

# ---- Files/dirs ----
mkdir -p "$TARGET_HOME/.config/systemd/user" "$TARGET_HOME/.config/autostart"

# 1) Launcher: start-kiosk.sh
tee "$TARGET_HOME/start-kiosk.sh" >/dev/null <<'SH'
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
SH
chmod +x "$TARGET_HOME/start-kiosk.sh"

# 2) Wrapper page: kiosk.html (edit URL here if you like)
tee "$TARGET_HOME/kiosk.html" >/dev/null <<'HTML'
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

# 3) Hotkey to disable kiosk until reboot: Shift+Alt+Enter
tee "$TARGET_HOME/disable-kiosk.sh" >/dev/null <<'SH'
#!/usr/bin/env bash
set -euo pipefail
FLAG="${XDG_RUNTIME_DIR:-/run/user/$UID}/kiosk.disabled"
mkdir -p "$(dirname "$FLAG")"; touch "$FLAG"
systemctl --user stop kiosk.service 2>/dev/null || true
systemctl --user mask --runtime kiosk.service 2>/dev/null || true
systemctl --user reset-failed kiosk.service 2>/dev/null || true
pkill -f chromium-browser 2>/dev/null || true
pkill -f '(^|/)chromium(\s|$)' 2>/dev/null || true
echo "Kiosk disabled until reboot."
SH
chmod +x "$TARGET_HOME/disable-kiosk.sh"

tee "$TARGET_HOME/.xbindkeysrc" >/dev/null <<'RC'
# Disable kiosk until reboot: Shift + Alt + Enter
"bash -lc '$HOME/disable-kiosk.sh'"
  Shift+Alt + Return
RC

tee "$TARGET_HOME/.config/autostart/xbindkeys.desktop" >/dev/null <<'DESK'
[Desktop Entry]
Type=Application
Name=xbindkeys
Exec=/usr/bin/xbindkeys
X-GNOME-Autostart-enabled=true
DESK

# 4) User systemd service (reliable autostart on Bookworm)
tee "$TARGET_HOME/.config/systemd/user/kiosk.service" >/dev/null <<'UNIT'
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

# 5) Optional nightly reboot at 03:00
if [ ! -f /etc/cron.d/kiosk-reboot ]; then
  echo '0 3 * * * root /sbin/shutdown -r now' | sudo tee /etc/cron.d/kiosk-reboot >/dev/null
fi

# 6) Ownership + enable linger + enable service
sudo chown -R "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.config" \
  "$TARGET_HOME/start-kiosk.sh" "$TARGET_HOME/disable-kiosk.sh" "$TARGET_HOME/kiosk.html"

sudo loginctl enable-linger "$TARGET_USER"

sudo -u "$TARGET_USER" systemctl --user daemon-reload
sudo -u "$TARGET_USER" systemctl --user unmask kiosk.service 2>/dev/null || true
sudo -u "$TARGET_USER" systemctl --user enable --now kiosk.service

echo "✅ Install complete. If Chromium didn't pop up, check:"
echo "   systemctl --user status kiosk.service"
echo "   journalctl --user -u kiosk.service -e"
