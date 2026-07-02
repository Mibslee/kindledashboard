#!/bin/sh
SCRIPT_DIR="$(dirname "$0")"
. "$SCRIPT_DIR/config.sh"

OUT="$EXT_DIR/statusbar-restore.txt"
KIOSK_FLAG="$EXT_DIR/kiosk-statusbar.enabled"

mkdir -p "$EXT_DIR"
rm -f "$KIOSK_FLAG"
{
  echo "KindleDashboard restore statusbar"
  echo "time: $(date)"
  echo
  /sbin/start statusbar 2>&1 || true
  /sbin/status statusbar 2>&1 || true
} > "$OUT" 2>&1

eips 2 2 "Statusbar restored" 2>/dev/null || true
exit 0
