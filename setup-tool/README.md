# locspoof Setup

One double-click to get an iPhone ready for locspoof: it waits for the phone and "Trust", checks locspoof is installed, turns on Developer Mode, makes a fresh pairing file and puts it straight into locspoof over the cable, then installs Apple's developer disk image (the Cryptex variant on iOS 27+, which the app can't install itself).

Download it from the [latest release](https://github.com/opsec-bot/locspoof-ios/releases/latest). Step-by-step guide: [docs/SETUP.md](../docs/SETUP.md).

Run from source: `pip install -r requirements.txt` then `python locspoof_setup.py`. Keep the pin: older pymobiledevice3 with srptools 2.x breaks pairing, and only 11.48+ installs the iOS 27 disk image.

GPL-3.0-or-later (it uses pymobiledevice3), unlike the rest of this repo. See `LICENSE` in this folder.
