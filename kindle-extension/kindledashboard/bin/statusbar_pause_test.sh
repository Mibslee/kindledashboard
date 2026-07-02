#!/bin/sh
SCRIPT_DIR="$(dirname "$0")"
. "$SCRIPT_DIR/config.sh"

OUT="$EXT_DIR/statusbar-pause-test.txt"
LOG="$EXT_DIR/kindledashboard.log"
TEST_SECONDS=20

status_job() {
  /sbin/status "$1" 2>&1 || true
}

restore_statusbar() {
  {
    echo
    echo "== restore statusbar =="
    /sbin/start statusbar 2>&1 || true
    status_job statusbar
    echo "restore time: $(date)"
  } >> "$OUT" 2>&1
  eips 2 2 "Statusbar restored" 2>/dev/null || true
}

mkdir -p "$EXT_DIR"

{
  echo "KindleDashboard statusbar pause test"
  echo "time: $(date)"
  echo "duration: ${TEST_SECONDS}s"
  echo
  echo "== before =="
  for job in statusbar framework kppmainapp lab126_gui x pillow powerd wifid wifis; do
    echo "-- $job --"
    status_job "$job"
  done
} > "$OUT" 2>&1

trap restore_statusbar EXIT INT TERM

{
  echo
  echo "== stop statusbar =="
  /sbin/stop statusbar 2>&1 || true
  sleep 2
  status_job statusbar
} >> "$OUT" 2>&1

eips 2 2 "Statusbar paused" 2>/dev/null || true

if [ -x "$EXT_DIR/bin/render_once.sh" ]; then
  echo "statusbar pause test render $(date)" >> "$LOG"
  "$EXT_DIR/bin/render_once.sh" >> "$LOG" 2>&1 || true
fi

sleep "$TEST_SECONDS"
trap - EXIT INT TERM
restore_statusbar

{
  echo
  echo "== after =="
  for job in statusbar framework kppmainapp lab126_gui x pillow powerd wifid wifis; do
    echo "-- $job --"
    status_job "$job"
  done
} >> "$OUT" 2>&1

exit 0
