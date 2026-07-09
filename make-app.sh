#!/bin/bash
# Builds FlowVoice and assembles FlowVoice.app in the project root.
set -euo pipefail
cd "$(dirname "$0")"

# The installed Command Line Tools SDK is missing HIServices/Icons.h; a VFS
# overlay maps a stub into place (see SDKShim/HIServices/Icons.h). The overlay
# itself is generated below (not checked into git) so it always points at
# whichever SDK is active and at this checkout's actual path — a static
# overlay.yaml would hard-code both to one machine.
SDK_PATH=$(xcrun --show-sdk-path)
SDK_REALPATH=$(cd "$SDK_PATH" && pwd -P)
export SDKROOT="$SDK_PATH"

ICONS_STUB="$PWD/SDKShim/HIServices/Icons.h"
mkdir -p .build
OVERLAY="$PWD/.build/overlay.yaml"

overlay_roots_for_sdk() {
  local sdk="$1"
  for sub in "Headers" "Versions/A/Headers" "Versions/Current/Headers"; do
    printf '  {"type": "directory", "name": "%s/System/Library/Frameworks/ApplicationServices.framework/Frameworks/HIServices.framework/%s", "contents": [{"type": "file", "name": "Icons.h", "external-contents": "%s"}]}\n' \
      "$sdk" "$sub" "$ICONS_STUB"
  done
}

{
  echo '{'
  echo ' "version": 0,'
  echo ' "case-sensitive": "false",'
  echo ' "fallthrough": true,'
  echo ' "roots": ['
  overlay_roots_for_sdk "$SDK_PATH" | paste -sd, -
  if [ "$SDK_REALPATH" != "$SDK_PATH" ]; then
    echo ','
    overlay_roots_for_sdk "$SDK_REALPATH" | paste -sd, -
  fi
  echo ' ]'
  echo '}'
} > "$OVERLAY"

swift build -c release \
  -Xswiftc -vfsoverlay -Xswiftc "$OVERLAY" \
  -Xcc -ivfsoverlay -Xcc "$OVERLAY"

APP=FlowVoice.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/FlowVoice "$APP/Contents/MacOS/FlowVoice"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>FlowVoice</string>
    <key>CFBundleIdentifier</key><string>dev.hugh.flowvoice</string>
    <key>CFBundleName</key><string>FlowVoice</string>
    <key>CFBundleDisplayName</key><string>FlowVoice</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>FlowVoice records your voice to transcribe dictation.</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>FlowVoice converts your speech to text on-device.</string>
</dict>
</plist>
EOF

# Prefer a real signing identity so macOS keeps permissions across rebuilds;
# fall back to ad-hoc (requires re-granting Accessibility after each build).
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
  | grep -Eo '"(Developer ID Application|Apple Development)[^"]*"' | head -1 | tr -d '"' || true)
if [ -n "$IDENTITY" ]; then
  echo "Signing with: $IDENTITY"
  codesign --force --deep --options runtime --sign "$IDENTITY" "$APP" || codesign --force --deep --sign - "$APP"
else
  echo "No signing identity found — using ad-hoc signature (re-grant Accessibility after rebuilds)."
  codesign --force --deep --sign - "$APP"
fi
echo "Built $PWD/$APP"

# Install to /Applications (the canonical copy).
if [ -d "/Applications/$APP" ] || [ -w /Applications ]; then
  rm -rf "/Applications/$APP"
  cp -R "$APP" "/Applications/$APP"
  echo "Installed to /Applications/$APP"
  echo "Note: re-grant Accessibility after each rebuild (ad-hoc signature)."
fi
echo "Run with: open /Applications/$APP"
