#!/usr/bin/env bash
#
# Builds Vox.app from the SwiftPM executable, writes a proper Info.plist
# (usage strings + menu-bar-only flag) and ad-hoc signs it so macOS remembers
# the granted permissions (mic / speech / accessibility) across launches.
#
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="Vox"
BUNDLE_ID="com.tdzapps.vox"
VERSION="0.1.0"
BUILD="1"

echo "▸ Building release binary…"
swift build -c release

BIN_PATH="$(swift build -c release --show-bin-path)/${APP_NAME}"
APP_DIR="build/${APP_NAME}.app"

echo "▸ Assembling ${APP_DIR}…"
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

cp "${BIN_PATH}" "${APP_DIR}/Contents/MacOS/${APP_NAME}"

cat > "${APP_DIR}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>     <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>      <string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key>      <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key>         <string>${BUILD}</string>
    <key>LSMinimumSystemVersion</key>  <string>26.0</string>
    <key>LSUIElement</key>             <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>O Vox usa o microfone para transcrever sua fala em texto.</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>O Vox transcreve sua fala no próprio dispositivo, sem enviar áudio para fora.</string>
</dict>
</plist>
PLIST

# Prefer a stable identity (Apple Development) so TCC permission grants
# (Accessibility / Mic / Speech) persist across rebuilds. Falls back to ad-hoc.
SIGN_ID="${VOX_SIGN_ID:-$(security find-identity -v -p codesigning 2>/dev/null | grep -m1 'Apple Development' | sed -E 's/.*\) ([0-9A-F]+) .*/\1/')}"
if [ -n "${SIGN_ID}" ]; then
    echo "▸ Signing with stable identity ${SIGN_ID}…"
    codesign --force --deep --sign "${SIGN_ID}" --identifier "${BUNDLE_ID}" "${APP_DIR}"
else
    echo "▸ Ad-hoc signing (no stable identity found)…"
    codesign --force --deep --sign - "${APP_DIR}"
fi

echo "✓ Pronto: ${APP_DIR}"
echo "  Instalar:  cp -R \"${APP_DIR}\" /Applications/"
echo "  Abrir:     open \"${APP_DIR}\""
