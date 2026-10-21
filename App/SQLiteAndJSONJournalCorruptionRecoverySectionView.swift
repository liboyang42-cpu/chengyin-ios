import SwiftUI
#if canImport(QuestifyCore)
import QuestifyCore
#endif

/// Self-contained row modeling atomic write-rename durability, corrupt payload quarantine,
/// and schema version validation for one local durable store.
public struct DurableStoreRecoveryRow: Sendable, Equatable, Identifiable {
    public enum StoreKind: String, CaseIterable, Sendable, Equatable {
        case runAuthorityJournal = "RunAuthorityJournal"
        case offlineActionOutbox = "OfflineActionOutbox"
        case walkingCheckpointStore = "WalkingCheckpointStore"
        case roamTileAndDraftCache = "RoamTileAndDraftCache"
    }

    public enum Status: String, Sendable, Equatable {
        case healthy
        case quarantinedWarning
    }

    public let id: String
    public let storeKind: StoreKind
    public let schemaVersion: Int
    public let titleText: String
    public let atomicWriteRenameVerified: Bool
    public let corruptPayloadQuarantined: Bool
    public let statusDetailText: String
    public let status: Status

    public init(
        id: String,
        storeKind: StoreKind,
        schemaVersion: Int,
        titleText: String,
        atomicWriteRenameVerified: Bool = true,
        corruptPayloadQuarantined: Bool = false,
        statusDetailText: String,
        status: Status = .healthy
    ) {
        self.id = id
        self.storeKind = storeKind
        self.schemaVersion = schemaVersion
        self.titleText = titleText
        self.atomicWriteRenameVerified = atomicWriteRenameVerified
        self.corruptPayloadQuarantined = corruptPayloadQuarantined
        self.statusDetailText = statusDetailText
        self.status = status
    }

    public var isHealthy: Bool {
        status == .healthy && atomicWriteRenameVerified && !corruptPayloadQuarantined && schemaVersion > 0
    }

    public var statusBadgeText: String {
        switch status {
        case .healthy:
            return "原子落盘正常"
        case .quarantinedWarning:
            return "已隔离损坏分片"
        }
    }
}

/// Self-contained snapshot of atomic write-rename durability, corrupt payload quarantine,
/// and schema version validation across all 4 local stores.
public struct JournalCorruptionRecoverySnapshot: Sendable, Equatable {
    public let rows: [DurableStoreRecoveryRow]

    public init(
        runJournalHealthy: Bool = true,
        offlineOutboxHealthy: Bool = true,
        walkingCheckpointHealthy: Bool = true,
        roamTileCacheHealthy: Bool = true
    ) {
        self.rows = [
            DurableStoreRecoveryRow(
                id: "store-run-authority-journal",
                storeKind: .runAuthorityJournal,
                schemaVersion: 1,
                titleText: "权威场次意图日志 (RunAuthorityJournal · H-W03)",
                atomicWriteRenameVerified: runJournalHealthy,
                corruptPayloadQuarantined: !runJournalHealthy,
                statusDetailText: runJournalHealthy
                    ? "采用临时文件原子 write-rename 落盘，未知响应重启后凭原 requestId 服务端回读恢复。"
                    : "告警：检测到场次意图日志损坏或非原子写入，已隔离损坏载荷并要求服务端快照校准。",
                status: runJournalHealthy ? .healthy : .quarantinedWarning
            ),
            DurableStoreRecoveryRow(
                id: "store-offline-action-outbox",
                storeKind: .offlineActionOutbox,
                schemaVersion: 1,
                titleText: "离线幂等动作发件箱 (OfflineActionOutbox · I02)",
                atomicWriteRenameVerified: offlineOutboxHealthy,
                corruptPayloadQuarantined: !offlineOutboxHealthy,
                statusDetailText: offlineOutboxHealthy
                    ? "严格校验 schemaVersion == 1 与 SHA-256 摘要，损坏条目自动移入隔离区且不阻塞主线程。"
                    : "告警：发件箱存在损坏 JSON 条目，已移入隔离区等待回读清理。",
                status: offlineOutboxHealthy ? .healthy : .quarantinedWarning
            ),
            DurableStoreRecoveryRow(
                id: "store-walking-checkpoint",
                storeKind: .walkingCheckpointStore,
                schemaVersion: 1,
                titleText: "步行导航断点存储 (WalkingCheckpointStore · W15)",
                atomicWriteRenameVerified: walkingCheckpointHealthy,
                corruptPayloadQuarantined: !walkingCheckpointHealthy,
                statusDetailText: walkingCheckpointHealthy
                    ? "断点进度按会话世代与路线版本绑定，旧版本或截断文件自动丢弃并从权威路线状态重建。"
                    : "告警：步行导航断点文件校验未通过，已回退至服务端路线进度。",
                status: walkingCheckpointHealthy ? .healthy : .quarantinedWarning
            ),
            DurableStoreRecoveryRow(
                id: "store-roam-tile-draft-cache",
                storeKind: .roamTileAndDraftCache,
                schemaVersion: 1,
                titleText: "漫游迷雾瓦片与草稿缓存 (RoamTileAndDraftCache · I06 / U01)",
                atomicWriteRenameVerified: roamTileCacheHealthy,
                corruptPayloadQuarantined: !roamTileCacheHealthy,
                statusDetailText: roamTileCacheHealthy
                    ? "SQLite / JSON 缓存严格按账号隔离，草稿恢复仅保留服务端已确认回读条目。"
                    : "告警：本地缓存分片校验异常，已隔离损坏缓存并触发安全重建。",
                status: roamTileCacheHealthy ? .healthy : .quarantinedWarning
            )
        ]
    }

    public static let defaultReady = JournalCorruptionRecoverySnapshot()

    public var isAllHealthy: Bool {
        !rows.isEmpty && rows.allSatisfy(\.isHealthy)
    }

    public var warningCount: Int {
        rows.filter { !$0.isHealthy }.count
    }

    public var summaryHeadlineText: String {
        isAllHealthy
            ? "4 大本地持久化存储（原子写入 / 损坏隔离 / Schema 校验）全部正常（\(rows.count)/\(rows.count)）"
            : "存在 \(warningCount) 项本地存储损坏隔离告警，已启动回读安全恢复"
    }

    public func row(for storeKind: DurableStoreRecoveryRow.StoreKind) -> DurableStoreRecoveryRow? {
        rows.first { $0.storeKind == storeKind }
    }
}

/// Offline SwiftUI section view displaying atomic write-rename durability, corrupt payload
/// quarantine, and schema version validation across all 4 local stores using `Text(verbatim:)`
/// (`0` new localization keys) and deterministic `journalCorruptionRecovery.*` accessibility hooks.
@MainActor
public struct SQLiteAndJSONJournalCorruptionRecoverySectionView: View {
    public let snapshot: JournalCorruptionRecoverySnapshot
    public var onSelectRow: ((DurableStoreRecoveryRow) -> Void)?

    public init(
        snapshot: JournalCorruptionRecoverySnapshot = .defaultReady,
        onSelectRow: ((DurableStoreRecoveryRow) -> Void)? = nil
    ) {
        self.snapshot = snapshot
        self.onSelectRow = onSelectRow
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: "SQLite 与 JSON 意图日志损坏隔离恢复面板")
                        .font(.headline)
                        .accessibilityIdentifier("journalCorruptionRecovery.header.title")
                    Text(verbatim: snapshot.summaryHeadlineText)
                        .font(.subheadline)
                        .foregroundStyle(snapshot.isAllHealthy ? .green : .orange)
                        .accessibilityIdentifier("journalCorruptionRecovery.header.summary")
                }
                Spacer()
                Text(verbatim: snapshot.isAllHealthy ? "存储完好" : "隔离恢复中")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(
                            snapshot.isAllHealthy
                                ? Color.green.opacity(0.15)
                                : Color.orange.opacity(0.15)
                        )
                    )
                    .accessibilityIdentifier("journalCorruptionRecovery.header.badge")
            }

            ForEach(snapshot.rows) { row in
                rowView(row)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.08)))
        .accessibilityIdentifier("journalCorruptionRecovery.section")
    }

    @ViewBuilder
    private func rowView(_ row: DurableStoreRecoveryRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: row.titleText)
                    .font(.subheadline.weight(.medium))
                    .accessibilityIdentifier("journalCorruptionRecovery.row.\(row.id).title")
                Spacer()
                Text(verbatim: "v\(row.schemaVersion)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("journalCorruptionRecovery.row.\(row.id).schema")
                Text(verbatim: row.statusBadgeText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(row.isHealthy ? .green : .orange)
                    .accessibilityIdentifier("journalCorruptionRecovery.row.\(row.id).status")
            }

            Text(verbatim: row.statusDetailText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("journalCorruptionRecovery.row.\(row.id).detail")

            if let onSelectRow {
                Button(action: { onSelectRow(row) }) {
                    Text(verbatim: "查看存储恢复详情")
                        .font(.caption)
                }
                .accessibilityIdentifier("journalCorruptionRecovery.row.\(row.id).action")
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.06)))
        .accessibilityIdentifier("journalCorruptionRecovery.row.\(row.id)")
    }
}
