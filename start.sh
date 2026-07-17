#!/bin/sh
cd "$(dirname "$0")"
if [ -d "/Applications/KindleDashboard.app" ]; then
  exec open "/Applications/KindleDashboard.app"
fi
if [ -x ".build/debug/KindleDashboard" ]; then
  exec ".build/debug/KindleDashboard"
fi
exec swift run KindleDashboard
