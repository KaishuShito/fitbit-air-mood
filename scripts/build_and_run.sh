#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
MONOREPO_DIR="$(cd "$APP_DIR/../.." && pwd)"
if [[ -f "$MONOREPO_DIR/go.mod" && -f "$MONOREPO_DIR/.env" ]]; then
  PROJECT_DIR="$MONOREPO_DIR"
else
  PROJECT_DIR="$APP_DIR"
fi
BUILD_DIR="$APP_DIR/.build/release"
DIST_DIR="$APP_DIR/dist"
APP_NAME="FitbitAirMoodBar"
APP_BUNDLE="$DIST_DIR/${APP_NAME}.app"
EXECUTABLE="$BUILD_DIR/$APP_NAME"

mkdir -p "$DIST_DIR"
pkill -x "$APP_NAME" >/dev/null 2>&1 || true

echo "Building $APP_NAME..."
(
  cd "$APP_DIR"
  swift build -c release
)

SPARKLE_FRAMEWORK="$BUILD_DIR/Sparkle.framework"
if [[ ! -d "$SPARKLE_FRAMEWORK" ]]; then
  SPARKLE_FRAMEWORK="$(find "$APP_DIR/.build" -maxdepth 6 -path '*/release/Sparkle.framework' -type d | head -n 1)"
fi
if [[ -z "$SPARKLE_FRAMEWORK" ]]; then
  echo "error: Sparkle.framework was not found in SwiftPM build artifacts." >&2
  exit 1
fi

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources" "$APP_BUNDLE/Contents/Frameworks"
cp "$EXECUTABLE" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
ditto "$SPARKLE_FRAMEWORK" "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
if ! otool -l "$APP_BUNDLE/Contents/MacOS/$APP_NAME" | grep -q "@executable_path/../Frameworks"; then
  install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
fi
if [[ -f "$APP_DIR/Resources/AppIcon.icns" ]]; then
  cp "$APP_DIR/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi
printf '%s\n' "$PROJECT_DIR" > "$APP_BUNDLE/Contents/Resources/project-root.txt"

cat > "$APP_BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>FitbitAirMoodBar</string>
    <key>CFBundleIdentifier</key>
    <string>com.kai.fitbit-air-journal.moodbar</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleName</key>
    <string>FitbitAirMoodBar</string>
    <key>CFBundleDisplayName</key>
    <string>Fitbit Air Mood</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.3.1</string>
    <key>CFBundleVersion</key>
    <string>6</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSPrefersDisplaySafeAreaCompatibilityMode</key>
    <false/>
    <key>SUEnableAutomaticChecks</key>
    <true/>
    <key>SUFeedURL</key>
    <string>https://github.com/KaishuShito/fitbit-air-mood/releases/latest/download/appcast.xml</string>
    <key>SUPublicEDKey</key>
    <string>QcIpM0YElQfVecF5R9bQt0GYfUkMUzlv4lMkA4+p6qk=</string>
  </dict>
</plist>
PLIST

if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null 2>&1 || true
fi

echo "Built app bundle: $APP_BUNDLE"
if [[ "${FITBIT_AIR_MOODBAR_SKIP_LAUNCH:-0}" == "1" ]]; then
  echo "Skipping launch."
  exit 0
fi

echo "Launching..."
FITBIT_AIR_JOURNAL_PROJECT_DIR="$PROJECT_DIR" open "$APP_BUNDLE"
