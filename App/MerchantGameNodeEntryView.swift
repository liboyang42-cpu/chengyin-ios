import SwiftUI

/// The accepted-project "更多" rows (howto / service / review / pause): authorised station entries
/// filtered by topic. None explains why, one opens the station page, several ask for 选择场次.
@MainActor struct MerchantGameNodeEntryView: View {
    let service: any MerchantGameNodeServing
    let topicID: Int?
    var focusPause = false
    @State private var result: MerchantGameNodeEntriesResult?
    @State private var loadedScope: UUID?
    private var rows: [MerchantGameNodeEntry] {
        guard case .ready(let entries)? = result else { return [] }
        guard let topicID else { return entries }
        return entries.filter { $0.topicID == topicID && $0.activityID > 0 }
    }
    var body: some View {
        Group {
            if loadedScope != service.scope || result == nil {
                ProgressView().frame(maxWidth: .infinity, minHeight: 200)
            } else if case .failure(let message)? = result {
                VStack(spacing: 12) {
                    MerchantGameNodeCopy.text(message)
                    Button { Task { await load() } } label: { MerchantGameNodeCopy.text("merchantGameNode.retry") }
                        .buttonStyle(.bordered).accessibilityIdentifier("gameNode.entries.retry")
                }.frame(maxWidth: .infinity, minHeight: 200).accessibilityIdentifier("gameNode.entries.failure")
            } else if rows.isEmpty {
                VStack(spacing: 8) {
                    MerchantGameNodeCopy.text("merchantGameNode.entries.noneTitle").font(.headline)
                    MerchantGameNodeCopy.text("merchantGameNode.entries.noneMessage").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.padding().frame(maxWidth: .infinity, minHeight: 200).accessibilityIdentifier("gameNode.entries.none")
            } else if rows.count == 1, let only = rows.first {
                MerchantGameNodeView(service: service, activityID: only.activityID, focusPause: focusPause).id(only.activityID)
            } else {
                List {
                    Section {
                        ForEach(rows) { entry in
                            NavigationLink {
                                MerchantGameNodeView(service: service, activityID: entry.activityID, focusPause: focusPause)
                            } label: {
                                if entry.activityName.isEmpty { MerchantGameNodeCopy.text("merchantGameNode.entries.untitled") }
                                else { Text(verbatim: String(entry.activityName.prefix(30))) }
                            }.accessibilityIdentifier("gameNode.entries.\(entry.activityID)")
                        }
                    } header: { MerchantGameNodeCopy.text("merchantGameNode.entries.pick") }
                }
            }
        }
        .navigationTitle(MerchantGameNodeCopy.string("merchantGameNode.title"))
        .task(id: service.scope) { await load() }
    }
    private func load() async {
        let scope = service.scope
        result = nil
        let value = await service.loadEntries()
        guard scope == service.scope, !Task.isCancelled else { return }
        result = value; loadedScope = scope
    }
}
