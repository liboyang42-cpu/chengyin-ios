import SwiftUI
import Core

public struct UnifiedOPT040To043PlayGPSPassportSectionView: View {
    public init() {}

    public var body: some View {
        Section("跨设备恢复、80m GPS闸门、后台音频时钟与护照徽章 (OPT-040..043)") {
            ForEach(UnifiedOPT040To043PlayRecoveryGPSAudioAndPassportContract.packages) { pkg in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(pkg.optID) · \(pkg.title)")
                        .font(.subheadline.weight(.semibold))
                    Text("旧52单: \(pkg.mappedLegacy52Tickets.count) 项 · 切片: \(pkg.reusedSliceIDs.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
