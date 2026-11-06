import SwiftUI

/// CITY read surface and explicitly injected original command journeys remain independently authorized.
struct SessionCityPlayerView: View {
    @EnvironmentObject private var session: AppSession
    var body: some View {
        VStack(spacing: 0) {
            if let model = session.makeCityCurrentSnapshotPresentation() {
                NavigationLink("城市地图快照") { CityCurrentSnapshotView(model: model) }
                    .padding().frame(minHeight: 44)
                    .accessibilityIdentifier("city.currentSnapshot.entry")
            }
            if let model = session.makeCityOrderedMapPresentation() {
                NavigationLink("城市地图更新") { CityOrderedMapView(model: model) }
                    .padding().frame(minHeight: 44)
                    .accessibilityIdentifier("city.orderedMap.entry")
            }
            if let owner = session.makeCityParticipationRuntimeOwner() {
                NavigationLink("城市队伍参与") {
                    CityParticipationRuntimeHostView(owner: owner, revision: session.cityParticipationRuntimeRevision)
                }
                .padding().frame(minHeight: 44)
                .accessibilityIdentifier("city.participation.entry")
            }
            if let model = session.makeCityActionBudgetRecovery(), let context = session.currentRuntimeDependencyContext {
                NavigationLink("城市行动额度") {
                    CityActionBudgetView(model: model, context: context, identityVersion: session.cityActionBudgetRuntimeRevision)
                }
                .padding().frame(minHeight: 44)
                .accessibilityIdentifier("city.actionBudget.entry")
            }
            NavigationLink { SessionCityPlayerValueView() } label: {
                Label { Text("cityValue.title", tableName: "CityValue") } icon: { Image(systemName: "map") }
                    .frame(minHeight: 44)
            }.accessibilityIdentifier("city.value.entry")
            CityPlayerView(reader: session.makeCityPlayerReader(), rulesFactory: { session.makeCityPlayerRulesFlow(read: $0) }, historyFactory: { session.makeCityTaskHistoryRuntimeOwner() }, historyRevision: session.cityTaskHistoryRuntimeRevision, onsiteFactory: { session.makeCityOnsiteTaskRuntimeOwner(board: $0) }, onsiteRevision: session.cityOnsiteTaskRuntimeRevision, neutralFactory: { session.makeCityNeutralTaskRuntimeOwner(board: $0) }, neutralRevision: session.cityNeutralTaskRuntimeRevision, arrivalFactory: { session.makeCityArrivalEvidenceRuntimeOwner(audience: .player(regionID: $0.regionId), board: $0) }, arrivalRevision: session.cityArrivalEvidenceRuntimeRevision).id(session.cityPlayerReadIdentity)
                .environment(\.cityAcquisitionEntryContext, CityAcquisitionEntryContext(acquisitionFactory: { session.makeCityAcquisitionController() }))
        }
    }
}
struct CityPlayerView: View {
    @Environment(\.cityAcquisitionEntryContext) private var acquisitionEntry
    @State private var acquisition: CityAcquisitionDestination?
    @Environment(\.scenePhase) private var scenePhase
    @State var reader: CityPlayerReader
    @State private var rulesSheet: CityPlayerRulesPresentation?
    @State private var selection: CityPointSelection?
    @State private var visible = false
    @State private var readRequest = UUID()
    /// W20 business section factory. nil in production (no reviewed endpoint); DEBUG fixtures only.
    private let rulesFactory: (@MainActor (CityReadSnapshot) -> CityPlayerRulesFlow)?
    private let gameFactory: (@MainActor (CityReadSnapshot) -> CityGameCoordinator?)?
    private let arrivalFactory: (@MainActor (CityReadBoard) -> CityArrivalEvidenceRuntimeOwner?)?
    private let arrivalRevision: UInt64
    private let onsiteFactory: (@MainActor (CityReadBoard) -> CityOnsiteTaskRuntimeOwner?)?
    private let onsiteRevision: UInt64
    private let historyFactory: (@MainActor () -> CityTaskHistoryRuntimeOwner?)?
    private let historyRevision: UInt64
    private let neutralFactory: (@MainActor (CityReadBoard) -> CityNeutralTaskRuntimeOwner?)?
    private let neutralRevision: UInt64
    init(reader: CityPlayerReader, rulesFactory: (@MainActor (CityReadSnapshot) -> CityPlayerRulesFlow)? = nil, historyFactory: (@MainActor () -> CityTaskHistoryRuntimeOwner?)? = nil, historyRevision: UInt64 = 0, onsiteFactory: (@MainActor (CityReadBoard) -> CityOnsiteTaskRuntimeOwner?)? = nil, onsiteRevision: UInt64 = 0, neutralFactory: (@MainActor (CityReadBoard) -> CityNeutralTaskRuntimeOwner?)? = nil, neutralRevision: UInt64 = 0, arrivalFactory: (@MainActor (CityReadBoard) -> CityArrivalEvidenceRuntimeOwner?)? = nil, arrivalRevision: UInt64 = 0, gameFactory: (@MainActor (CityReadSnapshot) -> CityGameCoordinator?)? = nil) {
        _reader = State(initialValue: reader); self.rulesFactory = rulesFactory; self.gameFactory = gameFactory
        self.arrivalFactory = arrivalFactory; self.arrivalRevision = arrivalRevision
        self.onsiteFactory = onsiteFactory; self.onsiteRevision = onsiteRevision
        self.historyFactory = historyFactory; self.historyRevision = historyRevision
        self.neutralFactory = neutralFactory; self.neutralRevision = neutralRevision
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Independent original titles/request recovery does not require a published board.
                CityAcquisitionEntry(factory: acquisitionEntry?.acquisitionFactory, open: {
                    guard visible, scenePhase == .active, let factory = acquisitionEntry?.acquisitionFactory else { return }
                    acquisition = CityAcquisitionDestination(controller: factory())
                })
                // Personal history uses its own original region approval, even without a published map.
                if let owner = historyFactory?(), owner.isCurrent {
                    NavigationLink { CityTaskHistoryRuntimeHostView(owner: owner, revision: historyRevision) } label: {
                        Label { Text("cityHistory.entry", tableName: "CityTaskHistory") } icon: { Image(systemName: "clock.arrow.circlepath") }
                            .frame(minHeight: 44)
                    }.accessibilityIdentifier("city.history.entry")
                }
                switch reader.state {
                case .unavailable:
                    ContentUnavailableView("city.read.unavailable", systemImage: "building.2", description: Text("city.read.unavailable.hint"))
                case .loading: ProgressView("city.read.loading")
                case .notPublished:
                    ContentUnavailableView("city.read.notPublished", systemImage: "building.2")
                case .available(let snapshot):
                    // Board header: title, then season state and my membership as status chips.
                    VStack(alignment: .leading, spacing: 10) {
                        Text(verbatim: snapshot.board.title).font(.largeTitle.bold()).fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 8) {
                            Label(lifecycle(snapshot.board.lifecycle), systemImage: snapshot.board.lifecycle == "OPEN" ? "flag.fill" : "flag.slash")
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background((snapshot.board.lifecycle == "OPEN" ? Color.green : Color.secondary).opacity(0.18), in: Capsule())
                            Label(membership(snapshot.membership), systemImage: snapshot.membership == .joined ? "person.fill.checkmark" : "person")
                                .font(.subheadline)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(Color.accentColor.opacity(snapshot.membership == .joined ? 0.18 : 0.08), in: Capsule())
                        }
                    }
                    .accessibilityElement(children: .combine)
                    Button {
                        guard visible, scenePhase == .active,
                              let selected = reader.pointMapContext, selected.snapshot == snapshot else { return }
                        rulesSheet = CityPlayerRulesPresentation(readID: selected.readID, read: snapshot,
                            flow: rulesFactory?(snapshot) ?? CityPlayerRulesFlow(client: nil))
                    } label: {
                        Label { Text("cityRules.entry", tableName: "CityPlayerRules") } icon: { Image(systemName: "doc.text") }
                            .frame(minHeight: 44)
                    }
                    .disabled(!visible || scenePhase != .active)
                    .accessibilityIdentifier("cityRules.entry")
                    if let owner = arrivalFactory?(snapshot.board), owner.isCurrent {
                        NavigationLink {
                            CityArrivalEvidenceRuntimeHostView(owner: owner, revision: arrivalRevision)
                        } label: {
                            Label { Text("cityArrival.playerEntry", tableName: "CityArrivalEvidence") } icon: { Image(systemName: "checkmark.shield") }
                                .frame(minHeight: 44)
                        }.accessibilityIdentifier("cityArrival.player.entry")
                    }
                    if let owner = onsiteFactory?(snapshot.board), owner.isCurrent {
                        NavigationLink {
                            CityOnsiteTaskRuntimeHostView(arrivalFactory: arrivalFactory.map { factory in
                                { board in
                                    // Arrival retains its own independent approval and lifetime owner.
                                    factory(board)?.controller ?? CityArrivalEvidenceController(audience: .player(regionID: board.regionId), service: nil, journal: nil)
                                }
                            }, owner: owner, revision: onsiteRevision)
                        } label: {
                            Label { Text("cityOnsite.entry", tableName: "CityOnsiteTask") } icon: { Image(systemName: "questionmark.circle") }
                                .frame(minHeight: 44)
                        }.accessibilityIdentifier("city.onsite.entry")
                    }
                    if let owner = neutralFactory?(snapshot.board), owner.isCurrent {
                        NavigationLink {
                            CityNeutralTaskRuntimeHostView(owner: owner, revision: neutralRevision)
                        } label: {
                            Label { Text("cityNeutral.entry", tableName: "CityNeutralTask") } icon: { Image(systemName: "questionmark.circle") }
                        }.frame(minHeight: 44).accessibilityIdentifier("city.neutral.entry")
                    }
                    if let context = reader.pointMapContext {
                        // Keyed to this exact read so a reload never reuses old game state.
                        CityGameSlot(snapshot: context.snapshot, factory: gameFactory).id(context.readID)
                    }
                    if let context = reader.pointMapContext {
                        if context.points.isEmpty { Text("city.read.points.empty") }
                        else { pointContent(context) }
                    } else { Text("city.read.points.unavailable").foregroundStyle(.secondary) }
                }
            }.padding()
        }
        .toolbar {
            if reader.isConfigured {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { selection = nil; reader.cancel(); readRequest = UUID() } label: { Label("action.retry", systemImage: "arrow.clockwise") }
                        .disabled(reader.state == .loading || !visible || scenePhase != .active)
                }
            }
        }
        .appNavigationTitle("city.read.title")
        .accessibilityIdentifier("city.read.screen")
        .navigationDestination(item: $acquisition) { selected in
            CityAcquisitionView(controller: selected.controller)
        }
        .task(id: readRequest) {
            guard visible, scenePhase == .active, !Task.isCancelled else { return }
            await reader.load()
        }
        .sheet(item: $rulesSheet, onDismiss: {
            // Keep only navigation; every authoritative parent fact is read again.
            selection = nil; reader.cancel(); readRequest = UUID()
        }) { presentation in
            CityPlayerRulesView(flow: presentation.flow, selectionIsCurrent: {
                visible && scenePhase == .active && reader.pointMapContext?.readID == presentation.readID
                    && reader.state == .available(presentation.read)
            })
        }
        .onAppear { visible = true; readRequest = UUID() }
        .onChange(of: scenePhase) { _, _ in
            // Clear old state before foreground recovery; only this visible page
            // may re-read, and the reader independently rechecks its lease.
            rulesSheet?.flow.cancel(); selection = nil; reader.cancel(); readRequest = UUID()
        }
        .onChange(of: reader.pointMapContext) { _, _ in selection = nil }
        .onDisappear { visible = false; rulesSheet?.flow.cancel(); selection = nil; reader.cancel() }
    }
    @ViewBuilder private func pointContent(_ context: CityPointMapContext) -> some View {
        let selected = selection?.point(in: reader.pointMapContext)
        let pins = context.points.compactMap { point -> SearchMapPin? in
            guard let coordinate = RoamCoordinate(latitude: point.latitude, longitude: point.longitude) else { return nil }
            return SearchMapPin(id: point.pointId, title: point.title, coordinate: coordinate, symbol: symbol(point))
        }
        if let first = pins.sorted(by: { $0.id < $1.id }).first {
            let fit = MapMarkerDensity.fit(pins.map { .init(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude) })
            let center = fit.flatMap { RoamCoordinate(latitude: $0.latitude, longitude: $0.longitude) } ?? first.coordinate
            // QuestifyDensityMap uses QuestifyMapAppearance.baseStyle and only the
            // supplied visible points. Camera movement never performs a read.
            QuestifyDensityMap(area: .init(coordinate: center, label: context.snapshot.board.title),
                pins: pins, selectedID: selected?.pointId, mapHeight: 280,
                initialSpan: fit.map { min(180, max($0.latitudeSpan, $0.longitudeSpan)) } ?? 0.04,
                interactionID: context.readID, pinIdentifierPrefix: "city.read.pin.",
                pinHint: { id in
                    if let point = context.points.first(where: { $0.pointId == id }) { return Text(ownStatus(point)) }
                    return Text("")
                }, onSelect: { id in select(id, rendered: context) })
                .id(context.readID)
                .accessibilityIdentifier("city.read.map")
        }
        if let renderedSelection = selection, let point = selected {
            VStack(alignment: .leading, spacing: 8) {
                Text("city.read.point.selected").font(.headline)
                Label {
                    Text(verbatim: point.title).fixedSize(horizontal: false, vertical: true)
                } icon: { Image(systemName: symbol(point)) }
                Text(ownStatus(point)).fixedSize(horizontal: false, vertical: true)
                CityAcquisitionPointStatus(board: context.snapshot.board, pointID: point.pointId,
                    factory: acquisitionEntry?.acquisitionFactory, open: {
                        guard visible, scenePhase == .active, selection?.id == renderedSelection.id,
                              renderedSelection.point(in: reader.pointMapContext) != nil,
                              let factory = acquisitionEntry?.acquisitionFactory else { return }
                        acquisition = CityAcquisitionDestination(controller: factory())
                    }).id("\(context.readID):\(point.pointId)")
                Button("city.read.point.clear") {
                    guard selection?.id == renderedSelection.id,
                          renderedSelection.point(in: reader.pointMapContext) != nil else { return }
                    selection = nil
                }.frame(minHeight: 44).accessibilityIdentifier("city.read.point.clear")
            }.padding().frame(maxWidth: .infinity, alignment: .leading)
                .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("city.read.point.card.\(point.pointId)")
        }
        Text("city.read.points.list").font(.headline)
        ForEach(context.points) { point in
            Button { select(point.pointId, rendered: context) } label: {
                HStack(alignment: .top, spacing: 12) {
                    QuestifyMapPinSymbol(symbol: symbol(point), selected: selected?.pointId == point.pointId)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: point.title).fixedSize(horizontal: false, vertical: true)
                        Text(ownStatus(point)).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }.buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: point.title) + Text(verbatim: ", ") + Text(ownStatus(point)))
                .accessibilityHint(Text("city.read.point.selectHint"))
                .accessibilityAddTraits(selected?.pointId == point.pointId ? .isSelected : [])
                .accessibilityIdentifier("city.read.point.select.\(point.pointId)")
        }
    }
    private func select(_ id: String, rendered: CityPointMapContext) {
        guard let next = CityPointSelection(pointID: id, rendered: rendered, current: reader.pointMapContext) else { return }
        selection = next
    }
    private func symbol(_ point: CityReadPoint) -> String { point.mine ? "flag.fill" : "mappin.circle.fill" }
    private func ownStatus(_ point: CityReadPoint) -> LocalizedStringKey {
        point.mine ? "city.read.point.mine" : "city.read.point.notMine"
    }
    private func membership(_ status: CityMembership) -> LocalizedStringKey {
        switch status { case .joined: return "city.read.joined"; case .notJoined: return "city.read.notJoined"; case .unavailable: return "city.read.participation.unavailable" }
    }
    private func lifecycle(_ value: String) -> LocalizedStringKey {
        switch value { case "OPEN": return "city.read.open"; case "FROZEN": return "city.read.frozen"; default: return "city.read.closed" }
    }
}
