# Design Principles

KindleDashboard is a status board, not a tiny web app.

## First Principles

- The Kindle is glanceable. Every page must answer one question within two seconds.
- E-ink favors bold hierarchy, stable geometry, and low refresh noise.
- The Mac controls configuration. The Kindle should mostly display, not require touch.
- Each module must justify itself by user benefit, not by available data.

## Page Purpose

- 首页: decide what to look at first today.
- Codex: know current agent work and next local action.
- 文档: keep a procedure, checklist, or reference note visible while operating on the Mac.
- 音乐: see and lightly control playback.
- 天气: decide clothing, windows, and commute.
- 日历: avoid missing the next commitment.
- 专注: keep one time block visible.
- 系统: spot resource pressure without opening Activity Monitor.
- 屏保: show time quietly when idle.

## Layout Rules

- Portrait only for now.
- Large main surface at the top, compact Dock at the bottom.
- No repeated information unless the repeated version has a different use.
- No raw API strings in primary visual areas.
- The Dock is status/navigation, not decoration.
- The document page must preserve scan rhythm: headings, steps, and checkbox states should remain obvious from arm's length.
