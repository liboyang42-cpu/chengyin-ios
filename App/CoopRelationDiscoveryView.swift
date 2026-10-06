import SwiftUI
import Combine

private struct CoopRelationDiscoveryDestinationKey: EnvironmentKey {
    static let defaultValue: (@MainActor (any CoopFlowReading) -> AnyView)? = nil
}
extension EnvironmentValues {
    var cooperationRelationDiscovery: (@MainActor (any CoopFlowReading) -> AnyView)? {
        get { self[CoopRelationDiscoveryDestinationKey.self] }
        set { self[CoopRelationDiscoveryDestinationKey.self] = newValue }
    }
}
@MainActor struct CoopRelationDiscoveryEntry: View {
    @Environment(\.cooperationRelationDiscovery) private var destination
    let reader: any CoopFlowReading
    var body: some View {
        if let destination { destination(reader) }
        else { CoopRelationDiscoveryView(reader: reader) }
    }
}
@MainActor struct CoopRelationProfileContext {
    let scope: CoopRelationProfileScope
    let isCurrent: () -> Bool
    let canOpen: (CoopRelationProfileRoute) -> Bool
    let destination: (CoopRelationProfileRoute, @escaping () -> Bool) -> AnyView
    var image: ((String) -> AnyView)? = nil
    var identityChanges: AnyPublisher<Void, Never>? = nil
#if DEBUG
    var debugTrace: ((String) -> Void)? = nil
#endif
}
@MainActor struct CoopRelationDiscoveryView: View {
    let reader: any CoopFlowReading
    var profiles: CoopRelationProfileContext? = nil
    var displayContext = CoopRelationDisplayContext()
    @State private var model: CoopRelationDiscoveryModel
    @State private var tab: CoopRelationDiscoveryKind = .merchants
    @StateObject private var presentation: CoopRelationPresentationOwner
    @State private var loadedKey: LoadKey?
    private struct LoadKey: Equatable {
        let reader: ObjectIdentifier
        let session: CoopFlowSession?
        let scope: CoopRelationProfileScope?
        let context: CoopRelationDisplayContext
    }
    private var key: LoadKey { .init(reader: ObjectIdentifier(reader), session: reader.session, scope: profiles?.scope, context: displayContext) }
    init(reader: any CoopFlowReading, profiles: CoopRelationProfileContext? = nil,
         displayContext: CoopRelationDisplayContext = .init(),
         model: CoopRelationDiscoveryModel? = nil, presentation: CoopRelationPresentationOwner? = nil) {
        self.reader = reader; self.profiles = profiles; self.displayContext = displayContext
        _model = State(initialValue: model ?? .init())
        _presentation = StateObject(wrappedValue: presentation ?? .init(identityChanges: profiles?.identityChanges))
    }
    var body: some View {
        List {
            CoopRelationContextLabel(context: displayContext)
            Section {
                Picker("cooprelation.kind", selection: $tab) {
                    Text("cooprelation.merchants").tag(CoopRelationDiscoveryKind.merchants)
                    Text("cooprelation.clubs").tag(CoopRelationDiscoveryKind.clubs)
                }.pickerStyle(.segmented).accessibilityIdentifier("cooprelation.tabs")
            }
            if reader.session == nil { Text("cooperation.login") }
            else if loadedKey == key && model.failed { Text("coopflow.read.failed").accessibilityIdentifier("cooprelation.failed") }
            else if loadedKey == key, model.isCurrent(reader: reader), let value = model.value {
                Section {
                    if value.hasInvalidRows(tab) { Text("cooprelation.partial").font(.footnote).accessibilityIdentifier("cooprelation.partial") }
                    if value.rows(tab).isEmpty && !value.hasInvalidRows(tab) {
                        Text(tab == .merchants ? "cooprelation.emptyMerchants" : "cooprelation.emptyClubs")
                            .accessibilityIdentifier("cooprelation.empty")
                    }
                    ForEach(value.rows(tab)) { row in
                        if let profiles, let choice = model.selection(row: row, reader: reader, scope: profiles.scope, context: displayContext), canOpen(choice) {
                            Button {
                                guard canOpen(choice) else { return }
                                open(choice, profiles: profiles)
#if DEBUG
                                trace("selection.open")
#endif
                            } label: {
                                card(row)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("cooprelation.open.\(row.kind.rawValue).\(row.id)")
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                card(row)
                                Text("cooprelation.unavailable").font(.footnote).foregroundStyle(.secondary)
                            }.accessibilityIdentifier("cooprelation.unavailable.\(row.kind.rawValue).\(row.id)")
                        }
                    }
                }
            } else { ProgressView("cooperation.loading") }
        }
        .navigationTitle("coopflow.discovery")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("cooperation.refresh", systemImage: "arrow.clockwise") { Task { await reload() } }
                    .disabled(reader.session == nil || model.isLoading).accessibilityIdentifier("cooprelation.refresh")
            }
        }
        .task(id: key) { await reload() }
        .refreshable { await reload() }
        .onChange(of: key) { _, _ in
#if DEBUG
            trace("key.changed")
#endif
            presentation.reconcileIdentity()
        }
        .onDisappear {
#if DEBUG
            trace("parent.disappear.before")
#endif
            model.leaveScreen()
#if DEBUG
            trace("parent.disappear.after")
#endif
        }
        .navigationDestination(item: presentation.binding) { choice in
            if canOpen(choice), let profiles {
                profiles.destination(choice.route, { presentation.isCurrent(choice) })
                    .safeAreaInset(edge: .top) { CoopRelationContextLabel(context: choice.displayContext).padding(.horizontal) }
            } else { Text("cooprelation.unavailable") }
        }
        .privacySensitive()
    }
#if DEBUG
    private func trace(_ event: String) {
        guard let sink = profiles?.debugTrace else { return }
        // Only booleans about this captured read/presentation; never IDs, names or tokens.
        sink(event + " current=\(profiles?.isCurrent() ?? false) key=\(loadedKey == key) model=\(model.isCurrent(reader: reader)) selected=\(presentation.selection != nil) loading=\(model.isLoading)")
    }
#endif
    private func reload() async {
#if DEBUG
        trace("reload.begin")
        defer { trace("reload.end") }
#endif
        let captured = key
        presentation.close(selectionID: presentation.selection?.id); loadedKey = nil
        await model.load(reader: reader, isCurrent: { key == captured && (profiles?.isCurrent() ?? true) })
        guard !Task.isCancelled, key == captured else { return }
        loadedKey = captured
    }
    private func canOpen(_ choice: CoopRelationProfileSelection) -> Bool {
        guard loadedKey == key, let profiles, profiles.isCurrent(), profiles.canOpen(choice.route) else { return false }
        return model.isCurrent(choice, reader: reader, scope: profiles.scope, context: displayContext)
    }
    private func open(_ choice: CoopRelationProfileSelection, profiles: CoopRelationProfileContext) {
        // Capture the accepted reader/model/scope, not a transient View value. The
        // owner remains observable while the list is underneath the pushed profile.
        let acceptedReader = reader, acceptedModel = model, context = displayContext
        presentation.open(choice, isCurrent: {
            profiles.isCurrent() && profiles.canOpen(choice.route) &&
                acceptedModel.isCurrent(choice, reader: acceptedReader, scope: profiles.scope, context: context)
        })
    }
    @ViewBuilder private func artwork(_ source: String) -> some View {
        if let image = profiles?.image { image(source).accessibilityLabel(Text("cooprelation.image")) }
        else { Label("cooprelation.image", systemImage: "photo").foregroundStyle(.secondary) }
    }
    private func card(_ row: CoopRelationDiscoveryRow) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Only the existing injected, approved renderer may fetch artwork.
            if let cover = row.cover { artwork(cover).accessibilityIdentifier("cooprelation.cover") }
            if let logo = row.logo, logo != row.cover { artwork(logo).accessibilityIdentifier("cooprelation.logo") }
            Text(verbatim: row.name).font(.headline)
            if let category = row.category { Text(verbatim: category).font(.subheadline) }
            if let place = row.address ?? row.city { Text(verbatim: place).foregroundStyle(.secondary) }
        }.fixedSize(horizontal: false, vertical: true).padding(.vertical, 6)
    }
}
private struct CoopRelationContextLabel: View {
    let context: CoopRelationDisplayContext
    var body: some View {
        if let topicID = context.topicID {
            VStack(alignment: .leading, spacing: 4) {
                LabeledContent("cooprelation.topic", value: context.topicName ?? String(topicID))
                if let chapterID = context.chapterID { LabeledContent("cooprelation.chapter", value: String(chapterID)) }
            }.font(.footnote).accessibilityIdentifier("cooprelation.displayContext")
        }
    }
}

/// Normal host observes session/content changes even while a profile is pushed.
@MainActor struct SessionCoopRelationDiscoveryView: View {
    @ObservedObject var session: AppSession
    let reader: any CoopFlowReading
    var body: some View {
        let home = session.publicMerchantHomeContext
        let scope = CoopRelationProfileScope(merchantScope: home.reader.scope, clubIdentity: session.clubIdentity,
            sessionRevision: session.sessionRevision, contentRevision: session.contentDetailRevision)
        let capturedSession = reader.session
        let current: () -> Bool = {
            reader.session == capturedSession && capturedSession != nil &&
                session.sessionRevision == scope.sessionRevision && session.contentDetailRevision == scope.contentRevision &&
                session.clubIdentity == scope.clubIdentity && session.publicMerchantHomeContext.reader.scope == scope.merchantScope
        }
        let profiles = CoopRelationProfileContext(scope: scope, isCurrent: current, canOpen: { route in
            guard current() else { return false }
            switch route {
            case .merchant: return home.reader.isConfigured
            case .club: return session.isClubConfigured
            }
        }, destination: { route, selectionCurrent in
            switch route {
            case .merchant(let owner):
                let reader = CoopRelationMerchantReader(base: home.reader, owner: owner, isCurrent: { current() && selectionCurrent() })
                return AnyView(PublicMerchantHomeView(target: .ownerMemberID(owner), context: .init(reader: reader, image: home.image)))
            case .club(let id):
                return AnyView(CoopRelationClubProfileHost(id: id, base: session, isCurrent: { current() && selectionCurrent() }))
            }
        }, image: home.image, identityChanges: session.objectWillChange.eraseToAnyPublisher())
        CoopRelationDiscoveryView(reader: reader, profiles: profiles)
    }
}

/// Restrict this entry to the selected public owner and verify returned identity.
@MainActor struct CoopRelationMerchantReader: PublicMerchantHomeReading {
    let base: any PublicMerchantHomeReading
    let owner: PublicMerchantOwnerID
    let isCurrent: () -> Bool
    var scope: UUID { base.scope }
    var isConfigured: Bool { base.isConfigured && isCurrent() }
    var isOfflineExample: Bool { base.isOfflineExample }
    func home(_ target: PublicMerchantHomeTarget) async throws -> PublicMerchantHome {
        guard isCurrent(), target == .ownerMemberID(owner) else { throw PublicMerchantHomeFailure.unavailable }
        let value = try await base.home(target)
        guard !Task.isCancelled, isCurrent(), value.memberId == owner.rawValue, (value.id ?? 0) > 0 else { throw PublicMerchantHomeFailure.unavailable }
        return value
    }
}

@MainActor struct CoopRelationClubProfileHost: View {
    let id: Int
    @StateObject private var reader: CoopRelationClubProfileReader
    init(id: Int, base: any ClubReading, isCurrent: @escaping () -> Bool) {
        self.id = id
        _reader = StateObject(wrappedValue: CoopRelationClubProfileReader(base: base, clubID: id, isCurrent: isCurrent))
    }
    var body: some View { ClubDetailView(id: id, reader: reader) }
}
/// The read-only adapter intentionally cannot be cast to AppSession. No chat, AI,
/// membership/action coordinator, management or cooperation authority is inherited.
@MainActor final class CoopRelationClubProfileReader: ObservableObject, ClubReading {
    let base: any ClubReading
    let clubID: Int
    private var requestGeneration = UUID()
    let isCurrent: () -> Bool
    init(base: any ClubReading, clubID: Int, isCurrent: @escaping () -> Bool) {
        self.base = base; self.clubID = clubID; self.isCurrent = isCurrent
    }
    var isClubConfigured: Bool { base.isClubConfigured && isCurrent() }
    var clubIdentity: ClubReadIdentity { base.clubIdentity }
    func clubDetail(id: Int) async throws -> ClubRecord {
        guard id == clubID, isCurrent() else { throw CancellationError() }
        let request = UUID(); requestGeneration = request
        let current = { self.isCurrent() && self.requestGeneration == request }
        let value = try await base.clubDetail(id: id, isCurrent: current)
        guard !Task.isCancelled, current(), value.id == id else { throw CancellationError() }
        return value
    }
    func clubMembers(id: Int) async throws -> ClubMemberDirectory {
        guard id == clubID, isCurrent() else { throw CancellationError() }
        let request = UUID(); requestGeneration = request
        let current = { self.isCurrent() && self.requestGeneration == request }
        let value = try await base.clubMembers(id: id, isCurrent: current)
        guard !Task.isCancelled, current(), value.club.id == id else { throw CancellationError() }
        return value
    }
    func clubHome() async throws -> ClubHome { throw CoopFlowFailure.unavailable }
    func clubOwned() async throws -> [ClubRecord] { throw CoopFlowFailure.unavailable }
    func clubDirectory(name: String?) async throws -> [ClubRecord] { throw CoopFlowFailure.unavailable }
}

extension AppSession {
    func clubDetail(id: Int, isCurrent: @escaping () -> Bool) async throws -> ClubRecord {
        try await clubReader.clubDetail(id: id, isCurrent: isCurrent)
    }
    func clubMembers(id: Int, isCurrent: @escaping () -> Bool) async throws -> ClubMemberDirectory {
        try await clubReader.clubMembers(id: id, isCurrent: isCurrent)
    }
}
