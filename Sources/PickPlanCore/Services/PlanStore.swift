import Combine
import Foundation

/// Transient toast/banner surfaced to the UI layer by `PlanStore`.
public struct StatusBanner: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let message: String
    public let isError: Bool

    public init(id: UUID = UUID(), message: String, isError: Bool = false) {
        self.id = id
        self.message = message
        self.isError = isError
    }
}

/// Main-actor observable application store bridging `LocalVaultStore`, `SmartSectionEngine`,
/// `PlainWordsParser`, `AIService`, Pomodoro focus timer, and `NotificationCoordinator`.
@MainActor
public final class PlanStore: ObservableObject {
    @Published public private(set) var todos: [TodoItem] = []
    @Published public private(set) var aiSettings: AISettingsRecord = AISettingsRecord()
    @Published public private(set) var preferences: AppPreferencesRecord = AppPreferencesRecord()
    @Published public private(set) var chatHistory: [ChatHistoryEntry] = []
    @Published public private(set) var snapshots: [BackupSnapshotMetadata] = []
    @Published public private(set) var storageBreakdown: StorageBreakdown = StorageBreakdown()
    @Published public private(set) var lastDeletedTodo: TodoItem? = nil
    @Published public private(set) var activeFocusTodoId: String? = nil
    @Published public private(set) var focusRemainingSeconds: Int = 25 * 60
    @Published public private(set) var isFocusRunning: Bool = false
    @Published public private(set) var isLoadingAI: Bool = false
    @Published public var lastStatusBanner: StatusBanner? = nil

    public let vault: LocalVaultStore
    public let aiService: AIService
    public let notifications: NotificationCoordinator

    private var focusTotalSeconds: Int = 25 * 60
    private var focusTimerTask: Task<Void, Never>?

    public init(
        vault: LocalVaultStore = LocalVaultStore(),
        aiService: AIService = AIService(),
        notifications: NotificationCoordinator = NotificationCoordinator()
    ) {
        self.vault = vault
        self.aiService = aiService
        self.notifications = notifications
        refreshFromVault()
    }

    deinit {
        focusTimerTask?.cancel()
    }

    // MARK: - Derived View Helpers

    public var language: AppLanguage {
        AppLanguage.from(code: preferences.languageCode)
    }

    public var activeFocusTodo: TodoItem? {
        guard let activeFocusTodoId else { return nil }
        return todos.first { $0.id == activeFocusTodoId }
    }

    public var focusTotalDurationSeconds: Int {
        focusTotalSeconds
    }

    public func sections(
        query: String = "",
        tag: TodoTag? = nil,
        sectionFilter: TimeSectionKind? = nil,
        now: Date = Date()
    ) -> [TodoSection] {
        let filtered = SmartSectionEngine.filterTodos(
            todos,
            query: query,
            tag: tag,
            sectionFilter: sectionFilter,
            now: now
        )
        return SmartSectionEngine.groupIntoSections(filtered, now: now)
    }

    // MARK: - Lifecycle & Refresh

    public func reload() async {
        refreshFromVault()
        await notifications.syncReminders(for: todos, language: language)
    }

    public func handleSceneDidEnterBackground() async {
        do {
            if let snapshot = try vault.evaluateScheduledBackup(now: Date(), isBackgroundTransition: true) {
                refreshFromVault()
                setBanner(
                    zh: "已自动创建后台保护快照（\(snapshot.taskCount) 项任务）",
                    en: "Auto-saved background backup snapshot (\(snapshot.taskCount) tasks)"
                )
            }
        } catch {
            setErrorBanner(error.localizedDescription)
        }
    }

    public func evaluateScheduledBackupIfNeeded() async {
        do {
            if try vault.evaluateScheduledBackup(now: Date(), isBackgroundTransition: false) != nil {
                refreshFromVault()
            }
        } catch {
            setErrorBanner(error.localizedDescription)
        }
    }

    @discardableResult
    public func requestNotificationPermission() async -> Bool {
        let granted = await notifications.requestAuthorization()
        if granted {
            await notifications.syncReminders(for: todos, language: language)
        }
        return granted
    }

    // MARK: - Todo CRUD & Undo

    @discardableResult
    public func addTodo(
        title: String,
        notes: String = "",
        subtasks: [SubtaskItem] = [],
        tag: TodoTag = .none,
        priority: TodoPriority = .normal,
        reminderTime: Date? = nil,
        deadline: Date? = nil
    ) async -> TodoItem {
        let now = Date()
        let item = TodoItem(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: notes,
            subtasks: subtasks,
            tag: tag,
            priority: priority,
            reminderTime: reminderTime,
            deadline: deadline,
            createdAt: now,
            updatedAt: now
        )
        vault.upsertTodo(item)
        refreshFromVault()
        await notifications.scheduleReminder(for: item, language: language)
        return item
    }

    public func addTodos(_ items: [TodoItem]) async {
        guard !items.isEmpty else { return }
        vault.addTodos(items)
        refreshFromVault()
        await notifications.syncReminders(for: todos, language: language)
    }

    public func updateTodo(_ todo: TodoItem) async {
        var updated = todo
        updated.updatedAt = Date()
        vault.upsertTodo(updated)
        refreshFromVault()
        await notifications.scheduleReminder(for: updated, language: language)
    }

    public func toggleCompletion(id: String) async {
        guard let updated = vault.toggleTodoCompletion(id: id, now: Date()) else { return }
        refreshFromVault()
        await notifications.scheduleReminder(for: updated, language: language)
    }

    public func toggleSubtask(todoId: String, subtaskId: String) async {
        _ = vault.toggleSubtask(todoId: todoId, subtaskId: subtaskId, now: Date())
        refreshFromVault()
    }

    public func deleteTodo(id: String) async {
        if activeFocusTodoId == id {
            await stopFocus(logElapsedMinutes: false)
        }
        if let removed = vault.deleteTodo(id: id) {
            lastDeletedTodo = removed
            refreshFromVault()
            await notifications.cancelReminder(forTodoId: id)
        }
    }

    public func undoLastDelete() async {
        guard let deleted = lastDeletedTodo else { return }
        lastDeletedTodo = nil
        vault.upsertTodo(deleted)
        refreshFromVault()
        await notifications.scheduleReminder(for: deleted, language: language)
        setBanner(zh: "已恢复任务「\(deleted.title)」", en: "Restored \"\(deleted.title)\"")
    }

    public func dismissUndo() async {
        lastDeletedTodo = nil
    }

    // MARK: - Plain Words & AI Chat

    @discardableResult
    public func quickParseAndAdd(_ input: String) async -> [TodoItem] {
        let parsed = PlainWordsParser.parse(input, referenceDate: Date())
        guard !parsed.isEmpty else { return [] }
        await addTodos(parsed)
        setBanner(
            zh: "已快速解析并添加 \(parsed.count) 项任务",
            en: "Quickly parsed & added \(parsed.count) task(s)"
        )
        return parsed
    }

    public func sendChatPrompt(_ text: String, preferAI: Bool = true) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let userEntry = ChatHistoryEntry(text: trimmed, isUser: true, createdAt: Date())
        vault.appendChatMessage(userEntry)
        refreshFromVault()

        let hasConfiguredKey = !(aiSettings.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let isCustomWithEndpoint = aiSettings.providerName.caseInsensitiveCompare("Custom") == .orderedSame
            && !aiSettings.baseUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !aiSettings.modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        if preferAI && (hasConfiguredKey || isCustomWithEndpoint) {
            isLoadingAI = true
            defer { isLoadingAI = false }
            do {
                let parsed = try await aiService.parseTodosFromText(
                    trimmed,
                    settings: aiSettings,
                    language: language,
                    referenceDate: Date()
                )
                let replyText = AppLocalizer.t(
                    zh: "已通过 \(aiSettings.modelName) 为你整理出 \(parsed.count) 条待办，确认后可一键加入清单。",
                    en: "Extracted \(parsed.count) task(s) via \(aiSettings.modelName). Review and add them below.",
                    language: language
                )
                let aiEntry = ChatHistoryEntry(
                    text: replyText,
                    isUser: false,
                    createdAt: Date(),
                    parsedTodos: parsed,
                    isAdded: false
                )
                vault.appendChatMessage(aiEntry)
                refreshFromVault()
                return
            } catch {
                let offlineParsed = PlainWordsParser.parse(trimmed, referenceDate: Date())
                let fallbackMsg = AppLocalizer.t(
                    zh: "云端 AI 请求失败（\(error.localizedDescription)），已使用本地离线引擎解析出 \(offlineParsed.count) 条待办。",
                    en: "Cloud AI failed (\(error.localizedDescription)). Parsed \(offlineParsed.count) task(s) offline instead.",
                    language: language
                )
                let aiEntry = ChatHistoryEntry(
                    text: fallbackMsg,
                    isUser: false,
                    createdAt: Date(),
                    parsedTodos: offlineParsed,
                    isAdded: false
                )
                vault.appendChatMessage(aiEntry)
                refreshFromVault()
                setErrorBanner(error.localizedDescription)
                return
            }
        }

        let offlineParsed = PlainWordsParser.parse(trimmed, referenceDate: Date())
        let replyText: String
        if offlineParsed.isEmpty {
            replyText = AppLocalizer.t(
                zh: "暂未识别到明确待办，请尝试描述具体的事项或时间（例如：明天下午三点开会）。",
                en: "Could not detect clear tasks yet. Try adding an action or time (e.g. Call client tomorrow at 3 PM).",
                language: language
            )
        } else {
            replyText = AppLocalizer.t(
                zh: "已使用本地智能解析提取 \(offlineParsed.count) 条待办（在设置中填写 API Key 可切换云端 AI 推理）。",
                en: "Parsed \(offlineParsed.count) task(s) offline (add an API key in Settings for cloud AI).",
                language: language
            )
        }
        let assistantEntry = ChatHistoryEntry(
            text: replyText,
            isUser: false,
            createdAt: Date(),
            parsedTodos: offlineParsed,
            isAdded: false
        )
        vault.appendChatMessage(assistantEntry)
        refreshFromVault()
    }

    public func addParsedTodosFromChat(messageId: String) async {
        guard let entry = chatHistory.first(where: { $0.id == messageId }),
              !entry.isAdded,
              !entry.parsedTodos.isEmpty
        else {
            return
        }
        vault.addTodos(entry.parsedTodos)
        vault.markChatTodosAdded(messageId: messageId)
        refreshFromVault()
        await notifications.syncReminders(for: todos, language: language)
        setBanner(
            zh: "已将 \(entry.parsedTodos.count) 条待办加入清单",
            en: "Added \(entry.parsedTodos.count) task(s) to your list"
        )
    }

    public func clearChatHistory() async {
        vault.clearChatHistory()
        refreshFromVault()
        setBanner(zh: "已清空 AI 对话记录", en: "Cleared chat history")
    }

    // MARK: - Pomodoro Focus Timer

    public func startFocus(forTodoId id: String, durationMinutes: Int = 25) async {
        focusTimerTask?.cancel()
        let seconds = max(60, durationMinutes * 60)
        activeFocusTodoId = id
        focusTotalSeconds = seconds
        focusRemainingSeconds = seconds
        isFocusRunning = true
        runFocusLoop()
    }

    public func pauseFocus() async {
        focusTimerTask?.cancel()
        focusTimerTask = nil
        isFocusRunning = false
    }

    public func resumeFocus() async {
        guard activeFocusTodoId != nil, focusRemainingSeconds > 0, !isFocusRunning else { return }
        isFocusRunning = true
        runFocusLoop()
    }

    public func stopFocus(logElapsedMinutes: Bool = true) async {
        focusTimerTask?.cancel()
        focusTimerTask = nil
        isFocusRunning = false

        if logElapsedMinutes, let todoId = activeFocusTodoId {
            let elapsedSeconds = max(0, focusTotalSeconds - focusRemainingSeconds)
            let loggedMinutes = elapsedSeconds / 60
            if loggedMinutes > 0 {
                _ = vault.logFocusMinutes(todoId: todoId, minutes: loggedMinutes, now: Date())
                refreshFromVault()
                setBanner(
                    zh: "已记录 \(loggedMinutes) 分钟专注时长",
                    en: "Logged \(loggedMinutes) focus minute(s)"
                )
            }
        }

        activeFocusTodoId = nil
        focusTotalSeconds = 25 * 60
        focusRemainingSeconds = 25 * 60
    }

    public func completeFocusSession() async {
        focusTimerTask?.cancel()
        focusTimerTask = nil
        isFocusRunning = false

        let completedMinutes = max(1, focusTotalSeconds / 60)
        if let todoId = activeFocusTodoId {
            _ = vault.logFocusMinutes(todoId: todoId, minutes: completedMinutes, now: Date())
            refreshFromVault()
        }
        setBanner(
            zh: "专注完成！已累计 \(completedMinutes) 分钟",
            en: "Focus session complete! Logged \(completedMinutes) min"
        )
        activeFocusTodoId = nil
        focusTotalSeconds = 25 * 60
        focusRemainingSeconds = 25 * 60
    }

    private func runFocusLoop() {
        focusTimerTask?.cancel()
        focusTimerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self, self.isFocusRunning else { break }
                if self.focusRemainingSeconds > 1 {
                    self.focusRemainingSeconds -= 1
                } else {
                    self.focusRemainingSeconds = 0
                    await self.completeFocusSession()
                    break
                }
            }
        }
    }

    // MARK: - Settings & Preferences

    public func updateAISettings(_ settings: AISettingsRecord) async {
        vault.updateAISettings(settings)
        refreshFromVault()
        setBanner(zh: "AI 配置已保存", en: "AI settings saved")
    }

    public func testAIConnection() async -> Result<String, Error> {
        isLoadingAI = true
        defer { isLoadingAI = false }
        do {
            let reply = try await aiService.testConnection(settings: aiSettings)
            setBanner(zh: "AI 连接成功：\(reply)", en: "AI connected: \(reply)")
            return .success(reply)
        } catch {
            setErrorBanner(error.localizedDescription)
            return .failure(error)
        }
    }

    public func setLanguage(_ newLanguage: AppLanguage) async {
        var prefs = vault.getPreferences()
        prefs.languageCode = newLanguage.rawValue
        vault.updatePreferences(prefs)
        refreshFromVault()
        await notifications.syncReminders(for: todos, language: newLanguage)
    }

    public func updateBackupPolicy(_ policy: BackupPolicy) async {
        var prefs = vault.getPreferences()
        prefs.backupPolicy = policy
        vault.updatePreferences(prefs)
        _ = vault.pruneSnapshotsIfNeeded()
        refreshFromVault()
    }

    public func setHapticsEnabled(_ enabled: Bool) async {
        var prefs = vault.getPreferences()
        prefs.hapticsEnabled = enabled
        vault.updatePreferences(prefs)
        refreshFromVault()
    }

    // MARK: - Backup, Snapshots, Import/Export & Hygiene

    @discardableResult
    public func createManualSnapshot(note: String = "") async -> BackupSnapshotMetadata? {
        do {
            let cleanNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedNote = cleanNote.isEmpty
                ? AppLocalizer.t(zh: "手动快照", en: "Manual snapshot", language: language)
                : cleanNote
            let metadata = try vault.createSnapshot(trigger: .manual, note: resolvedNote, now: Date())
            refreshFromVault()
            setBanner(zh: "已创建快照（\(metadata.taskCount) 项任务）", en: "Created snapshot (\(metadata.taskCount) tasks)")
            return metadata
        } catch {
            setErrorBanner(error.localizedDescription)
            return nil
        }
    }

    @discardableResult
    public func restoreSnapshot(id: String) async -> ImportResult? {
        do {
            let result = try vault.restoreSnapshot(id: id, now: Date())
            refreshFromVault()
            await notifications.syncReminders(for: todos, language: language)
            setBanner(
                zh: "已恢复快照（已先保存恢复前保护快照）",
                en: "Snapshot restored (safety backup created first)"
            )
            return result
        } catch {
            setErrorBanner(error.localizedDescription)
            return nil
        }
    }

    public func togglePinSnapshot(id: String) async {
        do {
            _ = try vault.togglePinSnapshot(id: id)
            refreshFromVault()
        } catch {
            setErrorBanner(error.localizedDescription)
        }
    }

    public func deleteSnapshot(id: String) async {
        do {
            try vault.deleteSnapshot(id: id)
            refreshFromVault()
        } catch {
            setErrorBanner(error.localizedDescription)
        }
    }

    public func exportBackupData(includeApiKey: Bool? = nil) throws -> Data {
        try vault.exportArchive(includeApiKey: includeApiKey, exportedAt: Date())
    }

    public func exportMarkdownText() -> String {
        BackupCodec.exportMarkdown(todos: todos, language: language, now: Date())
    }

    public func previewImport(data: Data) throws -> ImportPreviewSummary {
        try vault.previewImport(data: data)
    }

    @discardableResult
    public func applyImport(data: Data, strategy: ImportStrategy) async throws -> ImportResult {
        let result = try vault.applyImport(data: data, strategy: strategy, now: Date())
        refreshFromVault()
        await notifications.syncReminders(for: todos, language: language)
        setBanner(
            zh: "导入完成：新增 \(result.addedCount) 项，更新 \(result.updatedCount) 项",
            en: "Import complete: \(result.addedCount) added, \(result.updatedCount) updated"
        )
        return result
    }

    @discardableResult
    public func clearCompletedTodos() async -> Int {
        let removed = vault.clearCompletedTodos()
        refreshFromVault()
        setBanner(
            zh: "已清理 \(removed) 项已完成任务",
            en: "Cleared \(removed) completed task(s)"
        )
        return removed
    }

    @discardableResult
    public func deduplicateTodos() async -> Int {
        let removed = vault.deduplicateTodos()
        refreshFromVault()
        await notifications.syncReminders(for: todos, language: language)
        setBanner(
            zh: removed > 0 ? "已合并去重 \(removed) 项重复任务" : "未发现重复任务",
            en: removed > 0 ? "Removed \(removed) duplicate task(s)" : "No duplicate tasks found"
        )
        return removed
    }

    public func factoryReset(deleteSnapshots: Bool = true) async {
        await stopFocus(logElapsedMinutes: false)
        lastDeletedTodo = nil
        vault.factoryReset(deleteSnapshots: deleteSnapshots)
        await notifications.cancelAllReminders()
        refreshFromVault()
        setBanner(zh: "已重置应用数据", en: "All app data reset")
    }

    public func dismissStatusBanner() {
        lastStatusBanner = nil
    }

    // MARK: - Private

    private func refreshFromVault() {
        let current = vault.loadState()
        todos = SmartSectionEngine.sortTodos(current.todos)
        aiSettings = current.aiSettings
        preferences = current.preferences
        chatHistory = current.chatHistory ?? []
        snapshots = vault.listSnapshots()
        storageBreakdown = vault.computeStorageBreakdown()
    }

    private func setBanner(zh: String, en: String) {
        lastStatusBanner = StatusBanner(
            message: AppLocalizer.t(zh: zh, en: en, language: language),
            isError: false
        )
    }

    private func setErrorBanner(_ message: String) {
        lastStatusBanner = StatusBanner(message: message, isError: true)
    }
}
