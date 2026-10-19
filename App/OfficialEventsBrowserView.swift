import SwiftUI

/// A distinct official-event destination; never replace ActivityBrowserView with this screen.
@MainActor struct OfficialEventsBrowserView: View {
    let reader: any OfficialEventReading
    var actions: OfficialActionCoordinator? = nil
    var onClose: (() -> Void)? = nil
    var onLogin: (() -> Void)? = nil
    var topicLinks: OfficialTopicLinks? = nil
    @State private var bucket: OfficialEventBucket = .live
    @State private var keyword = ""
    @State private var publisherScope: UUID?
    @State private var canPublish = false
    private var query: OfficialEventBrowseQuery { .sourceList(bucket: bucket, keyword: keyword) }
    private var privateList: Bool { query.isPrivate }
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                VStack(spacing: 8) {
                    // Source order: search (hidden on "mine"), chip tabs, then the summary row.
                    if bucket.isSearchable {
                        TextField("official.search", text: $keyword)
                            .textFieldStyle(.roundedBorder).submitLabel(.search)
                            .frame(minHeight: 44).accessibilityIdentifier("official.search")
                    }
                    Picker("official.filter", selection: $bucket) {
                        ForEach(OfficialEventBucket.allCases) { value in
                            Text(LocalizedStringKey(value.tabTitleKey)).tag(value)
                        }
                    }.pickerStyle(.segmented).frame(minHeight: 44).accessibilityIdentifier("official.filter")
                    summaryLinks
                }.padding(.horizontal)
                OfficialReadScreen(reader: reader, isPrivate: privateList, requestID: privateList ? "mine" : "public", onLogin: onLogin,
                                   load: { if privateList { return try await reader.myEvents() }; return try await reader.events(city: nil) }) { rows in
                    eventList(rows)
                }
            }
            .appNavigationTitle("official.title")
            .toolbar {
                if let onClose { ToolbarItem(placement: .cancellationAction) { Button("action.close", action: onClose) } }
            }
            .task(id: reader.scope) { await checkPublisherPermission() }
            .onChange(of: reader.scope) { _, _ in keyword = "" }
            // Keep IDs on the search, filter, and action leaves. A VStack ID can
            // propagate to those controls and hide their individual identifiers.
        }
    }
    /// The source keeps the navigation bar to the page title and places these
    /// secondary entries at the end of the summary row ("我发布的 ›", "邀约 ›").
    private var summaryLinks: some View {
        HStack(spacing: 16) {
            Spacer(minLength: 0)
            if canPublish && publisherScope == reader.scope {
                NavigationLink { OfficialPublishedView(reader: reader, actions: actions, onLogin: onLogin) } label: {
                    Label("official.publishedLink", systemImage: "chevron.right").labelStyle(OfficialTrailingIconLabelStyle())
                }.frame(minHeight: 44).accessibilityIdentifier("official.publishedLink")
            }
            NavigationLink { OfficialInboxView(reader: reader, actions: actions, publisher: canPublish && publisherScope == reader.scope, onLogin: onLogin) } label: {
                Label("official.inboxLink", systemImage: "chevron.right").labelStyle(OfficialTrailingIconLabelStyle())
            }.frame(minHeight: 44).accessibilityIdentifier("official.inboxLink")
        }.font(.subheadline)
    }
    private func eventList(_ rows: [OfficialEvent]) -> some View {
        let visible = query.visible(rows)
        return List {
            Section {
                Group {
                    if query.isSearching { Text("official.summary.search \(query.trimmedKeyword) \(visible.count)") }
                    else {
                        switch bucket {
                        case .live: Text("official.summary.live \(visible.count)")
                        case .upcoming: Text("official.summary.upcoming \(visible.count)")
                        case .ended: Text("official.summary.ended \(visible.count)")
                        case .mine: Text("official.summary.mine \(visible.count)")
                        }
                    }
                }.font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("officialList.summary")
                if visible.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(LocalizedStringKey(query.emptyTitleKey)).font(.headline)
                        Text(LocalizedStringKey(query.emptyDetailKey)).font(.subheadline).foregroundStyle(.secondary)
                    }.fixedSize(horizontal: false, vertical: true)
                }
            }
            ForEach(visible) { event in
                NavigationLink { OfficialEventDetailView(id: event.id, reader: reader, actions: actions, onLogin: onLogin, topicLinks: topicLinks) } label: { OfficialEventCard(event: event) }
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
private struct OfficialTrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 2) { configuration.title; configuration.icon.imageScale(.small).accessibilityHidden(true) }
    }
}
