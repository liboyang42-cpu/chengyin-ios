import SwiftUI
import Core

public struct UnifiedOPT090To092AndEXT01To11SectionView: View {
    public init() {}

    public var body: some View {
        Section("核心链独立读回、真机现场验证、分层签收与11项条件扩展 (OPT-090..092 & EXT-01..11)") {
            ForEach(UnifiedOPT090To092AndEXT01To11ReleaseSignoffContract.releasePackages) { pkg in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(pkg.optID) · \(pkg.title)")
                        .font(.subheadline.weight(.semibold))
                    Text("7层签收: \(pkg.sevenLayerSignoff.joined(separator: " -> "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(UnifiedOPT090To092AndEXT01To11ReleaseSignoffContract.conditionalExtensions) { ext in
                LabeledContent("\(ext.extID) \(ext.title)", value: ext.disposition)
                    .font(.caption)
            }
        }
    }
}
