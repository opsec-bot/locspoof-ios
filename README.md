# locspoof for iOS

Set your iPhone's location from the iPhone itself. Teleport to a spot, or drive, bike or walk a real route with road speeds, slowing for corners, stops at junctions and natural GPS drift.

No Mac and no jailbreak. It runs on the phone through LocalDevVPN, so once it's connected it keeps working off Wi-Fi.

This is the on-device side of [locspoof](https://github.com/opsec-bot/locspoof). It started as a fork of [RouteSim](https://github.com/felix88195/RouteSim), which is a fork of [StikDebug](https://github.com/StephenDev0/StikDebug).

## What it does

- **Teleport.** Pick a spot on the map or search for one. Tap the map again to jump somewhere else.
- **Routes.** Add as many stops as you want, then drive, bike or walk them. Routes follow real roads (OSRM, with Apple Maps as the fallback).
- **Realistic motion.**
  - Speed follows each road's limit.
  - It speeds up and brakes smoothly.
  - It slows down for corners.
  - It sometimes waits at real intersections.
  - You can set a max speed in mph.
- **GPS wander.** The point drifts a few metres the way real GPS does, so it never sits perfectly still or rides the exact centre of the road.
- **Finds its own connection port.** iOS picks a new RemotePairing port every time the phone restarts. locspoof finds the new one by itself instead of failing with "connection refused".
- **Connection check screen.** It checks the pairing file, LocalDevVPN, the port, the tunnel and the developer disk image in order, and tells you which step is broken and how to fix it.
- **Pairing files are easy to swap.** Replace one in Settings, or tap the file in Files or a chat and open it with locspoof. No reinstall.
- **Saved routes and GPX.** Save routes, and import or export GPX that works with the PC version.

## Setup

1. Turn on Developer Mode: Settings > Privacy & Security > Developer Mode.
2. Install [LocalDevVPN](https://apps.apple.com/app/id6755608044) from the App Store.
3. Make a pairing file on a computer, with the iPhone plugged in:
   ```
   pip install pymobiledevice3
   python -m pymobiledevice3 lockdown remotepairing --pair
   ```
   That writes `~/.pymobiledevice3/remote_<udid>.plist`. locspoof wants a plist with three keys: `identifier`, `private_key` and `public_key`. The `identifier` is pymobiledevice3's `generate_host_id()`.
4. Send the file to the iPhone and import it in locspoof's setup screens.
5. Turn on LocalDevVPN and connect the tunnel (see below).

## Using it on cellular

The tunnel can only start while the iPhone is on Wi-Fi. Once it's up, it keeps running on cellular.

1. Join any Wi-Fi network. A friend's hotspot works, and so does free Wi-Fi at a store or cafe. It doesn't need working internet.
2. Open locspoof and wait until the status at the top says **Connected**. Start your route or teleport.
3. **Turn Wi-Fi off** in Settings or Control Center, and leave cellular data on.
4. Leave Wi-Fi off the whole time. If the phone joins another Wi-Fi network by itself, the tunnel resets and your location jumps back to the real one. Then you have to do step 1 again.

That's it. As long as Wi-Fi stays off and cellular stays on, it keeps running.

## Install

Download `locspoof-Debug.ipa` from the latest [Actions run](../../actions/workflows/build_ipa.yml), then sign and install it.

I sign mine with [FlareStore](https://flarestore.app/). A cert is about $3, and you sign the IPA right in the browser. SideStore or AltStore work too if you'd rather use a free Apple ID.

## Build

There's no Mac needed. Every push to `main` builds an unsigned IPA on GitHub Actions in about 3 minutes. Unit tests run only when you start them by hand from the Actions tab.

The Xcode project and target are still called `StikDebug`. Renaming them only adds CI risk.

| Folder | What's in it |
| --- | --- |
| `Simulation/` | Motion plan, GPS wander, route player |
| `Routes/` | Routing, place search, saved routes, GPX |
| `Tunnel/` | Pairing file, port finder, tunnel, error explanations |
| `Features/` | Map, routes list, settings, connection checks, setup |

## Limits

- It only changes GPS position. Motion sensors aren't faked, so apps that also use the accelerometer (like Life360's driving detection) may not always agree.
- When locspoof stops or the tunnel drops, the iPhone goes back to its real location. That's how iOS 17 and later work.
- Background playback depends on the silent audio and location keep-alive settings. Force-quitting the app stops it.

## License

New code is MIT, see [LICENSE](LICENSE). Parts of the tunnel layer come from StikDebug (AGPL-3.0), and `libidevice_ffi.a` comes from [idevice](https://github.com/jkcoxson/idevice). See [NOTICE.md](NOTICE.md).
