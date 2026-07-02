#!/bin/sh
EXT_DIR="/mnt/us/extensions/kindledashboard"
OUT="$EXT_DIR/charge-restore.txt"
CHARGER_DIR="/sys/devices/system/wario_charger/wario_charger0"

mkdir -p "$EXT_DIR"
{
  echo "KindleDashboard charge restore"
  echo "time: $(date)"
  if [ -w "$CHARGER_DIR/allow_charging" ]; then
    echo 1 > "$CHARGER_DIR/allow_charging"
    sleep 2
    echo "allow_charging: $(cat "$CHARGER_DIR/allow_charging" 2>&1)"
    echo "charging: $(cat "$CHARGER_DIR/charging" 2>&1)"
    echo "result: restored"
  else
    echo "ERROR: allow_charging is not writable"
  fi
} > "$OUT" 2>&1

eips 2 2 "Charging restored"
exit 0
