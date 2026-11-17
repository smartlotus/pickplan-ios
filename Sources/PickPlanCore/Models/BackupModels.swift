import Foundation

/// Reason a local backup snapshot was created.
public enum BackupTrigger: String, Codable, CaseIterable, Sendable {
    case manual
    case scheduled
    case safetyPreRestore

    public func displayName(language: AppLanguage) -> String {
        switch self {
        case .manual:
            return AppLocalizer.t(zh: "手动备份", en: "Manual", language: language)
        case .scheduled:
            return AppLocalizer.t(zh: "定时自动", en: "Scheduled", language: language)
        case .safetyPreRestore:
            return AppLocalizer.t(zh: "恢复前保护", en: "Pre-Restore Safety", language: language)
        }
    }
}

/// Strategy used when importing tasks from an archive file.
public enum ImportStrategy: String, Codable, CaseIterable, Sendable, Identifiable {
    case smartMerge
    case appendCopy
    case replaceAll

    public var id: String { rawValue }

    public func displayName(language: AppLanguage) -> String {
        switch self {
        case .smartMerge:
            return AppLocalizer.t(zh: "智能合并（按最新时间）", en: "Smart Merge (Latest Wins)", language: language)
        case .appendCopy:
            return AppLocalizer.t(zh: "追加为新任务副本", en: "Append as Copies", language: language)
        case .replaceAll:
            return AppLocalizer.t(zh: "覆盖全部（先生成安全快照）", en: "Replace All (Auto Safety Snapshot)", language: language)
        }
    }
}

/// Automatic snapshot and retention policy.
public struct BackupPolicy: Codable, Equatable, Hashable, Sendable {
    public static let supportedIntervals: [Int] = [1, 6, 12, 24, 168]

    public var isEnabled: Bool
    public var intervalHours: Int
    public var backupOnBackgroundAfterChanges: Bool
    public var preferredHour: Int
    public var preferredMinute: Int
    public var maxSnapshots: Int
    public var includeApiKey: Bool

    public init(
        isEnabled: Bool = true,
        intervalHours: Int = 24,
        backupOnBackgroundAfterChanges: Bool = true,
        preferredHour: Int = 22,
        preferredMinute: Int = 0,
        maxSnapshots: Int = 15,
        includeApiKey: Bool = false
    ) {
        self.isEnabled = isEnabled
        self.intervalHours = max(1, intervalHours)
        self.backupOnBackgroundAfterChanges = backupOnBackgroundAfterChanges
        self.preferredHour = min(23, max(0, preferredHour))
        self.preferredMinute = min(59, max(0, preferredMinute))
        self.maxSnapshots = max(1, maxSnapshots)
        self.includeApiKey = includeApiKey
    }
}

/// Stored configuration for the OpenAI-compatible AI parser.
public struct AISettingsRecord: Codable, Equatable, Hashable, Sendable {
    public var providerName: String
    public var baseUrl: String
    public var modelName: String
    public var apiKey: String?

    public init(
        providerName: String = "DeepSeek",
        baseUrl: String = "https://api.deepseek.com/v1",
        modelName: String = "deepseek-chat",
        apiKey: String? = nil
    ) {
        self.providerName = providerName
        self.baseUrl = baseUrl
        self.modelName = modelName
        self.apiKey = apiKey
    }
}

/// Persisted user preferences and backup metadata.
public struct AppPreferencesRecord: Codable, Equatable, Hashable, Sendable {
    public var languageCode: String
    public var backupPolicy: BackupPolicy
    public var hapticsEnabled: Bool
    public var lastBackupAt: Date?
    public var hasPendingChangesForBackup: Bool

    public init(
        languageCode: String = "zh",
        backupPolicy: BackupPolicy = BackupPolicy(),
        hapticsEnabled: Bool = true,
        lastBackupAt: Date? = nil,
        hasPendingChangesForBackup: Bool = false
    ) {
        self.languageCode = languageCode
        self.backupPolicy = backupPolicy
        self.hapticsEnabled = hapticsEnabled
        self.lastBackupAt = lastBackupAt
        self.hasPendingChangesForBackup = hasPendingChangesForBackup
    }

    private enum CodingKeys: String, CodingKey {
        case languageCode
        case backupPolicy
        case hapticsEnabled
        case lastBackupAt
        case hasPendingChangesForBackup
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.languageCode = try container.decodeIfPresent(String.self, forKey: .languageCode) ?? "zh"
        self.backupPolicy = try container.decodeIfPresent(BackupPolicy.self, forKey: .backupPolicy) ?? BackupPolicy()
        self.hapticsEnabled = try container.decodeIfPresent(Bool.self, forKey: .hapticsEnabled) ?? true
        self.lastBackupAt = try PickPlanDateCodec.decodeDateIfPresent(from: container, forKey: .lastBackupAt)
        self.hasPendingChangesForBackup = try container.decodeIfPresent(Bool.self, forKey: .hasPendingChangesForBackup) ?? false
    }
}

/// Chat assistant message entry containing optional parsed todos.
public struct ChatHistoryEntry: Codable, Identifiable, Equatable, Hashable, Sendable {
    public var id: String
    public var text: String
    public var isUser: Bool
    public var createdAt: Date
    public var parsedTodos: [TodoItem]
    public var isAdded: Bool

    public init(
        id: String = UUID().uuidString,
        text: String,
        isUser: Bool,
        createdAt: Date = Date(),
        parsedTodos: [TodoItem] = [],
        isAdded: Bool = false
    ) {
        self.id = id
        self.text = text
        self.isUser = isUser
        self.createdAt = createdAt
        self.parsedTodos = parsedTodos
        self.isAdded = isAdded
    }
}

/// Complete local vault payload serialized into snapshots and v2 export files.
public struct PickPlanBackupPayload: Codable, Equatable, Sendable {
    public var todos: [TodoItem]
    public var aiSettings: AISettingsRecord
    public var preferences: AppPreferencesRecord
    public var chatHistory: [ChatHistoryEntry]?

    public init(
        todos: [TodoItem] = [],
        aiSettings: AISettingsRecord = AISettingsRecord(),
        preferences: AppPreferencesRecord = AppPreferencesRecord(),
        chatHistory: [ChatHistoryEntry]? = nil
    ) {
        self.todos = todos
        self.aiSettings = aiSettings
        self.preferences = preferences
        self.chatHistory = chatHistory
    }
}

/// Signed/checksummed versioned export container (`schemaVersion = 2`).
public struct PickPlanBackupEnvelope: Codable, Equatable, Sendable {
    public var format: String
    public var schemaVersion: Int
    public var exportedAt: Date
    public var appVersion: String
    public var deviceHint: String
    public var checksum: String
    public var payload: PickPlanBackupPayload

    public init(
        format: String = "pickplan-backup",
        schemaVersion: Int = 2,
        exportedAt: Date = Date(),
        appVersion: String = "2.0.0-ios-liquid",
        deviceHint: String = "iOS",
        checksum: String,
        payload: PickPlanBackupPayload
    ) {
        self.format = format
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.appVersion = appVersion
        self.deviceHint = deviceHint
        self.checksum = checksum
        self.payload = payload
    }
}

/// Metadata entry persisted in `<baseDirectory>/Backups/index.json`.
public struct BackupSnapshotMetadata: Codable, Identifiable, Equatable, Hashable, Sendable {
    public var id: String
    public var fileName: String
    public var createdAt: Date
    public var trigger: BackupTrigger
    public var note: String
    public var taskCount: Int
    public var completedCount: Int
    public var byteSize: Int
    public var isPinned: Bool
    public var checksum: String

    public init(
        id: String,
        fileName: String,
        createdAt: Date,
        trigger: BackupTrigger,
        note: String,
        taskCount: Int,
        completedCount: Int,
        byteSize: Int,
        isPinned: Bool,
        checksum: String
    ) {
        self.id = id
        self.fileName = fileName
        self.createdAt = createdAt
        self.trigger = trigger
        self.note = note
        self.taskCount = taskCount
        self.completedCount = completedCount
        self.byteSize = byteSize
        self.isPinned = isPinned
        self.checksum = checksum
    }
}

/// Dry-run inspection summary returned before applying an import.
public struct ImportPreviewSummary: Sendable, Equatable {
    public let detectedFormatDescription: String
    public let isV1Legacy: Bool
    public let checksumValid: Bool?
    public let incomingTaskCount: Int
    public let incomingCompletedCount: Int
    public let newTaskCount: Int
    public let conflictingIdCount: Int
    public let includesAISettings: Bool
    public let includesApiKey: Bool
    public let exportedAt: Date?

    public init(
        detectedFormatDescription: String,
        isV1Legacy: Bool,
        checksumValid: Bool?,
        incomingTaskCount: Int,
        incomingCompletedCount: Int,
        newTaskCount: Int,
        conflictingIdCount: Int,
        includesAISettings: Bool,
        includesApiKey: Bool,
        exportedAt: Date?
    ) {
        self.detectedFormatDescription = detectedFormatDescription
        self.isV1Legacy = isV1Legacy
        self.checksumValid = checksumValid
        self.incomingTaskCount = incomingTaskCount
        self.incomingCompletedCount = incomingCompletedCount
        self.newTaskCount = newTaskCount
        self.conflictingIdCount = conflictingIdCount
        self.includesAISettings = includesAISettings
        self.includesApiKey = includesApiKey
        self.exportedAt = exportedAt
    }
}

/// Outcome report after applying an import or restoring a snapshot.
public struct ImportResult: Sendable, Equatable {
    public let addedCount: Int
    public let updatedCount: Int
    public let totalCountAfter: Int
    public let safetySnapshotId: String?

    public init(
        addedCount: Int,
        updatedCount: Int,
        totalCountAfter: Int,
        safetySnapshotId: String?
    ) {
        self.addedCount = addedCount
        self.updatedCount = updatedCount
        self.totalCountAfter = totalCountAfter
        self.safetySnapshotId = safetySnapshotId
    }
}

/// Live vault & backup storage diagnostics.
public struct StorageBreakdown: Sendable, Equatable {
    public let liveDatabaseBytes: Int
    public let snapshotsTotalBytes: Int
    public let snapshotCount: Int
    public let pinnedSnapshotCount: Int
    public let totalTodos: Int
    public let activeTodos: Int
    public let completedTodos: Int
    public let chatMessageCount: Int

    public var totalBytes: Int {
        liveDatabaseBytes + snapshotsTotalBytes
    }

    public init(
        liveDatabaseBytes: Int = 0,
        snapshotsTotalBytes: Int = 0,
        snapshotCount: Int = 0,
        pinnedSnapshotCount: Int = 0,
        totalTodos: Int = 0,
        activeTodos: Int = 0,
        completedTodos: Int = 0,
        chatMessageCount: Int = 0
    ) {
        self.liveDatabaseBytes = liveDatabaseBytes
        self.snapshotsTotalBytes = snapshotsTotalBytes
        self.snapshotCount = snapshotCount
        self.pinnedSnapshotCount = pinnedSnapshotCount
        self.totalTodos = totalTodos
        self.activeTodos = activeTodos
        self.completedTodos = completedTodos
        self.chatMessageCount = chatMessageCount
    }
}
