import SwiftUI
import Core

public struct UnifiedOPT050To053ClubScheduleBroadcastSectionView: View {
    public init() {}

    public var body: some View {
        Section("俱乐部会费合同、64期排期候补、带队位置共享与置顶广播 (OPT-050..053)") {
            ForEach(UnifiedOPT050To053ClubMembershipScheduleLeadAndBroadcastContract.packages) { pkg in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(pkg.optID) · \(pkg.title)")
                        .font(.subheadline.weight(.semibold))
                    Text("旧52单: \(pkg.mappedLegacy52Tickets.count) 项 · 决策: \(pkg.decisionDependencies.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
