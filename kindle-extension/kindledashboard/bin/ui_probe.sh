#!/bin/sh
EXT_DIR="/mnt/us/extensions/kindledashboard"
OUT="$EXT_DIR/ui-probe.txt"

mkdir -p "$EXT_DIR"
{
  echo "KindleDashboard UI probe"
  echo "time: $(date)"
  echo

  echo "== uname =="
  uname -a 2>&1
  echo

  echo "== process snapshot =="
  ps ww 2>&1
  echo

  echo "== likely UI processes =="
  ps ww 2>&1 | grep -Ei 'KPP|MainApp|framework|pillow|appmgr|lipc|window|blanket|booklet|reader|home|browser|xorg|awesome|matchbox|eips|fbink' | grep -v grep
  echo

  echo "== init/upstart commands =="
  command -v initctl 2>&1
  command -v start 2>&1
  command -v stop 2>&1
  command -v status 2>&1
  echo

  echo "== initctl list =="
  if command -v initctl >/dev/null 2>&1; then
    initctl list 2>&1
  else
    echo "initctl not found"
  fi
  echo

  echo "== upstart configs =="
  for dir in /etc/upstart /etc/init /etc/event.d; do
    if [ -d "$dir" ]; then
      echo "-- $dir --"
      ls -la "$dir" 2>&1
      echo
      find "$dir" -maxdepth 1 -type f 2>/dev/null | sort | while read file; do
        echo "---- $file ----"
        sed -n '1,80p' "$file" 2>&1
      done
    fi
  done
  echo

  echo "== init scripts =="
  if [ -d /etc/init.d ]; then
    ls -la /etc/init.d 2>&1
  else
    echo "/etc/init.d missing"
  fi
  echo

  echo "== lipc publishers =="
  if command -v lipc-probe >/dev/null 2>&1; then
    lipc-probe -a 2>&1
  elif command -v lipc-probe-list >/dev/null 2>&1; then
    lipc-probe-list 2>&1
  else
    echo "lipc probe command not found"
  fi
  echo

  echo "== lipc com.lab126 candidates =="
  for publisher in \
    com.lab126.appmgrd \
    com.lab126.powerd \
    com.lab126.blanket \
    com.lab126.pillow \
    com.lab126.kaf \
    com.lab126.winmgr \
    com.lab126.system; do
    echo "-- $publisher --"
    if command -v lipc-probe >/dev/null 2>&1; then
      lipc-probe "$publisher" 2>&1
    else
      echo "lipc-probe unavailable"
    fi
  done
  echo

  echo "== framebuffer and eink devices =="
  ls -la /dev/fb* /dev/mxc* /dev/graphics* /proc/eink_fb 2>&1
  echo

  echo "== fbink =="
  ls -la /mnt/us/libkh/bin/fbink 2>&1
  /mnt/us/libkh/bin/fbink --version 2>&1
  echo

  echo "== display/power related sysfs =="
  find /sys -maxdepth 5 \( -iname '*eink*' -o -iname '*fb*' -o -iname '*display*' -o -iname '*blank*' -o -iname '*power*' \) 2>/dev/null | sort | sed -n '1,200p'
} > "$OUT" 2>&1

eips 2 2 "UI probe saved"
exit 0
