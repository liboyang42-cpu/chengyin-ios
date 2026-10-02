import SwiftUI

/// Exact TemplateApi own-shelf. This is not the generic MyProjectApi manager.
@MainActor struct TemplateAuthoringMineView: View {
    let coordinator: TemplateAuthoringCoordinator
    let sessionRevision: UInt64
    @State private var rows: [DiscoveryPlayTemplate] = []
    @State private var messageKey: String?
    @State private var review: TemplateOwnShelfReview?
    @State private var busy = false
    @State private var locked = true
    var body: some View {
        List {
            Section {
                Text("templateAuthor.mineScope").foregroundStyle(.secondary)
                Text("templateAuthor.shelf.limit").font(.caption)
                if !coordinator.canSubmit { Text("templateAuthor.unavailable") }
                Button("templateAuthor.shelf.refresh") { Task { await refresh() } }
                    .disabled(busy).accessibilityIdentifier("templateAuthor.shelf.refresh")
            }
            ForEach(rows) { row in
                Section {
                    Text(verbatim: row.title).font(.headline)
                    LabeledContent("templateAuthor.shelf.identity", value: String(row.id))
                    if let text = row.description { Text(verbatim: text) }
                    Text(LocalizedStringKey(row.status == 1 ? "templateAuthor.published" : row.status == 2 ? "templateAuthor.underReview" : "templateAuthor.unpublished"))
                    Text(LocalizedStringKey(row.publishStatus == 1 ? "templateAuthor.shelf.inLibrary" : "templateAuthor.shelf.outLibrary"))
                    Text("templateAuthor.existingEditUnavailable").font(.caption).foregroundStyle(.secondary)
                    Button(LocalizedStringKey(row.publishStatus == 1 ? "templateAuthor.shelf.removeLibrary" : "templateAuthor.shelf.addLibrary")) {
                        prepare(row.id, .libraryStatus)
                    }.disabled(locked || busy).accessibilityIdentifier("templateAuthor.shelf.library.\(row.id)")
                    Button("templateAuthor.shelf.delete", role: .destructive) { prepare(row.id, .remove) }
                        .disabled(locked || busy).accessibilityIdentifier("templateAuthor.shelf.delete.\(row.id)")
                }
            }
            if let messageKey { Text(LocalizedStringKey(messageKey)).accessibilityIdentifier("templateAuthor.shelf.status") }
        }.navigationTitle("templateAuthor.mine")
            .task(id: sessionRevision) { rows = []; review = nil; await refresh() }
            .onDisappear { coordinator.leaveShelfScreen(); review = nil }
            .sheet(item: $review, onDismiss: { coordinator.cancelShelfReview() }) { value in
                NavigationStack {
                    Form {
                        Section("templateAuthor.reviewTitle") {
                            Text(verbatim: value.title)
                            LabeledContent("templateAuthor.shelf.identity", value: String(value.templateID.rawValue))
                            Text(LocalizedStringKey(value.action == .remove ? "templateAuthor.shelf.deleteReview" : value.desiredPublishStatus == 1 ? "templateAuthor.shelf.addReview" : "templateAuthor.shelf.removeReview"))
                            Text("templateAuthor.shelf.readback")
                        }
                        if coordinator.canSimulate { Text("templateAuthor.fixtureNotice") }
                        if coordinator.canSubmit {
                            Button(LocalizedStringKey(coordinator.canSimulate ? "templateAuthor.confirmSimulation" : "templateAuthor.confirmRequest"), role: value.action == .remove ? .destructive : nil) {
                                busy = true; locked = true
                                Task { await coordinator.confirmShelf(value); review = nil; sync(); busy = false }
                            }.disabled(busy).accessibilityIdentifier("templateAuthor.shelf.confirm")
                        } else { Text("templateAuthor.unavailable") }
                    }.navigationTitle("templateAuthor.reviewTitle")
                        .toolbar { ToolbarItem(placement: .cancellationAction) {
                            Button("templateAuthor.cancel") { coordinator.cancelShelfReview(); review = nil }
                                .accessibilityIdentifier("templateAuthor.shelf.cancel")
                        } }
                }
            }
    }
    private func sync() {
        rows = coordinator.rows; messageKey = coordinator.shelfMessageKey; locked = coordinator.shelfLocked
    }
    private func prepare(_ id: Int, _ action: TemplateOwnShelfAction) {
        coordinator.prepareShelf(templateID: id, action: action); review = coordinator.shelfReview; sync()
    }
    private func refresh() async {
        busy = true; review = nil; coordinator.synchronizeSession(); await coordinator.loadMine(); sync(); busy = false
    }
}
