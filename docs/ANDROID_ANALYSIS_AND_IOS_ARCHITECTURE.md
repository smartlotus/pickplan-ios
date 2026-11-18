# Pickplan Android 深度解析与 iOS/iPadOS 原生液态玻璃架构设计

> 原仓库对照：[`smartlotus/pickplan`](https://github.com/smartlotus/pickplan)（`main` + `wip/monorepo-migration` 分支）

---

## 一、原 Android 项目深度剖析

### 1.1 产品定位与视觉语言
- **标语**：*“做计划，说大白话” / “Plan in plain words”*
- **美学哲学**：开屏页使用纯净 `#FFFFFF` 暖白底色配合真实 `pickplanlogo.jpg` 标志与 900ms 呼吸缩放，随后过渡到标志性纯黑 `#000000` 主画布、`#1E1E1E` 深灰卡片、纯白高对比高亮胶囊与 `#CF6679` 珊瑚红截止提示。
- **核心价值**：无账号门槛、100% 本地优先、极速手工记录 + BYOK（Bring Your Own Key）自然语言拆解为任务草稿后再确认加入。

### 1.2 核心功能与架构（`main` vs `wip/monorepo-migration`）
| 维度 | Android 原版实现 | iOS / iPadOS 原生移植与增强 |
|---|---|---|
| **数据模型** | `id`, `title`, `reminderTime`, `deadline`, `isCompleted`, `createdAt`, `replaceSchedule()` | 完全兼容 `title/reminderTime/deadline/isCompleted/createdAt`，并拓展 `notes`, `subtasks`, `tag`, `priority`, `updatedAt`, `completedAt`, `focusMinutesLogged`；**100% 无损读取 Android v1 JSON** |
| **分组与提醒** | 6 大智能分组（`已逾期` / `今天` / `明天` / `之后` / `无时间` / `已完成`）、5 组快捷时间标签（含明天下午 `15:00`）、单条删除 + Undo 条、双本地通知（提醒 + 截止）与 🔔 立即测试通知 | 完整 1:1 保留 6 大分组、5 组快捷芯片、1-tap 删除 + 液态玻璃 Undo 条、双本地通知 + `UNUserNotificationCenterDelegate` 前台直接弹窗，新增 iPad 多栏预览、搜索过滤与极简专注计时浮层 |
| **AI 帮做模式** | DeepSeek / Kimi (Moonshot) / Tongyi Qwen (`qwen-turbo`) / GLM (`glm-4`) / SiliconFlow / OpenAI / Custom；`GET /models` 探测返回 `200`；多草稿单条 `编辑`、`加入`（绿色 `✓ 已加入计划`）、`全部加入计划` | 完整保留全部 7 大厂商 URL/模型预设、`GET /models` 测试与 404/405 回退探测、每张草稿独立编辑 (`DraftConfirmEditorSheet`) 与单条/全部加入，并**新增完全离线大白话拆解器 (`PlainWordsParser`)** |
| **双端自适应** | 手机底部两态切换（`自己做` / `AI 帮做`）+ 900ms 缩放开屏 + `PressScale` 按压反馈 | **iPhone** 底部三态悬浮液态玻璃胶囊（`自己做` / `AI 帮做` / `本地数据`）；**iPad** 原生三栏 `NavigationSplitView` + 分屏/台前调度 + `⌘N`/`⌘F`/`⌘B` 键盘快捷键 |
| **数据安全与备份** | 仅存本机 `SharedPreferences`，缺少导出、备份与恢复能力 | 新增 **本地数据金库 (`LocalVaultStore`)**：`.pickplan.json` v2（CryptoKit SHA256 校验）、Android v1 导入、Markdown 导出、**每日定时自动本地快照**、快照内容预览、置顶防清理与存储占用管理 |

---

## 二、为什么针对 iOS 26 液态玻璃（Liquid Glass）做原生重构？

1. **视觉同源、材质升维**：
   - 在保留 Android 原版高对比极简黑白骨骼的同时，导航栏、底部悬浮胶囊栏、快捷筛选条、Undo 浮动条均采用 `GlassEffectContainer` + `.glassEffect(.regular.interactive(), in:)` 与 `.glassEffectID(_:in:)`；在 Xcode 16 / iOS 17–18 环境自动优雅降级为 `.ultraThinMaterial` 光学毛玻璃，保证跨系统版本编译运行无忧。
2. **微交互与触感细节**：
   - 勾选任务、打开 AI 草稿编辑器、触发 Undo、创建快照、切换 `中/EN` 均搭配 `UIImpactFeedbackGenerator` / `UINotificationFeedbackGenerator` 与弹簧微缩放反馈，严格遵守系统 `accessibilityReduceMotion`。
3. **免 \$99 开发者费用原生交付策略**：
   - **零付费 Entitlements**：不使用 iCloud / Push Notifications 等收费证书权限；系统本地提醒使用 `UNUserNotificationCenter`，导出与自动快照直通系统 **「文件 (Files)」App**（`UIFileSharingEnabled = YES`）。
   - **三条零费用原生安装路径**：SideStore / AltStore 无线侧载 `.ipa`（支持 LiveContainer）/ Sideloadly & 爱思助手 USB 安装 `.ipa` / Xcode 免费 Personal Apple ID 源码直装。

---

## 三、本地导入导出、定时自动备份与数据管理架构

1. **统一信封格式（`PickPlanBackupEnvelope`, v2）**：
   - 包含 `format: "pickplan-backup"`、`schemaVersion: 2`、`exportedAt`、`deviceHint`、`checksum`（CryptoKit SHA256），以及 `payload`（`todos`、`aiSettings`（可选是否含 `apiKey`）、`preferences`（含 `backupPolicy` 与首选每日备份时刻）、`chatHistory`）。
2. **定时自动本地备份策略（`BackupPolicy`）**：
   - 支持一键开关、周期选择（每 1 / 6 / 12 / 24 小时或每周）、每日触发时刻微调（`preferredHour` / `preferredMinute`）、切后台有变更自动快照（`BGAppRefreshTask` + `scenePhase == .background`）、保留份数上限自动轮转清理（**置顶快照永久受保护**）。
3. **三大安全导入模式**：
   - **智能合并（推荐）**：同 `id` 按 `updatedAt` 新旧合并，新任务直接加入。
   - **追加导入**：为所有导入任务重新生成唯一 `id` 作为副本追加，绝不覆盖现有任务。
   - **安全覆盖**：覆盖前**强制自动生成 `.safetyPreRestore` 本地快照**，支持随时一键回滚，并可直接在界面内预览任意快照的具体待办内容。
