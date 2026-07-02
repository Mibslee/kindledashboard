# Kindle Device Setup

This is the device-side checklist for KindleDashboard v0.2.

KindleDashboard does not provide jailbreak instructions or tools. Prepare KUAL and FBInk by following the original upstream/community documentation first.

Reference entry points:

- https://kindlemodding.org/jailbreaking/
- https://kindlemodding.org/jailbreaking/post-jailbreak/

## Verified Target

- Kindle Paperwhite 3 / PW3.
- KUAL is available.
- FBInk is available at `/mnt/us/libkh/bin/fbink`.
- Mac and Kindle are on the same Wi-Fi.

## Mac Checklist

1. Build:

   ```bash
   swift build
   ```

2. Start:

   ```bash
   ./start.sh
   ```

3. Find the Mac LAN IP:

   ```bash
   ipconfig getifaddr en0
   ```

4. Confirm local endpoints:

   ```text
   http://127.0.0.1:8787/control.json
   http://127.0.0.1:8787/frame.png
   ```

5. Confirm LAN endpoint from another device:

   ```text
   http://<mac-ip>:8787/frame.png
   ```

## Kindle Extension Install

1. Connect Kindle to Mac.

2. Recommended: run the sync helper from the project root:

   ```bash
   scripts/sync-kindle-extension.sh
   ```

   If the detected IP is wrong, pass it explicitly:

   ```bash
   scripts/sync-kindle-extension.sh 192.168.1.23
   ```

   The helper copies the extension, updates `SERVER`, applies executable permissions, removes `._*` files, and runs `sync`.

3. Manual alternative: copy the extension template:

   ```bash
   cp -R kindle-extension/kindledashboard /Volumes/Kindle/extensions/
   ```

4. Edit:

   ```text
   /Volumes/Kindle/extensions/kindledashboard/bin/config.sh
   ```

5. Set:

   ```sh
   SERVER="http://<mac-ip>:8787"
   ```

6. Make scripts executable:

   ```bash
   chmod +x /Volumes/Kindle/extensions/kindledashboard/bin/*.sh
   ```

7. Clean macOS AppleDouble files if needed:

   ```bash
   find /Volumes/Kindle/extensions/kindledashboard -name '._*' -delete
   ```

8. Eject:

   ```bash
   diskutil eject /Volumes/Kindle
   ```

9. Open KUAL -> `KindleDashboard`.

## KUAL Actions

- `Show Once`: one delayed render.
- `Start Auto Refresh`: start the background loop.
- `Start Clean Dashboard`: start the background loop and keep Kindle's native `statusbar` stopped.
- `Stop Clean Dashboard`: stop the background loop and restore Kindle's native `statusbar`.
- `Stop Auto Refresh`: stop the background loop.
- `Battery Probe`: write `battery-probe.txt`.
- `UI Probe`: write `ui-probe.txt` for read-only kiosk-mode discovery.
- `Statusbar Pause Test`: stop `statusbar` for 20 seconds, render once, then restore it.
- `Restore Statusbar`: manually restore Kindle's native `statusbar`.
- `Charge Guard Test`: disable charging briefly, restore it, write `charge-guard-test.txt`.
- `Restore Charging`: force `allow_charging=1`, write `charge-restore.txt`.

## Daily Run

1. Start the Mac app.
2. On Kindle, run `Start Clean Dashboard` for the cleanest screen, or `Start Auto Refresh` if you want to keep Kindle's native statusbar.
3. Use the Mac menu bar to switch pages, refresh immediately, toggle frontlight, or toggle battery protection.

## Refresh Strategy

The Kindle loop uses an e-ink-friendly fixed strategy:

- Light render every 1 minute.
- Full render every 5 minutes.
- Page changes and Mac-triggered refreshes render immediately in light mode.

Light render avoids clearing the screen and does not request a full flash. Full render keeps the display clean by periodically clearing and refreshing the full frame.

The Kindle reports its own battery level back to the Mac through `/kindle/status`, so the rendered frame can show Kindle battery information in the lower-right footer.

## Battery Protection

Battery protection is controlled by the Mac app and executed by the Kindle background loop.

Default:

- Disabled.

When enabled:

- Battery >= 55%: write `allow_charging=0`.
- Battery <= 45%: write `allow_charging=1`.
- Disabled: force `allow_charging=1`.

Before relying on it on a new model, run:

1. `Battery Probe`
2. `Charge Guard Test`
3. `Restore Charging`

Then read the generated logs after reconnecting Kindle to Mac.

## Clean Dashboard / Kiosk-Like Mode

Clean Dashboard is the recommended daily mode for reducing native Kindle UI interference.

It starts the normal render loop and pauses Kindle's native `statusbar`, which prevents the system time/battery area from repainting over KindleDashboard's top bar.

Safe flow:

1. Start the Mac app.
2. Connect Kindle by USB if the extension is not installed yet.
3. Sync or resync the extension:

   ```bash
   scripts/sync-kindle-extension.sh
   ```

4. Eject Kindle.
5. On Kindle: `KUAL -> KindleDashboard -> Start Clean Dashboard`.
6. If you need to leave dashboard mode, use `Stop Clean Dashboard`.
7. If the statusbar does not restore, use:

   ```text
   Restore Statusbar
   ```

## Troubleshooting

### Menu Does Not Show

Check:

- `/mnt/us/extensions/kindledashboard/config.xml`
- `/mnt/us/extensions/kindledashboard/menu.json`
- No `._*` files under the extension directory.

### Fetch Failed

Check:

- Kindle Wi-Fi is on.
- Mac and Kindle are on the same network.
- `bin/config.sh` uses the Mac LAN IP, not `127.0.0.1`.
- Mac firewall allows port `8787`.

### Render Failed

Check:

- FBInk exists and is executable.
- `frame.png` works from another browser.
- `kindledashboard.log` under the extension directory.

### Charging Does Not Restore

Run:

```text
Restore Charging
```

Then reconnect Kindle and read:

```text
/Volumes/Kindle/extensions/kindledashboard/charge-restore.txt
```
