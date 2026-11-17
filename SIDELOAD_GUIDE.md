# Pickplan iOS & iPadOS 零费用安装指南（无需 $99 Apple Developer 账号）

不花一分钱开发者费用，在 **iPhone** 和 **iPad** 上长期稳定使用 Pickplan 液态玻璃版的三种官方/社区方案：

---

## 方案一：Safari「添加到主屏幕」—— 零电脑、立即可用（最推荐体验）

本项目配套部署在 Cloudflare Pages 的 `app.html` 是一个为 **iPhone 与 iPad** 定制的 **Liquid Glass 独立 Web App（PWA）**：
- 使用相同的 `.pickplan.json` v2 备份格式，**可与原生 App 之间无损互相导入导出数据**。
- 支持离线缓存（Service Worker）、`viewport-fit=cover` 全面屏沉浸式状态栏、定时自动本地快照与数据管理中心。
- **操作**：用 iPhone/iPad 的 Safari 打开部署网址 `/app.html` → 点击底部分享按钮 → **「添加到主屏幕」**。

---

## 方案二：SideStore / LiveContainer 无线侧载 `.ipa`（摆脱 7 天重签烦恼）

如果你需要原生 SwiftUI 26 `GlassEffectContainer` 液态玻璃、原生 `UNUserNotificationCenter` 本地通知与系统“文件”夹同步：

1. **生成未签名 `.ipa`**：
   - 方法 A：在任意 Mac 上运行 `./scripts/build_unsigned_ipa.sh` 生成 `build/PickPlan-Unsigned.ipa`。
   - 方法 B：将仓库内 `docs/ci/build-unsigned-ipa.yml` 复制到 GitHub 仓库的 `.github/workflows/build-unsigned-ipa.yml`，在 GitHub Actions 免费 macOS Runner 自动打包下载 `PickPlan-Unsigned.ipa`。
2. **使用 SideStore（免费个人 Apple ID）**：
   - 在 iPhone/iPad 安装 [SideStore](https://sidestore.io/)（仅首次需电脑配对一次）。
   - 将 `PickPlan-Unsigned.ipa` 分享导入 SideStore 安装；开启 **StosVPN** 即可直接在手机端每 7 天内一键无线续签，无需电脑。
3. **突破免费账号 3 个 App 上限：LiveContainer**：
   - 在 SideStore 中安装 **LiveContainer**，再将 `PickPlan-Unsigned.ipa` 放入 LiveContainer 运行，可绕过免费 Apple ID 最多 3 个应用的限制。

---

## 方案三：Xcode 个人免费账号源码直装（Mac + 数据线）

1. 克隆本仓库：
   ```bash
   git clone https://github.com/smartlotus/pickplan-ios.git
   cd pickplan-ios
   ```
2. 用 Xcode（推荐 Xcode 26 及以上以激活原生 `.glassEffect`）打开 `PickPlan.xcodeproj`。
3. 选择 `PickPlan` Target → **Signing & Capabilities**：
   - Team 选择你的免费 **Personal Team (Apple ID)**（无需付费）。
   - 将 `Bundle Identifier` 改为唯一值（例如 `com.yourname.pickplan.ios`）。
   - 保持 Capabilities 为空（零付费权限，无需 Push / iCloud Entitlements）。
4. 用 USB 连接 iPhone 或 iPad，点击 **Run (`⌘R`)** 安装；首次在设备上前往 **设置 → 通用 → VPN 与设备管理** 信任个人开发者证书即可运行。

> 💡 **7 天重签保护贴士**：Pickplan 已在 **文件 App → Pickplan → Backups** 开启 `UIFileSharingEnabled` 与定时自动本地快照。即便证书 7 天到期重新覆盖安装，或定期导出一份 `.pickplan.json`，所有待办、AI 设置与历史记录都会完整保留。
