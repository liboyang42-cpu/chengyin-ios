import SwiftUI
#if canImport(QuestifyCore)
import QuestifyCore
#elseif canImport(Core)
import Core
#endif

public struct UnifiedOPT060To062MerchantAggregateCRMSectionView: View {
    public init() {}

    public var body: some View {
        Section("商家认领履约、同口径经营看板与CRM触达权限 (OPT-060..062)") {
            ForEach(UnifiedOPT060To062MerchantClaimAggregateAndCRMContract.packages) { pkg in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(pkg.optID) · \(pkg.title)")
                        .font(.subheadline.weight(.semibold))
                    Text("实现: \(pkg.iosCoreImplementation) -> \(pkg.iosViewImplementation)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
