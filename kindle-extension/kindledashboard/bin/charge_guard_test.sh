#!/bin/sh
EXT_DIR="/mnt/us/extensions/kindledashboard"
OUT="$EXT_DIR/charge-guard-test.txt"
CHARGER_DIR="/sys/devices/system/wario_charger/wario_charger0"
BATTERY_DIR="/sys/devices/system/wario_battery/wario_battery0"
POWER_BATTERY="/sys/class/power_supply/max77696-battery"
POWER_CHARGER="/sys/class/power_supply/max77696-charger"

restore_charging() {
  if [ -w "$CHARGER_DIR/allow_charging" ]; then
    echo 1 > "$CHARGER_DIR/allow_charging" 2>/dev/null || true
  fi
}

trap restore_charging EXIT HUP INT TERM

read_file() {
  file="$1"
  if [ -f "$file" ]; then
    cat "$file" 2>&1
  else
    echo "missing"
  fi
}

snapshot() {
  label="$1"
  echo "== $label =="
  echo "time: $(date)"
  echo "allow_charging: $(read_file "$CHARGER_DIR/allow_charging")"
  echo "charging: $(read_file "$CHARGER_DIR/charging")"
  echo "battery_capacity: $(read_file "$BATTERY_DIR/battery_capacity")"
  echo "battery_current: $(read_file "$BATTERY_DIR/battery_current")"
  echo "battery_voltage: $(read_file "$BATTERY_DIR/battery_voltage")"
  echo "power_status: $(read_file "$POWER_BATTERY/status")"
  echo "power_capacity: $(read_file "$POWER_BATTERY/capacity")"
  echo "power_current_now: $(read_file "$POWER_BATTERY/current_now")"
  echo "charger_online: $(read_file "$POWER_CHARGER/online")"
  echo
}

mkdir -p "$EXT_DIR"
{
  echo "KindleDashboard charge guard test"
  echo "This test temporarily disables charging for 3 seconds, then restores it."
  echo

  if [ ! -w "$CHARGER_DIR/allow_charging" ]; then
    echo "ERROR: $CHARGER_DIR/allow_charging is not writable."
    snapshot "not writable"
    exit 1
  fi

  snapshot "before"
  echo "writing allow_charging=0"
  echo 0 > "$CHARGER_DIR/allow_charging" 2>&1
  sync
  sleep 3
  snapshot "after disable 3s"

  echo "writing allow_charging=1"
  echo 1 > "$CHARGER_DIR/allow_charging" 2>&1
  sync
  sleep 3
  snapshot "after restore 3s"
  echo "result: done"
} > "$OUT" 2>&1

restore_charging
eips 2 2 "Charge test saved"
exit 0
