import SwiftUI

/// A distinct official-event destination; never replace ActivityBrowserView with this screen.
@MainActor struct OfficialEventsBrowserView: View {
    let reader: any OfficialEventReading
    var actions: OfficialActionCoordinator? = nil
    var onClose: (() -> Void)? = nil
    var onLogin: (() -> Void)? = nil
    @State private var bucket: OfficialEventBucket = .live
    @State private var keyword = ""
    @State private var publisherScope: UUID?
    @State private var canPublish = false
    private var privateList: Bool { bucket == .mine }
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                VStack(spacing: 8) {
                    if !privateList {
                        TextField("official.search", text: $keyword)
                            .textFieldStyle(.roundedBorder).submitLabel(.search)
                            .frame(minHeight: 44).accessibilityIdentifier("official.search")
                    }
                    Picker("official.filter", selection: $bucket) {
                        ForEach(OfficialEventBucket.allCases) { value in
                            Text(LocalizedStringKey(value.titleKey)).tag(value)
                        }
                    }.pickerStyle(.menu).frame(minHeight: 44).accessibilityIdentifier("official.filter")
                }.padding(.horizontal)
                OfficialReadScreen(reader: reader, isPrivate: privateList, requestID: privateList ? "mine" : "public", onLogin: onLogin,
                                   load: { if privateList { return try await reader.myEvents() }; return try await reader.events(city: nil) }) { rows in
                    eventList(rows)
                }
            }
            .appNavigationTitle("official.title")
            .toolbar {
                if let onClose { ToolbarItem(placement: .cancellationAction) { Button("action.close", action: onClose) } }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        NavigationLink { OfficialInboxView(reader: reader, actions: actions, publisher: canPublish && publisherScope == reader.scope, onLogin: onLogin) } label: { Label("official.inbox", systemImage: "tray") }
                        if canPublish && publisherScope == reader.scope {
                            NavigationLink { OfficialPublishedView(reader: reader, actions: actions, onLogin: onLogin) } label: { Label("official.published", systemImage: "doc.text") }
                        }
                    } label: { Label("official.more", systemImage: "ellipsis.circle") }
                    .accessibilityIdentifier("official.more")
                }
            }
            .task(id: reader.scope) { await checkPublisherPermission() }
            // Keep IDs on the search, filter, and action leaves. A VStack ID can
            // propagate to those controls and hide their individual identifiers.
        }
    }
    private func eventList(_ rows: [OfficialEvent]) -> some View {
        let visible = OfficialEventFilter.visible(rows, bucket: bucket, keyword: privateList ? "" : keyword)
        return List {
            Section {
                LabeledContent("official.results", value: String(visible.count)).font(.caption)
                if visible.isEmpty { Text(privateList ? "official.emptyMine" : (keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "official.empty" : "official.searchEmpty")) }
            }
            ForEach(visible) { event in
                NavigationLink { OfficialEventDetailView(id: event.id, reader: reader, actions: actions, onLogin: onLogin) } label: { OfficialEventCard(event: event) }
                    .buttonStyle(QuestifyCardButtonStyle()).questifyCardListRow()
                    .accessibilityIdentifier("official.event.\(event.id)")
            }
            Section { OfficialReadOnlyNotice(offline: reader.isOfflineExample) }
        }
    }
    private func checkPublisherPermission() async {
        let captured = reader.scope
        canPublish = false; publisherScope = nil
        guard reader.isConfigured, reader.isAuthenticated else { return }
        do {
            let allowed = try await reader.canPublish()
            guard !Task.isCancelled, reader.scope == captured else { return }
            canPublish = allowed; publisherScope = captured
        } catch { /* A failed capability check does not break public discovery or expose publishing. */ }
    }
}
