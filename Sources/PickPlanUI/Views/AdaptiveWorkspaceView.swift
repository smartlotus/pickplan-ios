import SwiftUI
import PickPlanCore

/// Primary adaptive workspace:
/// - iPhone (compact): full-bleed views with floating morphing `GlassEffectContainer` capsule dock
/// - iPad / macOS (regular): 3-column `NavigationSplitView` + keyboard shortcuts + live Focus/Inspector column
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
            case .vault: return AppLocalizer.t(zh: "数据金库", en: "Vault", language: language)
            }
        }

        var symbol: String {
            switch self {
            case .manual: return "checklist"
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
    }

    // MARK: - iPhone Compact Layout (Morphing Liquid Glass Capsule Dock)

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
                            onEditTodo: { editingTodo = $0 },
                            onStartFocus: { todo in
                                Task {
                                    await store.startFocus(forTodoId: todo.id)
                                    showFocusModal = true
                                }
                            }
                        )
                    case .ai:
                        AIPlanBuilderView(store: store)
                    case .vault:
                        DataVaultView(store: store)
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .automatic) {
                        HStack(spacing: 8) {
                            if store.activeFocusTodoId != nil {
                                Button {
                                    showFocusModal = true
                                } label: {
                                    Label(formatFocusClock(store.focusRemainingSeconds), systemImage: "timer")
                                        .font(.caption.monospacedDigit().bold())
                                }
                            }
                            Button {
                                Task {
                                    let next: AppLanguage = store.language == .zh ? .en : .zh
                                    await store.setLanguage(next)
                                }
                            } label: {
                                Text(store.language == .zh ? "中" : "EN")
                                    .font(.caption.bold())
                            }
                            Button {
                                showSettingsSheet = true
                            } label: {
                                Image(systemName: "gearshape")
                            }
                        }
                    }
                }
            }

            // Floating Liquid Glass Capsule Bar + Morphing + Orb
            PickPlanGlassGroup(spacing: 16) {
                HStack(spacing: 12) {
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
                                        .font(.system(size: 10, weight: .semibold))
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

                    Button {
                        HapticsBridge.impact(store.preferences.hapticsEnabled, style: 1)
                        showCreateSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 54, height: 54)
                    }
                    .pickPlanGlass(in: Circle(), interactive: true)
                    .pickPlanGlassID("primaryAddOrb", in: glassNamespace)
                    .accessibilityLabel(AppLocalizer.t(zh: "新建任务", en: "New Task", language: store.language))
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
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
                        onEditTodo: { editingTodo = $0 },
                        onStartFocus: { todo in
                            Task { await store.startFocus(forTodoId: todo.id) }
                        }
                    )
                case .ai:
                    AIPlanBuilderView(store: store)
                case .vault:
                    DataVaultView(store: store)
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .automatic) {
                    Button {
                        showCreateSheet = true
                    } label: {
                        Label(AppLocalizer.t(zh: "新建", en: "New", language: store.language), systemImage: "plus")
                    }
                    .keyboardShortcut("n", modifiers: .command)

                    Button {
                        Task { await store.createManualSnapshot() }
                    } label: {
                        Label(AppLocalizer.t(zh: "立即备份", en: "Backup", language: store.language), systemImage: "externaldrive.badge.plus")
                    }
                    .keyboardShortcut("b", modifiers: .command)

                    Button {
                        Task {
                            let next: AppLanguage = store.language == .zh ? .en : .zh
                            await store.setLanguage(next)
                        }
                    } label: {
                        Text(store.language == .zh ? "中" : "EN")
                            .font(.caption.bold())
                    }

                    Button {
                        showSettingsSheet = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
        } detail: {
            iPadInspectorColumn
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
                    Text(AppLocalizer.t(zh: "已删除「\(deleted.title)」", en: "Deleted \"\(deleted.title)\"", language: store.language))
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
                .padding(.bottom, isRegularLayout ? 18 : 84)
                .transition(.move(edge: .bottom).combined(with: .opacity))
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
                .padding(.bottom, isRegularLayout ? 18 : 84)
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
