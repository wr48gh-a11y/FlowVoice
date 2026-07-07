#!/bin/bash
# Builds FlowVoice and assembles FlowVoice.app in the project root.
set -euo pipefail
cd "$(dirname "$0")"

# The installed Command Line Tools SDK is missing HIServices/Icons.h; a VFS
# overlay maps a stub into place (see SDKShim/).
export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX15.5.sdk
OVERLAY="$PWD/SDKShim/overlay.yaml"
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
