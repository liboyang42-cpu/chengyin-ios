import SwiftUI

@MainActor struct NativeHomeReturnRunSection: View {
    let model: NativeHomeReturnSelectionCoordinator
    let home: PrivateHomeSnapshot?
    var body: some View {
        if model.isAuthorized {
            Section {
                Text("homeReturn.runBoundary", tableName: "NativeHomeReturn").font(.footnote)
                if model.phase == .loading { ProgressView() }
                if model.phase == .unavailable { Text("homeReturn.unavailable", tableName: "NativeHomeReturn") }
                if model.phase == .blocked { Text("homeReturn.failure.storageUnavailable", tableName: "NativeHomeReturn") }
                if model.phase == .ready, model.runs.isEmpty, !model.truncated, model.selected == nil {
                    Text("homeReturn.noRuns", tableName: "NativeHomeReturn")
                }
                if model.truncated { Text("homeReturn.runsTruncated", tableName: "NativeHomeReturn").font(.footnote) }
                if model.truncated {
                    Button { Task { await model.loadMore() } } label: { Text("homeReturn.loadMoreRuns", tableName: "NativeHomeReturn") }
                        .disabled(!model.canSelect).accessibilityIdentifier("homeReturn.loadMoreRuns")
                }
                if model.loadingMore { ProgressView() }
                if model.paginationUnavailable { Text("homeReturn.moreUnavailable", tableName: "NativeHomeReturn").font(.footnote) }
                ForEach(model.runs) { run in
                    Button { Task { await model.select(run) } } label: {
                        VStack(alignment: .leading) {
                            Text("homeReturn.selectRun", tableName: "NativeHomeReturn") + Text(verbatim: " #\(run.runId)")
                            (Text("homeReturn.sourceActivity", tableName: "NativeHomeReturn") + Text(verbatim: " #\(run.activityId) · ") +
                             Text("homeReturn.sourceTopic", tableName: "NativeHomeReturn") + Text(verbatim: " #\(run.topicId)")).font(.caption)
                        }
                    }.disabled(!model.canSelect).accessibilityIdentifier("homeReturn.run.\(run.runId)")
                }
                Button { Task { await model.load() } } label: { Text("homeReturn.refreshRuns", tableName: "NativeHomeReturn") }
                    .disabled(model.phase == .loading || model.selected?.isBusy == true)
                    .accessibilityIdentifier("homeReturn.refreshRuns")
            } header: { Text("homeReturn.selectRun", tableName: "NativeHomeReturn") }
            if let selected = model.selected, model.phase == .ready {
                NativeHomeReturnSection(model: selected, home: home).id(ObjectIdentifier(selected))
            }
        } else {
            Section { Text("homeReturn.phase.invalidated", tableName: "NativeHomeReturn") }
        }
    }
    // The parent Form's task loads read-only selection; no GPS or restore is automatic.
}

private struct NativeHomeReturnSelectionKey: EnvironmentKey { static let defaultValue: NativeHomeReturnSelectionCoordinator? = nil }
extension EnvironmentValues {
    var nativeHomeReturnSelection: NativeHomeReturnSelectionCoordinator? {
        get { self[NativeHomeReturnSelectionKey.self] }
        set { self[NativeHomeReturnSelectionKey.self] = newValue }
    }
}
