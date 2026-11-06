import SwiftUI

/// A distinct official-event destination; never replace ActivityBrowserView with this screen.
@MainActor struct OfficialEventsBrowserView: View {
    let reader: any OfficialEventReading
    var actions: OfficialActionCoordinator? = nil
    var onClose: (() -> Void)? = nil
    var onLogin: (() -> Void)? = nil
    var topicLinks: OfficialTopicLinks? = nil
    @StateObject private var sourceObservation = OfficialReadInvalidationObserver()
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
                }.padding(.horizontal)
                OfficialReadScreen(reader: reader, isPrivate: privateList, requestID: privateList ? "mine" : "public", onLogin: onLogin,
                                   load: { if privateList { return try await reader.myEvents() }; return try await reader.events(city: nil) }) { rows in
                    eventList(rows)
                }
            }
            .appNavigationTitle("official.title")
            .toolbar {
                if let onClose { ToolbarItem(placement: .cancellationAction) { Button("action.close", action: onClose) } }
                // The app has no WeChat capsule, so 我发布的 and 邀约 take the top-right slot.
                ToolbarItemGroup(placement: .topBarTrailing) { summaryLinks }
            }
            .task(id: reader.scope) { await checkPublisherPermission() }
            .onChange(of: reader.scope) { _, _ in keyword = "" }
        .onAppear { sourceObservation.bind(reader) }
        .onChange(of: ObjectIdentifier(reader)) { _, _ in sourceObservation.bind(reader) }
        .onChange(of: sourceObservation.revision) { _, _ in
            guard sourceObservation.isBound(to: reader) else { return }
            keyword = ""
            if publisherScope != reader.scope { canPublish = false; publisherScope = nil }
        }
        .onDisappear { sourceObservation.stop() }
            // Keep IDs on the search, filter, and action leaves. A VStack ID can
            // propagate to those controls and hide their individual identifiers.
        }
    }
    /// The mini-program puts these at the end of its summary row only because the WeChat capsule
    /// owns the top-right corner; here they are the page's two toolbar entries.
    @ViewBuilder private var summaryLinks: some View {
            if canPublish && publisherScope == reader.scope {
                NavigationLink { OfficialPublishedView(reader: reader, actions: actions, onLogin: onLogin) } label: {
                    Text("official.publishedLink")
                }.frame(minHeight: 44).accessibilityIdentifier("official.publishedLink")
            }
            NavigationLink { OfficialInboxView(reader: reader, actions: actions, publisher: canPublish && publisherScope == reader.scope, onLogin: onLogin) } label: {
                Text("official.inboxLink")
            }.frame(minHeight: 44).accessibilityIdentifier("official.inboxLink")
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
                    ContentUnavailableView {
                        Label(LocalizedStringKey(query.emptyTitleKey), systemImage: "sparkles")
                    } description: {
                        Text(LocalizedStringKey(query.emptyDetailKey))
                    }
                }
            }
            ForEach(visible) { event in
                NavigationLink { OfficialEventDetailView(id: event.id, reader: reader, actions: actions, onLogin: onLogin, topicLinks: topicLinks) } label: { OfficialEventCard(event: event) }
                    .buttonStyle(QuestifyCardButtonStyle()).questifyCardListRow()
                    .accessibilityIdentifier("official.event.\(event.id)")
            }
            Section { OfficialReadOnlyNotice(offline: reader.isOfflineExample) }
        }
        .listStyle(.insetGrouped)
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
