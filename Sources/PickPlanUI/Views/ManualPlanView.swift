import SwiftUI
import PickPlanCore

/// Faithful Liquid Glass port of Android Pickplan's `ManualModeView`:
/// - Header: `Pickplan`, Notification Test, Refresh, Language Pill (`中`/`EN`), Settings
/// - 6 smart sections: 已逾期, 今天, 明天, 之后, 无时间, 已完成
/// - Cards: square checkbox, bold title, reminder & coral deadline badges, trailing delete button + swipe/context actions
/// - Floating `+ 新任务` / `+ New` Liquid Glass button
public struct ManualPlanView: View {
    @ObservedObject private var store: PlanStore
    @Binding private var searchQuery: String
    @Binding private var tagFilter: TodoTag?
    @Binding private var sectionFilter: TimeSectionKind?
    @Binding private var selectedTodoId: String?

    private let onCreateTodo: () -> Void
    private let onEditTodo: (TodoItem) -> Void
    private let onStartFocus: (TodoItem) -> Void

    @State private var showTagBar = false

    public init(
        store: PlanStore,
        searchQuery: Binding<String>,
        tagFilter: Binding<TodoTag?>,
        sectionFilter: Binding<TimeSectionKind?>,
        selectedTodoId: Binding<String?>,
        onCreateTodo: @escaping () -> Void,
        onEditTodo: @escaping (TodoItem) -> Void,
        onStartFocus: @escaping (TodoItem) -> Void
    ) {
        self.store = store
        self._searchQuery = searchQuery
        self._tagFilter = tagFilter
        self._sectionFilter = sectionFilter
        self._selectedTodoId = selectedTodoId
        self.onCreateTodo = onCreateTodo
        self.onEditTodo = onEditTodo
        self.onStartFocus = onStartFocus
    }

    public var body: some View {
        let sections = store.sections(
            query: searchQuery,
            tag: tagFilter,
            sectionFilter: sectionFilter
        )

        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if showTagBar || tagFilter != nil || sectionFilter != nil {
                        tagFilterBar
                    }

                    if sections.isEmpty {
                        emptyStateCard
                    } else {
                        ForEach(sections) { section in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 8) {
                                    Image(systemName: section.kind.symbolName)
                                        .font(.system(size: 14))
                                        .foregroundStyle(section.kind == .overdue ? PickPlanPalette.deadlineCoral : Color.white.opacity(0.70))
                                    Text(section.kind.title(language: store.language))
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(Color.white.opacity(0.70))
                                    Text("\(section.todos.count)")
                                        .font(.system(size: 12))
                                        .foregroundStyle(PickPlanPalette.subtle)
                                    Spacer()
                                    if section.kind == .overdue || sections.first?.id == section.id {
                                        Button {
                                            withAnimation(PickPlanPalette.quickSpring) {
                                                showTagBar.toggle()
                                            }
                                        } label: {
                                            Image(systemName: "line.3.horizontal.decrease.circle")
                                                .font(.caption)
                                                .foregroundStyle(PickPlanPalette.muted)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 4)
                                .padding(.top, 8)

                                ForEach(section.todos) { todo in
                                    todoRow(todo)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)
                .padding(.bottom, 128)
            }
            .searchable(
                text: $searchQuery,
                prompt: AppLocalizer.t(zh: "搜索待办或备注…", en: "Search tasks or notes…", language: store.language)
            )
            .navigationTitle("Pickplan")
            .refreshable {
                await store.reload()
            }

            // Floating `+ 新任务` / `+ New` Liquid Glass button matching Android FloatingActionButton
            Button {
                HapticsBridge.impact(store.preferences.hapticsEnabled, style: 1)
                onCreateTodo()
            } label: {
                Label(
                    AppLocalizer.t(zh: "新任务", en: "New", language: store.language),
                    systemImage: "plus"
                )
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.black)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: .black.opacity(0.45), radius: 14, y: 6)
            }
            .buttonStyle(PickPlanPressScaleStyle())
            .padding(.trailing, 18)
            .padding(.bottom, 86)
        }
    }

    private var tagFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                tagPill(
                    title: AppLocalizer.t(zh: "全部", en: "All", language: store.language),
                    selected: tagFilter == nil && sectionFilter == nil
                ) {
                    withAnimation(PickPlanPalette.quickSpring) {
                        tagFilter = nil
                        sectionFilter = nil
                    }
                }

                ForEach(TodoTag.allCases.filter { $0 != .none }) { tag in
                    tagPill(
                        title: tag.displayName(language: store.language),
                        selected: tagFilter == tag
                    ) {
                        withAnimation(PickPlanPalette.quickSpring) {
                            tagFilter = tagFilter == tag ? nil : tag
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func tagPill(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.bold())
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .foregroundStyle(selected ? .black : .white)
                .background {
                    if selected {
                        Capsule().fill(Color.white)
                    } else {
                        Capsule().fill(Color.clear).pickPlanGlass(in: Capsule(), interactive: true)
                    }
                }
        }
        .buttonStyle(PickPlanPressScaleStyle())
    }

    private func todoRow(_ todo: TodoItem) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                HapticsBridge.impact(store.preferences.hapticsEnabled, style: 0)
                Task { await store.toggleCompletion(id: todo.id) }
            } label: {
                Image(systemName: todo.isCompleted ? "checkmark.square.fill" : "square")
                    .font(.system(size: 21))
                    .foregroundStyle(todo.isCompleted ? .white : Color.white.opacity(0.54))
            }
            .buttonStyle(PickPlanPressScaleStyle(pressedScale: 0.90))

            VStack(alignment: .leading, spacing: 6) {
                Text(todo.title)
                    .font(.body.weight(.bold))
                    .strikethrough(todo.isCompleted)
                    .foregroundStyle(todo.isCompleted ? Color.gray : .white)

                if !todo.notes.isEmpty {
                    Text(todo.notes)
                        .font(.caption)
                        .foregroundStyle(PickPlanPalette.muted)
                        .lineLimit(2)
                }

                if todo.reminderTime != nil || todo.deadline != nil || todo.tag != .none || !todo.subtasks.isEmpty {
                    HStack(spacing: 8) {
                        if let reminder = todo.reminderTime {
                            Label(PickPlanDateCodec.formatDisplayDateTime(reminder), systemImage: "bell.badge.fill")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.white)
                        }
                        if let deadline = todo.deadline {
                            Label(PickPlanDateCodec.formatDisplayDateTime(deadline), systemImage: "flag.fill")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(PickPlanPalette.deadlineCoral)
                        }
                        if todo.tag != .none {
                            Text(todo.tag.displayName(language: store.language))
                                .font(.caption2.bold())
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.12), in: Capsule())
                        }
                        if !todo.subtasks.isEmpty {
                            let done = todo.subtasks.filter(\.isCompleted).count
                            Label("\(done)/\(todo.subtasks.count)", systemImage: "checklist")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(PickPlanPalette.muted)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                selectedTodoId = todo.id
                onEditTodo(todo)
            }

            // Direct 1-tap Delete action matching Android Card trailing IconButton
            Button {
                HapticsBridge.impact(store.preferences.hapticsEnabled, style: 1)
                Task { await store.deleteTodo(id: todo.id) }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.gray)
                    .padding(6)
            }
            .buttonStyle(PickPlanPressScaleStyle(pressedScale: 0.90))
            .accessibilityLabel(AppLocalizer.t(zh: "删除", en: "Delete", language: store.language))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .pickPlanGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            if selectedTodoId == todo.id {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.65), lineWidth: 1.4)
            }
        }
        .contextMenu {
            Button(AppLocalizer.t(zh: "编辑任务", en: "Edit", language: store.language)) {
                onEditTodo(todo)
            }
            Button(AppLocalizer.t(zh: "开启 25 分钟专注", en: "Focus 25 min", language: store.language)) {
                onStartFocus(todo)
            }
            Button(AppLocalizer.t(zh: "删除", en: "Delete", language: store.language), role: .destructive) {
                Task { await store.deleteTodo(id: todo.id) }
            }
        }
        .animation(PickPlanPalette.springAnimation, value: todo.isCompleted)
    }

    private var emptyStateCard: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 60)
            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                .font(.system(size: 46))
                .foregroundStyle(Color.white.opacity(0.38))
            Text(
                AppLocalizer.t(
                    zh: "还没有任务。\n点 + 写下下一件要做的事。",
                    en: "No tasks yet.\nTap + and write the next thing to do.",
                    language: store.language
                )
            )
            .font(.subheadline)
            .foregroundStyle(Color.gray.opacity(0.85))
            .multilineTextAlignment(.center)
            .lineSpacing(5)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }
}
