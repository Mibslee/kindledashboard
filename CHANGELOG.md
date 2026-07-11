# Changelog

## v0.3.0

### Added

- Added data-driven black-and-white weather icons for clear, cloudy, fog, wind, snow, thunder, and light/moderate/heavy rain states.
- Added precipitation intensity and the highest-value rain window to the weather and overview pages.
- Added `--dump-preview <mode>` for generating privacy-safe public screenshots from fixed sample data.

### Changed

- Rebuilt the overview around three decisions: weather risk, current Codex work with quota, and Mac health.
- Replaced the generic hourly weather list with an icon-led timeline that keeps time, condition, temperature, and rain probability aligned.
- Improved music, calendar, and focus empty/supporting states so unused space communicates a clear next action.
- Tightened CJK line wrapping to prevent long tasks from crossing the right edge.

### Fixed

- Avoided SVG transforms in weather artwork so the production `sips` PNG path remains compatible with the Kindle renderer.
- Prevented repository preview generation from accidentally capturing live Codex tasks or local system data.

## v0.2.2

### Added

- Added richer weather cards with current conditions, the next few hourly forecast rows, precipitation probability, and short action advice.
- Added Codex workboard status using the current task, local rate-limit snapshots, reset times, and fallback aggregate usage when service-side quota data is not available.
- Added configurable light/full refresh intervals in the Mac menu and passed those settings to the Kindle extension.
- Added `--dump-mode <mode>` for exporting any dashboard page as SVG during QA.

### Changed

- Reworked all main dashboard pages around clearer “what should I know / what should I do next” information hierarchy.
- Improved home, document, image, music, calendar, focus, and system pages with more useful labels, larger primary information, and fewer placeholder-style rows.
- Changed page switching on Kindle to trigger a light refresh instead of forcing repeated full refreshes.
- Kept full refreshes on a separate cadence so long-running desk use has less flashing while still cleaning ghosting periodically.

### Fixed

- Fixed stale placeholder copy such as “用途”, “后续接入”, and English fallback rows in public-facing screens.
- Fixed calendar empty-state advice so “暂无日程” no longer suggests preparing for a nonexistent event.
- Fixed long music titles and Mac status strings competing with the primary content area.

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
