#!/bin/sh
# Rebuilds macos/AppIcon.icns. Needs only the Command Line Tools (swift, iconutil).
set -eu
here=$(cd "$(dirname "$0")" && pwd)
swift "$here/make_icon.swift" "$here" >/dev/null
iconutil -c icns "$here/AppIcon.iconset" -o "$here/AppIcon.icns"
rm -rf "$here/AppIcon.iconset"
echo "$here/AppIcon.icns"
