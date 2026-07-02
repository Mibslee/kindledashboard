# Contributing

KindleDashboard is still a small hardware-adjacent project, so useful contributions are usually concrete and testable:

- Kindle model compatibility reports with firmware version, jailbreak environment, KUAL version, and screenshots.
- UI fixes that improve readability on a real e-ink panel, not only on a Retina display.
- Safer install scripts, diagnostics, and recovery paths.
- New dashboard cards that are useful at a glance and do not require tiny text.
- Documentation improvements that help another person reproduce the setup without private context.

## Local Development

```bash
swift build
swift run KindleDashboard
```

Then open:

```text
http://127.0.0.1:8787/
http://127.0.0.1:8787/frame.png
```

## Before Opening a PR

Run:

```bash
swift build
```

Check that generated files are not staged:

```bash
git status --short
```

Do not commit:

- `.build/`
- `.DS_Store`
- Kindle runtime logs, PID files, generated PNG/SVG frames, or probe files
- Private IP addresses, local user paths, tokens, screenshots containing personal content

## Documentation Rule

This repository documents how KindleDashboard works after a Kindle is already in a user-controlled, post-jailbreak state. It does not redistribute jailbreak tools or provide step-by-step jailbreak instructions. Link to the upstream references instead.
