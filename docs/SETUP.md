# Set up locspoof (Windows or Mac)

About 15 minutes. Do the steps in order and don't skip any. After each step there's a ✅ line telling you what you should see. If you don't see it, stop and check **Stuck?** at the bottom.

**You need:**

- An iPhone on iOS 17 or newer (Settings > General > About > iOS Version).
- A Windows PC or a Mac, only for one step.
- The iPhone's charging cable.
- **$3** for a signing certificate. This is the only install method this guide supports. Free methods break every 7 days; the $3 one lasts about a year.

---

## Part 1: on the iPhone

### Step 1. Install LocalDevVPN

1. On the iPhone, open the App Store and install **[LocalDevVPN](https://apps.apple.com/app/id6755608044)**.
2. Open it once. If it asks to add a VPN configuration, tap **Allow** and enter your passcode.

✅ LocalDevVPN is on your home screen.

### Step 2. Buy the $3 certificate

1. On the iPhone, open **Safari** (not Chrome) and go to **[flarestore.app](https://flarestore.app/)**.
2. Buy the **$3 certificate** and follow FlareStore's steps. It installs a small profile so it knows your iPhone; allow it when asked.
3. Wait until FlareStore says your certificate is ready. This can take a few minutes.

✅ FlareStore shows your certificate as active.

### Step 3. Install locspoof

1. Still in Safari on the iPhone, open the **[latest locspoof release](https://github.com/opsec-bot/locspoof-ios/releases/latest)** and tap **`locspoof-….ipa`** to download it.
2. In FlareStore, choose that downloaded `.ipa`, tap **Sign**, then **Install**.
3. If the iPhone says the developer isn't trusted: **Settings > General > VPN & Device Management**, tap the profile under "Enterprise App", tap **Trust**.

✅ The locspoof icon is on your home screen and opens.

---

## Part 2: on the computer (one time)

### Step 4. Windows only: install Apple Devices

Mac users skip this step.

1. Install **[Apple Devices](https://apps.microsoft.com/detail/9np83lwlpz9k)** from the Microsoft Store (free). This is what lets Windows talk to an iPhone. iTunes works too if you already have it.
2. Open it once, then close it.

✅ Apple Devices opened without errors.

### Step 5. Download locspoof Setup

From the **[latest release](https://github.com/opsec-bot/locspoof-ios/releases/latest)**, download the one for your computer:

| Your computer | Download |
|---|---|
| Windows | `locspoof-setup.exe` |
| Mac with an Apple chip (M1, M2, M3, M4…) | `locspoof-setup-mac-apple-silicon.zip` |
| Mac with an Intel processor | `locspoof-setup-mac-intel.zip` |

Not sure which Mac? Apple menu  > **About This Mac**. "Chip: Apple M…" means Apple chip. "Processor: Intel" means Intel.

### Step 6. Open locspoof Setup

**Windows:**

1. Double-click `locspoof-setup.exe`.
2. If a blue box says **"Windows protected your PC"**: click **More info**, then **Run anyway**. (It says this because the app isn't from a big company, not because something is wrong.)

**Mac:**

1. Double-click the `.zip` to unzip it, then double-click **locspoof-setup**.
2. If it says it **can't be opened** or **Apple could not verify** it: click **Done**. Open **System Settings > Privacy & Security**, scroll to the bottom, click **Open Anyway** next to locspoof-setup, enter your Mac password, then **Open**.

✅ A black window opens that says **locspoof Setup** at the top.

### Step 7. Follow the yellow lines

1. Plug the iPhone into the computer with the cable.
2. Do exactly what each **yellow line** says, one at a time. It will ask you to:
   - unlock the iPhone,
   - tap **Trust** on the iPhone and enter your passcode,
   - turn on **Developer Mode** if it isn't already on. The iPhone restarts; unlock it and tap **Turn On**. Keep the cable plugged in the whole time.
3. Don't close the window. It waits for you and moves on by itself.

✅ The window says **All done.** in green. You can unplug the iPhone and close the window.

---

## Part 3: use it

### Step 8. Connect

1. If locspoof is open, close it fully: swipe up from the bottom, then swipe locspoof away.
2. Open **LocalDevVPN** and turn it **on**.
3. Open **locspoof**. The first time it shows a few setup screens; go through them.

✅ The top of locspoof says **Connected**. The first time can take up to a minute.

### Step 9. Move your location

- **Teleport:** tap **Teleport**, search a place or tap the map, then press **Teleport**. Press **Stop** to get your real location back.
- **Drive:** pick **Drive**, **Bike** or **Walk**, tap a start and an end on the map, then **Start drive**. It follows real roads and stops at real traffic lights.

### Using it on cellular (no Wi-Fi)

The connection can only start on Wi-Fi, but it keeps running on cellular.

1. Join any Wi-Fi (a friend's hotspot works) and wait for **Connected**.
2. Turn Wi-Fi **off**. Leave cellular on.
3. Keep Wi-Fi off. If the iPhone joins a Wi-Fi network again, your real location comes back and you have to redo 1 and 2.

---

## Things to know

- **Restarted your iPhone?** It forgets the pairing on every restart. Plug it in and run locspoof Setup again (Step 6 and 7, about a minute). Nothing else needs redoing.
- **Certificate expired** (after about a year)? Buy a new one and redo Step 3.
- **Never send anyone your pairing file** or let someone else run locspoof Setup with your phone. It controls your iPhone's developer tools.

## Stuck?

| What you see | Do this |
|---|---|
| Windows: "Windows can't see iPhones yet" | Do Step 4, open Apple Devices once, leave the window open. |
| "Plug your iPhone into this computer" but it is plugged in | Try another cable or USB port. Unlock the iPhone. |
| You tapped "Don't Trust" | Unplug, plug back in, tap **Trust**. |
| No Developer Mode switch in Settings | Leave locspoof Setup running with the phone plugged in; it makes the switch appear. |
| "locspoof isn't on this iPhone yet" | Finish Step 3 first. The window keeps checking. |
| locspoof never says Connected | Is LocalDevVPN on? Restarted the phone since setup? Run Setup again. Then use the connection check inside locspoof; it tells you which part failed. |

Still stuck? Ask ChatGPT (or any AI with web access). Paste this and add a screenshot:

> I'm setting up locspoof on my iPhone. The guide is https://github.com/opsec-bot/locspoof-ios/blob/main/docs/SETUP.md and the code is https://github.com/opsec-bot/locspoof-ios. I'm on step [number], on a [Windows PC / Mac]. This is what I see: [exact message].
