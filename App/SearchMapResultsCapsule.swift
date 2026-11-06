import SwiftUI

/// Mini-program result capsule under the map. Failure retries; a settled result opens the sheet.
struct SearchMapResultsCapsuleView: View {
    let state: SearchMapResultCapsule
    let retry: () -> Void
    let open: () -> Void
    var body: some View {
        Button {
            if state.opensSheet { open() } else if state == .failed { retry() }
        } label: {
            HStack(spacing: 8) {
                if state == .loading { ProgressView().accessibilityHidden(true) }
                switch state {
                case .results(let total, let listOnly):
                    Text("searchMap.w208.capsule.results \(total)")
                    if listOnly > 0 { Text("searchMap.w208.capsule.listOnly \(listOnly)").foregroundStyle(.secondary) }
                default:
                    Text(LocalizedStringKey(state.key))
                }
            }.font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16).padding(.vertical, 10).frame(minHeight: 44)
                .background(.regularMaterial, in: Capsule())
        }.buttonStyle(.plain).disabled(state == .loading || state == .empty)
            .accessibilityIdentifier("searchMap.w208.capsule")
    }
}

/// 全部 N 个结果 sheet. It renders the explorer's current rows only; it never reads by itself.
struct SearchMapAllResultsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let rows: [ActivitySummary]
    let loading: Bool
    let failed: Bool
    let refreshing: Bool
    let refreshFailed: Bool
    let offline: Bool
    let retry: () -> Void
    let open: (ActivitySummary) -> Void
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if refreshing {
                        ProgressView("searchMap.w208.sheet.refreshingActivities")
                        Text("searchMap.w208.sheet.refreshingNodes").font(.footnote).foregroundStyle(.secondary)
                    }
                    if refreshFailed {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("searchMap.w208.sheet.refreshFailed", systemImage: "exclamationmark.circle").font(.headline)
                            Text("searchMap.w208.sheet.refreshFailed.detail").font(.footnote).foregroundStyle(.secondary)
                            Button("mapRefresh.retry", action: retry).frame(minHeight: 44)
                        }.accessibilityIdentifier("searchMap.w208.sheet.refreshFailed")
                    }
                    if loading {
                        ForEach(0..<3, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 18).fill(.secondary.opacity(0.1)).frame(height: 96).accessibilityHidden(true)
                        }
                    } else if failed && rows.isEmpty {
                        ContentUnavailableView {
                            Label("searchMap.w208.sheet.failed", systemImage: "exclamationmark.triangle")
                        } actions: {
                            Button("searchMap.retry", action: retry).frame(minHeight: 44)
                        }.accessibilityIdentifier("searchMap.w208.sheet.failed")
                    } else if rows.isEmpty {
                        ContentUnavailableView("searchMap.w208.capsule.empty", systemImage: "mappin.slash",
                                               description: Text("searchMap.w208.sheet.emptyHint"))
                            .accessibilityIdentifier("searchMap.w208.sheet.empty")
                    }
                    let listOnly = rows.filter { !$0.hasValidCoordinates }.count
                    if listOnly > 0 {
                        Text("searchMap.w208.sheet.listOnlyTip \(listOnly)").font(.footnote).foregroundStyle(.secondary)
                            .accessibilityIdentifier("searchMap.w208.sheet.listOnlyTip")
                    }
                    ForEach(rows) { row in
                        Button { open(row) } label: { SearchMapActivityCard(item: row, offline: offline) }
                            .buttonStyle(QuestifyCardButtonStyle())
                            .accessibilityIdentifier("searchMap.w208.sheet.activity.\(row.id)")
                    }
                }.padding()
            }
            .navigationTitle(rows.isEmpty ? Text("searchMap.w208.sheet.title") : Text("searchMap.w208.sheet.titleCount \(rows.count)"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("searchMap.cancel") { dismiss() }.accessibilityIdentifier("searchMap.w208.sheet.close")
                }
            }
        }
    }
}
