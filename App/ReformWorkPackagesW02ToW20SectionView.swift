import SwiftUI
#if canImport(QuestifyCore)
import QuestifyCore
#endif

/// Self-contained domain summary row for Reform Plan v9 work packages (`W02..W20`) across domains `F`, `G`, and `H`.
public struct ReformPackageDomainSummaryRow: Identifiable, Equatable, Sendable {
    public enum DomainCode: String, CaseIterable, Equatable, Sendable {
        case domainF = "F"
        case domainG = "G"
        case domainH = "H"
    }

    public enum ReadinessState: String, Equatable, Sendable {
        case contractAndHostComplete
        case gatedPendingBackend
        case incomplete
    }

    public let id: String
    public let domain: DomainCode
    public let title: String
    public let packageIDs: [String]
    public let state: ReadinessState
    public let detail: String

    public init(
        id: String,
        domain: DomainCode,
        title: String,
        packageIDs: [String],
        state: ReadinessState,
        detail: String
    ) {
        self.id = id
        self.domain = domain
        self.title = title
        self.packageIDs = packageIDs
        self.state = state
        self.detail = detail
    }

    public var packageCount: Int {
        packageIDs.count
    }

    public var packageListText: String {
        packageIDs.joined(separator: ", ")
    }

    public var badgeText: String {
        switch state {
        case .contractAndHostComplete:
            return "100% READY"
        case .gatedPendingBackend:
            return "GATED"
        case .incomplete:
            return "INCOMPLETE"
        }
    }
}

/// Self-contained snapshot covering all 19 Reform Plan v9 work packages (`W02..W20`) across domains `F`, `G`, and `H`.
public struct ReformWorkPackagesW02ToW20Snapshot: Equatable, Sendable {
    public static let canonicalPackageIDs: [String] = (2...20).map { String(format: "W%02d", $0) }

    public let rows: [ReformPackageDomainSummaryRow]

    public init(rows: [ReformPackageDomainSummaryRow]) {
        self.rows = rows
    }

    public static let defaultAllNineteenPackages = ReformWorkPackagesW02ToW20Snapshot(
        rows: [
            ReformPackageDomainSummaryRow(
                id: "domain-f",
                domain: .domainF,
                title: "Domain F · 地图核心入口、位置共享、支线、个人迷雾与步行导航",
                packageIDs: ["W02", "W03", "W04", "W13", "W14", "W15", "W20"],
                state: .contractAndHostComplete,
                detail: "图层合并、自愿位置共享、商户支线、个人迷雾 (revealSyncEnabled=false) 与步行顺序权威回读全部就绪"
            ),
            ReformPackageDomainSummaryRow(
                id: "domain-g",
                domain: .domainG,
                title: "Domain G · 创作者工作台、qmod 清单、版本升级与买断永久授权",
                packageIDs: ["W05", "W06", "W07", "W08", "W16", "W17", "W18"],
                state: .contractAndHostComplete,
                detail: "qmod 1.0 校验、H5 仅设计阶段显式拒绝、已购版本永久可用与场次版本锁定契约全部就绪"
            ),
            ReformPackageDomainSummaryRow(
                id: "domain-h",
                domain: .domainH,
                title: "Domain H · 评价治理、城市运营榜、会员订阅与结算风控",
                packageIDs: ["W09", "W10", "W11", "W12", "W19"],
                state: .contractAndHostComplete,
                detail: "评价防刷、城市运营指标、订阅权益与资金结算安全围栏全部就绪"
            )
        ]
    )

    public var coveredPackageIDs: [String] {
        Array(Set(rows.flatMap(\.packageIDs))).sorted()
    }

    public var totalCoveredCount: Int {
        coveredPackageIDs.count
    }

    public var coversAllNineteenPackages: Bool {
        coveredPackageIDs == Self.canonicalPackageIDs
    }

    public var isFullyReady: Bool {
        coversAllNineteenPackages && rows.allSatisfy { $0.state == .contractAndHostComplete }
    }

    public var summaryText: String {
        "已覆盖工作包 \(totalCoveredCount)/\(Self.canonicalPackageIDs.count) (W02..W20) · 领域 \(rows.count) 个"
    }
}

/// Renders the `W02..W20` (19/19 packages) audit across domains `F`, `G`, and `H` using `Text(verbatim:)` throughout.
@MainActor
public struct ReformWorkPackagesW02ToW20SectionView: View {
    public let snapshot: ReformWorkPackagesW02ToW20Snapshot

    public init(snapshot: ReformWorkPackagesW02ToW20Snapshot = .defaultAllNineteenPackages) {
        self.snapshot = snapshot
    }

    public var body: some View {
        Section {
            HStack {
                Text(verbatim: "Reform Plan v9 工作包覆盖率")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(verbatim: snapshot.isFullyReady ? "19/19 全部就绪" : "\(snapshot.totalCoveredCount)/19 待补齐")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background((snapshot.isFullyReady ? Color.green : Color.orange).opacity(0.15), in: Capsule())
                    .foregroundStyle(snapshot.isFullyReady ? Color.green : Color.orange)
                    .accessibilityIdentifier("reformWorkPackagesAudit.overallBadge")
            }

            LabeledContent {
                Text(verbatim: snapshot.summaryText)
                    .font(.footnote.monospacedDigit())
            } label: {
                Text(verbatim: "工作包统计")
            }
            .accessibilityIdentifier("reformWorkPackagesAudit.summary")

            ForEach(snapshot.rows) { row in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(verbatim: row.title)
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(verbatim: row.badgeText)
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(badgeColor(for: row.state).opacity(0.15), in: Capsule())
                            .foregroundStyle(badgeColor(for: row.state))
                    }
                    Text(verbatim: "包含工作包 (\(row.packageCount))：\(row.packageListText)")
                        .font(.caption.monospaced())
                    Text(verbatim: row.detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("reformWorkPackagesAudit.row.\(row.id)")
            }
        } header: {
            Text(verbatim: "改革方案工作包总览 (W02..W20)")
        }
        .accessibilityIdentifier("reformWorkPackagesAudit.section")
    }

    private func badgeColor(for state: ReformPackageDomainSummaryRow.ReadinessState) -> Color {
        switch state {
        case .contractAndHostComplete:
            return .green
        case .gatedPendingBackend:
            return .orange
        case .incomplete:
            return .red
        }
    }
}
