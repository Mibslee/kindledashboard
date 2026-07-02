#!/bin/sh
SCRIPT_DIR="$(dirname "$0")"
. "$SCRIPT_DIR/config.sh"

RENDER_MODE="${1:-full}"
OUT="$EXT_DIR/current.png"
LOG="$EXT_DIR/kindledashboard.log"
CONTROL_FILE="$EXT_DIR/control.json"
CHARGER_DIR="/sys/devices/system/wario_charger/wario_charger0"
BATTERY_DIR="/sys/devices/system/wario_battery/wario_battery0"
POWER_BATTERY="/sys/class/power_supply/max77696-battery"

read_capacity() {
  if [ -f "$BATTERY_DIR/battery_capacity" ]; then
    cat "$BATTERY_DIR/battery_capacity" 2>/dev/null
  elif [ -f "$POWER_BATTERY/capacity" ]; then
    cat "$POWER_BATTERY/capacity" 2>/dev/null
  else
    echo ""
  fi
}

read_charging() {
  if [ -f "$CHARGER_DIR/charging" ]; then
    cat "$CHARGER_DIR/charging" 2>/dev/null
  elif [ -f "$POWER_BATTERY/status" ]; then
    status="$(cat "$POWER_BATTERY/status" 2>/dev/null)"
    [ "$status" = "Charging" ] && echo "1" || echo "0"
  else
    echo ""
  fi
}

report_kindle_status() {
  capacity="$(read_capacity)"
  charging="$(read_charging)"
  case "$capacity" in
    ''|*[!0-9]*) return 0 ;;
  esac
  [ -z "$charging" ] && charging=0
  wget -q -O /dev/null "$SERVER/kindle/status?battery=$capacity&charging=$charging" 2>/dev/null || true
}

mkdir -p "$EXT_DIR"
lipc-set-prop com.lab126.powerd preventScreenSaver 1 2>/dev/null || true

case "$SERVER" in
  *KINDLE_DASHBOARD_MAC_IP*)
    echo "server not configured: run scripts/sync-kindle-extension.sh <mac-ip>" >> "$LOG"
    eips 2 2 "KindleDashboard needs Mac IP"
    exit 4
    ;;
esac

if wget -q -O "$CONTROL_FILE.tmp" "$SERVER/control.json"; then
  mv "$CONTROL_FILE.tmp" "$CONTROL_FILE"
  frontlight="$(sed -n 's/.*"frontlightEnabled":\(true\|false\).*/\1/p' "$CONTROL_FILE")"
  level="$(sed -n 's/.*"frontlightLevel":\([0-9][0-9]*\).*/\1/p' "$CONTROL_FILE")"
  [ -z "$level" ] && level=10
  if [ "$frontlight" = "true" ]; then
    lipc-set-prop com.lab126.powerd flIntensity "$level" 2>/dev/null || true
  elif [ "$frontlight" = "false" ]; then
    lipc-set-prop com.lab126.powerd flIntensity 0 2>/dev/null || true
  fi
else
  rm -f "$CONTROL_FILE.tmp"
fi
report_kindle_status

echo "render_once $RENDER_MODE $(date): fetching $SERVER/frame.png" >> "$LOG"
wget -q -O "$OUT" "$SERVER/frame.png" || {
  echo "fetch failed" >> "$LOG"
  eips 2 2 "KindleDashboard fetch failed"
  exit 1
}

if [ -x "$FBINK" ]; then
  if [ "$RENDER_MODE" = "light" ]; then
    "$FBINK" -a -g "file=$OUT" >> "$LOG" 2>&1 || {
      echo "fbink light failed" >> "$LOG"
      eips 2 2 "KindleDashboard render failed"
      exit 2
    }
  else
    eips -c 2>/dev/null || true
    sleep 1
    "$FBINK" -c -f -a -g "file=$OUT" >> "$LOG" 2>&1 || {
      echo "fbink full failed" >> "$LOG"
      eips 2 2 "KindleDashboard render failed"
      exit 2
    }
    sleep 2
    "$FBINK" -c -f -a -g "file=$OUT" >> "$LOG" 2>&1 || {
      echo "fbink full second pass failed" >> "$LOG"
      exit 2
    }
  fi
else
  echo "fbink missing: $FBINK" >> "$LOG"
  eips 2 2 "FBInk not found"
  exit 3
fi

echo "render_once done" >> "$LOG"
