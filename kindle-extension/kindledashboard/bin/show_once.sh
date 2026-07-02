#!/bin/sh
EXT_DIR="/mnt/us/extensions/kindledashboard"
LOG="$EXT_DIR/kindledashboard.log"

mkdir -p "$EXT_DIR"
echo "show_once $(date): render scheduled after desktop settles" >> "$LOG"
( sleep 8; "$EXT_DIR/bin/render_once.sh" >> "$LOG" 2>&1 ) &
eips 2 2 "KindleDashboard rendering..."
exit 0
