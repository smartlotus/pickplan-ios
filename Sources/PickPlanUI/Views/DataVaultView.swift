import SwiftUI
import UniformTypeIdentifiers
import PickPlanCore

/// Portable document wrapper for exporting `.pickplan.json` or `.md` via SwiftUI `.fileExporter`.
public struct PickPlanExportDocument: FileDocument, @unchecked Sendable {
    public static var readableContentTypes: [UTType] { [.json, .plainText] }
    public let data: Data

    public init(data: Data) {
        self.data = data
    }

    public init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }

    public func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// Comprehensive local Data Vault:
/// - Lossless Import & Export (`.pickplan.json` v2 + Android v1 JSON + Markdown)
/// - Scheduled Local Auto-Backup configuration (interval, preferred time, background dirty snapshot, retention)
/// - Storage telemetry, snapshot preview sheet, pin/restore/export/delete, and data hygiene actions
public struct DataVaultView: View {
    @ObservedObject private var store: PlanStore

    @State private var exportDocument: PickPlanExportDocument? = nil
    @State private var exportFileName: String = "PickPlan-Backup.pickplan.json"
    @State private var exportContentType: UTType = .json
    @State private var showExporter: Bool = false
    @State private var showImporter: Bool = false

    @State private var pendingImportData: Data? = nil
    @State private var importSummary: ImportPreviewSummary? = nil
    @State private var selectedImportStrategy: ImportStrategy = .smartMerge
    @State private var showImportReviewSheet: Bool = false
    @State private var previewedSnapshot: BackupSnapshotMetadata? = nil
    @State private var previewedEnvelope: PickPlanBackupEnvelope? = nil
    @State private var showResetConfirmation: Bool = false

    public init(store: PlanStore) {
        self.store = store
    }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                storageBreakdownCard
                importExportCard
                scheduledBackupPolicyCard
                snapshotTimelineCard
                dataHygieneCard
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 110)
        }
        .navigationTitle(AppLocalizer.t(zh: "本地数据金库", en: "Local Data Vault", language: store.language))
        .fileExporter(
            isPresented: $showExporter,
            document: exportDocument,
            contentType: exportContentType,
            defaultFilename: exportFileName
        ) { _ in }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.json, .plainText],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url),
               let summary = try? store.previewImport(data: data) {
                pendingImportData = data
                importSummary = summary
                showImportReviewSheet = true
            }
        }
        .sheet(isPresented: $showImportReviewSheet) {
            importReviewSheet
        }
        .sheet(item: $previewedSnapshot) { meta in
            snapshotPreviewSheet(meta)
        }
        .confirmationDialog(
            AppLocalizer.t(zh: "确认重置全部本地数据？", en: "Reset all local data?", language: store.language),
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button(AppLocalizer.t(zh: "全部清空（包含快照）", en: "Reset Everything", language: store.language), role: .destructive) {
                Task { await store.factoryReset(deleteSnapshots: true) }
            }
            Button(AppLocalizer.t(zh: "保留快照仅清空任务", en: "Keep Snapshots Only", language: store.language), role: .destructive) {
                Task { await store.factoryReset(deleteSnapshots: false) }
            }
            Button(AppLocalizer.t(zh: "取消", en: "Cancel", language: store.language), role: .cancel) {}
        }
    }

    // MARK: - 1. Storage Telemetry

    private var storageBreakdownCard: some View {
        let b = store.storageBreakdown
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(AppLocalizer.t(zh: "本机存储占用", en: "Local Storage Usage", language: store.language), systemImage: "internaldrive.fill")
                    .font(.headline)
                Spacer()
                Text(AppLocalizer.formatByteCount(b.totalBytes))
                    .font(.subheadline.monospacedDigit().bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.14), in: Capsule())
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                statCell(
                    label: AppLocalizer.t(zh: "实时待办", en: "Live Tasks", language: store.language),
                    value: "\(b.totalTodos) (\(AppLocalizer.formatByteCount(b.liveDatabaseBytes)))"
                )
                statCell(
                    label: AppLocalizer.t(zh: "本地快照", en: "Snapshots", language: store.language),
                    value: "\(b.snapshotCount) (\(AppLocalizer.formatByteCount(b.snapshotsTotalBytes)))"
                )
                statCell(
                    label: AppLocalizer.t(zh: "已完成任务", en: "Completed", language: store.language),
                    value: "\(b.completedTodos)"
                )
                statCell(
                    label: AppLocalizer.t(zh: "置顶受保护", en: "Pinned", language: store.language),
                    value: "\(b.pinnedSnapshotCount)"
                )
            }
        }
        .padding(16)
        .pickPlanGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func statCell(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(PickPlanPalette.muted)
            Text(value)
                .font(.subheadline.monospacedDigit().bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - 2. Import & Export

    private var importExportCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(AppLocalizer.t(zh: "本地导入与导出", en: "Local Import & Export", language: store.language), systemImage: "arrow.up.arrow.down.circle.fill")
                .font(.headline)

            Text(AppLocalizer.t(zh: "导出带 SHA256 校验的 .pickplan.json v2 文件或 Markdown 清单，并无损兼容原 Android 版 JSON 导入。", en: "Export SHA256-verified .pickplan.json v2 archives or Markdown, and seamlessly import Android Pickplan v1 JSON.", language: store.language))
                .font(.caption)
                .foregroundStyle(PickPlanPalette.muted)

            Toggle(
                AppLocalizer.t(zh: "导出时包含 AI API Key（默认脱敏隐藏）", en: "Include API Key in exports (hidden by default)", language: store.language),
                isOn: Binding(
                    get: { store.preferences.backupPolicy.includeApiKey },
                    set: { val in
                        var policy = store.preferences.backupPolicy
                        policy.includeApiKey = val
                        Task { await store.updateBackupPolicy(policy) }
                    }
                )
            )
            .font(.subheadline)

            HStack(spacing: 10) {
                Button {
                    if let data = try? store.exportBackupData() {
                        exportDocument = PickPlanExportDocument(data: data)
                        exportContentType = .json
                        exportFileName = "PickPlan-Backup.pickplan.json"
                        showExporter = true
                    }
                } label: {
                    Label(AppLocalizer.t(zh: "导出 JSON", en: "Export JSON", language: store.language), systemImage: "square.and.arrow.up")
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.white, in: Capsule())
                        .foregroundStyle(.black)
                }
                .buttonStyle(PickPlanPressScaleStyle())

                Button {
                    let md = store.exportMarkdownText()
                    exportDocument = PickPlanExportDocument(data: Data(md.utf8))
                    exportContentType = .plainText
                    exportFileName = "PickPlan-Tasks.md"
                    showExporter = true
                } label: {
                    Label(AppLocalizer.t(zh: "导出 MD", en: "Markdown", language: store.language), systemImage: "doc.plaintext")
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .pickPlanGlass(in: Capsule(), interactive: true)
                }
                .buttonStyle(PickPlanPressScaleStyle())
            }

            Button {
                showImporter = true
            } label: {
                Label(AppLocalizer.t(zh: "从本机 / 文件 App 导入备份…", en: "Import Archive from Files…", language: store.language), systemImage: "square.and.arrow.down")
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .pickPlanGlass(in: Capsule(), interactive: true)
            }
            .buttonStyle(PickPlanPressScaleStyle())
        }
        .padding(16)
        .pickPlanGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - 3. Scheduled Auto-Backup Policy

    private var scheduledBackupPolicyCard: some View {
        let policy = store.preferences.backupPolicy
        return VStack(alignment: .leading, spacing: 12) {
            Label(AppLocalizer.t(zh: "定时自动本地备份", en: "Scheduled Auto-Backup", language: store.language), systemImage: "clock.arrow.2.circlepath")
                .font(.headline)

            Toggle(
                AppLocalizer.t(zh: "开启定时自动快照", en: "Enable Scheduled Snapshots", language: store.language),
                isOn: Binding(
                    get: { policy.isEnabled },
                    set: { val in
                        var next = policy
                        next.isEnabled = val
                        Task { await store.updateBackupPolicy(next) }
                    }
                )
            )

            Toggle(
                AppLocalizer.t(zh: "切后台若有改动自动增量备份", en: "Auto-backup on background when changed", language: store.language),
                isOn: Binding(
                    get: { policy.backupOnBackgroundAfterChanges },
                    set: { val in
                        var next = policy
                        next.backupOnBackgroundAfterChanges = val
                        Task { await store.updateBackupPolicy(next) }
                    }
                )
            )

            Picker(
                AppLocalizer.t(zh: "自动周期", en: "Backup Interval", language: store.language),
                selection: Binding(
                    get: { policy.intervalHours },
                    set: { hrs in
                        var next = policy
                        next.intervalHours = hrs
                        Task { await store.updateBackupPolicy(next) }
                    }
                )
            ) {
                Text(AppLocalizer.t(zh: "每 1 小时", en: "Every 1 hour", language: store.language)).tag(1)
                Text(AppLocalizer.t(zh: "每 6 小时", en: "Every 6 hours", language: store.language)).tag(6)
                Text(AppLocalizer.t(zh: "每 12 小时", en: "Every 12 hours", language: store.language)).tag(12)
                Text(AppLocalizer.t(zh: "每天（24 小时）", en: "Daily (24 hours)", language: store.language)).tag(24)
                Text(AppLocalizer.t(zh: "每周（7 天）", en: "Weekly (7 days)", language: store.language)).tag(168)
            }

            DatePicker(
                AppLocalizer.t(zh: "每日首选备份时间", en: "Preferred Daily Time", language: store.language),
                selection: Binding(
                    get: {
                        Calendar.current.date(bySettingHour: policy.preferredHour, minute: policy.preferredMinute, second: 0, of: Date()) ?? Date()
                    },
                    set: { date in
                        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
                        var next = policy
                        next.preferredHour = comps.hour ?? 22
                        next.preferredMinute = comps.minute ?? 0
                        Task { await store.updateBackupPolicy(next) }
                    }
                ),
                displayedComponents: .hourAndMinute
            )

            Picker(
                AppLocalizer.t(zh: "最多保留快照数", en: "Max Retention", language: store.language),
                selection: Binding(
                    get: { policy.maxSnapshots },
                    set: { count in
                        var next = policy
                        next.maxSnapshots = count
                        Task { await store.updateBackupPolicy(next) }
                    }
                )
            ) {
                ForEach([5, 10, 15, 30, 50], id: \.self) { count in
                    Text("\(count)").tag(count)
                }
            }

            Button {
                HapticsBridge.success(store.preferences.hapticsEnabled)
                Task { await store.createManualSnapshot() }
            } label: {
                Label(AppLocalizer.t(zh: "立即备份快照到 Files/Backups", en: "Create Local Snapshot Now", language: store.language), systemImage: "plus.circle.fill")
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.white, in: Capsule())
                    .foregroundStyle(.black)
            }
            .buttonStyle(PickPlanPressScaleStyle())
        }
        .padding(16)
        .pickPlanGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - 4. Snapshot Timeline

    private var snapshotTimelineCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(AppLocalizer.t(zh: "快照时间线与预览回滚", en: "Snapshot Timeline", language: store.language), systemImage: "tray.full.fill")
                .font(.headline)

            if store.snapshots.isEmpty {
                Text(AppLocalizer.t(zh: "尚无本地快照，点击上方按钮即可生成。", en: "No snapshots yet. Tap Create Snapshot above.", language: store.language))
                    .font(.caption)
                    .foregroundStyle(PickPlanPalette.muted)
            } else {
                ForEach(store.snapshots) { snap in
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                if snap.isPinned {
                                    Image(systemName: "pin.fill")
                                        .font(.caption2)
                                }
                                Text(snap.fileName)
                                    .font(.caption.monospaced().bold())
                                    .lineLimit(1)
                            }
                            Text("\(PickPlanDateCodec.formatDisplayDateTime(snap.createdAt)) · \(snap.taskCount) \(AppLocalizer.t(zh: "项", en: "tasks", language: store.language)) · \(AppLocalizer.formatByteCount(snap.byteSize)) · \(snap.trigger.displayName(language: store.language))")
                                .font(.caption2)
                                .foregroundStyle(PickPlanPalette.muted)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if let env = try? store.vault.loadSnapshotPayload(id: snap.id) {
                                previewedEnvelope = env
                                previewedSnapshot = snap
                            }
                        }

                        Spacer()
                        HStack(spacing: 6) {
                            Button {
                                Task { await store.togglePinSnapshot(id: snap.id) }
                            } label: {
                                Image(systemName: snap.isPinned ? "pin.slash" : "pin")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)

                            Button(AppLocalizer.t(zh: "恢复", en: "Restore", language: store.language)) {
                                HapticsBridge.success(store.preferences.hapticsEnabled)
                                Task { await store.restoreSnapshot(id: snap.id) }
                            }
                            .font(.caption.bold())
                            .buttonStyle(.borderedProminent)
                            .tint(.white)
                            .foregroundStyle(.black)

                            Button(role: .destructive) {
                                Task { await store.deleteSnapshot(id: snap.id) }
                            } label: {
                                Image(systemName: "trash")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
        .padding(16)
        .pickPlanGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func snapshotPreviewSheet(_ meta: BackupSnapshotMetadata) -> some View {
        NavigationStack {
            List {
                Section(AppLocalizer.t(zh: "快照信息", en: "Snapshot Metadata", language: store.language)) {
                    LabeledContent(AppLocalizer.t(zh: "文件名", en: "File", language: store.language), value: meta.fileName)
                    LabeledContent(AppLocalizer.t(zh: "任务数", en: "Tasks", language: store.language), value: "\(meta.taskCount)")
                    LabeledContent("SHA256", value: String(meta.checksum.prefix(16)) + "…")
                }

                if let todos = previewedEnvelope?.payload.todos {
                    Section(AppLocalizer.t(zh: "内含任务预览", en: "Included Tasks", language: store.language)) {
                        ForEach(todos) { t in
                            HStack {
                                Image(systemName: t.isCompleted ? "checkmark.square.fill" : "square")
                                Text(t.title)
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle(AppLocalizer.t(zh: "快照内容预览", en: "Snapshot Preview", language: store.language))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalizer.t(zh: "关闭", en: "Close", language: store.language)) {
                        previewedSnapshot = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppLocalizer.t(zh: "恢复此快照", en: "Restore", language: store.language)) {
                        Task {
                            await store.restoreSnapshot(id: meta.id)
                            previewedSnapshot = nil
                        }
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - 5. Data Hygiene

    private var dataHygieneCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(AppLocalizer.t(zh: "本地数据清理与维护", en: "Local Data Hygiene", language: store.language), systemImage: "slider.horizontal.3")
                .font(.headline)

            HStack(spacing: 10) {
                Button(AppLocalizer.t(zh: "清理已完成", en: "Clear Done", language: store.language)) {
                    Task { await store.clearCompletedTodos() }
                }
                .buttonStyle(.bordered)

                Button(AppLocalizer.t(zh: "智能去重", en: "Deduplicate", language: store.language)) {
                    Task { await store.deduplicateTodos() }
                }
                .buttonStyle(.bordered)

                Button(AppLocalizer.t(zh: "清空 AI 记录", en: "Clear AI Chat", language: store.language)) {
                    Task { await store.clearChatHistory() }
                }
                .buttonStyle(.bordered)
            }

            Button(role: .destructive) {
                showResetConfirmation = true
            } label: {
                Label(AppLocalizer.t(zh: "重置全部本地数据…", en: "Factory Reset Local Data…", language: store.language), systemImage: "exclamationmark.triangle")
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)
            .tint(PickPlanPalette.deadlineCoral)
        }
        .padding(16)
        .pickPlanGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var importReviewSheet: some View {
        NavigationStack {
            Form {
                if let summary = importSummary {
                    Section(AppLocalizer.t(zh: "文件校验摘要", en: "Archive Summary", language: store.language)) {
                        LabeledContent(AppLocalizer.t(zh: "识别格式", en: "Format", language: store.language), value: summary.detectedFormatDescription)
                        LabeledContent(AppLocalizer.t(zh: "包含任务", en: "Tasks", language: store.language), value: "\(summary.incomingTaskCount)")
                        LabeledContent(AppLocalizer.t(zh: "新增任务", en: "New Tasks", language: store.language), value: "\(summary.newTaskCount)")
                        if let valid = summary.checksumValid {
                            LabeledContent("SHA256", value: valid ? "Verified" : "Modified")
                        }
                    }

                    Section(AppLocalizer.t(zh: "选择导入方式", en: "Import Strategy", language: store.language)) {
                        Picker(AppLocalizer.t(zh: "策略", en: "Strategy", language: store.language), selection: $selectedImportStrategy) {
                            ForEach(ImportStrategy.allCases) { strategy in
                                Text(strategy.displayName(language: store.language)).tag(strategy)
                            }
                        }
                        .pickerStyle(.inline)
                    }
                }
            }
            .navigationTitle(AppLocalizer.t(zh: "确认导入", en: "Confirm Import", language: store.language))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalizer.t(zh: "取消", en: "Cancel", language: store.language)) {
                        showImportReviewSheet = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppLocalizer.t(zh: "确认导入", en: "Import", language: store.language)) {
                        guard let data = pendingImportData else { return }
                        Task {
                            _ = try? await store.applyImport(data: data, strategy: selectedImportStrategy)
                            pendingImportData = nil
                            showImportReviewSheet = false
                        }
                    }
                    .fontWeight(.bold)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
