import SwiftUI

/// Read-only P045 section. Its input reader is the already-configured cooperation reader;
/// neither a search field nor a rendered owner badge grants service capabilities.
@MainActor struct ClubMerchantDiscoveryView<ClubReader: ClubReading & ObservableObject>: View {
    let club: ClubRecord
    @ObservedObject var clubReader: ClubReader
    let reader: any CoopFlowReading
    @Environment(\.clubMerchantProfile) private var profile
    @State private var presentation = ClubMerchantProfilePresentation()
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
                            if let choice = model.profileSelection(row: row, permit: permit),
                               let profile, profile.canRead {
                                Button { open(choice, profile: profile) } label: {
                                    HStack {
                                        card(row)
                                        Spacer()
                                        Image(systemName: "chevron.right").accessibilityHidden(true)
                                    }.contentShape(Rectangle())
                                }
                                .buttonStyle(.borderless)
                                .accessibilityHint("club.merchantProfile.open")
                                .accessibilityIdentifier("club.merchantProfile.open.\(row.id)")
                            } else {
                                VStack(alignment: .leading, spacing: 4) {
                                    card(row)
                                    Text("club.merchantProfile.unavailable").font(.caption).foregroundStyle(.secondary)
                                }
                            }
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
        .sheet(item: Binding(get: { presentation.selection }, set: { if $0 == nil { presentation.close() } })) { choice in
            if let profile {
                ClubMerchantProfileDestination(selection: choice, profile: profile, presentation: presentation,
                    close: { presentation.close() })
                    .presentationDetents([.large]).presentationCompactAdaptation(.sheet)
            }
        }
        .onChange(of: scope) { _, _ in presentation.close() }
        .onChange(of: profile?.key) { _, _ in presentation.close() }
        .onChange(of: profile?.canRead) { _, valid in if valid != true { presentation.close() } }
        .onChange(of: model.phase(in: scope)) { _, phase in if phase != .ready { presentation.close() } }
        .onDisappear { presentation.close() }
        .onDisappear { model.leave(scope) }
    }
    private func card(_ row: ClubMerchantDiscoveryRow) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if row.name.isEmpty { Text("club.merchantDiscovery.unnamed").font(.headline) }
            else { Text(verbatim: row.name).font(.headline) }
            if !row.activityTypes.isEmpty { Text(verbatim: row.activityTypes) }
            if !row.address.isEmpty { Text(verbatim: row.address).font(.subheadline) }
            if !row.city.isEmpty { Text(verbatim: row.city).font(.subheadline) }
        }.accessibilityIdentifier("club.merchantDiscovery.row.\(row.id)")
    }
    private func open(_ choice: ClubMerchantProfileSelection, profile: ClubMerchantProfileContext) {
        let acceptedModel = model, acceptedClubReader = clubReader, acceptedReader = reader
        presentation.open(choice, isCurrent: {
            profile.canRead && acceptedModel.isCurrent(choice, clubReader: acceptedClubReader, reader: acceptedReader)
        })
    }
    private func reloadButton(permit: ClubMerchantDiscoveryModel.Permit?, title: LocalizedStringKey) -> some View {
        Button(title) {
            guard let permit else { return }
            Task { await model.load(clubReader: clubReader, reader: reader, permit: permit) }
        }.accessibilityIdentifier("club.merchantDiscovery.reload")
    }
}
