# Pickplan iOS & iPadOS · Liquid Glass Edition

<p align="left">
  <strong>做计划，说大白话。如今凝成液态玻璃。</strong><br>
  <em>Plan in plain words. Refracted in iOS 26 Liquid Glass.</em>
</p>

Pickplan iOS & iPadOS 是从 Android 原版 [`smartlotus/pickplan`](https://github.com/smartlotus/pickplan) 深度演进与原生重构的作品。保留标志性的**极简黑白高对比美学**与**无账号本地优先哲学**，专为 **iPhone** 与 **iPad**（包括 iPad Split View / Stage Manager / 键盘快捷键）重塑为 **iOS 26 液态玻璃（Liquid Glass）**体验，且**无需 $99 付费开发者账号**即可零成本使用。

---

## 核心升级与功能矩阵

- **iOS 26 原生液态玻璃交互 (`LiquidGlassTheme`)**
  - 当编译/运行环境为 iOS 26+ 时自动启用原生 `GlassEffectContainer`、`.glassEffect(.regular.interactive(), in:)`、`.glassEffectID(_:in:)` 形变胶囊导航与浮动撤销 Toast；在 iOS 18 上自动优雅降级为 `.ultraThinMaterial` 高光玻璃材质。
  - 微光单色环境场背景（`AmbientMonochromeCanvas`）搭配触感反馈（`UIImpactFeedbackGenerator`）与物理弹簧动画（支持 `Reduce Motion`）。
- **iPhone 与 iPad 双端专属适配**
  - **iPhone**：单手友好的底部悬浮液态玻璃形变胶囊栏 + 全手势交互（右滑完成 / 左滑删除）。
  - **iPad**：原生三栏 `NavigationSplitView`（侧边智能分组 & 数据状态栏 / 任务流 / 右侧实时详情或大白话拆解台），支持 `⌘N`、`⌘F`、`⌘B`、`⌘E`、`⌘I` 键盘快捷键与四方向多任务分屏。
- **自己做 & AI 帮做（在线 BYOK + 离线大白话解析）**
  - 内置 **7 大 AI 预设**：DeepSeek、Kimi (Moonshot)、通义千问 (Tongyi Qwen)、智谱 GLM、SiliconFlow、OpenAI 与 Custom，兼容原 Android 全部提示词与测试连接功能。
  - **离线大白话拆解器 (`PlainWordsParser`)**：无需 API Key、完全断网时也可把 `"明天上午买菜，下午三点开会，周五前交报告"` 自动拆分为带提醒/截止时间的任务草稿，先编辑确认再加入。
  - **专注模式 (`FocusOverlayView`)**：单任务极简番茄/正计时浮层，与待办卡片无缝联动。
- **本地数据金库 (`LocalVaultStore`) —— 导入导出、定时自动备份与数据管理**
  - **全量本地导入导出**：导出带 SHA256 完整性校验的 `.pickplan.json`（v2 信封格式，可选是否包含 API Key）或可读 Markdown；支持无损导入原 Android v1 JSON 数组及 v2 备份，并提供 **智能合并 / 追加副本 / 安全覆盖（覆盖前强制自动建快照）** 三种策略与导入前摘要预览。
  - **定时自动本地备份**：可开关、可设周期（每 1 / 6 / 12 / 24 小时或每周）、切后台有变更自动快照（`BGAppRefreshTask` + `scenePhase`）、自定义保留上限（置顶快照受保护不被轮转清理），一键在系统 **「文件 (Files)」** App 访问 `Pickplan/Backups`。
  - **本地数据管理面板**：直观存储占用分析、快照时间线预览与一键回滚、置顶保护、清理已完成任务、去重校验、清空 AI 对话、二次确认重置。

---

## 仓库结构

```text
pickplan-ios/
├── Package.swift                 # Swift 6 Package (PickPlanCore + PickPlanUI + PreviewApp + Tests)
├── PickPlan.xcodeproj/           # 免付费权限的 iOS & iPadOS 通用工程 (Targeted Device Family 1,2)
├── App/                          # iOS/iPadOS App 入口、Info.plist（开启 Files 共享）、AppIcon 资源
├── Sources/
│   ├── PickPlanCore/             # 跨平台核心：数据模型、SHA256 备份引擎、定时快照、大白话离线解析、AI 客户端
│   ├── PickPlanUI/               # SwiftUI 液态玻璃主题、iPhone/iPad 自适应工作台、数据金库面板
│   └── PickPlanPreviewApp/       # macOS SwiftPM 预览可运行入口
├── Tests/
│   └── PickPlanCoreTests/        # 备份、校验、轮转清理、Android v1 兼容、大白话解析单元测试
├── scripts/
│   └── build_unsigned_ipa.sh     # 打包免签 .ipa 供 SideStore / LiveContainer 安装
├── docs/
│   ├── ANDROID_ANALYSIS_AND_IOS_ARCHITECTURE.md
│   └── ci/build-unsigned-ipa.yml # 可选的 GitHub Actions macOS 自动打包模板
└── SIDELOAD_GUIDE.md             # 零 $99 开发者费用安装全攻略
```

---

## 本地构建与测试

```bash
# 1. 在任意装有 Swift 6 的 Mac 上验证核心引擎、UI 编译与全部单元测试
swift build
swift test

# 2. 在装有 Xcode 的 Mac 上打开 PickPlan.xcodeproj 运行到 iPhone/iPad（免费 Personal Team）
open PickPlan.xcodeproj

# 3. 或生成未签名 .ipa 供 SideStore / LiveContainer 无线侧载
./scripts/build_unsigned_ipa.sh
```

更多免 $99 安装说明，请阅读 [SIDELOAD_GUIDE.md](./SIDELOAD_GUIDE.md)。
