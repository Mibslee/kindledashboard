#!/bin/sh
SCRIPT_DIR="$(dirname "$0")"
. "$SCRIPT_DIR/config.sh"

KIOSK_FLAG="$EXT_DIR/kiosk-statusbar.enabled"
LOG="$EXT_DIR/kindledashboard.log"

rm -f "$KIOSK_FLAG"
"$EXT_DIR/bin/stop.sh" >> "$LOG" 2>&1 || true

{
  echo "stop clean dashboard $(date)"
  /sbin/start statusbar 2>&1 || true
  /sbin/status statusbar 2>&1 || true
} >> "$LOG" 2>&1

eips 2 2 "Clean Dashboard stopped" 2>/dev/null || true
exit 0
