#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="DayHelm"
BUILD_CONFIG="${BUILD_CONFIG:-release}"
OUTPUT_DIR="${OUTPUT_DIR:-${ROOT_DIR}/build}"
APP_BUNDLE="${OUTPUT_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "[DayHelm] Building ${APP_NAME} (${BUILD_CONFIG})..."
cd "${ROOT_DIR}"
swift build -c "${BUILD_CONFIG}" --product DayHelmApp

BIN_DIR="$(swift build -c "${BUILD_CONFIG}" --show-bin-path)"
EXECUTABLE_SRC="${BIN_DIR}/DayHelmApp"

if [[ ! -x "${EXECUTABLE_SRC}" ]]; then
  echo "Error: Built executable not found at ${EXECUTABLE_SRC}" >&2
  exit 1
fi

ICON_SCRIPT="${ROOT_DIR}/scripts/generate-icon.swift"
BRANDING_DIR="${ROOT_DIR}/branding"
ICON_ICNS="${BRANDING_DIR}/AppIcon.icns"
ICON_PNG="${BRANDING_DIR}/dayhelm-icon-1024.png"

if [[ ! -f "${ICON_ICNS}" || ! -f "${ICON_PNG}" || "${ICON_SCRIPT}" -nt "${ICON_ICNS}" ]]; then
  echo "[DayHelm] Generating app icon assets..."
  swift "${ICON_SCRIPT}"
fi

rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

cp "${EXECUTABLE_SRC}" "${MACOS_DIR}/${APP_NAME}"
chmod +x "${MACOS_DIR}/${APP_NAME}"
cp "${ICON_ICNS}" "${RESOURCES_DIR}/AppIcon.icns"
cp "${ICON_PNG}" "${RESOURCES_DIR}/dayhelm-icon-1024.png"

cat > "${CONTENTS_DIR}/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleDisplayName</key>
    <string>DayHelm</string>
    <key>CFBundleExecutable</key>
    <string>DayHelm</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.dayhelm.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>DayHelm</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsLocalNetworking</key>
        <true/>
    </dict>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSScreenCaptureUsageDescription</key>
    <string>DayHelm 使用本地屏幕快照与 Apple Vision OCR 自动提取工作上下文（所有数据仅保留在本地，隐私应用/窗口自动跳过）。</string>
</dict>
</plist>
PLIST

SIGN_IDENTITY="-"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "Stage0 Local Code Signing"; then
  SIGN_IDENTITY="Stage0 Local Code Signing"
fi

echo "[DayHelm] Signing ${APP_BUNDLE} with identity '${SIGN_IDENTITY}'..."
codesign --force --deep --sign "${SIGN_IDENTITY}" "${APP_BUNDLE}"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "${APP_BUNDLE}" 2>/dev/null || true

echo "[DayHelm] Packaged successfully: ${APP_BUNDLE}"
echo "  Run live:           open \"${APP_BUNDLE}\""
echo "  Run synthetic demo: \"${MACOS_DIR}/${APP_NAME}\" --synthetic-demo"
echo "  CLI status:         \"${MACOS_DIR}/${APP_NAME}\" status"
echo "  CLI query:          \"${MACOS_DIR}/${APP_NAME}\" query --today --format md"
echo "  CLI search:         \"${MACOS_DIR}/${APP_NAME}\" search <keyword> --format json"
echo "  CLI sessions:       \"${MACOS_DIR}/${APP_NAME}\" sessions --format md"
echo "  CLI purge:          \"${MACOS_DIR}/${APP_NAME}\" purge --before YYYY-MM-DD"
