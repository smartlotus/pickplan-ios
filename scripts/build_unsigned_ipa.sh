#!/usr/bin/env bash
set -euo pipefail

# Build an unsigned Pickplan iOS/iPadOS .ipa suitable for SideStore / AltStore / LiveContainer
# Zero paid Apple Developer Program account required.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/build"
ARCHIVE_PATH="${BUILD_DIR}/PickPlan.xcarchive"
PAYLOAD_DIR="${BUILD_DIR}/Payload"
IPA_PATH="${BUILD_DIR}/PickPlan-Unsigned.ipa"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "Error: Full Xcode (xcodebuild) is required to package an iOS .ipa."
  echo "Tip: On Linux/Windows or Mac without full Xcode, use GitHub Actions macOS runner (see docs/ci/build-unsigned-ipa.yml)"
  echo "     or open PickPlan.xcodeproj in Xcode on any Mac."
  exit 1
fi

rm -rf "${BUILD_DIR}"
mkdir -p "${PAYLOAD_DIR}"

echo "[1/3] Building PickPlan (iOS + iPadOS, unsigned)..."
xcodebuild \
  -project "${ROOT_DIR}/PickPlan.xcodeproj" \
  -scheme PickPlan \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -derivedDataPath "${BUILD_DIR}/DerivedData" \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  AD_HOC_CODE_SIGNING_ALLOWED=YES \
  clean build

APP_BUNDLE="$(find "${BUILD_DIR}/DerivedData/Build/Products/Release-iphoneos" -maxdepth 1 -name "*.app" | head -n 1)"
if [[ -z "${APP_BUNDLE}" || ! -d "${APP_BUNDLE}" ]]; then
  echo "Error: Could not find built .app bundle."
  exit 1
fi

echo "[2/3] Packaging Payload..."
cp -R "${APP_BUNDLE}" "${PAYLOAD_DIR}/"
(
  cd "${BUILD_DIR}"
  zip -qry "${IPA_PATH}" Payload
)

echo "[3/3] Done: ${IPA_PATH}"
ls -lh "${IPA_PATH}"
