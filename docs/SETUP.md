# Set up locspoof (Windows or Mac)

About 15 minutes. Do the steps in order and don't skip any. After each step there's a ✅ line telling you what you should see. If you don't see it, stop and check **Stuck?** at the bottom.

**You need:**

- An iPhone on iOS 17 or newer (Settings > General > About > iOS Version).
- A Windows PC or a Mac, for the start and the end of setup.
- The iPhone's charging cable.
- **$3** for a signing certificate. This is the only install method this guide supports. Free methods break every 7 days; the $3 one lasts about a year.

---

## Part 1: on the computer (Developer Mode first)

Developer Mode has to be on **before** anything else: the FlareStore app and locspoof won't even open without it. locspoof Setup turns it on for you.

### Step 1. Windows only: install Apple Devices

Mac users skip this step.

1. Install **[Apple Devices](https://apps.microsoft.com/detail/9np83lwlpz9k)** from the Microsoft Store (free). This is what lets Windows talk to an iPhone. iTunes works too if you already have it.
2. Open it once, then close it.

✅ Apple Devices opened without errors.

### Step 2. Download locspoof Setup

From the **[latest release](https://github.com/opsec-bot/locspoof-ios/releases/latest)**, download the one for your computer:

| Your computer | Download |
|---|---|
| Windows | `locspoof-setup.exe` |
| Mac with an Apple chip (M1, M2, M3, M4…) | `locspoof-setup-mac-apple-silicon.zip` |
| Mac with an Intel processor | `locspoof-setup-mac-intel.zip` |

Not sure which Mac? Apple menu  > **About This Mac**. "Chip: Apple M…" means Apple chip. "Processor: Intel" means Intel.

### Step 3. Open locspoof Setup

**Windows:**

1. Double-click `locspoof-setup.exe`.
2. If a blue box says **"Windows protected your PC"**: click **More info**, then **Run anyway**. (It says this because the app isn't from a big company, not because something is wrong.)

**Mac:**

1. Double-click the `.zip` to unzip it, then double-click **locspoof-setup**.
2. If it says it **can't be opened** or **Apple could not verify** it: click **Done**. Open **System Settings > Privacy & Security**, scroll to the bottom, click **Open Anyway** next to locspoof-setup, enter your Mac password, then **Open**.

✅ A black window opens that says **locspoof Setup** at the top.

### Step 4. Plug in and turn on Developer Mode

1. Plug the iPhone into the computer with the cable.
2. Do exactly what each **yellow line** in the window says, one at a time:
   - unlock the iPhone,
   - tap **Trust** on the iPhone and enter your passcode,
   - Developer Mode: the window either turns it on by itself (the iPhone restarts) or tells you to go to **Settings > Privacy & Security > Developer Mode**, turn it on and restart. After the restart, unlock the iPhone and tap **Turn On**. Keep the cable plugged in.

✅ The window says **OK Developer Mode is on** and then **Now install locspoof on the iPhone**. **Leave the window open.** You can unplug the iPhone now.

---

## Part 2: on the iPhone (while the window waits)

### Step 5. Install LocalDevVPN

1. On the iPhone, open the App Store and install **[LocalDevVPN](https://apps.apple.com/app/id6755608044)**.
2. Open it once. If it asks to add a VPN configuration, tap **Allow** and enter your passcode.

✅ LocalDevVPN is on your home screen.

### Step 6. Buy the $3 certificate

FlareStore asks for your iPhone's **UDID** (its ID number) when you buy, so get that first.

1. On the iPhone, open **Safari** (not Chrome) and go to **[udid.website](https://udid.website/)**.
2. Tap the button to get your UDID. It asks to download a profile: tap **Allow**, then open **Settings**, tap **Profile Downloaded** near the top, and tap **Install** (enter your passcode).
3. Safari comes back and shows your UDID, a long code of letters and numbers. **Copy it.**
4. Go to **[flarestore.app](https://flarestore.app/)** in Safari and buy the **$3 certificate**. When it asks for your UDID, paste the one you copied.
5. Wait until FlareStore says your certificate is ready. This can take a few minutes.
6. On FlareStore's page, enter the same UDID and install the **FlareStore app** from there. It's signed for your iPhone, so it only works on the phone with that UDID. Trust it if asked: **Settings > General > VPN & Device Management**.

✅ The FlareStore app is on your home screen and shows your certificate as active.

### Step 7. Install locspoof

1. In Safari on the iPhone, open the **[latest locspoof release](https://github.com/opsec-bot/locspoof-ios/releases/latest)** and tap **`locspoof-….ipa`** to download it.
2. Open the **FlareStore app** and import that downloaded `.ipa` (it's in Files > Downloads).
3. In FlareStore, tap **Sign**, then **Install**.
4. If the iPhone says the developer isn't trusted: **Settings > General > VPN & Device Management**, tap the profile, tap **Trust**.

✅ The locspoof icon is on your home screen and opens.

### Step 8. Finish setup

1. Plug the iPhone back into the computer. The locspoof Setup window is still open and waiting.
2. It sees locspoof, makes the pairing file, puts it inside locspoof, and installs Apple's developer disk image. All by itself; the last part needs internet and takes up to a minute.

✅ The window says **All done.** in green. Unplug the iPhone and close the window.

If you closed the window by accident, just open locspoof Setup again and plug in. It skips what's already done.

---

## Part 3: use it

### Step 9. Connect

1. If locspoof is open, close it fully: swipe up from the bottom, then swipe locspoof away.
2. Open **LocalDevVPN** and turn it **on**.
3. Open **locspoof**. The first time it shows a few setup screens; go through them.

✅ The top of locspoof says **Connected**. The first time can take up to a minute.

### Step 10. Move your location

- **Teleport:** tap **Teleport**, search a place or tap the map, then press **Teleport**. Press **Stop** to get your real location back.
- **Drive:** pick **Drive**, **Bike** or **Walk**, tap a start and an end on the map, then **Start drive**. It follows real roads and stops at real traffic lights.

### Using it on cellular (no Wi-Fi)

The connection can only start on Wi-Fi, but it keeps running on cellular.

1. Join any Wi-Fi (a friend's hotspot works) and wait for **Connected**.
2. Turn Wi-Fi **off**. Leave cellular on.
3. Keep Wi-Fi off. If the iPhone joins a Wi-Fi network again, your real location comes back and you have to redo 1 and 2.

---

## Things to know

- **Restarted your iPhone?** It forgets the pairing and the disk image on every restart. Plug it in and run locspoof Setup again (Step 3, about a minute). Nothing else needs redoing.
- **Certificate expired** (after about a year)? Buy a new one and redo Steps 6 and 7.
- **Never send anyone your pairing file** or let someone else run locspoof Setup with your phone. It controls your iPhone's developer tools.

## Stuck?

| What you see | Do this |
|---|---|
| Windows: "Windows can't see iPhones yet" | Do Step 1, open Apple Devices once, leave the window open. |
| "Plug your iPhone into this computer" but it is plugged in | Try another cable or USB port. Unlock the iPhone. |
| You tapped "Don't Trust" | Unplug, plug back in, tap **Trust**. |
| No Developer Mode switch in Settings | Leave locspoof Setup running with the phone plugged in; it makes the switch appear. |
| "Now install locspoof on the iPhone" | That's expected: do Part 2, then plug back in. The window keeps waiting. |
| FlareStore app or locspoof won't open | Developer Mode is off. Plug in and run locspoof Setup (Part 1) first. |
| locspoof says **DDI Mount Failed** or **BadBuildManifest** | Your iPhone needs the newer disk image (iOS 27 and the newest iPhones). Plug in and run the latest locspoof Setup; it installs it. |
| locspoof never says Connected | Is LocalDevVPN on? Restarted the phone since setup? Run Setup again. Then use the connection check inside locspoof; it tells you which part failed. |

Still stuck? Ask ChatGPT (or any AI with web access). Paste this and add a screenshot:

> I'm setting up locspoof on my iPhone. The guide is https://github.com/opsec-bot/locspoof-ios/blob/main/docs/SETUP.md and the code is https://github.com/opsec-bot/locspoof-ios. I'm on step [number], on a [Windows PC / Mac]. This is what I see: [exact message].
