import SwiftUI
import PickPlanCore

/// Adaptive iPhone & iPad workspace faithfully unifying Android Pickplan's Manual + AI workflow
/// with native Liquid Glass navigation, notification testing, scheduled local backup Vault, and Focus Timer.
public struct AdaptiveWorkspaceView: View {
    public enum WorkspaceTab: String, CaseIterable, Identifiable {
        case manual
        case ai
        case vault

        public var id: String { rawValue }

        func title(language: AppLanguage) -> String {
            switch self {
            case .manual: return AppLocalizer.t(zh: "自己做", en: "Manual", language: language)
            case .ai: return AppLocalizer.t(zh: "AI 帮做", en: "AI", language: language)
            case .vault: return AppLocalizer.t(zh: "本地数据", en: "Data", language: language)
            }
        }

        var symbol: String {
            switch self {
            case .manual: return "list.bullet.rectangle"
            case .ai: return "sparkles"
            case .vault: return "externaldrive.badge.timemachine"
            }
        }
    }

    @ObservedObject private var store: PlanStore
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @Namespace private var glassNamespace

    @State private var activeTab: WorkspaceTab = .manual
    @State private var sectionFilter: TimeSectionKind? = nil
    @State private var tagFilter: TodoTag? = nil
    @State private var searchQuery: String = ""
    @State private var selectedTodoId: String? = nil
    @State private var editingTodo: TodoItem? = nil
    @State private var showCreateSheet: Bool = false
    @State private var showSettingsSheet: Bool = false
    @State private var showFocusModal: Bool = false
    @State private var showPermissionAlert: Bool = false
    @State private var refreshToastBanner: String? = nil

    public init(store: PlanStore) {
        self.store = store
    }

    private var isRegularLayout: Bool {
        #if os(iOS)
        return horizontalSizeClass == .regular
        #else
        return true
        #endif
    }

    public var body: some View {
        ZStack {
            AmbientMonochromeCanvas()

            if isRegularLayout {
                iPadThreeColumnLayout
            } else {
                iPhoneCompactLayout
            }

            floatingToasts
        }
        .sheet(isPresented: $showCreateSheet) {
            TodoEditorSheet(store: store, initialTodo: nil)
        }
        .sheet(item: $editingTodo) { todo in
            TodoEditorSheet(store: store, initialTodo: todo)
        }
        .sheet(isPresented: $showSettingsSheet) {
            SettingsSheetView(store: store)
        }
        .sheet(isPresented: $showFocusModal) {
            FocusOverlayView(store: store)
        }
        .alert(
            AppLocalizer.t(zh: "通知未开启", en: "Notifications disabled", language: store.language),
            isPresented: $showPermissionAlert
        ) {
            Button(AppLocalizer.t(zh: "我知道了", en: "OK", language: store.language), role: .cancel) {}
        } message: {
            Text(
                AppLocalizer.t(
                    zh: "请在系统设置里开启 Pickplan 的通知权限，然后重试。",
                    en: "Enable notification permission for Pickplan in iOS Settings, then try again.",
                    language: store.language
                )
            )
        }
    }

    // MARK: - iPhone Compact Layout (Floating Liquid Glass Capsule Dock + Android AppBar Actions)

    private var iPhoneCompactLayout: some View {
        ZStack(alignment: .bottom) {
            NavigationStack {
                Group {
                    switch activeTab {
                    case .manual:
                        ManualPlanView(
                            store: store,
                            searchQuery: $searchQuery,
                            tagFilter: $tagFilter,
                            sectionFilter: $sectionFilter,
                            selectedTodoId: $selectedTodoId,
                            onCreateTodo: { showCreateSheet = true },
                            onEditTodo: { editingTodo = $0 },
                            onStartFocus: { todo in
                                Task {
                                    await store.startFocus(forTodoId: todo.id)
                                    showFocusModal = true
                                }
                            }
                        )
                    case .ai:
                        AIPlanBuilderView(store: store, onOpenSettings: { showSettingsSheet = true })
                    case .vault:
                        DataVaultView(store: store)
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .automatic) {
                        sharedToolbarActions
                    }
                }
            }

            // Floating Liquid Glass Capsule Bar
            PickPlanGlassGroup(spacing: 14) {
                HStack(spacing: 4) {
                    ForEach(WorkspaceTab.allCases) { tab in
                        Button {
                            HapticsBridge.impact(store.preferences.hapticsEnabled, style: 0)
                            withAnimation(PickPlanPalette.springAnimation) {
                                activeTab = tab
                            }
                        } label: {
                            VStack(spacing: 3) {
                                Image(systemName: tab.symbol)
                                    .font(.system(size: 16, weight: .semibold))
                                Text(tab.title(language: store.language))
                                    .font(.system(size: 10.5, weight: .semibold))
                            }
                            .foregroundStyle(activeTab == tab ? .white : PickPlanPalette.muted)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background {
                                if activeTab == tab {
                                    Capsule()
                                        .fill(Color.white.opacity(0.18))
                                        .pickPlanGlassID("activeTabIndicator", in: glassNamespace)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(5)
                .pickPlanGlass(in: Capsule(), interactive: true)
                .padding(.horizontal, 28)
                .padding(.bottom, 8)
            }
        }
    }

    // MARK: - iPad / Desktop 3-Column NavigationSplitView

    private var iPadThreeColumnLayout: some View {
        NavigationSplitView {
            List {
                Section(AppLocalizer.t(zh: "工作区", en: "Workspace", language: store.language)) {
                    ForEach(WorkspaceTab.allCases) { tab in
                        Button {
                            withAnimation(PickPlanPalette.springAnimation) {
                                activeTab = tab
                            }
                        } label: {
                            HStack {
                                Label(tab.title(language: store.language), systemImage: tab.symbol)
                                Spacer()
                                if tab == .manual {
                                    Text("\(store.storageBreakdown.activeTodos)")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(PickPlanPalette.muted)
                                } else if tab == .vault {
                                    Text("\(store.snapshots.count)")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(PickPlanPalette.muted)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .listRowBackground(activeTab == tab ? Color.white.opacity(0.14) : Color.clear)
                    }
                }

                Section(AppLocalizer.t(zh: "智能时间分组", en: "Smart Sections", language: store.language)) {
                    Button {
                        activeTab = .manual
                        sectionFilter = nil
                    } label: {
                        HStack {
                            Label(AppLocalizer.t(zh: "全部任务", en: "All", language: store.language), systemImage: "tray.2")
                            Spacer()
                            Text("\(store.todos.count)").font(.caption.monospacedDigit())
                        }
                    }
                    ForEach(TimeSectionKind.allCases) { kind in
                        Button {
                            activeTab = .manual
                            sectionFilter = kind
                        } label: {
                            Label(kind.title(language: store.language), systemImage: kind.symbolName)
                        }
                        .listRowBackground(sectionFilter == kind ? Color.white.opacity(0.12) : Color.clear)
                    }
                }

                Section(AppLocalizer.t(zh: "自动本地备份", en: "Auto-Backup", language: store.language)) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(store.preferences.backupPolicy.isEnabled
                                 ? AppLocalizer.t(zh: "已开启", en: "Active", language: store.language)
                                 : AppLocalizer.t(zh: "已暂停", en: "Paused", language: store.language))
                            .font(.subheadline.bold())
                            Spacer()
                            Button(AppLocalizer.t(zh: "备份", en: "Now", language: store.language)) {
                                Task { await store.createManualSnapshot() }
                            }
                            .font(.caption.bold())
                            .buttonStyle(.bordered)
                        }
                        if let last = store.preferences.lastBackupAt {
                            Text(PickPlanDateCodec.formatDisplayDateTime(last))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(PickPlanPalette.muted)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Pickplan")
        } content: {
            Group {
                switch activeTab {
                case .manual:
                    ManualPlanView(
                        store: store,
                        searchQuery: $searchQuery,
                        tagFilter: $tagFilter,
                        sectionFilter: $sectionFilter,
                        selectedTodoId: $selectedTodoId,
                        onCreateTodo: { showCreateSheet = true },
                        onEditTodo: { editingTodo = $0 },
                        onStartFocus: { todo in
                            Task { await store.startFocus(forTodoId: todo.id) }
                        }
                    )
                case .ai:
                    AIPlanBuilderView(store: store, onOpenSettings: { showSettingsSheet = true })
                case .vault:
                    DataVaultView(store: store)
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .automatic) {
                    sharedToolbarActions
                }
            }
        } detail: {
            iPadInspectorColumn
        }
    }

    private var sharedToolbarActions: some View {
        HStack(spacing: 8) {
            if store.activeFocusTodoId != nil {
                Button {
                    showFocusModal = true
                } label: {
                    Label(formatFocusClock(store.focusRemainingSeconds), systemImage: "timer")
                        .font(.caption.monospacedDigit().bold())
                }
            }

            if activeTab == .manual {
                Button {
                    Task {
                        let ok = await store.sendTestNotification()
                        if !ok {
                            showPermissionAlert = true
                        }
                    }
                } label: {
                    Image(systemName: "bell.badge")
                }
                .accessibilityLabel(AppLocalizer.t(zh: "测试通知", en: "Test notifications", language: store.language))

                Button {
                    Task {
                        await store.reload()
                        refreshToastBanner = AppLocalizer.t(zh: "已刷新待办列表。", en: "Todo list refreshed.", language: store.language)
                        try? await Task.sleep(for: .seconds(2))
                        refreshToastBanner = nil
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: .command)
                .accessibilityLabel(AppLocalizer.t(zh: "刷新", en: "Refresh", language: store.language))
            }

            Button {
                Task {
                    let next: AppLanguage = store.language == .zh ? .en : .zh
                    await store.setLanguage(next)
                }
            } label: {
                Text(store.language == .zh ? "中" : "EN")
                    .font(.system(size: 12, weight: .bold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.38), lineWidth: 1))
            }
            .buttonStyle(.plain)

            Button {
                showSettingsSheet = true
            } label: {
                Image(systemName: "gearshape")
            }
            .keyboardShortcut(",", modifiers: .command)
            .accessibilityLabel(AppLocalizer.t(zh: "设置", en: "Settings", language: store.language))
        }
    }

    private var iPadInspectorColumn: some View {
        ScrollView {
            VStack(spacing: 18) {
                FocusOverlayView(store: store, embedded: true)

                if let selectedId = selectedTodoId,
                   let todo = store.todos.first(where: { $0.id == selectedId }) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(AppLocalizer.t(zh: "选中任务详情", en: "Selected Task", language: store.language))
                            .font(.caption.bold())
                            .foregroundStyle(PickPlanPalette.muted)
                        Text(todo.title)
                            .font(.title3.bold())
                        if !todo.notes.isEmpty {
                            Text(todo.notes)
                                .font(.subheadline)
                                .foregroundStyle(PickPlanPalette.muted)
                        }
                        if !todo.subtasks.isEmpty {
                            Divider().overlay(Color.white.opacity(0.15))
                            ForEach(todo.subtasks) { sub in
                                Button {
                                    Task { await store.toggleSubtask(todoId: todo.id, subtaskId: sub.id) }
                                } label: {
                                    HStack {
                                        Image(systemName: sub.isCompleted ? "checkmark.square.fill" : "square")
                                        Text(sub.title)
                                            .strikethrough(sub.isCompleted)
                                        Spacer()
                                    }
                                    .foregroundStyle(sub.isCompleted ? PickPlanPalette.muted : .white)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        HStack {
                            Button(AppLocalizer.t(zh: "编辑", en: "Edit", language: store.language)) {
                                editingTodo = todo
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.white)
                            .foregroundStyle(.black)

                            Button(AppLocalizer.t(zh: "开始专注", en: "Focus", language: store.language)) {
                                Task { await store.startFocus(forTodoId: todo.id) }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(18)
                    .pickPlanGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
            }
            .padding(20)
        }
        .background(AmbientMonochromeCanvas())
    }

    // MARK: - Floating Liquid Glass Undo & Status Toast

    private var floatingToasts: some View {
        VStack(spacing: 10) {
            Spacer()
            if let deleted = store.lastDeletedTodo {
                HStack(spacing: 12) {
                    Text(AppLocalizer.t(zh: "已删除任务「\(deleted.title)」", en: "Deleted \"\(deleted.title)\"", language: store.language))
                        .font(.subheadline)
                        .lineLimit(1)
                    Spacer()
                    Button(AppLocalizer.t(zh: "撤销", en: "Undo", language: store.language)) {
                        HapticsBridge.success(store.preferences.hapticsEnabled)
                        Task { await store.undoLastDelete() }
                    }
                    .font(.subheadline.bold())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.white, in: Capsule())
                    .foregroundStyle(.black)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .pickPlanGlass(in: Capsule(), interactive: true)
                .padding(.horizontal, 18)
                .padding(.bottom, isRegularLayout ? 18 : 82)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if let refreshMsg = refreshToastBanner {
                Text(refreshMsg)
                    .font(.subheadline)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .pickPlanGlass(in: Capsule())
                    .padding(.bottom, isRegularLayout ? 18 : 82)
            } else if let banner = store.lastStatusBanner {
                HStack(spacing: 10) {
                    Image(systemName: banner.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(banner.isError ? PickPlanPalette.deadlineCoral : .white)
                    Text(banner.message)
                        .font(.subheadline)
                        .lineLimit(2)
                    Spacer()
                    Button {
                        store.dismissStatusBanner()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption.bold())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .pickPlanGlass(in: Capsule(), interactive: true)
                .padding(.horizontal, 18)
                .padding(.bottom, isRegularLayout ? 18 : 82)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(PickPlanPalette.springAnimation, value: store.lastDeletedTodo?.id)
        .animation(PickPlanPalette.springAnimation, value: store.lastStatusBanner?.id)
    }

    private func formatFocusClock(_ seconds: Int) -> String {
        let mins = max(0, seconds) / 60
        let secs = max(0, seconds) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}
