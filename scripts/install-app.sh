#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
APP_NAME="DayHelm.app"
SRC_APP="${ROOT_DIR}/build/${APP_NAME}"

LAUNCH_AFTER_INSTALL=false
for arg in "$@"; do
  case "${arg}" in
    --launch)
      LAUNCH_AFTER_INSTALL=true
      ;;
    --help|-h)
      echo "Usage: $0 [--launch]"
      echo "  Builds release DayHelm.app and installs a standalone copy into /Applications/DayHelm.app"
      echo "  (falls back to ~/Applications/DayHelm.app if /Applications is not writable)."
      echo "  --launch   Restart installed DayHelm.app after installation."
      exit 0
      ;;
    *)
      echo "Unknown option: ${arg}" >&2
      exit 1
      ;;
  esac
done

# 1. Build release DayHelm.app into build/DayHelm.app
BUILD_CONFIG=release "${SCRIPT_DIR}/build-app.sh"

if [[ ! -d "${SRC_APP}" ]]; then
  echo "Error: Built app bundle not found at ${SRC_APP}" >&2
  exit 1
fi

# 2. Determine install directory (/Applications primary, ~/Applications fallback)
if [[ -w "/Applications" ]]; then
  INSTALL_DIR="/Applications"
else
  INSTALL_DIR="${HOME}/Applications"
  mkdir -p "${INSTALL_DIR}"
  echo "[DayHelm] /Applications is not writable; falling back to ${INSTALL_DIR}"
fi

DEST_APP="${INSTALL_DIR}/${APP_NAME}"

# 3. Stop running instance from destination bundle if active
if pgrep -f "${DEST_APP}/Contents/MacOS/DayHelm" >/dev/null 2>&1; then
  echo "[DayHelm] Stopping running instance at ${DEST_APP}..."
  pkill -f "${DEST_APP}/Contents/MacOS/DayHelm" || true
  sleep 1
fi

# 4. Install standalone copy into destination
echo "[DayHelm] Installing standalone bundle to ${DEST_APP}..."
rm -rf "${DEST_APP}"
cp -R "${SRC_APP}" "${DEST_APP}"

# 5. Re-apply ad-hoc codesign at final production path
echo "[DayHelm] Ad-hoc signing ${DEST_APP}..."
codesign --force --deep --sign - "${DEST_APP}"
codesign -v "${DEST_APP}"

echo "[DayHelm] Installed successfully: ${DEST_APP}"

if [[ "${LAUNCH_AFTER_INSTALL}" == "true" ]]; then
  echo "[DayHelm] Launching ${DEST_APP}..."
  open "${DEST_APP}"
fi
