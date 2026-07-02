# Kiosk Mode References

This note records external references that are useful for KindleDashboard's "Plan A": keep Kindle Linux and drivers, then make the dashboard behave like a dedicated appliance.

## What We Can Borrow

### FBInk

Reference:

- https://github.com/NiLuJe/FBInk

Why it matters:

- FBInk is the right abstraction level for KindleDashboard: draw directly to the e-ink framebuffer instead of depending on the Kindle browser.
- It already handles Kindle-class e-ink display details better than a generic image viewer or browser refresh.
- KindleDashboard should keep using PNG -> FBInk as the stable rendering path.

What not to assume:

- FBInk does not by itself suppress Kindle's native UI.
- It solves rendering, not kiosk lifecycle management.

### KOReader on Kindle

References:

- https://github.com/koreader/koreader
- https://github.com/koreader/koreader/wiki/Installation-on-Kindle-devices

Why it matters:

- KOReader is the strongest proof that a jailbreak-era Kindle can run a substantial userland app outside the normal reading flow.
- Its Kindle launcher ecosystem is a useful model for a reversible "enter app / exit app / restore normal Kindle UI" workflow.
- It suggests that KindleDashboard should treat kiosk mode as a session with a restore path, not as a permanent OS modification.

What not to assume:

- KOReader's service names and launcher scripts are not automatically correct for this PW3 firmware.
- We should not copy any stop/kill behavior until `UI Probe` identifies the real local service manager and restore command.

### KindleModding Post-Jailbreak Ecosystem

References:

- https://kindlemodding.org/jailbreaking/
- https://kindlemodding.org/jailbreaking/post-jailbreak/

Why it matters:

- KUAL-style extensions remain the safest user-facing entry point for this project.
- The docs give users a responsible upstream place to learn about jailbreak and post-jailbreak setup.
- KindleDashboard docs should continue to avoid bundling jailbreak tools or step-by-step jailbreak instructions.

What not to assume:

- A working jailbreak does not mean every low-level UI or battery interface exists on every Kindle model.

## Design Direction From These Cases

KindleDashboard should not try to replace the Kindle OS.

The viable high-control path is:

1. Keep Kindle Linux, Wi-Fi, power management, frontlight, USB storage, and e-ink drivers.
2. Keep KUAL as the manual recovery and launch surface.
3. Keep FBInk as the display renderer.
4. Add a reversible kiosk session only after the actual PW3 service topology is known.

## Tonight's Test Boundary

Tonight's connected-device work should stop at read-only discovery unless the probe gives a clear and reversible restore path.

Allowed:

- Sync the latest KUAL extension.
- Run `UI Probe`.
- Read `ui-probe.txt`.
- Identify candidate UI services and restore commands.
- Prepare a future short pause test.

Not allowed yet:

- Stopping framework/UI services.
- Killing broad process patterns.
- Adding boot autostart.
- Disabling native UI without a separate restore action.
