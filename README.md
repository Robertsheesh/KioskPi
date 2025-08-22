<br />
<div align="center">
  <a href="https://github.com/Robertsheesh/KioskPi">
    <img src="KioskPi_logo.png" alt="Logo" width="200" height="200">
  </a>
</div>

# KioskPi

Chromium kiosk for Raspberry Pi OS Desktop/Lite.
- Fullscreen Chromium
- Wrapper page with 2-minute refresh
- Shift+Alt+Enter to disable kiosk until reboot
- Nightly reboot at 03:00

## Install
1. Install Raspberry Pi OS Desktop on to your Raspberry Pi.
2. Open Terminal
3. Type "sudo apt update && sudo apt install -y git"
4. Type "git clone https://github.com/Robertsheesh/KioskPi"
5. Change directory to KioskPi "cd KioskPi"
6. Install the script "sudo bash install.sh"
7. Reboot the device "sudo reboot".
   
To change the URL:
- Edit ~/kiosk.html "const URL_TO_LOAD = "https://your_url.com/display1";"
