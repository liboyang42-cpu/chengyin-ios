import SwiftUI
#if canImport(QuestifyCore)
import QuestifyCore
#elseif canImport(Core)
import Core
#endif

public struct UnifiedOPT010To014CommerceLedgerSectionView: View {
    public init() {}

    public var body: some View {
        Section("积分报价、购物车原子性、退款与商家账本 (OPT-010..014)") {
            ForEach(UnifiedOPT010To014CommerceCartRefundAndLedgerContract.packages) { pkg in
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
