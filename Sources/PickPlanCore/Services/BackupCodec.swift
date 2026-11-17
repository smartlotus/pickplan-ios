import CryptoKit
import Foundation

/// Errors thrown while encoding, decoding, or verifying PickPlan backups.
public enum BackupCodecError: Error, LocalizedError, Sendable, Equatable {
    case emptyData
    case invalidJSON
    case unsupportedFormat(String)
    case unsupportedSchemaVersion(Int)

    public var errorDescription: String? {
        switch self {
        case .emptyData:
            return "Backup data is empty."
        case .invalidJSON:
            return "File is neither a valid PickPlan v2 archive nor an Android v1 task JSON array."
        case .unsupportedFormat(let format):
            return "Unsupported backup format: \(format)."
        case .unsupportedSchemaVersion(let version):
            return "Unsupported backup schema version: \(version)."
        }
    }
}

/// Handles canonical SHA-256 checksums, v2 envelope serialization, Android v1 legacy JSON
/// auto-detection/migration, and human-readable Markdown export.
public enum BackupCodec {
    public static let envelopeFormat = "pickplan-backup"
    public static let currentSchemaVersion = 2

    private struct LegacyTodosWrapper: Decodable {
        let todos: [TodoItem]
    }

    private struct EnvelopeHeaderProbe: Decodable {
        let format: String?
        let schemaVersion: Int?
    }

    /// Canonically encodes `PickPlanBackupPayload` (`sortedKeys`, `iso8601`) for deterministic hashing.
    public static func canonicalPayloadData(_ payload: PickPlanBackupPayload) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(payload)
    }

    /// Computes lowercase hex SHA-256 digest of canonically encoded `PickPlanBackupPayload`.
    public static func computeChecksum(for payload: PickPlanBackupPayload) throws -> String {
        let canonical = try canonicalPayloadData(payload)
        let digest = SHA256.hash(data: canonical)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Verifies that `envelope.checksum` matches the SHA-256 of `envelope.payload`.
    public static func verifyChecksum(_ envelope: PickPlanBackupEnvelope) throws -> Bool {
        let trimmed = envelope.checksum.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return false }
        let expected = try computeChecksum(for: envelope.payload)
        return expected == trimmed
    }

    /// Encodes a `PickPlanBackupPayload` inside a checksummed v2 `PickPlanBackupEnvelope`.
    public static func encodeEnvelope(
        _ payload: PickPlanBackupPayload,
        appVersion: String = "2.0.0-ios-liquid",
        deviceHint: String = "iOS",
        exportedAt: Date = Date()
    ) throws -> Data {
        let checksum = try computeChecksum(for: payload)
        let envelope = PickPlanBackupEnvelope(
            format: envelopeFormat,
            schemaVersion: currentSchemaVersion,
            exportedAt: exportedAt,
            appVersion: appVersion,
            deviceHint: deviceHint,
            checksum: checksum,
            payload: payload
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(envelope)
    }

    /// Decodes either a v2 `PickPlanBackupEnvelope` or a legacy Android v1 JSON array / `{ "todos": [...] }` wrapper.
    public static func decodeAndInspect(
        _ data: Data
    ) throws -> (envelope: PickPlanBackupEnvelope, isLegacyV1: Bool, checksumValid: Bool?) {
        guard !data.isEmpty else {
            throw BackupCodecError.emptyData
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { nestedDecoder in
            try PickPlanDateCodec.decodeDate(from: nestedDecoder)
        }

        if let probe = try? decoder.decode(EnvelopeHeaderProbe.self, from: data),
           probe.format != nil || probe.schemaVersion != nil {
            if let format = probe.format, format != envelopeFormat {
                throw BackupCodecError.unsupportedFormat(format)
            }
            if let version = probe.schemaVersion, version > currentSchemaVersion || version < 1 {
                throw BackupCodecError.unsupportedSchemaVersion(version)
            }
        }

        if let envelope = try? decoder.decode(PickPlanBackupEnvelope.self, from: data) {
            guard envelope.format == envelopeFormat else {
                throw BackupCodecError.unsupportedFormat(envelope.format)
            }
            guard (1...currentSchemaVersion).contains(envelope.schemaVersion) else {
                throw BackupCodecError.unsupportedSchemaVersion(envelope.schemaVersion)
            }
            let valid = (try? verifyChecksum(envelope)) ?? false
            return (envelope, false, valid)
        }

        if let v1Array = try? decoder.decode([TodoItem].self, from: data) {
            let payload = PickPlanBackupPayload(todos: v1Array)
            let checksum = (try? computeChecksum(for: payload)) ?? ""
            let wrapped = PickPlanBackupEnvelope(
                format: envelopeFormat,
                schemaVersion: 1,
                exportedAt: Date(),
                appVersion: "1.x-android-legacy",
                deviceHint: "Android",
                checksum: checksum,
                payload: payload
            )
            return (wrapped, true, nil)
        }

        if let wrapper = try? decoder.decode(LegacyTodosWrapper.self, from: data) {
            let payload = PickPlanBackupPayload(todos: wrapper.todos)
            let checksum = (try? computeChecksum(for: payload)) ?? ""
            let wrapped = PickPlanBackupEnvelope(
                format: envelopeFormat,
                schemaVersion: 1,
                exportedAt: Date(),
                appVersion: "1.x-legacy-object",
                deviceHint: "Legacy",
                checksum: checksum,
                payload: payload
            )
            return (wrapped, true, nil)
        }

        throw BackupCodecError.invalidJSON
    }

    /// Exports tasks grouped by `SmartSectionEngine` sections into clean Markdown.
    public static func exportMarkdown(
        todos: [TodoItem],
        language: AppLanguage,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        let sections = SmartSectionEngine.groupIntoSections(todos, now: now, calendar: calendar)
        let activeCount = todos.filter { !$0.isCompleted }.count
        let completedCount = todos.count - activeCount

        var lines: [String] = []
        let headerTitle = AppLocalizer.t(zh: "PickPlan 任务清单", en: "PickPlan Task List", language: language)
        lines.append("# \(headerTitle)")
        lines.append("")
        let exportedLabel = AppLocalizer.t(zh: "导出时间", en: "Exported", language: language)
        let summaryLabel = AppLocalizer.t(
            zh: "共 \(todos.count) 项 · 待办 \(activeCount) · 已完成 \(completedCount)",
            en: "\(todos.count) total · \(activeCount) active · \(completedCount) completed",
            language: language
        )
        lines.append("> \(exportedLabel): \(PickPlanDateCodec.formatDisplayDateTime(now, timeZone: calendar.timeZone)) | \(summaryLabel)")
        lines.append("")

        if sections.isEmpty {
            lines.append(AppLocalizer.t(zh: "_暂无任务_", en: "_No tasks yet_", language: language))
            return lines.joined(separator: "\n")
        }

        for section in sections {
            lines.append("## \(section.kind.title(language: language)) (\(section.todos.count))")
            lines.append("")

            for todo in section.todos {
                let checkbox = todo.isCompleted ? "[x]" : "[ ]"
                var metaTokens: [String] = []

                if todo.priority != .normal {
                    metaTokens.append("[\(todo.priority.displayName(language: language))]")
                }
                if todo.tag != .none {
                    metaTokens.append("#\(todo.tag.displayName(language: language))")
                }
                if let reminder = todo.reminderTime {
                    let label = AppLocalizer.t(zh: "提醒", en: "Remind", language: language)
                    metaTokens.append("⏰ \(label): \(PickPlanDateCodec.formatDisplayDateTime(reminder, timeZone: calendar.timeZone))")
                }
                if let deadline = todo.deadline {
                    let label = AppLocalizer.t(zh: "截止", en: "Due", language: language)
                    metaTokens.append("⏳ \(label): \(PickPlanDateCodec.formatDisplayDateTime(deadline, timeZone: calendar.timeZone))")
                }
                if todo.focusMinutesLogged > 0 {
                    metaTokens.append("🍅 \(todo.focusMinutesLogged)m")
                }

                let suffix = metaTokens.isEmpty ? "" : " — " + metaTokens.joined(separator: " · ")
                lines.append("- \(checkbox) **\(todo.title)**\(suffix)")

                let trimmedNotes = todo.notes.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedNotes.isEmpty {
                    let notePrefix = AppLocalizer.t(zh: "备注", en: "Notes", language: language)
                    lines.append("  - \(notePrefix): \(trimmedNotes.replacingOccurrences(of: "\n", with: " "))")
                }

                for subtask in todo.subtasks {
                    let subBox = subtask.isCompleted ? "[x]" : "[ ]"
                    lines.append("  - \(subBox) \(subtask.title)")
                }
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }
}
