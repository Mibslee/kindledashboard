#!/bin/sh
EXT_DIR="/mnt/us/extensions/kindledashboard"
PID_FILE="$EXT_DIR/kindledashboard.pid"
CHARGER_DIR="/sys/devices/system/wario_charger/wario_charger0"

if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
  kill "$(cat "$PID_FILE")" 2>/dev/null || true
  rm -f "$PID_FILE"
  eips 2 2 "KindleDashboard stopped"
else
  eips 2 2 "KindleDashboard not running"
fi

if [ -w "$CHARGER_DIR/allow_charging" ]; then
  echo 1 > "$CHARGER_DIR/allow_charging" 2>/dev/null || true
fi
