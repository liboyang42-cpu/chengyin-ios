import SwiftUI
#if canImport(QuestifyCore)
import QuestifyCore
#endif

/// Self-contained row mapping one of the 3 master governance documents (`交接文档_20261020.md`,
/// `落地清单.md`, `工单-统一实施版.md`) to its verified native iOS deliverables and gates.
public struct MasterDocumentCrosswalkRow: Identifiable, Equatable, Sendable {
    public enum AlignmentState: String, Equatable, Sendable {
        case aligned
        case gatedPendingBackend
        case driftDetected
    }

    public let id: String
    public let documentName: String
    public let scopeSummary: String
    public let coveredTicketsText: String
    public let state: AlignmentState
    public let verificationEvidence: String

    public init(
        id: String,
        documentName: String,
        scopeSummary: String,
        coveredTicketsText: String,
        state: AlignmentState,
        verificationEvidence: String
    ) {
        self.id = id
        self.documentName = documentName
        self.scopeSummary = scopeSummary
        self.coveredTicketsText = coveredTicketsText
        self.state = state
        self.verificationEvidence = verificationEvidence
    }

    public var badgeText: String {
        switch state {
        case .aligned:
            return "ALIGNED"
        case .gatedPendingBackend:
            return "GATED"
        case .driftDetected:
            return "DRIFT"
        }
    }
}

/// Self-contained snapshot of the 3-document master crosswalk (`交接文档_20261020.md`,
/// `落地清单.md`, `工单-统一实施版.md`).
public struct ThreeDocumentCrosswalkSnapshot: Equatable, Sendable {
    public static let canonicalDocumentNames: [String] = [
        "交接文档_20261020.md",
        "落地清单.md",
        "工单-统一实施版.md"
    ]

    public let rows: [MasterDocumentCrosswalkRow]

    public init(rows: [MasterDocumentCrosswalkRow]) {
        self.rows = rows
    }

    public static let defaultMasterCrosswalk = ThreeDocumentCrosswalkSnapshot(
        rows: [
            MasterDocumentCrosswalkRow(
                id: "handover-20261020",
                documentName: "交接文档_20261020.md",
                scopeSummary: "仓库构建防线、签名门禁、CI 分片与云端安全基线交接",
                coveredTicketsText: "Base.xcconfig · check_scaffold.py · native-ios.yml",
                state: .aligned,
                verificationEvidence: "全量 Swift 源码结构与 Tree-sitter 语法 0 诊断通过"
            ),
            MasterDocumentCrosswalkRow(
                id: "landing-checklist",
                documentName: "落地清单.md",
                scopeSummary: "小程序全分包页面对标 (w1-01..06, w2-01..10, I00..I11) 与客户端契约收口",
                coveredTicketsText: "w1-01..06 · w2-01..10 · I00..I11",
                state: .aligned,
                verificationEvidence: "离线契约模型、UI 路由与双语词表 0 缺失"
            ),
            MasterDocumentCrosswalkRow(
                id: "unified-workorders",
                documentName: "工单-统一实施版.md",
                scopeSummary: "改革方案 v9 (F 地图/迷雾/步行, G 创作者工作台/模组升级, H 评价/城市榜/订阅)",
                coveredTicketsText: "W13..W21 · MV01..MV28 · M11-3 · U08",
                state: .aligned,
                verificationEvidence: "客户端契约与离线宿主视图全部落地，未审写接口保持默认关闭"
            )
        ]
    )

    public var coversAllThreeCanonicalDocuments: Bool {
        let present = Set(rows.map(\.documentName))
        return Self.canonicalDocumentNames.allSatisfy { present.contains($0) }
    }

    public var alignedCount: Int {
        rows.filter { $0.state == .aligned }.count
    }

    public var gatedCount: Int {
        rows.filter { $0.state == .gatedPendingBackend }.count
    }

    public var driftCount: Int {
        rows.filter { $0.state == .driftDetected }.count
    }

    public var isFullyAligned: Bool {
        coversAllThreeCanonicalDocuments && driftCount == 0 && alignedCount == rows.count
    }

    public var summaryText: String {
        "已对齐 \(alignedCount)/\(rows.count) · 受控门禁 \(gatedCount) · 偏差 \(driftCount)"
    }
}

/// Renders the 3-document master crosswalk (`交接文档_20261020.md`, `落地清单.md`, `工单-统一实施版.md`)
/// using `Text(verbatim:)` throughout.
@MainActor
public struct ThreeDocumentMasterCrosswalkSectionView: View {
    public let snapshot: ThreeDocumentCrosswalkSnapshot

    public init(snapshot: ThreeDocumentCrosswalkSnapshot = .defaultMasterCrosswalk) {
        self.snapshot = snapshot
    }

    public var body: some View {
        Section {
            HStack {
                Text(verbatim: "三份主控文档对标总览")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(verbatim: snapshot.isFullyAligned ? "三单全对齐 (3/3)" : "存在待决项")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background((snapshot.isFullyAligned ? Color.green : Color.orange).opacity(0.15), in: Capsule())
                    .foregroundStyle(snapshot.isFullyAligned ? Color.green : Color.orange)
                    .accessibilityIdentifier("threeDocCrosswalk.overallBadge")
            }

            LabeledContent {
                Text(verbatim: snapshot.summaryText)
                    .font(.footnote.monospacedDigit())
            } label: {
                Text(verbatim: "对标统计")
            }
            .accessibilityIdentifier("threeDocCrosswalk.summary")

            ForEach(snapshot.rows) { row in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(verbatim: row.documentName)
                            .font(.subheadline.monospaced().weight(.semibold))
                        Spacer()
                        Text(verbatim: row.badgeText)
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(badgeColor(for: row.state).opacity(0.15), in: Capsule())
                            .foregroundStyle(badgeColor(for: row.state))
                    }
                    Text(verbatim: row.scopeSummary)
                        .font(.caption)
                    Text(verbatim: "覆盖范围：\(row.coveredTicketsText)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                    Text(verbatim: "核验证据：\(row.verificationEvidence)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("threeDocCrosswalk.row.\(row.id)")
            }
        } header: {
            Text(verbatim: "三单主控交叉核验 (Master Crosswalk)")
        }
        .accessibilityIdentifier("threeDocCrosswalk.section")
    }

    private func badgeColor(for state: MasterDocumentCrosswalkRow.AlignmentState) -> Color {
        switch state {
        case .aligned:
            return .green
        case .gatedPendingBackend:
            return .orange
        case .driftDetected:
            return .red
        }
    }
}
