# Pickplan Android 深度解析与 iOS/iPadOS 液态玻璃架构设计

> 原仓库对照：[`smartlotus/pickplan`](https://github.com/smartlotus/pickplan)（`main` + `wip/monorepo-migration` 分支）

---

## 一、原 Android 项目深度剖析

### 1.1 产品定位与视觉语言
- **标语**：*“做计划，说大白话” / “Plan in plain words”*
- **美学哲学**：极简黑白高对比（`#000000` 纯黑画布、`#1E1E1E` 卡片表面、`#FFFFFF` 主高亮与描边、`#CF6679` 截止警示玫瑰红），开屏页采用 900ms 呼吸缩放动画由暖白淡入主界面。
- **核心价值**：无账号门槛、纯本机保存、手动快速记待办 + BYOK（Bring Your Own Key）自然语言拆解为任务草稿。

### 1.2 核心功能与架构（`main` vs `wip/monorepo-migration`）
| 维度 | `main` 基线实现 | `wip/monorepo-migration` 进化 | iOS/iPadOS 2.0 升级方案 |
|---|---|---|---|
| **数据模型** | `id`, `title`, `reminderTime`, `deadline`, `isCompleted` | 新增 `createdAt`、`replaceSchedule()` | 新增 `notes`、`subtasks`、`tag`、`priority`、`updatedAt`、`completedAt`、`focusMinutesLogged`，并**100% 兼容导入 Android v1 JSON** |
| **分组与排序** | 平铺时间线 | 6 大智能分组（已逾期 / 今天 / 明天 / 之后 / 无时间 / 已完成）+ 快捷时间标签 + 删除撤销 Undo | 保留 6 大分组并新增搜索、标签过滤、子任务进度、右划完成/左划删除、**专注计时浮层** |
| **AI 帮做模式** | 单句解析后直接写入 | 单句拆分多任务草稿（`"tasks": [...]`），先编辑确认再 `加入` / `全部加入计划` | 保留 7 大厂商预设（DeepSeek / Kimi / Qwen / GLM / SiliconFlow / OpenAI / Custom），并**新增离线中英文大白话本地拆解器**（无 Key 也能拆多任务） |
| **双端自适应** | 手机单栏 `BottomNavigationBar` | 引入 `Motion` 微动画（`PressScale`、`AnimatedNavIcon`） | **iPhone** 底部悬浮可形变 `GlassEffectContainer` 液态玻璃胶囊；**iPad** 原生三栏 `NavigationSplitView` + 键盘快捷键（`⌘N` / `⌘F` / `⌘B`） |
| **数据安全与备份** | 仅存 `SharedPreferences`，无导出/备份 | 同左 | **本地数据金库**：`.pickplan.json` v2（SHA256 校验）+ Android v1 无损导入 + Markdown 导出 + **定时自动本地备份** + 快照管理与存储占用统计 |

---

## 二、为什么针对 iOS 26 液态玻璃（Liquid Glass）做原生重构？

1. **视觉同源、材质升维**：
   - 原 Android 版用 1px 纯白细线勾勒黑底卡片；在 **iOS 26 / iPadOS 26 Liquid Glass** 中，我们将导航层、底部悬浮胶囊栏、快捷筛选条与浮动 Undo 提示置于 `.glassEffect(.regular.interactive(), in:)` 与 `GlassEffectContainer` 之中，底层叠加极克制的单色珍珠微光环境场（`AmbientMonochromeCanvas`），使液态玻璃在不破坏 Pickplan 黑白极简基因的前提下产生真实的折射与边缘高光。
2. **微交互与触感细节**：
   - **触感反馈（Haptics）**：完成任务、触发 Undo、创建本地快照、打开专注模式均映射至 `UIImpactFeedbackGenerator` / `UINotificationFeedbackGenerator`。
   - **物理弹簧动效**：采用 `.spring(response: 0.38, dampingFraction: 0.78)` 与 `@Namespace` + `.glassEffectID` 实现模式切换与新增按钮形变，严格尊重系统 `accessibilityReduceMotion`。
3. **免 $99 开发者费用策略**：
   - **零付费 Entitlements**：不使用 iCloud / Push Notifications 付费权限，本地通知使用免费的 `UNUserNotificationCenter`，数据导出与自动快照直通系统 **“文件 (Files)” App**（`UIFileSharingEnabled = YES`）。
   - **三条零成本安装路径**：Safari 一键安装 Liquid Glass 独立 Web App（即开即用） / SideStore + LiveContainer 无线侧载（无需每 7 天连电脑） / Xcode 个人免费 Apple ID 源码直装。

---

## 三、本地导入导出、定时自动备份与数据管理架构

1. **统一信封格式（`PickPlanBackupEnvelope`, v2）**：
   - 包含 `format: "pickplan-backup"`、`schemaVersion: 2`、`exportedAt`、`deviceHint`、`checksum`（CryptoKit SHA256），以及 `payload`（`todos`、`aiSettings`（可选是否含 `apiKey`）、`preferences`（含 `backupPolicy`）、`chatHistory`）。
2. **定时自动本地备份策略（`BackupPolicy`）**：
   - 支持开关、备份周期（每 1 / 6 / 12 / 24 小时或每周）、切后台有变更自动快照（`BGAppRefreshTask` + `scenePhase == .background`）、保留份数上限（自动轮转清理最旧非置顶快照，**置顶快照永久保护**）。
3. **三大安全导入模式**：
   - **智能合并（推荐）**：同 `id` 按 `updatedAt` 新旧合并，新任务直接加入。
   - **追加导入**：为所有导入任务重新生成唯一 `id` 作为副本追加，绝不覆盖现有任务。
   - **安全覆盖**：覆盖前**强制自动生成 `.safetyPreRestore` 本地快照**，支持随时一键回滚。
