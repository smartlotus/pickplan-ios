#!/usr/bin/env bash
set -euo pipefail

# Build, sign (free Apple ID Personal Team), and install Pickplan directly onto a connected physical iPhone/iPad.
# Usage:
#   ./scripts/install_to_iphone.sh [TEAM_ID] [BUNDLE_ID]
# Prerequisites on device & Mac:
#   1. iPhone Settings -> Privacy & Security -> Developer Mode = ON (restarted + unlocked)
#   2. Xcode -> Settings -> Accounts -> signed in with your Apple ID (free Personal Team is enough)

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEAM_ID="${1:-${DEVELOPMENT_TEAM:-}}"
BUNDLE_ID="${2:-com.smartlotus.pickplan.ios}"
DERIVED_DIR="${ROOT_DIR}/build/DeviceDerivedData"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "Error: Xcode (xcodebuild) not found."
  exit 1
fi

# 1. Detect connected physical iPhone/iPad
DEVICE_LINE="$(xcrun xctrace list devices 2>/dev/null | grep -E 'iPhone|iPad' | grep -v 'Simulator' | head -n 1 || true)"
if [[ -z "${DEVICE_LINE}" ]]; then
  echo "未检测到通过 USB 连接的 iPhone / iPad，请插线并解锁设备后点击「信任此电脑」。"
  exit 1
fi

UDID="$(echo "${DEVICE_LINE}" | sed -nE 's/.*\(([0-9A-Za-z-]+)\)[^()]*$/\1/p')"
if [[ -z "${UDID}" ]]; then
  echo "无法解析设备 UDID：${DEVICE_LINE}"
  exit 1
fi
echo "[1/4] 检测到真机：${DEVICE_LINE}"

# 2. Check Developer Mode
DEV_DETAILS="$(xcrun devicectl device info details --device "${UDID}" 2>&1 || true)"
if echo "${DEV_DETAILS}" | grep -q "Developer Mode is turned off\|Developer Mode Status: Disabled"; then
  echo "报错：iPhone 尚未开启「开发者模式」。"
  echo "请在 iPhone 上打开：设置 -> 隐私与安全性 -> 开发者模式 -> 开启并重启 iPhone，解锁后再运行本脚本。"
  exit 2
fi

# 3. Auto-detect Apple Development Team ID if omitted
extract_team_id() {
  local key="$1"
  defaults read com.apple.dt.Xcode "${key}" 2>/dev/null \
    | sed -nE 's/.*teamID[[:space:]]*=[[:space:]]*"?([A-Za-z0-9]+)"?;.*/\1/p' \
    | head -n 1 || true
}

if [[ -z "${TEAM_ID}" ]]; then
  TEAM_ID="$(extract_team_id IDEProvisioningTeamByIdentifier)"
fi
if [[ -z "${TEAM_ID}" ]]; then
  TEAM_ID="$(extract_team_id IDEProvisioningTeams)"
fi

if [[ -z "${TEAM_ID}" ]]; then
  echo "报错：Xcode 尚未登录 Apple ID / Personal Team 签名证书。"
  echo "请打开 Xcode -> Settings (⌘,) -> Accounts -> 点击左下角「+」登录免费 Apple ID，或传入 Team ID：./scripts/install_to_iphone.sh <TEAM_ID>"
  exit 3
fi

echo "[2/4] 使用个人签名团队 ${TEAM_ID} (Bundle ID: ${BUNDLE_ID}) 编译 PickPlan..."
rm -rf "${DERIVED_DIR}"
xcodebuild \
  -project "${ROOT_DIR}/PickPlan.xcodeproj" \
  -scheme PickPlan \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -derivedDataPath "${DERIVED_DIR}" \
  -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration \
  DEVELOPMENT_TEAM="${TEAM_ID}" \
  PRODUCT_BUNDLE_IDENTIFIER="${BUNDLE_ID}" \
  build

APP_BUNDLE="${DERIVED_DIR}/Build/Products/Release-iphoneos/PickPlan.app"
if [[ ! -d "${APP_BUNDLE}" ]]; then
  echo "Error: 未找到已构建的 ${APP_BUNDLE}"
  exit 1
fi

echo "[3/4] 安装 PickPlan.app 到设备 ${UDID}..."
if ! xcrun devicectl device install app --device "${UDID}" "${APP_BUNDLE}"; then
  echo "安装失败：若上方出现 CryptexKitHost.TatsuError / 12051，请暂时关闭电脑 VPN（或将 gs.apple.com 设为直连）并保持 iPhone 解锁后重试。"
  exit 1
fi

echo "[4/4] 尝试启动 Pickplan..."
xcrun devicectl device process launch --device "${UDID}" "${BUNDLE_ID}" || \
  echo "如果提示证书未受信任，请在 iPhone「设置 -> 通用 -> VPN 与设备管理」中信任你的 Apple ID 开发者 App 后点击桌面图标打开。"
