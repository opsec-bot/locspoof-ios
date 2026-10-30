"""locspoof Setup: get an iPhone ready for locspoof with one double-click.

Runs on Windows and macOS. With the iPhone plugged in by cable it:

1. waits for the phone and for "Trust This Computer",
2. checks locspoof is installed,
3. turns on Developer Mode (or shows exactly where to tap),
4. makes a fresh RemotePairing file,
5. puts it straight into locspoof's Documents folder over the cable.

locspoof moves that file into place the next time it opens, replacing any
older one. The pairing file never touches this computer's disk outside
pymobiledevice3's own pair-record folder.

GPL-3.0-or-later, because it uses pymobiledevice3.
"""
from __future__ import annotations

import asyncio
import os
import plistlib
import sys
import traceback

from pymobiledevice3.exceptions import (
    ConnectionFailedToUsbmuxdError,
    MuxException,
    PairingDialogResponsePendingError,
    PasswordRequiredError,
    RemotePairingCompletedError,
    UserDeniedPairingError,
)
from pymobiledevice3.lockdown import create_using_usbmux
from pymobiledevice3.pair_records import generate_host_id
from pymobiledevice3.remote.tunnel_service import RemotePairingLockdownService
from pymobiledevice3.services.amfi import AmfiService
from pymobiledevice3.services.house_arrest import HouseArrestService
from pymobiledevice3.services.installation_proxy import InstallationProxyService
from pymobiledevice3.usbmux import list_devices

VERSION = "1.0.0"
BUNDLE_ID = "app.locspoof.ios"
# locspoof's PairingFileStore picks this name up from Documents.
DROP_NAME = "pairingFile.plist"
WINDOWS = sys.platform == "win32"
POLL_S = 1.5

if WINDOWS:
    os.system("")  # turns on colour codes in the Windows console
# Print each line as it happens, even when the output isn't a console.
sys.stdout.reconfigure(line_buffering=True)

GREEN, YELLOW, RED, BOLD, RESET = "\033[32m", "\033[33m", "\033[31m", "\033[1m", "\033[0m"


def title(n: int, text: str) -> None:
    print(f"\n{BOLD}Step {n} of 5: {text}{RESET}")


def todo(text: str) -> None:
    print(f"  {YELLOW}>> {text}{RESET}")


def done(text: str) -> None:
    print(f"  {GREEN}OK {text}{RESET}")


class Once:
    """Prints each waiting message once, not every poll."""

    def __init__(self) -> None:
        self.shown: set[str] = set()

    def __call__(self, text: str) -> None:
        if text not in self.shown:
            self.shown.add(text)
            todo(text)


async def wait_for_phone() -> str:
    say = Once()
    while True:
        try:
            usb = [d for d in await list_devices() if d.connection_type == "USB"]
        except (ConnectionFailedToUsbmuxdError, MuxException, OSError):
            if WINDOWS:
                say("Windows can't see iPhones yet. Install the free \"Apple Devices\" app from the "
                    "Microsoft Store (or iTunes), open it once, then come back. This window keeps checking.")
            else:
                say("Can't reach the iPhone service on this Mac. Restart the Mac and try again.")
            await asyncio.sleep(3)
            continue
        if len(usb) > 1:
            say("More than one iPhone or iPad is plugged in. Unplug all but the one you're setting up.")
        elif usb:
            return usb[0].serial
        else:
            say("Plug your iPhone into this computer with a cable.")
        await asyncio.sleep(POLL_S)


async def wait_for_trust(udid: str):
    say = Once()
    while True:
        try:
            return await create_using_usbmux(serial=udid, autopair=True)
        except PasswordRequiredError:
            say("Unlock your iPhone (enter your passcode).")
        except PairingDialogResponsePendingError:
            say("On your iPhone, tap \"Trust\", then enter your passcode.")
        except UserDeniedPairingError:
            say("You tapped \"Don't Trust\". Unplug the iPhone, plug it back in, and tap \"Trust\" this time.")
        except (ConnectionFailedToUsbmuxdError, MuxException, OSError):
            say("Lost the iPhone. Check the cable is plugged in.")
            udid = await wait_for_phone()
        await asyncio.sleep(POLL_S)


async def wait_for_locspoof(lockdown) -> None:
    say = Once()
    while True:
        apps = await InstallationProxyService(lockdown).get_apps(bundle_identifiers=[BUNDLE_ID])
        if BUNDLE_ID in apps:
            version = apps[BUNDLE_ID].get("CFBundleShortVersionString", "?")
            done(f"locspoof {version} is installed.")
            return
        say("locspoof isn't on this iPhone yet. Install it with your cert first (guide step 2). "
            "Leave this window open, it keeps checking.")
        await asyncio.sleep(3)


async def ensure_developer_mode(udid: str, lockdown):
    if await lockdown.get_developer_mode_status():
        done("Developer Mode is on.")
        return lockdown

    await AmfiService(lockdown).reveal_developer_mode_option_in_ui()
    todo("Turn on Developer Mode on the iPhone:")
    print("       Settings > Privacy & Security > Developer Mode (near the bottom) > turn it on > Restart")
    print("       After the iPhone restarts and you unlock it, tap \"Turn On\" and enter your passcode.")
    todo("Waiting for that. Keep the cable plugged in.")

    while True:
        await asyncio.sleep(3)
        try:
            udid = await wait_for_phone()
            lockdown = await create_using_usbmux(serial=udid, autopair=True)
            if await lockdown.get_developer_mode_status():
                done("Developer Mode is on.")
                return lockdown
        except (PasswordRequiredError, PairingDialogResponsePendingError):
            pass  # still restarting or locked; keep waiting quietly
        except (ConnectionFailedToUsbmuxdError, MuxException, OSError):
            pass


async def make_pairing_file(lockdown) -> bytes:
    service = await RemotePairingLockdownService.create(lockdown)
    record = service.pair_record_path
    # Always pair fresh: an iPhone forgets RemotePairing hosts when it restarts,
    # and a stale record would give locspoof a file that no longer works.
    if record.exists():
        record.unlink()
    try:
        await service.connect(autopair=True)
    except RemotePairingCompletedError:
        pass
    finally:
        await service.close()
    rec = plistlib.loads(record.read_bytes())
    done("Pairing file made.")
    return plistlib.dumps({
        "identifier": generate_host_id(),
        "private_key": rec["private_key"],
        "public_key": rec["public_key"],
    })


async def put_into_locspoof(lockdown, data: bytes) -> None:
    async with await HouseArrestService.create(lockdown, BUNDLE_ID, documents_only=True) as afc:
        for path in (f"/Documents/{DROP_NAME}", f"/{DROP_NAME}"):
            try:
                await afc.set_file_contents(path, data)
                if await afc.exists(path):
                    done("Pairing file is inside locspoof.")
                    return
            except Exception:
                continue
    raise RuntimeError("Couldn't write the pairing file into locspoof.")


async def main() -> None:
    print(f"{BOLD}locspoof Setup {VERSION}{RESET}")
    print("Gets your iPhone ready for locspoof. Follow the yellow lines.")

    title(1, "Connect your iPhone")
    udid = await wait_for_phone()
    lockdown = await wait_for_trust(udid)
    major = int(str(lockdown.product_version).split(".")[0])
    if major < 17:
        raise SystemExit(f"This iPhone runs iOS {lockdown.product_version}. locspoof needs iOS 17 or newer.")
    done(f"Connected to {lockdown.short_info.get('DeviceName', 'your iPhone')} (iOS {lockdown.product_version}).")

    title(2, "Check locspoof is installed")
    await wait_for_locspoof(lockdown)

    title(3, "Developer Mode")
    lockdown = await ensure_developer_mode(udid, lockdown)

    title(4, "Make the pairing file")
    data = await make_pairing_file(lockdown)

    title(5, "Put it into locspoof")
    await put_into_locspoof(lockdown, data)

    print(f"\n{GREEN}{BOLD}All done.{RESET} You can unplug the iPhone.")
    print("  1. If locspoof is open, close it fully (swipe it away in the app switcher).")
    print("  2. Open LocalDevVPN and turn it on.")
    print("  3. Open locspoof and wait for \"Connected\" at the top.")


def run() -> None:
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\nStopped.")
    except SystemExit as exc:
        print(f"\n{RED}{exc}{RESET}")
    except Exception:
        print(f"\n{RED}Something went wrong. Take a screenshot of this whole window and send it to "
              f"whoever set you up, or paste it into ChatGPT with the guide link.{RESET}\n")
        traceback.print_exc()
    if getattr(sys, "frozen", False) or WINDOWS:
        input("\nPress Enter to close this window.")


if __name__ == "__main__":
    run()
