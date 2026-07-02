#!/bin/sh
SCRIPT_DIR="$(dirname "$0")"
. "$SCRIPT_DIR/config.sh"

KIOSK_FLAG="$EXT_DIR/kiosk-statusbar.enabled"
LOG="$EXT_DIR/kindledashboard.log"

mkdir -p "$EXT_DIR"
touch "$KIOSK_FLAG"

{
  echo "start clean dashboard $(date)"
  /sbin/stop statusbar 2>&1 || true
  /sbin/status statusbar 2>&1 || true
} >> "$LOG" 2>&1

"$EXT_DIR/bin/start.sh" >> "$LOG" 2>&1 || true
eips 2 2 "Clean Dashboard started" 2>/dev/null || true
exit 0
