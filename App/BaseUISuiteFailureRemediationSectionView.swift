import SwiftUI
import Core

public struct BaseUISuiteFailureRemediationSectionView: View {
    public init() {}

    public var body: some View {
        Section("Base UI 测试分片与 gitleaks 门禁修复闭环") {
            ForEach(BaseUISuiteFailureRemediationCoordinator.clusters) { cluster in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(cluster.clusterID) · \(cluster.title)")
                        .font(.subheadline.weight(.semibold))
                    Text(cluster.remediationApplied)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
