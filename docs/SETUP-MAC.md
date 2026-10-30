# Set up locspoof with a Mac

About 15 minutes. You need a Mac, an iPhone on iOS 17 or later, a USB cable, and an Apple ID. No Python, no Terminal.

## 1. Get the apps

On the **iPhone**, install [LocalDevVPN](https://apps.apple.com/app/id6755608044) from the App Store.

On the **Mac**, download three things:

- **locspoof**: `locspoof-2.1.0.ipa` from the [latest release](https://github.com/opsec-bot/locspoof-ios/releases/latest).
- **Sideloadly**, to install the IPA: [sideloadly.io](https://sideloadly.io/).
- **idevice_pair**, to make the pairing file: `idevice_pair--macos-universal.dmg` from [its releases](https://github.com/jkcoxson/idevice_pair/releases/latest).

If macOS says an app "can't be opened", right-click it, choose **Open**, then **Open** again.

## 2. Install locspoof

**Bought a signing cert (FlareStore or similar)?** Skip Sideloadly. On the iPhone, open the signer's site, upload `locspoof-2.1.0.ipa` (download it on the phone from the release link above), sign it, and tap install. Then trust it in **Settings > General > VPN & Device Management** if asked. A cert lasts about a year, so there's no 7-day renewal. Go to step 3.

**Free Apple ID instead:**

1. Plug the iPhone into the Mac and unlock it. Tap **Trust** if it asks.
2. Open Sideloadly. Drag `locspoof-2.1.0.ipa` onto it.
3. Type your Apple ID email and press **Start**. Enter your password and any code Apple sends you.
4. On the iPhone: **Settings > General > VPN & Device Management**, tap your Apple ID, then **Trust**.

With a free Apple ID the app stops opening after 7 days. Plug in and press Start in Sideloadly again to renew it. Your settings and pairing file stay.

## 3. Turn on Developer Mode

On the iPhone: **Settings > Privacy & Security > Developer Mode**, turn it on, and let the phone restart. After the restart, tap **Turn On** and enter your passcode.

The Developer Mode switch only shows up once a sideloaded app is installed, so do step 2 first. Still not there? idevice_pair (step 4) can turn Developer Mode on over the cable.

## 4. Make the pairing file

This file is what lets locspoof talk to the iPhone's location service. You make it once.

1. Keep the iPhone plugged in and unlocked.
2. Open idevice_pair and pick your iPhone from the list.
3. Create a **RemotePairing (RPPairing)** file, not a lockdown one, and save it.
4. AirDrop the file to the iPhone. Tap it and open it with **locspoof**. (Or save it to Files and import it from locspoof's setup screens.)

If the iPhone restarts later and locspoof says the pairing is bad, make a new file the same way and replace it in locspoof's Settings.

Keep this file private. Anyone with it can control the phone's developer services.

## 5. Connect

1. Open **LocalDevVPN** and turn it on.
2. Open **locspoof**. Go through the setup screens. Wait until the top says **Connected**. The first time can take up to a minute.

If it doesn't connect, open the connection check in locspoof. It goes through each step in order and tells you which one failed.

## 6. Use it

- **Teleport:** tap the Teleport tab, search a place or tap the map, then press Teleport. **Stop** gives your real location back.
- **Drive a route:** pick Drive, Bike or Walk, tap a start and an end, then **Start drive**.

## Using it on cellular

The tunnel can only start on Wi-Fi, but it keeps running on cellular.

1. Join any Wi-Fi (a hotspot works) and wait for **Connected**.
2. Turn Wi-Fi off. Leave cellular on.
3. Don't let the phone join Wi-Fi again, or the location jumps back to your real one.

## Stuck?

Ask ChatGPT (or any AI with web access). Paste this:

> I'm setting up locspoof on my iPhone with a Mac. The repo is https://github.com/opsec-bot/locspoof-ios and the setup guide is https://github.com/opsec-bot/locspoof-ios/blob/main/docs/SETUP-MAC.md. I'm on step [number] and this happened: [what you see, or the exact error]. What do I do?

A screenshot of the error helps a lot.

## No idevice_pair? (Terminal fallback)

If idevice_pair doesn't work, the Terminal way makes the same file. Run these with the iPhone plugged in:

```
python3 -m pip install --user pymobiledevice3
python3 -m pymobiledevice3 lockdown remotepairing --pair
python3 - <<'EOF'
import glob, os, plistlib
from pymobiledevice3.pair_records import generate_host_id
src = max(glob.glob(os.path.expanduser("~/.pymobiledevice3/remote_*.plist")), key=os.path.getmtime)
rec = plistlib.load(open(src, "rb"))
out = os.path.expanduser("~/Desktop/locspoof.mobiledevicepairing")
plistlib.dump({"identifier": generate_host_id(), "private_key": rec["private_key"], "public_key": rec["public_key"]}, open(out, "wb"))
print("Saved", out)
EOF
```

If `python3` asks to install developer tools, say yes and run the commands again. The file lands on the Desktop; send it to the iPhone like in step 4.
