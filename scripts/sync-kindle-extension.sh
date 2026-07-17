#!/bin/sh
set -eu

ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)"
SRC="$ROOT/kindle-extension/kindledashboard"
KINDLE_ROOT="${KINDLE_ROOT:-/Volumes/Kindle}"
DST="$KINDLE_ROOT/extensions/kindledashboard"
MAC_IP="${1:-}"

if [ ! -d "$SRC" ]; then
  echo "Extension template not found: $SRC" >&2
  exit 1
fi

if [ ! -d "$KINDLE_ROOT" ]; then
  echo "Kindle volume not found: $KINDLE_ROOT" >&2
  echo "Connect Kindle by USB first, then run this script again." >&2
  exit 1
fi

if [ -z "$MAC_IP" ]; then
  MAC_IP="$(ipconfig getifaddr en0 2>/dev/null || true)"
fi

if [ -z "$MAC_IP" ]; then
  MAC_IP="$(ipconfig getifaddr en1 2>/dev/null || true)"
fi

if [ -z "$MAC_IP" ]; then
  echo "Could not detect Mac LAN IP." >&2
  echo "Usage: scripts/sync-kindle-extension.sh 192.168.1.23" >&2
  exit 1
fi

mkdir -p "$KINDLE_ROOT/extensions"
mkdir -p "$DST"
cp -R "$SRC/." "$DST/"

CONFIG="$DST/bin/config.sh"
TMP_CONFIG="$CONFIG.tmp"
awk -v server="http://$MAC_IP:8787" '
  /^SERVER=/ {
    print "SERVER=\"" server "\""
    next
  }
  { print }
' "$CONFIG" > "$TMP_CONFIG"
mv "$TMP_CONFIG" "$CONFIG"

chmod +x "$DST"/bin/*.sh
find "$DST" -name '._*' -delete 2>/dev/null || true
sync

cat <<EOF
KindleDashboard extension synced.

Kindle volume: $KINDLE_ROOT
Server: http://$MAC_IP:8787
Extension: $DST

Next:
1. Make sure KindleDashboard.app is running (./start.sh also opens the installed app)
2. Eject Kindle: diskutil eject $KINDLE_ROOT
3. On Kindle: KUAL -> KindleDashboard -> UI Probe
4. Reconnect Kindle and read:
   $DST/ui-probe.txt
EOF
