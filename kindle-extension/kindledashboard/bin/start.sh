#!/bin/sh
SCRIPT_DIR="$(dirname "$0")"
. "$SCRIPT_DIR/config.sh"

PID_FILE="$EXT_DIR/kindledashboard.pid"
LOG_FILE="$EXT_DIR/kindledashboard.log"
CONTROL_FILE="$EXT_DIR/control.json"
KIOSK_FLAG="$EXT_DIR/kiosk-statusbar.enabled"
CHARGER_DIR="/sys/devices/system/wario_charger/wario_charger0"
BATTERY_DIR="/sys/devices/system/wario_battery/wario_battery0"
POWER_BATTERY="/sys/class/power_supply/max77696-battery"
LIGHT_RENDER_INTERVAL=60
FULL_RENDER_INTERVAL=300

read_capacity() {
  if [ -f "$BATTERY_DIR/battery_capacity" ]; then
    cat "$BATTERY_DIR/battery_capacity" 2>/dev/null
  elif [ -f "$POWER_BATTERY/capacity" ]; then
    cat "$POWER_BATTERY/capacity" 2>/dev/null
  else
    echo ""
  fi
}

apply_charge_guard() {
  enabled="$1"
  lower="$2"
  upper="$3"
  [ -z "$lower" ] && lower=45
  [ -z "$upper" ] && upper=55
  [ -w "$CHARGER_DIR/allow_charging" ] || return 0

  if [ "$enabled" != "true" ]; then
    current_allow="$(cat "$CHARGER_DIR/allow_charging" 2>/dev/null)"
    if [ "$current_allow" != "1" ]; then
      echo 1 > "$CHARGER_DIR/allow_charging" 2>/dev/null || true
      echo "charge guard disabled: allow_charging=1 $(date)" >> "$LOG_FILE"
    fi
    return 0
  fi

  capacity="$(read_capacity)"
  case "$capacity" in
    ''|*[!0-9]*) return 0 ;;
  esac

  current_allow="$(cat "$CHARGER_DIR/allow_charging" 2>/dev/null)"
  if [ "$capacity" -ge "$upper" ] && [ "$current_allow" != "0" ]; then
    echo 0 > "$CHARGER_DIR/allow_charging" 2>/dev/null || true
    echo "charge guard: capacity=${capacity}, allow_charging=0 $(date)" >> "$LOG_FILE"
  elif [ "$capacity" -le "$lower" ] && [ "$current_allow" != "1" ]; then
    echo 1 > "$CHARGER_DIR/allow_charging" 2>/dev/null || true
    echo "charge guard: capacity=${capacity}, allow_charging=1 $(date)" >> "$LOG_FILE"
  fi
}

apply_statusbar_guard() {
  [ -f "$KIOSK_FLAG" ] || return 0
  status="$(/sbin/status statusbar 2>/dev/null || true)"
  case "$status" in
    *"start/running"*)
      /sbin/stop statusbar >> "$LOG_FILE" 2>&1 || true
      echo "kiosk guard: stopped statusbar $(date)" >> "$LOG_FILE"
      ;;
  esac
}

mkdir -p "$EXT_DIR"
if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
  eips 2 2 "KindleDashboard already running"
  exit 0
fi

(
  sleep 8
  last_serial=""
  last_light_render=0
  last_full_render=0
  while :; do
    now="$(date +%s)"
    serial=""

    if wget -q -O "$CONTROL_FILE.tmp" "$SERVER/control.json"; then
      mv "$CONTROL_FILE.tmp" "$CONTROL_FILE"
      serial="$(sed -n 's/.*"refreshSerial":\([0-9][0-9]*\).*/\1/p' "$CONTROL_FILE")"
      frontlight="$(sed -n 's/.*"frontlightEnabled":\(true\|false\).*/\1/p' "$CONTROL_FILE")"
      level="$(sed -n 's/.*"frontlightLevel":\([0-9][0-9]*\).*/\1/p' "$CONTROL_FILE")"
      battery_protection="$(sed -n 's/.*"batteryProtectionEnabled":\(true\|false\).*/\1/p' "$CONTROL_FILE")"
      battery_lower="$(sed -n 's/.*"batteryLowerLimit":\([0-9][0-9]*\).*/\1/p' "$CONTROL_FILE")"
      battery_upper="$(sed -n 's/.*"batteryUpperLimit":\([0-9][0-9]*\).*/\1/p' "$CONTROL_FILE")"
      [ -z "$level" ] && level=10

      if [ "$frontlight" = "true" ]; then
        lipc-set-prop com.lab126.powerd flIntensity "$level" 2>/dev/null || true
      elif [ "$frontlight" = "false" ]; then
        lipc-set-prop com.lab126.powerd flIntensity 0 2>/dev/null || true
      fi
      apply_charge_guard "$battery_protection" "$battery_lower" "$battery_upper"
    else
      rm -f "$CONTROL_FILE.tmp"
      echo "control fetch failed $(date)" >> "$LOG_FILE"
    fi
    apply_statusbar_guard

    full_elapsed=$((now - last_full_render))
    light_elapsed=$((now - last_light_render))
    if [ "$last_full_render" -eq 0 ] || [ "$full_elapsed" -ge "$FULL_RENDER_INTERVAL" ]; then
      "$EXT_DIR/bin/render_once.sh" full >> "$LOG_FILE" 2>&1
      last_serial="$serial"
      last_full_render="$(date +%s)"
      last_light_render="$last_full_render"
    elif [ -z "$last_serial" ] || [ "$serial" != "$last_serial" ] || [ "$light_elapsed" -ge "$LIGHT_RENDER_INTERVAL" ]; then
      "$EXT_DIR/bin/render_once.sh" light >> "$LOG_FILE" 2>&1
      last_serial="$serial"
      last_light_render="$(date +%s)"
    fi
    sleep 2
  done
) &
echo $! > "$PID_FILE"
eips 2 2 "KindleDashboard started"
