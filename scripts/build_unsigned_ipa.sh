#!/usr/bin/env bash
set -euo pipefail

# Build an unsigned Pickplan iOS/iPadOS .ipa suitable for SideStore / AltStore / Sideloadly / LiveContainer
# Zero paid Apple Developer Program account required.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/build"
PAYLOAD_DIR="${BUILD_DIR}/Payload"
IPA_PATH="${BUILD_DIR}/PickPlan-Unsigned.ipa"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "Error: Full Xcode (xcodebuild) is required to package an iOS .ipa."
  echo "Tip: On Mac without full Xcode, Linux, or Windows, trigger GitHub Actions macOS runner"
  echo "     (see docs/ci/build-unsigned-ipa.yml) or open PickPlan.xcodeproj in Xcode on any Mac."
  exit 1
fi

rm -rf "${BUILD_DIR}"
mkdir -p "${PAYLOAD_DIR}"

echo "[1/4] Resolving Swift Package dependencies..."
xcodebuild \
  -project "${ROOT_DIR}/PickPlan.xcodeproj" \
  -scheme PickPlan \
  -resolvePackageDependencies

echo "[2/4] Building PickPlan (iOS + iPadOS Universal, unsigned)..."
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

echo "[3/4] Packaging Payload..."
cp -R "${APP_BUNDLE}" "${PAYLOAD_DIR}/"
if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "${PAYLOAD_DIR}/PickPlan.app" 2>/dev/null || true
fi
(
  cd "${BUILD_DIR}"
  zip -qry "${IPA_PATH}" Payload
)

echo "[4/4] Done: ${IPA_PATH}"
ls -lh "${IPA_PATH}"
