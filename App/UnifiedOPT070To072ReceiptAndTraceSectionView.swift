import SwiftUI
import Core

public struct UnifiedOPT070To072ReceiptAndTraceSectionView: View {
    public init() {}

    public var body: some View {
        Section("共享回执表单合同、迁移回退门禁与关键链追踪 (OPT-070..072)") {
            ForEach(UnifiedOPT070To072ReceiptCapabilitiesMigrationAndTraceContract.packages) { pkg in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(pkg.optID) · \(pkg.title)")
                        .font(.subheadline.weight(.semibold))
                    Text("切片: \(pkg.reusedSliceIDs.joined(separator: ", ")) · 视图: \(pkg.iosViewImplementation)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
