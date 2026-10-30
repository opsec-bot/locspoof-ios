# locspoof Setup

One double-click to get an iPhone ready for locspoof: it waits for the phone and "Trust", checks locspoof is installed, turns on Developer Mode, makes a fresh pairing file and puts it straight into locspoof over the cable.

Download it from the [latest release](https://github.com/opsec-bot/locspoof-ios/releases/latest). Step-by-step guide: [docs/SETUP.md](../docs/SETUP.md).

Run from source: `pip install -r requirements.txt` then `python locspoof_setup.py`. Keep the pins: srptools 2.x breaks pairing.

GPL-3.0-or-later (it uses pymobiledevice3), unlike the rest of this repo. See `LICENSE` in this folder.
