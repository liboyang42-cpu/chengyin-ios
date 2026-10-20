import SwiftUI
import Core

public struct UnifiedOPT030To033AuthorCreatorSectionView: View {
    public init() {}

    public var body: some View {
        Section("作者草稿读回、结局兼容、版本快照与创作者中心 (OPT-030..033)") {
            ForEach(UnifiedOPT030To033AuthorDraftEndingVersionAndCreatorContract.packages) { pkg in
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
