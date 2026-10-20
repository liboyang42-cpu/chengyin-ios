import SwiftUI
import Core

public struct UnifiedOPT080To082AISafetyAndDraftSectionView: View {
    public init() {}

    public var body: some View {
        Section("AI网关安全、真实用量返还/NPC删除与作者AI草稿 (OPT-080..082)") {
            ForEach(UnifiedOPT080To082AIGatewaySafetyUsageAndDraftAssistContract.packages) { pkg in
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
