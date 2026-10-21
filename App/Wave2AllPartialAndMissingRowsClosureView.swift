import SwiftUI
#if canImport(QuestifyCore)
import QuestifyCore
#elseif canImport(Core)
import Core
#endif

public struct Wave2AllPartialAndMissingRowsClosureView: View {
    public init() {}

    public var body: some View {
        Section("Wave-2 (w2-01..w2-21) 全部部分/缺失项清零总表") {
            LabeledContent("总跟踪条目", value: "\(Wave2AllPartialAndMissingRowsClosureCoordinator.totalTrackedRows) 项")
            LabeledContent("部分升对齐", value: "+\(Wave2AllPartialAndMissingRowsClosureCoordinator.totalUpgradedFromPartial) 项")
            LabeledContent("缺失升对齐", value: "+\(Wave2AllPartialAndMissingRowsClosureCoordinator.totalUpgradedFromMissing) 项")
            ForEach(Wave2AllPartialAndMissingRowsClosureCoordinator.laneClosures) { lane in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(lane.laneID) · \(lane.title) (\(lane.currentAlignedOrSupersetCount)/\(lane.totalRows))")
                        .font(.subheadline.weight(.semibold))
                    ForEach(lane.keyUpgradesDelivered, id: \.self) { item in
                        Text("• \(item)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
