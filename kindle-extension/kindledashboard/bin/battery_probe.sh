#!/bin/sh
EXT_DIR="/mnt/us/extensions/kindledashboard"
OUT="$EXT_DIR/battery-probe.txt"

mkdir -p "$EXT_DIR"
{
  echo "KindleDashboard battery probe"
  echo "time: $(date)"
  echo
  echo "== uname =="
  uname -a 2>&1
  echo
  echo "== power supplies =="
  ls -la /sys/class/power_supply 2>&1
  echo
  for dir in /sys/class/power_supply/*; do
    [ -d "$dir" ] || continue
    echo "== $dir =="
    for file in "$dir"/*; do
      [ -f "$file" ] || continue
      name="$(basename "$file")"
      case "$name" in
        uevent|type|status|capacity|voltage_now|current_now|charge_now|charge_full|charge_full_design|online|present|health|temp|charging_enabled|charge_control_start_threshold|charge_control_end_threshold)
          printf "%s: " "$name"
          cat "$file" 2>&1
          ;;
      esac
    done
    echo
  done
  echo "== writable-looking charge controls =="
  find /sys -type f \( -name '*charg*' -o -name '*threshold*' -o -name '*batt*' -o -name '*usb*' \) 2>/dev/null | sort | while read file; do
    [ -w "$file" ] && echo "$file"
  done
} > "$OUT"

eips 2 2 "Battery probe saved"
exit 0
