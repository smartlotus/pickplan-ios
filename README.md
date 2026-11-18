# Pickplan iOS & iPadOS · Liquid Glass Edition

<p align="left">
  <strong>做计划，说大白话。忠实移植 Android 原版，重构为 iOS 原生液态玻璃应用。</strong><br>
  <em>Plan in plain words. Faithfully ported from Android to Native SwiftUI Liquid Glass for iPhone &amp; iPad.</em>
</p>

Pickplan iOS & iPadOS 是基于 Android 原版 [`smartlotus/pickplan`](https://github.com/smartlotus/pickplan)（涵盖 `main` 与 `wip/monorepo-migration` 分支）打造的 **100% 原生 iOS & iPadOS SwiftUI 应用**。完整还原原版极简黑白高对比视觉语言、900ms 暖白呼吸开屏页、全部操作流程与 7 大 AI 预设，并在 **iPhone** 与 **iPad** 上融入 **iOS 26 液态玻璃（Liquid Glass）** 材质与手势微交互；无需 \$99 付费开发者账号即可通过 SideStore / Sideloadly / Xcode 个人免费证书安装使用。

---

## 与 Android 原版 1:1 忠实还原 + iOS/iPadOS 原生增强

- **开屏与单色极简视觉 (`SplashRootView` / `LiquidGlassTheme`)**
  - 精确还原原版 `#FFFFFF` 暖白开屏页：顶部真实 `pickplanlogo.jpg` 品牌标志 + `PICKPLAN` 宽字距标题 + `做计划，说大白话` 副标题，900ms `easeInOutBack` 缩放脉冲后淡入纯黑 `#000000` 主画布（`#1E1E1E` 卡片、纯白高亮按钮、`#CF6679` 截止警示红）。
  - 在 Xcode 26 / iOS 26+ 环境自动启用原生 `GlassEffectContainer`、`.glassEffect(.regular.interactive(), in:)` 与 `.glassEffectID(_:in:)` 液态玻璃形变胶囊与浮动条；在 iOS 17–18 上自动平滑降级为 `.ultraThinMaterial` 光学毛玻璃。
- **自己做 (`ManualPlanView` & `TodoEditorSheet`)**
  - 完整保留原版 **6 大智能分组**：`已逾期` / `今天` / `明天` / `之后` / `无时间` / `已完成`，带组内数量统计与日期标签（`今天 · 周X`、`明天 · 周X`）。
  - 还原右上角 `🔔` 一键测试本地通知（未授权时弹出 `"通知未开启"` 提示引导）、`↻` 刷新计划列表 Toast、`中/EN` 双语切换胶囊与 `⚙` AI 引擎设置入口。
  - 任务卡片保留圆角复选框、白色提醒日期角标、`#CF6679` 珊瑚红截止角标与尾部单点击删按钮，并在删除后于底部弹出液态玻璃 **撤销 Undo** 悬浮条。
  - 底部纯白悬浮 **`+ 新任务`** Pill 与编辑器完整还原原版 5 组快捷时间标签（`今晚`、`明早`、`明天下午 (15:00)`、`下周一`、`1 小时后`）与独立的 `提醒: 未设置` / `截止: 未设置` 选择清除行，并额外增强可折叠的备注 / 标签 / 优先级 / 子任务与 **沉浸专注计时模式**。
- **AI 帮做 (`AIPlanBuilderView`)**
  - 完整保留 **7 大 AI 厂商预设**（DeepSeek、Kimi (Moonshot)、Tongyi Qwen、GLM、SiliconFlow、OpenAI、Custom）；非 Custom 模式下锁定对应 Base URL 与模型名，`连接测试` 先请求 `GET <baseUrl>/models` 并回显 `"连接成功（200）。"`（兼容 404/405 自动回退探测 `/chat/completions`）。
  - 完整还原多任务草稿确认流：`"我先整理成草稿，请确认后再加入计划。"`，每张草稿卡可单独点击 **`编辑`**（打开 `保存草稿` / `确认任务` 弹窗）或 **`加入`**（变成绿色 `✓ 已加入计划`），也可一键 **`全部加入计划`**。
  - **额外增强**：支持切换为**完全离线大白话解析引擎（On-Device `PlainWordsParser`）**，无 Key、断网状态下同样能拆解中英文自然语言。
- **本地数据管理与自动定时备份 (`LocalVaultStore` & `DataVaultView`)**
  - **全量本地导入导出**：导出 SHA256 校验的 `.pickplan.json` v2 备份包（可选是否导出 API Key）及可读 Markdown；支持无损导入原版 **Android v1 JSON** 与 v2 信封备份，导入前弹窗预览，支持 **智能合并 / 追加副本 / 安全覆盖（覆盖前强制自动建安全快照）**。
  - **自动定时本地备份**：可开关定时调度、可选频率（每 1 / 6 / 12 / 24 小时或每周）与每日偏好备份时刻（`DatePicker`）、App 退入后台有变更自动快照（`BGAppRefreshTask` + `scenePhase`）、最大保留份数自动轮转清理（已置顶快照永久受保护）。
  - **本地数据管理中心**：直观查看待办数、快照数与磁盘占用字节；支持任意快照预览任务摘要、一键回滚、置顶保护、单条清理已完成任务、去重清理、清空对话与二次确认重置；开启 `UIFileSharingEnabled` 直通系统 **「文件」App**。
- **iPhone & iPad 双端原生形态 (`AdaptiveWorkspaceView`)**
  - **iPhone**：底部悬浮三态液态玻璃胶囊导航（`自己做` / `AI 帮做` / `本地数据`），完整单手手势。
  - **iPad**：原生三栏 `NavigationSplitView` + 分屏/台前调度自适应布局 + `⌘N` / `⌘F` / `⌘B` 键盘快捷键与右侧实时细节/专注栏。

---

## 仓库结构

```text
pickplan-ios/
├── Package.swift                 # Swift 6 Package (iOS 17+ / macOS 14+，含 Resources)
├── PickPlan.xcodeproj/           # Universal iPhone & iPad 原生工程 + 共享 Scheme
├── App/                          # iOS/iPadOS App 入口、Assets（AppIcon + BrandLogo）、Info.plist
├── Sources/
│   ├── PickPlanCore/             # 核心模型、6分组引擎、SHA256备份/定时调度、离线大白话、AI 客户端、双通知调度
│   ├── PickPlanUI/               # 原生 SwiftUI 液态玻璃主题、开屏、手动/AI/数据金库界面、Resources/pickplanlogo.jpg
│   └── PickPlanPreviewApp/       # macOS SwiftPM 桌面预览入口
├── Tests/
│   └── PickPlanCoreTests/        # 全套 XCTest/Swift Testing 单元测试（含 Android v1 兼容性与草稿单条编辑测试）
├── scripts/
│   ├── run_tests.sh              # 兼容 CommandLineTools 与完整 Xcode 的测试运行脚本
│   └── build_unsigned_ipa.sh     # 打包免签 PickPlan-Unsigned.ipa 供 SideStore / Sideloadly 安装
├── docs/
│   ├── ANDROID_ANALYSIS_AND_IOS_ARCHITECTURE.md
│   └── ci/build-unsigned-ipa.yml # GitHub Actions macOS 云端打包 .ipa 模板
└── SIDELOAD_GUIDE.md             # 零 $99 开发者费用安装全攻略
```

---

## 构建、测试与安装

```bash
# 1. 编译库并运行完整单元测试（自动兼容 Swift CommandLineTools 与 Xcode）
swift build
./scripts/run_tests.sh

# 2. 在装有 Xcode 的 Mac 上直接连接 iPhone / iPad 运行（使用免费 Personal Team Apple ID）
open PickPlan.xcodeproj

# 3. 或生成未签名 .ipa 安装包（配合 SideStore / AltStore / Sideloadly 安装）
./scripts/build_unsigned_ipa.sh
```

详细零费用安装步骤（含 GitHub Actions 云端自动构建 `.ipa` 方案）请查阅 [SIDELOAD_GUIDE.md](./SIDELOAD_GUIDE.md)。
