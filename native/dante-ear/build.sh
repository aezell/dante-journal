#!/bin/sh
# Builds dante-ear with the Swift toolchain from the Command Line Tools; no
# Xcode project needed. Output: priv/bin/dante-ear
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
mkdir -p "$root/priv/bin"
swiftc -O -swift-version 5 -target arm64-apple-macos26.0 \
  -framework AVFoundation -framework Speech -framework CoreGraphics \
  -o "$root/priv/bin/dante-ear" "$here/main.swift"
echo "built $root/priv/bin/dante-ear"
