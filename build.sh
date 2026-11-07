#!/bin/sh
set -eu
cd "$(dirname "$0")"
app=/Applications/GryphonLocker.app
mkdir -p "$app/Contents/MacOS"
cp Info.plist "$app/Contents/"
swiftc -O -swift-version 5 Sources/main.swift -o "$app/Contents/MacOS/GryphonLocker"
codesign --force --sign - "$app"
echo "$app"
