import SwiftUI
#if canImport(QuestifyCore)
import QuestifyCore
#elseif canImport(Core)
import Core
#endif

public struct UnifiedOPT020To023PrivacyModerationSectionView: View {
    public init() {}

    public var body: some View {
        Section("私密内容保护、媒体审核、举报申诉与内容链切换 (OPT-020..023)") {
            ForEach(UnifiedOPT020To023PrivacyModerationTrustAndChainContract.packages) { pkg in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(pkg.optID) · \(pkg.title)")
                        .font(.subheadline.weight(.semibold))
                    Text("旧52单映射: \(pkg.mappedLegacy52Tickets.count) 项 · 切片: \(pkg.reusedSliceIDs.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
