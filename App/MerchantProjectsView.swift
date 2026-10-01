import SwiftUI

@MainActor
struct MerchantProjectsView<Reader: MerchantReading>: View {
    @ObservedObject var reader: Reader
    @StateObject private var model = MerchantLoadModel<MerchantProjectPage>()
    @State private var selection: ProjectSelection?
    private struct ProjectSelection: Identifiable {
        let id = UUID()
        let project: MerchantProject
        let revision: UInt64
    }
    var body: some View {
        ZStack {
            if !reader.isConfigured {
                ContentUnavailableView("merchant.projects", systemImage: "network.slash", description: Text("auth.notConfigured"))
            } else if !reader.isSignedIn {
                ContentUnavailableView("merchant.projects", systemImage: "lock", description: Text("merchant.signIn"))
            } else if model.loadedRevision == reader.sessionRevision, let page = model.value {
                List {
                    Section {
                        Text("merchant.projects.scope").font(.footnote).foregroundStyle(.secondary)
                        if page.hasUnloadedRows { Text("merchant.projects.partial").font(.footnote).foregroundStyle(.secondary) }
                        if model.isLoading { ProgressView("merchant.refreshing") }
                        if let error = model.errorKey {
                            Text("merchant.stale").font(.footnote).foregroundStyle(.secondary)
                            MerchantInlineFailure(errorKey: error, retry: { Task { await reload() } })
                        }
                    }
                    if page.rows.isEmpty {
                        Text("merchant.projects.empty").accessibilityIdentifier("merchant.projects.empty")
                    }
                    ForEach(page.rows) { project in
                        Button { selection = ProjectSelection(project: project, revision: reader.sessionRevision) } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(project.title.isEmpty ? String(localized: "merchant.project.untitled") : project.title).font(.headline)
                                if let text = project.projectTypeText, !text.isEmpty { Text(text).font(.subheadline) }
                                if let text = project.stateText, !text.isEmpty { Text(text).foregroundStyle(.secondary) }
                                if let text = project.startTime, !text.isEmpty { Label(text, systemImage: "calendar").font(.caption) }
                            }.padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("merchant.project.row.\(project.id)")
                    }
                }.refreshable { await reload() }
            } else if let error = model.errorKey {
                MerchantFailureView(errorKey: error, identifier: "merchant.projects", retry: { Task { await reload() } })
            } else { ProgressView("merchant.loading") }
        }
        .navigationTitle("merchant.projects")
        .task(id: reader.sessionRevision) { await reload(discardOldValue: true) }
        .onChange(of: reader.sessionRevision) { _, _ in selection = nil }
        .sheet(item: $selection) { selected in
            NavigationStack {
                if reader.isSignedIn && selected.revision == reader.sessionRevision {
                    MerchantProjectSummary(project: selected.project)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("merchant.done") { selection = nil } } }
                } else { ContentUnavailableView("merchant.signIn", systemImage: "lock") }
            }
        }
    }
    private func reload(discardOldValue: Bool = false) async {
        let revision = reader.sessionRevision
        await model.load(reader: reader, discardOldValue: discardOldValue) {
            let access = try await reader.merchantAccess()
            guard revision == reader.sessionRevision, reader.isSignedIn else { throw CancellationError() }
            guard access.allows(.projects) else { throw MerchantReadError.accessDenied }
            try Task.checkCancellation()
            return try await reader.merchantProjects(access: access)
        }
    }
}

private struct MerchantProjectSummary: View {
    let project: MerchantProject
    var body: some View {
        Form {
            Section {
                Text(project.title.isEmpty ? String(localized: "merchant.project.untitled") : project.title).font(.headline)
                Text("merchant.summarySnapshot").font(.footnote).foregroundStyle(.secondary)
                MerchantCountRow("merchant.recordID", value: project.projectID)
                if let text = project.projectTypeText, !text.isEmpty { LabeledContent("merchant.project.type", value: text) }
                if let text = project.stateText, !text.isEmpty { LabeledContent("merchant.project.state", value: text) }
                if let text = project.acceptStatusText, !text.isEmpty { LabeledContent("merchant.project.acceptance", value: text) }
                if let text = project.startTime, !text.isEmpty { LabeledContent("merchant.project.start", value: text) }
                if let text = project.endTime, !text.isEmpty { LabeledContent("merchant.project.end", value: text) }
            }
            if project.signupCount > 0 || project.viewCount > 0 {
                Section("merchant.project.statistics") {
                    if project.signupCount > 0 { MerchantCountRow("merchant.project.signups", value: project.signupCount) }
                    if project.viewCount > 0 { MerchantCountRow("merchant.project.views", value: project.viewCount) }
                }
            }
        }.navigationTitle("merchant.project.summary")
    }
}
