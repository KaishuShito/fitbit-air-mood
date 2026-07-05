#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_DIR="$APP_DIR/dist"
APP_NAME="FitbitAirMoodBar"
DIST_BUNDLE="$DIST_DIR/${APP_NAME}.app"
INSTALL_APP_NAME="Fitbit Air Mood"
TARGET_ROOT="${FITBIT_AIR_MOODBAR_INSTALL_DIR:-/Applications}"
if [[ ! -w "$TARGET_ROOT" ]]; then
  TARGET_ROOT="$HOME/Applications"
fi
TARGET_BUNDLE="$TARGET_ROOT/${INSTALL_APP_NAME}.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

FITBIT_AIR_MOODBAR_SKIP_LAUNCH=1 "$SCRIPT_DIR/build_and_run.sh"

pkill -f "${APP_NAME}.app/Contents/MacOS/${APP_NAME}" || true
pkill -x "$APP_NAME" >/dev/null 2>&1 || true
mkdir -p "$TARGET_ROOT"
rm -rf "$TARGET_BUNDLE"
rm -rf "$TARGET_ROOT/${APP_NAME}.app"
/usr/bin/ditto "$DIST_BUNDLE" "$TARGET_BUNDLE"

if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$TARGET_BUNDLE" >/dev/null 2>&1 || true
fi

if [[ -x "$LSREGISTER" ]]; then
  "$LSREGISTER" -f "$TARGET_BUNDLE"
fi

if command -v mdimport >/dev/null 2>&1; then
  mdimport "$TARGET_BUNDLE" >/dev/null 2>&1 || true
fi

touch "$TARGET_BUNDLE"
echo "Installed app bundle: $TARGET_BUNDLE"
open "$TARGET_BUNDLE"
