# Kiosk Mode Research

This document tracks the safer "Plan A" direction: keep Kindle Linux, Wi-Fi, power management, frontlight, touch, and e-ink drivers, but suppress or bypass the stock Kindle UI enough for KindleDashboard to behave like a dedicated e-ink appliance.

It is not a replacement-OS plan and not a bare-panel hardware plan.

External references and comparable projects are tracked in [kiosk-mode-cases.md](kiosk-mode-cases.md).

## Goal

Make a Kindle behave like a dedicated KindleDashboard screen:

- No browser chrome.
- No stock home screen interference.
- No native status bar partial refresh damaging the dashboard top edge.
- Mac remains the control surface.
- Kindle keeps Wi-Fi, FBInk rendering, frontlight control, battery protection, and safe recovery.

## Non-goals

- Replacing the Kindle operating system.
- Modifying boot partitions.
- Disabling recovery paths.
- Auto-starting kiosk mode before a safe manual restore path is verified.
- Publishing generic instructions for stopping unknown Kindle services across all models.

## Why This Is Better Than Replacing the OS

Kindle Linux already provides the hard parts:

- E-ink framebuffer and waveform handling.
- Wi-Fi and power management.
- Frontlight controls.
- Battery and charger interfaces.
- Touch and button input plumbing.
- USB storage and recovery entry points.

The stock reader UI is the problem, not the whole operating system. Kiosk mode should remove the UI interference while preserving the platform services that make the device useful.

## Current Known Interference

Observed on the Paperwhite 3:

- The native top time/battery status area can partially refresh independently.
- If KindleDashboard draws dark UI under that area, the corners can turn white after time or battery updates.
- v0.2 works around this with a white top safe area.

Kiosk mode may allow us to reclaim that top area, but only if the service responsible for native status refresh can be paused safely.

## Stage 0: Read-only Discovery

Use KUAL:

```text
KindleDashboard -> UI Probe
```

This writes:

```text
/mnt/us/extensions/kindledashboard/ui-probe.txt
```

The probe collects:

- Process snapshot.
- Likely UI processes.
- `initctl` / upstart availability.
- Upstart and init script definitions.
- LIPC publishers and likely UI-related services.
- Framebuffer and e-ink device nodes.
- FBInk version and availability.
- Display/power-related sysfs candidates.

The probe must remain read-only.

## Questions To Answer From UI Probe

1. Which process owns the stock UI?
2. Is the UI process managed by `initctl`, an init script, or a watchdog?
3. Does stopping the UI also stop Wi-Fi, powerd, lipc, frontlight, or battery interfaces?
4. Is there a documented or discoverable `start` command to restore the UI?
5. Does FBInk continue to work after the UI process is paused?
6. Does KUAL remain reachable, or do we need an independent restore trigger?
7. Does the native top status refresh stop after the UI process is paused?

## Stage 1: Short Manual Pause Test

Only after Stage 0 identifies candidate services and a restore command.

For the tested PW3 probe, the first candidate is `statusbar`, because it is a separate Upstart job and appears responsible for the native top chrome. This is safer than stopping `framework`, `lab126_gui`, `x`, or `kppmainapp`.

The test should:

1. Start KindleDashboard auto refresh.
2. Render a known frame.
3. Pause `statusbar` for a short fixed window.
4. Render another frame through FBInk.
5. Restore `statusbar`.
6. Write a log with before/after service state.

Rules:

- Always use a `trap` or equivalent restore path.
- Never kill broad process patterns.
- Never stop `powerd`, Wi-Fi, USB, or charger services.
- Never enable at boot during Stage 1.
- Keep `Restore Kindle UI` as a separate KUAL entry before testing.

Current KUAL entries for Stage 1:

- `Statusbar Pause Test`: stops `statusbar`, renders once, waits 20 seconds, then starts `statusbar`.
- `Restore Statusbar`: manually starts `statusbar` if needed.

Expected log:

```text
/mnt/us/extensions/kindledashboard/statusbar-pause-test.txt
```

## Stage 2: Kiosk Session

Only after Stage 1 proves restore works.

KUAL entries:

- `Start Kiosk`
- `Stop Kiosk`
- `Restore Kindle UI`
- `Safe Reboot`

Expected behavior:

- Pause stock UI.
- Start KindleDashboard auto refresh.
- Keep screen saver prevention enabled.
- Keep battery protection and frontlight controls active.
- Restore stock UI when stopped.

## Stage 3: Optional Auto-start

Only after repeated manual sessions are stable.

Auto-start should:

- Delay for at least 30-60 seconds after boot.
- Require a local config flag.
- Provide a physical or KUAL-accessible escape hatch.
- Never start if a sentinel file like `/mnt/us/DISABLE_KINDLEDASHBOARD_KIOSK` exists.

## Failure Modes

- Stock UI restarts automatically and overlays KindleDashboard.
- KUAL disappears after UI pause.
- Wi-Fi drops after UI pause.
- FBInk fails because another display service owns the framebuffer.
- Screen saver/power state resumes and blanks the screen.
- A bad auto-start loop makes the Kindle hard to use.

## Current Recommendation

Do not replace Kindle OS.

Proceed with:

1. `UI Probe`.
2. Analyze `ui-probe.txt`.
3. Build a model-specific, short-duration pause test.
4. Only then consider `Start Kiosk`.

The v0.2 top safe area remains the default stable path until kiosk mode is proven safe on the actual PW3.

## Tonight Preparation Checklist

Before connecting the Kindle:

1. Keep the Mac app buildable.
2. Keep the KUAL extension template current.
3. Use `scripts/sync-kindle-extension.sh` to sync the extension and write the Mac LAN IP.
4. Run only `UI Probe` on device.
5. Reconnect Kindle and inspect `ui-probe.txt`.

Do not add or test any script that stops the native UI until the probe shows a model-specific service name and a safe restore command.
