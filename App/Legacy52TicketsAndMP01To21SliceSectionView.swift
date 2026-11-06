import SwiftUI
#if canImport(QuestifyCore)
import QuestifyCore
#elseif canImport(Core)
import Core
#endif

public struct Legacy52TicketsAndMP01To21SliceSectionView: View {
    public init() {}

    public var body: some View {
        Section("业务必需52单映射与MP-01..21切片全量对齐") {
            LabeledContent("旧52单闭环数", value: "\(Legacy52TicketsAndMP01To21SliceParityContract.all52LegacyTickets.count)/52")
            LabeledContent("MP切片对齐数", value: "\(Legacy52TicketsAndMP01To21SliceParityContract.all21MiniProgramSlices.count)/21")
            ForEach(Legacy52TicketsAndMP01To21SliceParityContract.all21MiniProgramSlices) { slice in
                LabeledContent("\(slice.sliceID) (\(slice.parentOPT))", value: slice.summary)
                    .font(.caption)
            }
        }
    }
}
