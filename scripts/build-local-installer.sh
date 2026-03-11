#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Codex Switcher"
EXECUTABLE_NAME="codex-switcher"
BUNDLE_ID="com.codex.switcher"
DEFAULT_VERSION="1.0.0"
MIN_MACOS="13.0"
SYMBOL_NAME="lightswitch.on"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
VERSION_FILE="${REPO_ROOT}/VERSION"

if [[ -f "${VERSION_FILE}" ]]; then
  VERSION="$(tr -d '[:space:]' < "${VERSION_FILE}")"
fi
VERSION="${VERSION:-${DEFAULT_VERSION}}"
BUILD_DATE="$(git -C "${REPO_ROOT}" show -s --date=format:%Y-%m-%d --format=%cd HEAD 2>/dev/null || true)"
BUILD_SHORT_HASH="$(git -C "${REPO_ROOT}" rev-parse --short=7 HEAD 2>/dev/null || true)"
BUILD_DATE="${BUILD_DATE:-unknown-date}"
BUILD_SHORT_HASH="${BUILD_SHORT_HASH:-unknownhash}"

DIST_DIR="${REPO_ROOT}/dist"
STAGE_DIR="${DIST_DIR}/dmg-staging"
APP_DIR="${STAGE_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
APP_ICON_ICNS="${RESOURCES_DIR}/AppIcon.icns"
DMG_PATH="${DIST_DIR}/${APP_NAME}.dmg"
TMP_ICONSET_DIR=""

cleanup() {
  if [[ -n "${TMP_ICONSET_DIR}" && -d "${TMP_ICONSET_DIR}" ]]; then
    rm -rf "${TMP_ICONSET_DIR}"
  fi
}
trap cleanup EXIT

generate_symbol_png() {
  local size="$1"
  local output_path="$2"

  /usr/bin/swift - "${size}" "${output_path}" "${SYMBOL_NAME}" <<'SWIFT'
import AppKit
import Foundation

let args = CommandLine.arguments
guard args.count == 4 else { exit(1) }

guard let size = Int(args[1]), size > 0 else { exit(1) }
let outputPath = args[2]
let symbolName = args[3]

let imageSize = NSSize(width: size, height: size)
let canvas = NSImage(size: imageSize)
canvas.lockFocus()
NSColor.clear.setFill()
NSBezierPath(rect: NSRect(origin: .zero, size: imageSize)).fill()

if let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
    .withSymbolConfiguration(.init(pointSize: CGFloat(size) * 0.72, weight: .regular))
{
    symbol.isTemplate = false
    let side = CGFloat(size) * 0.76
    let symbolRect = NSRect(
        x: (CGFloat(size) - side) / 2,
        y: (CGFloat(size) - side) / 2,
        width: side,
        height: side
    )
    NSColor.labelColor.set()
    symbol.draw(in: symbolRect)
}

canvas.unlockFocus()

guard
    let tiff = canvas.tiffRepresentation,
    let rep = NSBitmapImageRep(data: tiff),
    let png = rep.representation(using: .png, properties: [:])
else {
    exit(1)
}

do {
    try png.write(to: URL(fileURLWithPath: outputPath))
} catch {
    exit(1)
}
SWIFT
}

build_iconset() {
  TMP_ICONSET_DIR="$(mktemp -d "${DIST_DIR}/AppIcon.XXXXXX.iconset")"
  generate_symbol_png 16 "${TMP_ICONSET_DIR}/icon_16x16.png"
  generate_symbol_png 32 "${TMP_ICONSET_DIR}/icon_16x16@2x.png"
  generate_symbol_png 32 "${TMP_ICONSET_DIR}/icon_32x32.png"
  generate_symbol_png 64 "${TMP_ICONSET_DIR}/icon_32x32@2x.png"
  generate_symbol_png 128 "${TMP_ICONSET_DIR}/icon_128x128.png"
  generate_symbol_png 256 "${TMP_ICONSET_DIR}/icon_128x128@2x.png"
  generate_symbol_png 256 "${TMP_ICONSET_DIR}/icon_256x256.png"
  generate_symbol_png 512 "${TMP_ICONSET_DIR}/icon_256x256@2x.png"
  generate_symbol_png 512 "${TMP_ICONSET_DIR}/icon_512x512.png"
  generate_symbol_png 1024 "${TMP_ICONSET_DIR}/icon_512x512@2x.png"
}

echo "==> Building release binary"
swift build -c release --package-path "${REPO_ROOT}"
BIN_DIR="$(swift build -c release --show-bin-path --package-path "${REPO_ROOT}")"
BIN_PATH="${BIN_DIR}/${EXECUTABLE_NAME}"

if [[ ! -x "${BIN_PATH}" ]]; then
  echo "Error: release binary not found at ${BIN_PATH}" >&2
  exit 1
fi

echo "==> Creating app bundle"
rm -rf "${STAGE_DIR}" "${DMG_PATH}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"
cp "${BIN_PATH}" "${MACOS_DIR}/${EXECUTABLE_NAME}"
chmod +x "${MACOS_DIR}/${EXECUTABLE_NAME}"

echo "==> Building app icon"
build_iconset
iconutil -c icns "${TMP_ICONSET_DIR}" -o "${APP_ICON_ICNS}"

cat > "${CONTENTS_DIR}/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CodexBuildDate</key>
    <string>${BUILD_DATE}</string>
    <key>CodexBuildShortHash</key>
    <string>${BUILD_SHORT_HASH}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>${EXECUTABLE_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>${MIN_MACOS}</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST

ln -sfn /Applications "${STAGE_DIR}/Applications"
find "${STAGE_DIR}" -name ".DS_Store" -delete

echo "==> Creating DMG"
hdiutil create \
  -volname "${APP_NAME}" \
  -srcfolder "${STAGE_DIR}" \
  -ov \
  -format UDZO \
  "${DMG_PATH}" >/dev/null

echo "Done: ${DMG_PATH}"
