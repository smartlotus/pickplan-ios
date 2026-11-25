# Pickplan iOS & iPadOS 零费用原生安装指南（无需 $99 Apple Developer 账号）

本仓库交付的是 **100% 原生 SwiftUI iOS / iPadOS 应用程序**（非 WebApp / 非 PWA），无需购买每年 \$99 的 Apple Developer 会员，即可在 **iPhone** 与 **iPad** 上直接安装运行。

---

## 获取未签名安装包（`PickPlan-Unsigned.ipa`）

- **方式 A（云端免费构建 `.ipa` — 本机无需安装 Xcode）**  
  本仓库包含现成的 GitHub Actions macOS 工作流模板 [`docs/ci/build-unsigned-ipa.yml`](./docs/ci/build-unsigned-ipa.yml)。将其放到 GitHub 仓库的 `.github/workflows/build-unsigned-ipa.yml`（通过 GitHub 网页添加，或运行 `gh auth refresh -h github.com -s workflow` 后推送），GitHub 免费 macOS Runner 会自动运行测试并产出 `PickPlan-Unsigned.ipa` Artifact 供下载。
- **方式 B（本机 Mac 打包）**  
  在装有完整 Xcode 的 Mac 上执行：
  ```bash
  ./scripts/build_unsigned_ipa.sh
  # 输出: build/PickPlan-Unsigned.ipa
  ```

---

## 方案一：SideStore / AltStore 无线侧载 `.ipa`（最省心，脱离电脑无线续签）

1. 在电脑上仅需首次配对一次，将 [SideStore](https://sidestore.io/) 或 [AltStore](https://altstore.io/) 安装到你的 iPhone / iPad（使用普通免费 Apple ID 即可）。
2. 将 `PickPlan-Unsigned.ipa` 发送至设备（隔空投送 / 文件 App），在 SideStore 中选择安装。
3. SideStore 搭配 **StosVPN**，可直接在手机端每 7 天内点击「Refresh」**无线自动续签**，之后完全不依赖电脑。
4. **突破免费账号 3 个应用数量上限**：在 SideStore 内安装 **LiveContainer**，再将 `PickPlan-Unsigned.ipa` 导入 LiveContainer 运行，可在不消耗免费 App ID 额度下长期使用。

---

## 方案二：Sideloadly / 爱思助手（Windows & Mac 通用）

1. 在 Windows 或 Mac 上安装 **Sideloadly** 或 **爱思助手**，用数据线连接 iPhone / iPad。
2. 拖入 `PickPlan-Unsigned.ipa`，填入免费个人 Apple ID 完成签发安装（支持 Apple Silicon 与 iPad 横屏分栏运行）。
3. 首次启动前，在 iPhone / iPad 前往：**设置 → 通用 → VPN 与设备管理**，信任你的 Apple ID 开发者证书即可。

---

## 方案三：Xcode 免费个人 Apple ID 源码直装（Mac + 数据线）

1. 克隆仓库并进入目录：
   ```bash
   git clone https://github.com/smartlotus/pickplan-ios.git
   cd pickplan-ios
   ```
2. 用 Xcode（支持 Xcode 16+，推荐 Xcode 26+ 激活原生 `.glassEffect`）打开 `PickPlan.xcodeproj`。
3. 选中 `PickPlan` Target → **Signing & Capabilities**：
   - Team 选择你的免费 **Personal Team (Apple ID)**。
   - 将 `Bundle Identifier` 修改为个人唯一前缀（例如 `com.yourname.pickplan.ios`）。
   - Capabilities 保持空白（零付费 Entitlements，无需 Push / iCloud 权限）。
4. 用 USB 连接 iPhone 或 iPad（支持“无线连接网络设备”），点击 **Run (`⌘R`)** 即可直装原生 App；或者登录 Xcode Accounts 并开启 iPhone「开发者模式」后直接执行一键脚本：
   ```bash
   ./scripts/install_to_iphone.sh
   ```

---

> 💡 **7 天重签防丢保护**：Pickplan 在 `Info.plist` 中开启了 `UIFileSharingEnabled` 与 `LSSupportsOpeningDocumentsInPlace`，本地数据与定时自动快照均存储在系统 **「文件」App → 我的 iPhone / 我的 iPad → Pickplan → Backups** 中。即使证书到期重新覆盖安装，或定期保留一份 `.pickplan.json`，所有待办、AI 引擎配置与历史记录均可一键无损恢复。
