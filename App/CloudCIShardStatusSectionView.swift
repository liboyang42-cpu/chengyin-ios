import SwiftUI
#if canImport(QuestifyCore)
import QuestifyCore
#endif

/// Self-contained presentation row for a single GitHub Actions `native-ios.yml` job or test shard.
public struct CIShardStatusRow: Identifiable, Equatable, Sendable {
    public enum Stage: String, Equatable, Sendable {
        case controls
        case build
        case testShard
    }

    public enum ExecutionState: String, Equatable, Sendable {
        case passed
        case pendingRunner
        case failed
    }

    public let id: String
    public let title: String
    public let runnerImage: String
    public let stage: Stage
    public let state: ExecutionState
    public let detail: String

    public init(
        id: String,
        title: String,
        runnerImage: String,
        stage: Stage,
        state: ExecutionState,
        detail: String
    ) {
        self.id = id
        self.title = title
        self.runnerImage = runnerImage
        self.stage = stage
        self.state = state
        self.detail = detail
    }

    public var badgeText: String {
        switch state {
        case .passed:
            return "PASSED"
        case .pendingRunner:
            return "NOT_RUN"
        case .failed:
            return "FAILED"
        }
    }
}

/// Self-contained snapshot of the GitHub Actions `native-ios.yml` pipeline (`controls`, `build`,
/// and `core` / `app-unit` / `ui-0..2` shards).
public struct CIPipelineReadinessSnapshot: Equatable, Sendable {
    public let workflowPath: String
    public let rows: [CIShardStatusRow]

    public init(workflowPath: String = ".github/workflows/native-ios.yml", rows: [CIShardStatusRow]) {
        self.workflowPath = workflowPath
        self.rows = rows
    }

    public static let defaultNativePipeline = CIPipelineReadinessSnapshot(
        rows: [
            CIShardStatusRow(
                id: "controls",
                title: "controls",
                runnerImage: "ubuntu-24.04",
                stage: .controls,
                state: .passed,
                detail: "check_scaffold.py + check_swift_syntax.py"
            ),
            CIShardStatusRow(
                id: "build",
                title: "build",
                runnerImage: "macos-26",
                stage: .build,
                state: .pendingRunner,
                detail: "build-for-testing (Questify + QuestifyAppUnitTests + QuestifyUITests)"
            ),
            CIShardStatusRow(
                id: "core",
                title: "test (core)",
                runnerImage: "macos-26",
                stage: .testShard,
                state: .pendingRunner,
                detail: "swift test --filter QuestifyCoreTests"
            ),
            CIShardStatusRow(
                id: "app-unit",
                title: "test (app-unit)",
                runnerImage: "macos-26",
                stage: .testShard,
                state: .pendingRunner,
                detail: "test-without-building -only-testing:QuestifyAppUnitTests"
            ),
            CIShardStatusRow(
                id: "ui-0",
                title: "test (ui-0)",
                runnerImage: "macos-26",
                stage: .testShard,
                state: .pendingRunner,
                detail: "QuestifyUITests shard 0"
            ),
            CIShardStatusRow(
                id: "ui-1",
                title: "test (ui-1)",
                runnerImage: "macos-26",
                stage: .testShard,
                state: .pendingRunner,
                detail: "QuestifyUITests shard 1"
            ),
            CIShardStatusRow(
                id: "ui-2",
                title: "test (ui-2)",
                runnerImage: "macos-26",
                stage: .testShard,
                state: .pendingRunner,
                detail: "QuestifyUITests shard 2"
            )
        ]
    )

    public var passedCount: Int {
        rows.filter { $0.state == .passed }.count
    }

    public var pendingCount: Int {
        rows.filter { $0.state == .pendingRunner }.count
    }

    public var failedCount: Int {
        rows.filter { $0.state == .failed }.count
    }

    public var summaryText: String {
        "通过 \(passedCount) · 待机执行 \(pendingCount) · 失败 \(failedCount)"
    }
}

/// Renders the GitHub Actions `native-ios.yml` shard matrix using `Text(verbatim:)` throughout.
@MainActor
public struct CloudCIShardStatusSectionView: View {
    public let snapshot: CIPipelineReadinessSnapshot

    public init(snapshot: CIPipelineReadinessSnapshot = .defaultNativePipeline) {
        self.snapshot = snapshot
    }

    public var body: some View {
        Section {
            LabeledContent {
                Text(verbatim: snapshot.workflowPath)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            } label: {
                Text(verbatim: "工作流配置")
            }
            .accessibilityIdentifier("cloudCIShard.workflowPath")

            LabeledContent {
                Text(verbatim: snapshot.summaryText)
                    .font(.footnote.monospacedDigit())
            } label: {
                Text(verbatim: "分片状态汇总")
            }
            .accessibilityIdentifier("cloudCIShard.summary")

            ForEach(snapshot.rows) { row in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(verbatim: row.title)
                            .font(.subheadline.weight(.semibold))
                        Text(verbatim: row.runnerImage)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(verbatim: row.badgeText)
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(badgeColor(for: row.state).opacity(0.15), in: Capsule())
                            .foregroundStyle(badgeColor(for: row.state))
                    }
                    Text(verbatim: row.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("cloudCIShard.row.\(row.id)")
            }
        } header: {
            Text(verbatim: "Cloud CI 流水线与测试分片")
        }
        .accessibilityIdentifier("cloudCIShard.section")
    }

    private func badgeColor(for state: CIShardStatusRow.ExecutionState) -> Color {
        switch state {
        case .passed:
            return .green
        case .pendingRunner:
            return .orange
        case .failed:
            return .red
        }
    }
}
