import Foundation

/// Errors thrown by `LocalVaultStore` during snapshot or persistence operations.
public enum LocalVaultError: Error, LocalizedError, Sendable, Equatable {
    case snapshotNotFound(String)
    case corruptedSnapshot(String)

    public var errorDescription: String? {
        switch self {
        case .snapshotNotFound(let id):
            return "Backup snapshot '\(id)' was not found."
        case .corruptedSnapshot(let id):
            return "Backup snapshot '\(id)' could not be decoded."
        }
    }
}

/// Thread-safe local JSON vault & snapshot manager.
/// Persists live state to `<baseDirectory>/pickplan_state_v2.json`,
/// optional API secret to `<baseDirectory>/pickplan_secrets.json`,
/// and versioned snapshots to `<baseDirectory>/Backups/<id>.pickplan.json` + `index.json`.
public final class LocalVaultStore: @unchecked Sendable {
    private struct SecretRecord: Codable {
        var apiKey: String?
    }

    public let baseDirectory: URL
    public let liveStateURL: URL
    public let secretsURL: URL
    public let backupsDirectory: URL
    public let snapshotIndexURL: URL

    private let lock = NSRecursiveLock()
    private let fileManager: FileManager
    private var state: PickPlanBackupPayload
    private var snapshotsIndex: [BackupSnapshotMetadata]

    public init(
        baseDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) {
        let resolvedBase = baseDirectory
            ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory.appendingPathComponent("PickPlanVault", isDirectory: true)

        self.baseDirectory = resolvedBase
        self.liveStateURL = resolvedBase.appendingPathComponent("pickplan_state_v2.json", isDirectory: false)
        self.secretsURL = resolvedBase.appendingPathComponent("pickplan_secrets.json", isDirectory: false)
        self.backupsDirectory = resolvedBase.appendingPathComponent("Backups", isDirectory: true)
        self.snapshotIndexURL = self.backupsDirectory.appendingPathComponent("index.json", isDirectory: false)
        self.fileManager = fileManager
        self.state = PickPlanBackupPayload()
        self.snapshotsIndex = []

        lock.lock()
        defer { lock.unlock() }
        ensureDirectoriesLocked()
        self.state = loadStateFromDiskLocked()
        self.snapshotsIndex = loadSnapshotIndexFromDiskLocked()
    }

    // MARK: - State Accessors & Todo CRUD

    public func loadState() -> PickPlanBackupPayload {
        lock.lock()
        defer { lock.unlock() }
        return state
    }

    public func getTodos() -> [TodoItem] {
        lock.lock()
        defer { lock.unlock() }
        return state.todos
    }

    public func getAISettings() -> AISettingsRecord {
        lock.lock()
        defer { lock.unlock() }
        return state.aiSettings
    }

    public func getPreferences() -> AppPreferencesRecord {
        lock.lock()
        defer { lock.unlock() }
        return state.preferences
    }

    public func getChatHistory() -> [ChatHistoryEntry] {
        lock.lock()
        defer { lock.unlock() }
        return state.chatHistory ?? []
    }

    public func upsertTodo(_ todo: TodoItem) {
        lock.lock()
        defer { lock.unlock() }
        if let idx = state.todos.firstIndex(where: { $0.id == todo.id }) {
            state.todos[idx] = todo
        } else {
            state.todos.append(todo)
        }
        state.preferences.hasPendingChangesForBackup = true
        saveStateLocked()
    }

    public func addTodos(_ newTodos: [TodoItem]) {
        guard !newTodos.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        for todo in newTodos {
            if let idx = state.todos.firstIndex(where: { $0.id == todo.id }) {
                state.todos[idx] = todo
            } else {
                state.todos.append(todo)
            }
        }
        state.preferences.hasPendingChangesForBackup = true
        saveStateLocked()
    }

    @discardableResult
    public func deleteTodo(id: String) -> TodoItem? {
        lock.lock()
        defer { lock.unlock() }
        guard let idx = state.todos.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        let removed = state.todos.remove(at: idx)
        state.preferences.hasPendingChangesForBackup = true
        saveStateLocked()
        return removed
    }

    @discardableResult
    public func toggleTodoCompletion(id: String, now: Date = Date()) -> TodoItem? {
        lock.lock()
        defer { lock.unlock() }
        guard let idx = state.todos.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        var updated = state.todos[idx]
        updated.isCompleted.toggle()
        updated.completedAt = updated.isCompleted ? now : nil
        updated.updatedAt = now
        state.todos[idx] = updated
        state.preferences.hasPendingChangesForBackup = true
        saveStateLocked()
        return updated
    }

    @discardableResult
    public func toggleSubtask(todoId: String, subtaskId: String, now: Date = Date()) -> TodoItem? {
        lock.lock()
        defer { lock.unlock() }
        guard let todoIdx = state.todos.firstIndex(where: { $0.id == todoId }),
              let subIdx = state.todos[todoIdx].subtasks.firstIndex(where: { $0.id == subtaskId })
        else {
            return nil
        }
        var updated = state.todos[todoIdx]
        updated.subtasks[subIdx].isCompleted.toggle()
        updated.updatedAt = now
        state.todos[todoIdx] = updated
        state.preferences.hasPendingChangesForBackup = true
        saveStateLocked()
        return updated
    }

    @discardableResult
    public func logFocusMinutes(todoId: String, minutes: Int, now: Date = Date()) -> TodoItem? {
        guard minutes > 0 else { return nil }
        lock.lock()
        defer { lock.unlock() }
        guard let idx = state.todos.firstIndex(where: { $0.id == todoId }) else {
            return nil
        }
        var updated = state.todos[idx]
        updated.focusMinutesLogged += minutes
        updated.updatedAt = now
        state.todos[idx] = updated
        state.preferences.hasPendingChangesForBackup = true
        saveStateLocked()
        return updated
    }

    public func updateAISettings(_ settings: AISettingsRecord) {
        lock.lock()
        defer { lock.unlock() }
        state.aiSettings = settings
        state.preferences.hasPendingChangesForBackup = true
        saveStateLocked()
    }

    public func updatePreferences(_ preferences: AppPreferencesRecord) {
        lock.lock()
        defer { lock.unlock() }
        state.preferences = preferences
        saveStateLocked()
    }

    public func appendChatMessage(_ entry: ChatHistoryEntry) {
        lock.lock()
        defer { lock.unlock() }
        var history = state.chatHistory ?? []
        history.append(entry)
        state.chatHistory = history
        state.preferences.hasPendingChangesForBackup = true
        saveStateLocked()
    }

    public func markChatTodosAdded(messageId: String) {
        lock.lock()
        defer { lock.unlock() }
        guard var history = state.chatHistory,
              let idx = history.firstIndex(where: { $0.id == messageId })
        else {
            return
        }
        history[idx].isAdded = true
        state.chatHistory = history
        state.preferences.hasPendingChangesForBackup = true
        saveStateLocked()
    }

    public func updateParsedTodoInChat(messageId: String, updatedTodo: TodoItem) {
        lock.lock()
        defer { lock.unlock() }
        guard var history = state.chatHistory,
              let idx = history.firstIndex(where: { $0.id == messageId })
        else {
            return
        }
        history[idx].parsedTodos = history[idx].parsedTodos.map { $0.id == updatedTodo.id ? updatedTodo : $0 }
        state.chatHistory = history
        state.preferences.hasPendingChangesForBackup = true
        saveStateLocked()
    }

    public func removeSingleParsedTodoFromChat(messageId: String, todoId: String) -> TodoItem? {
        lock.lock()
        defer { lock.unlock() }
        guard var history = state.chatHistory,
              let idx = history.firstIndex(where: { $0.id == messageId }),
              let todoIdx = history[idx].parsedTodos.firstIndex(where: { $0.id == todoId })
        else {
            return nil
        }
        let removed = history[idx].parsedTodos.remove(at: todoIdx)
        if history[idx].parsedTodos.isEmpty {
            history[idx].isAdded = true
        }
        state.chatHistory = history
        state.preferences.hasPendingChangesForBackup = true
        saveStateLocked()
        return removed
    }

    // MARK: - Archive Export & Import

    public func exportArchive(
        includeApiKey: Bool? = nil,
        appVersion: String = "2.0.0-ios-liquid",
        deviceHint: String = "iOS",
        exportedAt: Date = Date()
    ) throws -> Data {
        lock.lock()
        defer { lock.unlock() }

        let shouldIncludeKey = includeApiKey ?? state.preferences.backupPolicy.includeApiKey
        var exportPayload = state
        if !shouldIncludeKey {
            exportPayload.aiSettings.apiKey = nil
        }
        return try BackupCodec.encodeEnvelope(
            exportPayload,
            appVersion: appVersion,
            deviceHint: deviceHint,
            exportedAt: exportedAt
        )
    }

    public func previewImport(data: Data) throws -> ImportPreviewSummary {
        lock.lock()
        defer { lock.unlock() }

        let (envelope, isLegacyV1, checksumValid) = try BackupCodec.decodeAndInspect(data)
        let incomingTodos = envelope.payload.todos
        let existingIds = Set(state.todos.map(\.id))

        let conflictingCount = incomingTodos.reduce(0) { count, todo in
            count + (existingIds.contains(todo.id) ? 1 : 0)
        }
        let newCount = incomingTodos.count - conflictingCount
        let completedCount = incomingTodos.filter(\.isCompleted).count
        let hasKey = !(envelope.payload.aiSettings.apiKey?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty ?? true)

        let description = isLegacyV1
            ? "PickPlan v1 Legacy JSON"
            : "PickPlan v\(envelope.schemaVersion) Archive"

        return ImportPreviewSummary(
            detectedFormatDescription: description,
            isV1Legacy: isLegacyV1,
            checksumValid: checksumValid,
            incomingTaskCount: incomingTodos.count,
            incomingCompletedCount: completedCount,
            newTaskCount: newCount,
            conflictingIdCount: conflictingCount,
            includesAISettings: !isLegacyV1,
            includesApiKey: hasKey,
            exportedAt: isLegacyV1 ? nil : envelope.exportedAt
        )
    }

    @discardableResult
    public func applyImport(
        data: Data,
        strategy: ImportStrategy,
        now: Date = Date()
    ) throws -> ImportResult {
        lock.lock()
        defer { lock.unlock() }

        let (envelope, isLegacyV1, _) = try BackupCodec.decodeAndInspect(data)
        let incomingTodos = envelope.payload.todos

        var addedCount = 0
        var updatedCount = 0
        var safetySnapshotId: String?

        switch strategy {
        case .smartMerge:
            var indexById: [String: Int] = [:]
            for (idx, todo) in state.todos.enumerated() {
                indexById[todo.id] = idx
            }

            for incoming in incomingTodos {
                if let existingIdx = indexById[incoming.id] {
                    if incoming.updatedAt > state.todos[existingIdx].updatedAt {
                        state.todos[existingIdx] = incoming
                        updatedCount += 1
                    }
                } else {
                    indexById[incoming.id] = state.todos.count
                    state.todos.append(incoming)
                    addedCount += 1
                }
            }

            if !isLegacyV1, let incomingChat = envelope.payload.chatHistory, !incomingChat.isEmpty {
                var currentChat = state.chatHistory ?? []
                let existingChatIds = Set(currentChat.map(\.id))
                for entry in incomingChat where !existingChatIds.contains(entry.id) {
                    currentChat.append(entry)
                }
                state.chatHistory = currentChat
            }

        case .appendCopy:
            var seenIds = Set(state.todos.map(\.id))
            for incoming in incomingTodos {
                var copy = incoming
                if seenIds.contains(copy.id) {
                    copy.id = UUID().uuidString
                }
                seenIds.insert(copy.id)
                state.todos.append(copy)
                addedCount += 1
            }

        case .replaceAll:
            let safety = try createSnapshotLocked(
                trigger: .safetyPreRestore,
                note: "Pre-replace import safety snapshot",
                now: now
            )
            safetySnapshotId = safety.id

            var seen = Set<String>()
            var uniqueTodos: [TodoItem] = []
            for item in incomingTodos where !seen.contains(item.id) {
                seen.insert(item.id)
                uniqueTodos.append(item)
            }
            state.todos = uniqueTodos
            addedCount = uniqueTodos.count
            updatedCount = 0

            if !isLegacyV1 {
                state.aiSettings = envelope.payload.aiSettings
                state.preferences = envelope.payload.preferences
                state.chatHistory = envelope.payload.chatHistory ?? []
            }
        }

        state.preferences.hasPendingChangesForBackup = true
        saveStateLocked()

        return ImportResult(
            addedCount: addedCount,
            updatedCount: updatedCount,
            totalCountAfter: state.todos.count,
            safetySnapshotId: safetySnapshotId
        )
    }

    // MARK: - Snapshots, Scheduling & Retention

    @discardableResult
    public func createSnapshot(
        trigger: BackupTrigger,
        note: String = "",
        now: Date = Date()
    ) throws -> BackupSnapshotMetadata {
        lock.lock()
        defer { lock.unlock() }
        return try createSnapshotLocked(trigger: trigger, note: note, now: now)
    }

    public func listSnapshots() -> [BackupSnapshotMetadata] {
        lock.lock()
        defer { lock.unlock() }
        return sortedSnapshots(snapshotsIndex)
    }

    public func loadSnapshotPayload(id: String) throws -> PickPlanBackupEnvelope {
        lock.lock()
        defer { lock.unlock() }

        guard let meta = snapshotsIndex.first(where: { $0.id == id }) else {
            throw LocalVaultError.snapshotNotFound(id)
        }
        let fileURL = backupsDirectory.appendingPathComponent(meta.fileName, isDirectory: false)
        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw LocalVaultError.snapshotNotFound(id)
        }
        let data = try Data(contentsOf: fileURL)
        do {
            let (envelope, _, _) = try BackupCodec.decodeAndInspect(data)
            return envelope
        } catch {
            throw LocalVaultError.corruptedSnapshot(id)
        }
    }

    @discardableResult
    public func restoreSnapshot(id: String, now: Date = Date()) throws -> ImportResult {
        lock.lock()
        defer { lock.unlock() }

        guard let meta = snapshotsIndex.first(where: { $0.id == id }) else {
            throw LocalVaultError.snapshotNotFound(id)
        }
        let targetURL = backupsDirectory.appendingPathComponent(meta.fileName, isDirectory: false)
        guard fileManager.fileExists(atPath: targetURL.path) else {
            throw LocalVaultError.snapshotNotFound(id)
        }
        let targetData = try Data(contentsOf: targetURL)
        let (targetEnvelope, _, _) = try BackupCodec.decodeAndInspect(targetData)

        let safety = try createSnapshotLocked(
            trigger: .safetyPreRestore,
            note: "Pre-restore safety snapshot before \(id)",
            now: now
        )

        let existingApiKey = state.aiSettings.apiKey
        var restoredAI = targetEnvelope.payload.aiSettings
        if (restoredAI.apiKey?.isEmpty ?? true), let existingApiKey, !existingApiKey.isEmpty {
            restoredAI.apiKey = existingApiKey
        }

        state.todos = targetEnvelope.payload.todos
        state.aiSettings = restoredAI
        state.preferences = targetEnvelope.payload.preferences
        state.preferences.hasPendingChangesForBackup = false
        state.chatHistory = targetEnvelope.payload.chatHistory ?? []
        saveStateLocked()

        return ImportResult(
            addedCount: state.todos.count,
            updatedCount: 0,
            totalCountAfter: state.todos.count,
            safetySnapshotId: safety.id
        )
    }

    @discardableResult
    public func togglePinSnapshot(id: String) throws -> BackupSnapshotMetadata {
        lock.lock()
        defer { lock.unlock() }

        guard let idx = snapshotsIndex.firstIndex(where: { $0.id == id }) else {
            throw LocalVaultError.snapshotNotFound(id)
        }
        snapshotsIndex[idx].isPinned.toggle()
        let updated = snapshotsIndex[idx]
        saveSnapshotIndexLocked()
        return updated
    }

    public func deleteSnapshot(id: String) throws {
        lock.lock()
        defer { lock.unlock() }

        guard let idx = snapshotsIndex.firstIndex(where: { $0.id == id }) else {
            throw LocalVaultError.snapshotNotFound(id)
        }
        let removed = snapshotsIndex.remove(at: idx)
        let fileURL = backupsDirectory.appendingPathComponent(removed.fileName, isDirectory: false)
        try? fileManager.removeItem(at: fileURL)
        saveSnapshotIndexLocked()
    }

    @discardableResult
    public func evaluateScheduledBackup(
        now: Date = Date(),
        isBackgroundTransition: Bool = false
    ) throws -> BackupSnapshotMetadata? {
        lock.lock()
        defer { lock.unlock() }

        let policy = state.preferences.backupPolicy
        guard policy.isEnabled else {
            return nil
        }

        if isBackgroundTransition && policy.backupOnBackgroundAfterChanges && state.preferences.hasPendingChangesForBackup {
            return try createSnapshotLocked(
                trigger: .scheduled,
                note: "Auto backup on background",
                now: now
            )
        }

        if let lastBackup = state.preferences.lastBackupAt {
            let intervalSeconds = TimeInterval(max(1, policy.intervalHours) * 3600)
            if now.timeIntervalSince(lastBackup) >= intervalSeconds {
                return try createSnapshotLocked(
                    trigger: .scheduled,
                    note: "Scheduled \(policy.intervalHours)h backup",
                    now: now
                )
            }
            return nil
        } else {
            guard !state.todos.isEmpty || state.preferences.hasPendingChangesForBackup else {
                return nil
            }
            return try createSnapshotLocked(
                trigger: .scheduled,
                note: "Initial scheduled backup",
                now: now
            )
        }
    }

    @discardableResult
    public func pruneSnapshotsIfNeeded() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return pruneSnapshotsLocked(protectedSnapshotId: nil)
    }

    // MARK: - Storage Hygiene

    public func computeStorageBreakdown() -> StorageBreakdown {
        lock.lock()
        defer { lock.unlock() }

        let liveBytes = fileByteSize(at: liveStateURL) + fileByteSize(at: secretsURL)
        var snapshotBytes = 0
        var pinnedCount = 0

        for meta in snapshotsIndex {
            if meta.isPinned {
                pinnedCount += 1
            }
            let fileURL = backupsDirectory.appendingPathComponent(meta.fileName, isDirectory: false)
            let diskSize = fileByteSize(at: fileURL)
            snapshotBytes += diskSize > 0 ? diskSize : meta.byteSize
        }

        let totalTodos = state.todos.count
        let completedTodos = state.todos.filter(\.isCompleted).count
        let activeTodos = totalTodos - completedTodos
        let chatCount = state.chatHistory?.count ?? 0

        return StorageBreakdown(
            liveDatabaseBytes: liveBytes,
            snapshotsTotalBytes: snapshotBytes,
            snapshotCount: snapshotsIndex.count,
            pinnedSnapshotCount: pinnedCount,
            totalTodos: totalTodos,
            activeTodos: activeTodos,
            completedTodos: completedTodos,
            chatMessageCount: chatCount
        )
    }

    @discardableResult
    public func clearCompletedTodos() -> Int {
        lock.lock()
        defer { lock.unlock() }

        let beforeCount = state.todos.count
        state.todos.removeAll(where: \.isCompleted)
        let removed = beforeCount - state.todos.count
        if removed > 0 {
            state.preferences.hasPendingChangesForBackup = true
            saveStateLocked()
        }
        return removed
    }

    @discardableResult
    public func deduplicateTodos() -> Int {
        lock.lock()
        defer { lock.unlock() }

        let beforeCount = state.todos.count
        guard beforeCount > 1 else { return 0 }

        struct SemanticKey: Hashable {
            let title: String
            let reminderEpoch: Int?
            let deadlineEpoch: Int?
            let isCompleted: Bool
        }

        // First deduplicate by ID (keep latest updatedAt)
        var byId: [String: TodoItem] = [:]
        var idOrder: [String] = []
        for item in state.todos {
            if let existing = byId[item.id] {
                if item.updatedAt > existing.updatedAt {
                    byId[item.id] = item
                }
            } else {
                byId[item.id] = item
                idOrder.append(item.id)
            }
        }
        let uniqueById = idOrder.compactMap { byId[$0] }

        // Next deduplicate semantically identical tasks
        var bySemantic: [SemanticKey: TodoItem] = [:]
        var semanticOrder: [SemanticKey] = []
        for item in uniqueById {
            let key = SemanticKey(
                title: item.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                reminderEpoch: item.reminderTime.map { Int($0.timeIntervalSince1970) },
                deadlineEpoch: item.deadline.map { Int($0.timeIntervalSince1970) },
                isCompleted: item.isCompleted
            )
            if let existing = bySemantic[key] {
                let existingRichness = (existing.notes.isEmpty ? 0 : 1) + existing.subtasks.count
                let incomingRichness = (item.notes.isEmpty ? 0 : 1) + item.subtasks.count
                if item.updatedAt > existing.updatedAt || (item.updatedAt == existing.updatedAt && incomingRichness > existingRichness) {
                    bySemantic[key] = item
                }
            } else {
                bySemantic[key] = item
                semanticOrder.append(key)
            }
        }

        let deduplicated = semanticOrder.compactMap { bySemantic[$0] }
        let removed = beforeCount - deduplicated.count
        if removed > 0 {
            state.todos = deduplicated
            state.preferences.hasPendingChangesForBackup = true
            saveStateLocked()
        }
        return removed
    }

    public func clearChatHistory() {
        lock.lock()
        defer { lock.unlock() }
        guard !(state.chatHistory ?? []).isEmpty else { return }
        state.chatHistory = []
        state.preferences.hasPendingChangesForBackup = true
        saveStateLocked()
    }

    public func factoryReset(deleteSnapshots: Bool = true) {
        lock.lock()
        defer { lock.unlock() }

        state = PickPlanBackupPayload()
        try? fileManager.removeItem(at: liveStateURL)
        try? fileManager.removeItem(at: secretsURL)

        if deleteSnapshots {
            for meta in snapshotsIndex {
                let url = backupsDirectory.appendingPathComponent(meta.fileName, isDirectory: false)
                try? fileManager.removeItem(at: url)
            }
            snapshotsIndex = []
            try? fileManager.removeItem(at: snapshotIndexURL)
        }
    }

    // MARK: - Private Helpers (Caller Must Hold `lock`)

    private func ensureDirectoriesLocked() {
        try? fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
    }

    private func createSnapshotLocked(
        trigger: BackupTrigger,
        note: String,
        now: Date
    ) throws -> BackupSnapshotMetadata {
        ensureDirectoriesLocked()

        var snapshotPayload = state
        if !state.preferences.backupPolicy.includeApiKey {
            snapshotPayload.aiSettings.apiKey = nil
        }

        let checksum = try BackupCodec.computeChecksum(for: snapshotPayload)
        let data = try BackupCodec.encodeEnvelope(snapshotPayload, exportedAt: now)

        let id = "\(PickPlanDateCodec.formatTimestampForFilename(now))-\(UUID().uuidString.prefix(8).lowercased())"
        let fileName = "\(id).pickplan.json"
        let targetURL = backupsDirectory.appendingPathComponent(fileName, isDirectory: false)
        try data.write(to: targetURL, options: [.atomic])

        let completedCount = snapshotPayload.todos.filter(\.isCompleted).count
        let metadata = BackupSnapshotMetadata(
            id: id,
            fileName: fileName,
            createdAt: now,
            trigger: trigger,
            note: note,
            taskCount: snapshotPayload.todos.count,
            completedCount: completedCount,
            byteSize: data.count,
            isPinned: false,
            checksum: checksum
        )

        snapshotsIndex.insert(metadata, at: 0)
        snapshotsIndex = sortedSnapshots(snapshotsIndex)

        if trigger != .safetyPreRestore {
            state.preferences.lastBackupAt = now
            state.preferences.hasPendingChangesForBackup = false
            saveStateLocked()
        }

        _ = pruneSnapshotsLocked(protectedSnapshotId: metadata.id)
        saveSnapshotIndexLocked()
        return metadata
    }

    @discardableResult
    private func pruneSnapshotsLocked(protectedSnapshotId: String?) -> Int {
        let maxCount = max(1, state.preferences.backupPolicy.maxSnapshots)
        snapshotsIndex = sortedSnapshots(snapshotsIndex)
        var pruned = 0

        while snapshotsIndex.count > maxCount {
            guard let oldestUnpinnedIdx = snapshotsIndex.lastIndex(where: { meta in
                !meta.isPinned && meta.id != protectedSnapshotId
            }) else {
                break
            }
            let removed = snapshotsIndex.remove(at: oldestUnpinnedIdx)
            let fileURL = backupsDirectory.appendingPathComponent(removed.fileName, isDirectory: false)
            try? fileManager.removeItem(at: fileURL)
            pruned += 1
        }

        if pruned > 0 {
            saveSnapshotIndexLocked()
        }
        return pruned
    }

    private func sortedSnapshots(_ items: [BackupSnapshotMetadata]) -> [BackupSnapshotMetadata] {
        items.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt > rhs.createdAt
            }
            return lhs.id > rhs.id
        }
    }

    private func loadStateFromDiskLocked() -> PickPlanBackupPayload {
        var loaded = PickPlanBackupPayload()
        if fileManager.fileExists(atPath: liveStateURL.path),
           let data = try? Data(contentsOf: liveStateURL) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .custom { nestedDecoder in
                try PickPlanDateCodec.decodeDate(from: nestedDecoder)
            }
            if let decoded = try? decoder.decode(PickPlanBackupPayload.self, from: data) {
                loaded = decoded
            }
        }

        if (loaded.aiSettings.apiKey?.isEmpty ?? true),
           fileManager.fileExists(atPath: secretsURL.path),
           let secretData = try? Data(contentsOf: secretsURL),
           let secret = try? JSONDecoder().decode(SecretRecord.self, from: secretData) {
            loaded.aiSettings.apiKey = secret.apiKey
        }
        return loaded
    }

    private func saveStateLocked() {
        ensureDirectoriesLocked()

        var sanitizedState = state
        let apiKeyToPersist = sanitizedState.aiSettings.apiKey
        sanitizedState.aiSettings.apiKey = nil

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        if let stateData = try? encoder.encode(sanitizedState) {
            try? stateData.write(to: liveStateURL, options: [.atomic])
        }

        if let apiKeyToPersist, !apiKeyToPersist.isEmpty {
            if let secretData = try? encoder.encode(SecretRecord(apiKey: apiKeyToPersist)) {
                try? secretData.write(to: secretsURL, options: [.atomic])
                try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: secretsURL.path)
            }
        } else if fileManager.fileExists(atPath: secretsURL.path) {
            try? fileManager.removeItem(at: secretsURL)
        }
    }

    private func loadSnapshotIndexFromDiskLocked() -> [BackupSnapshotMetadata] {
        guard fileManager.fileExists(atPath: snapshotIndexURL.path),
              let data = try? Data(contentsOf: snapshotIndexURL)
        else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { nestedDecoder in
            try PickPlanDateCodec.decodeDate(from: nestedDecoder)
        }
        let items = (try? decoder.decode([BackupSnapshotMetadata].self, from: data)) ?? []
        return sortedSnapshots(items)
    }

    private func saveSnapshotIndexLocked() {
        ensureDirectoriesLocked()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(sortedSnapshots(snapshotsIndex)) {
            try? data.write(to: snapshotIndexURL, options: [.atomic])
        }
    }

    private func fileByteSize(at url: URL) -> Int {
        guard let attrs = try? fileManager.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? NSNumber
        else {
            return 0
        }
        return size.intValue
    }
}
