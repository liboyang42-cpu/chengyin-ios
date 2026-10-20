import SwiftUI
import Core

public struct UnifiedOPT001To003FoundationSectionView: View {
    public init() {}

    public var body: some View {
        Section("Stage 0 基线与509条旧线索复核 (OPT-001..003 & D-01..D-10)") {
            LabeledContent("主账版本", value: UnifiedOPT001To003FoundationAnd509DefectTriageContract.masterLedgerVersion)
            LabeledContent("509旧线索保真", value: "\(UnifiedOPT001To003FoundationAnd509DefectTriageContract.totalLegacyCluesPreserved) 条")
            ForEach(UnifiedOPT001To003FoundationAnd509DefectTriageContract.foundationPackages) { pkg in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(pkg.optID) · \(pkg.title)")
                        .font(.subheadline.weight(.semibold))
                    Text("优先级 \(pkg.priority) · 关联线索 \(pkg.trackedLegacyClueCount) 条")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(UnifiedOPT001To003FoundationAnd509DefectTriageContract.policyDecisions) { decision in
                LabeledContent("\(decision.decisionID.rawValue) \(decision.title)", value: decision.iosEnforcedDefault)
                    .font(.caption)
            }
        }
    }
}
