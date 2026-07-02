# Changelog

## v0.2.1

### Added

- Documented the Mac menu-bar controller as a first-class product feature.
- Added stateful Mac menu labels and checkmarks for Kindle frontlight, battery protection, and auto rotation.

### Changed

- Clarified the user value of page switching, immediate refresh, frontlight control, battery protection, Markdown projection, image projection, and music controls.

## v0.2.0

This is the first public-ready release candidate for KindleDashboard.

### Added

- Mac menu-bar controller for switching Kindle pages, forcing refreshes, toggling backlight, and viewing extension status.
- Kindle KUAL extension with `Show Once`, auto refresh, clean dashboard mode, restore statusbar, status probes, and battery/charge guard helpers.
- Clean Dashboard mode that pauses the native Kindle status bar and renders the dashboard from the top edge without the earlier reserved blank strip.
- Layered refresh strategy: lightweight refresh every minute and full refresh every five minutes.
- Kindle battery reporting from the device back to the Mac service, rendered as a compact footer status.
- Pages for home, weather, calendar, music, Codex/workboard, focus, system state, screensaver, Markdown document projection, and image/screenshot projection.
- Public documentation for install, architecture, API, troubleshooting, privacy boundaries, battery protection, and release validation.

### Changed

- Reworked the e-ink UI around portrait-only information-card layouts with larger text, clearer hierarchy, and Chinese-first labels.
- Removed raw local URLs from the main dashboard because they do not help day-to-day usage.
- Replaced user-configurable frequent full refreshes with a safer default policy tuned for Paperwhite 3.
- Updated documentation to link to jailbreak references instead of redistributing jailbreak steps or tools.

### Fixed

- Avoided native Kindle time/battery overlays that caused white corner artifacts over the dark top bar.
- Fixed oversized or clipped music-card typography.
- Added ignore rules for runtime probe files, logs, generated frames, and local Kindle state so public commits stay clean.

## v0.1.0

- Prototype local web dashboard served from macOS and rendered to a Kindle through KUAL.
- Initial menu-bar controls, static dashboard pages, and PNG frame endpoint.
