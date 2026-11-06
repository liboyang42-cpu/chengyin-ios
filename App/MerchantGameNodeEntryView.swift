import SwiftUI

/// The accepted-project "更多" rows (howto / service / review / pause): authorised station entries
/// filtered by topic. None explains why, one opens the station page, several ask for 选择场次.
@MainActor struct MerchantGameNodeEntryView: View {
    let service: any MerchantGameNodeServing
    let topicID: Int?
    let focusPause: Bool
    @StateObject private var reads = MerchantGameNodeEntryReadModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var visible = false
    private var result: MerchantGameNodeEntriesResult? { reads.currentResult(service: service) }
    init(service: any MerchantGameNodeServing, topicID: Int?, focusPause: Bool = false) {
        self.service = service; self.topicID = topicID; self.focusPause = focusPause
    }
    private var rows: [MerchantGameNodeEntry] {
        guard case .ready(let entries)? = result else { return [] }
        guard let topicID else { return entries }
        return entries.filter { $0.topicID == topicID && $0.activityID > 0 }
    }
    var body: some View {
        Group {
            if result == nil {
                ProgressView().frame(maxWidth: .infinity, minHeight: 200)
            } else if case .failure(let message)? = result {
                VStack(spacing: 12) {
                    MerchantGameNodeCopy.text(message)
                    Button { reads.refresh(service: service) } label: { MerchantGameNodeCopy.text("merchantGameNode.retry") }
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
        .onAppear { visible = true; if scenePhase == .active { reads.appear(service: service) } }
        .onDisappear { visible = false; reads.disappear() }
        .onChange(of: ObjectIdentifier(service)) { _, _ in
            if visible && scenePhase == .active { reads.appear(service: service) } else { reads.disappear() }
        }
        .onChange(of: service.scope) { _, _ in reads.refresh(service: service) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && visible { reads.appear(service: service) } else { reads.disappear() }
        }
        .task(id: reads.request?.id) {
            if let ticket = reads.request { await reads.read(ticket, service: service) }
        }
    }
}
