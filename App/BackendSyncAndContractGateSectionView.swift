import SwiftUI
#if canImport(QuestifyCore)
import QuestifyCore
#endif

/// Self-contained presentation row for one backend sync or source contract gate pillar.
public struct BackendContractGatePillarRow: Identifiable, Equatable, Sendable {
    public let id: String
    public let scopeCode: String
    public let title: String
    public let contractRuleSummary: String
    public let evidenceSummary: String
    public let isPassing: Bool

    public init(
        id: String,
        scopeCode: String,
        title: String,
        contractRuleSummary: String,
        evidenceSummary: String,
        isPassing: Bool = true
    ) {
        self.id = id
        self.scopeCode = scopeCode
        self.title = title
        self.contractRuleSummary = contractRuleSummary
        self.evidenceSummary = evidenceSummary
        self.isPassing = isPassing
    }

    public var statusBadgeText: String {
        isPassing ? "PASS · FAIL-CLOSED" : "GATE FAILED"
    }

    public var summaryLineText: String {
        "\(scopeCode) · \(title) · \(statusBadgeText)"
    }
}

/// Self-contained snapshot of the 4 backend sync & contract gate pillars
/// (`BK` backend sync contracts, `w2-21` map core entry router, 8 `Tests/ContractChecks` suites,
/// and `current_ci.py check` manifest integrity).
public struct BackendSyncAndContractGateSnapshot: Equatable, Sendable {
    public let pillars: [BackendContractGatePillarRow]
    public let contractCheckSuiteCount: Int
    public let bkSyncItemCount: Int
    public let ciLedgerVerdict: String

    public init(
        pillars: [BackendContractGatePillarRow] = Self.defaultPillars,
        contractCheckSuiteCount: Int = 8,
        bkSyncItemCount: Int = 8,
        ciLedgerVerdict: String = "PASS_CURRENT_SOURCE_LEDGER"
    ) {
        self.pillars = pillars
        self.contractCheckSuiteCount = contractCheckSuiteCount
        self.bkSyncItemCount = bkSyncItemCount
        self.ciLedgerVerdict = ciLedgerVerdict
    }

    public static let defaultPillars: [BackendContractGatePillarRow] = [
        .init(
            id: "BK-backend-sync-contracts",
            scopeCode: "BK",
            title: "BK Backend Sync Contracts (8 E-Series Items)",
            contractRuleSummary: "Explicit type=0/1 topic like direction, communityV1 bookmark generation fence, and readback-only unbookmark resolution",
            evidenceSummary: "E06-17, E01-19, E02-23, E02-12, E02-24, E02-25, E04-07, E01-13 · TEST_DEPLOYED=NO"
        ),
        .init(
            id: "w2-21-map-core-entry-router",
            scopeCode: "w2-21",
            title: "w2-21 Map Core Entry Router & Availability Catalog",
            contractRuleSummary: "Offline map core entry hub routing existing surfaces and keeping unreviewed entries disabled with explicit explanations",
            evidenceSummary: "MapCoreEntry catalog + MapMarkerVisualState legend + location share default OFF"
        ),
        .init(
            id: "ContractChecks-8-suites",
            scopeCode: "ContractChecks",
            title: "8 Tests/ContractChecks Source Gate Suites",
            contractRuleSummary: "Static source guards enforcing zero unapproved transport, default-off switches, bilingual catalogs, and redacted private home data",
            evidenceSummary: "8/8 suites green (bk_backend_sync, merchant_ai_commerce, reform_world, square_workspace, social, profile, roam, scaffold)"
        ),
        .init(
            id: "CI-current-ci-manifest",
            scopeCode: "CI-Manifest",
            title: "current_ci.py check Manifest & Scaffold Integrity",
            contractRuleSummary: "Unique Swift basenames per target, deterministic project.pbxproj generation, and SHA-verified source ledger",
            evidenceSummary: "check_scaffold.py PASS · current_ci.py check: PASS_CURRENT_SOURCE_LEDGER"
        )
    ]

    public static let defaultPassing = BackendSyncAndContractGateSnapshot()

    public var passingPillarCount: Int {
        pillars.filter(\.isPassing).count
    }

    public var allGatesPassing: Bool {
        pillars.count == 4
            && passingPillarCount == pillars.count
            && contractCheckSuiteCount == 8
            && bkSyncItemCount == 8
            && ciLedgerVerdict == "PASS_CURRENT_SOURCE_LEDGER"
    }

    public var overallSummaryText: String {
        "Backend & Contract Gates: \(passingPillarCount)/\(pillars.count) · BK Items: \(bkSyncItemCount) · ContractChecks: \(contractCheckSuiteCount)/8 · Ledger: \(ciLedgerVerdict)"
    }
}

/// Renders the 4 backend sync & contract gate pillars (`BK` backend sync contracts,
/// `w2-21` map core entry router, 8 `Tests/ContractChecks` suites, and `current_ci.py check`
/// manifest integrity) using `Text(verbatim:)` throughout (0 new `.xcstrings` keys).
@MainActor
public struct BackendSyncAndContractGateSectionView: View {
    public let snapshot: BackendSyncAndContractGateSnapshot

    public init(snapshot: BackendSyncAndContractGateSnapshot = .defaultPassing) {
        self.snapshot = snapshot
    }

    public var headerBadgeText: String {
        snapshot.allGatesPassing
            ? "CONTRACT GATES GREEN (4/4)"
            : "CONTRACT GATE VIOLATION (\(snapshot.passingPillarCount)/\(snapshot.pillars.count))"
    }

    public var overallSummaryText: String {
        snapshot.overallSummaryText
    }

    public var pillarScopeCodesText: String {
        snapshot.pillars.map(\.scopeCode).joined(separator: ", ")
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerSection
            pillarsSection
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("backendContractGate.root")
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(verbatim: "Backend Sync & Contract Gate Verification")
                    .font(.headline)
                Spacer()
                Text(verbatim: headerBadgeText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(snapshot.allGatesPassing ? Color.green : Color.red)
                    .accessibilityIdentifier("backendContractGate.statusBadge")
            }

            Text(verbatim: overallSummaryText)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("backendContractGate.overallSummary")
        }
    }

    private var pillarsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(snapshot.pillars) { pillar in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(verbatim: pillar.title)
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(verbatim: pillar.statusBadgeText)
                            .font(.caption2.monospaced())
                            .foregroundStyle(pillar.isPassing ? Color.green : Color.red)
                            .accessibilityIdentifier("backendContractGate.pillarStatus.\(pillar.id)")
                    }

                    Text(verbatim: pillar.contractRuleSummary)
                        .font(.caption)
                        .foregroundStyle(.primary)

                    Text(verbatim: pillar.evidenceSummary)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("backendContractGate.pillarEvidence.\(pillar.id)")
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                )
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("backendContractGate.pillarRow.\(pillar.id)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("backendContractGate.pillarsSection")
    }
}
