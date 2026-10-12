import SwiftUI

/// Uses only existing merchant reads; a project row is navigation intent, not a grant.
@MainActor final class MerchantProjectRecentEventsModel: ObservableObject {
    @Published private(set) var rows: [MerchantEvent]?
    @Published private(set) var loading = false
    @Published private(set) var errorKey: String?
    private var generation = UUID()
    private var active = false
    func activate() { active = true }
    func retire() { active = false; generation = UUID(); rows = nil; loading = false; errorKey = nil }
    func load<Reader: MerchantReading>(reader: Reader, project: MerchantProject, merchantID: Int,
                                      sourceIsCurrent: @escaping () -> Bool) async {
        guard active else { return }
        let request = UUID(), revision = reader.sessionRevision
        generation = request; rows = nil; errorKey = nil; loading = true
        func current() -> Bool {
            active && generation == request && reader.sessionRevision == revision
                && reader.isConfigured && reader.isSignedIn && sourceIsCurrent() && !Task.isCancelled
        }
        defer { if generation == request { loading = false } }
        guard current(), let key = MerchantProjectEventKey(project: project) else {
            errorKey = "merchant.projectEvents.changed"; return
        }
        do {
            let access = try await reader.merchantAccess()
            guard current() else { return }
            guard access.isOwner, access.merchantID == merchantID, access.allows(.projects) else {
                throw MerchantReadError.accessDenied
            }
            // Re-check the selected project in this merchant's existing project/my view.
            let page = try await reader.merchantProjects(access: access)
            guard current() else { return }
            guard page.rows.contains(project) else { errorKey = "merchant.projectEvents.changed"; return }
            let events = try await reader.merchantEvents(access: access)
            guard current() else { return }
            rows = key.recentEvents(in: events)
        } catch {
            guard current() else { return }
            if error as? MerchantReadError == .accessDenied { errorKey = "merchant.access.denied" }
            else if error as? APIError == .unauthorized { errorKey = "auth.expired" }
            else { errorKey = "merchant.loadFailed" }
        }
    }
}

@MainActor struct MerchantProjectRecentEventsView<Reader: MerchantReading>: View {
    @ObservedObject var reader: Reader
    let project: MerchantProject
    let merchantID: Int
    let sourceIsCurrent: () -> Bool
    @StateObject private var model = MerchantProjectRecentEventsModel()
    @Environment(\.scenePhase) private var scenePhase
    private struct LoadKey: Hashable {
        let readerID: ObjectIdentifier
        let revision: UInt64
        let configured: Bool
        let signedIn: Bool
        let current: Bool
        let active: Bool
    }
    private var key: LoadKey {
        .init(readerID: ObjectIdentifier(reader), revision: reader.sessionRevision, configured: reader.isConfigured,
              signedIn: reader.isSignedIn, current: sourceIsCurrent(), active: scenePhase == .active)
    }
    var body: some View {
        List {
            if key.current && key.configured && key.signedIn && key.active {
                Section {
                    Text(verbatim: project.title).font(.headline)
                    Text("merchant.projectEvents.boundary").font(.footnote).foregroundStyle(.secondary)
                }
            }
            if !key.current || !key.configured || !key.signedIn || !key.active {
                Text("merchant.projectEvents.changed")
            } else if model.loading {
                ProgressView("merchant.loading").accessibilityIdentifier("merchant.projectEvents.loading")
            } else if let error = model.errorKey {
                Text(LocalizedStringKey(error)).foregroundStyle(.secondary)
                Button("merchant.projectEvents.retry") { Task { await reload() } }
                    .accessibilityIdentifier("merchant.projectEvents.retry")
            } else if let rows = model.rows {
                if rows.isEmpty {
                    Text("merchant.projectEvents.empty").accessibilityIdentifier("merchant.projectEvents.empty")
                } else {
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, event in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(verbatim: event.content)
                            Text(verbatim: event.time).font(.caption).foregroundStyle(.secondary)
                        }.accessibilityIdentifier("merchant.projectEvents.row." + String(index))
                    }
                }
                Button("merchant.projectEvents.refresh") { Task { await reload() } }
                    .accessibilityIdentifier("merchant.projectEvents.refresh")
            }
        }
        .appNavigationTitle("merchant.projectEvents.title")
        .accessibilityIdentifier("merchant.projectEvents.screen")
        .task(id: key) {
            guard key.current && key.configured && key.signedIn && key.active else { model.retire(); return }
            model.activate(); await reload()
        }
        .refreshable { await reload() }
        .onDisappear { model.retire() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { model.retire() } }
    }
    private func reload() async {
        guard key.current && key.configured && key.signedIn && key.active else { model.retire(); return }
        await model.load(reader: reader, project: project, merchantID: merchantID, sourceIsCurrent: sourceIsCurrent)
    }
}
