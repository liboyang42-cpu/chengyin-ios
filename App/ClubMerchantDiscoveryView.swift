import SwiftUI

/// Read-only P045 section. Its input reader is the already-configured cooperation reader;
/// neither a search field nor a rendered owner badge grants service capabilities.
@MainActor struct ClubMerchantDiscoveryView<ClubReader: ClubReading & ObservableObject>: View {
    let club: ClubRecord
    @ObservedObject var clubReader: ClubReader
    let reader: any CoopFlowReading
    @State private var model = ClubMerchantDiscoveryModel()
    private var context: ClubMerchantDiscoveryContext { .init(club: club, clubReader: clubReader, reader: reader) }
    var body: some View {
        let scope = context
        let _ = model.bind(scope)
        let permit = model.permit(in: scope)
        Group {
            if scope.canRead {
                Section("club.merchantDiscovery.title") {
                    TextField("club.merchantDiscovery.search", text: Binding(
                        get: { model.keyword(in: scope) },
                        set: { model.setKeyword($0, permit: permit) }))
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("club.merchantDiscovery.search")
                    Text("club.merchantDiscovery.localOnly").font(.footnote).foregroundStyle(.secondary)
                    switch model.phase(in: scope) {
                    case .idle, .loading:
                        ProgressView("club.loading").accessibilityIdentifier("club.merchantDiscovery.loading")
                    case .denied:
                        Text("club.merchantDiscovery.ownerRequired").accessibilityIdentifier("club.merchantDiscovery.denied")
                        reloadButton(permit: permit, title: "action.retry")
                    case .failed:
                        Text("club.merchantDiscovery.failed").accessibilityIdentifier("club.merchantDiscovery.failed")
                        reloadButton(permit: permit, title: "action.retry")
                    case .ready:
                        let rows = model.rows(in: scope)
                        if rows.isEmpty {
                            Text(model.hasLoadedRows(in: scope) ? "club.merchantDiscovery.noMatches" : "club.merchantDiscovery.empty")
                                .accessibilityIdentifier("club.merchantDiscovery.empty")
                        }
                        ForEach(rows) { row in
                            VStack(alignment: .leading, spacing: 4) {
                                if row.name.isEmpty { Text("club.merchantDiscovery.unnamed").font(.headline) }
                                else { Text(verbatim: row.name).font(.headline) }
                                if !row.activityTypes.isEmpty { Text(verbatim: row.activityTypes) }
                                if !row.address.isEmpty { Text(verbatim: row.address).font(.subheadline) }
                                if !row.city.isEmpty { Text(verbatim: row.city).font(.subheadline) }
                            }.accessibilityIdentifier("club.merchantDiscovery.row.\(row.id)")
                        }
                        if !model.keyword(in: scope).isEmpty {
                            Button("club.merchantDiscovery.clear") { model.setKeyword("", permit: permit) }
                                .accessibilityIdentifier("club.merchantDiscovery.clear")
                        }
                        reloadButton(permit: permit, title: "club.refresh")
                    }
                }
            }
        }
        .task(id: scope) {
            guard let permit = model.activate(scope) else { return }
            await model.load(clubReader: clubReader, reader: reader, permit: permit)
        }
        .onDisappear { model.leave(scope) }
    }
    private func reloadButton(permit: ClubMerchantDiscoveryModel.Permit?, title: LocalizedStringKey) -> some View {
        Button(title) {
            guard let permit else { return }
            Task { await model.load(clubReader: clubReader, reader: reader, permit: permit) }
        }.accessibilityIdentifier("club.merchantDiscovery.reload")
    }
}
