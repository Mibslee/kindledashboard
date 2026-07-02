#!/bin/sh
cd "$(dirname "$0")"
if [ -x ".build/debug/KindleDashboard" ]; then
  exec ".build/debug/KindleDashboard"
fi
exec swift run KindleDashboard
