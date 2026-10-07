#!/usr/bin/env bash
# Builds "build/Agent Sessions.app". With --install it is copied to /Applications.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP="build/Agent Sessions.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/AgentSessions "$APP/Contents/MacOS/AgentSessions"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP" >/dev/null

echo "Gebaut: $APP"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x AgentSessions 2>/dev/null || true
    rm -rf "/Applications/Agent Sessions.app"
    cp -R "$APP" /Applications/
    echo "Installiert: /Applications/Agent Sessions.app"
    open "/Applications/Agent Sessions.app"
fi
