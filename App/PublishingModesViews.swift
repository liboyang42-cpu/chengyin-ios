import SwiftUI
import UIKit
import MapKit

/// Additive composition surface. Parent supplies professional-editor routing and the current
/// account epoch. No production mutation approval, map provider or token is created here.
@MainActor struct PublishingModesView: View {
    let service: PublishingService?
    let account: PublishingSession?
    var makeAIDraft: (() -> any PublishingAIDraftServing)? = nil
    var makeIdentityRegistration: (() -> PublisherIdentityRegistrationService?)? = nil
    var placeSearch: (any PublishingPlaceSearching)? = nil
    var draftStore: PublishingDraftStore? = nil
    var openProfessional: (ProjectEditDraft) -> Void
    var openResource: (PublishedResource) -> Void
    var body: some View {
        List {
            Section { Text("publishModes.offlineNotice").foregroundStyle(.secondary) }
            NavigationLink("publishModes.quick") { QuickPublishingView(placeSearch: placeSearch, account: account, draftStore: draftStore, makeAIDraft: makeAIDraft, openProfessional: openProfessional).id(account?.epoch) }
            NavigationLink("publishModes.activity") { ActivityPublishingView(service: service, account: account, placeSearch: placeSearch, draftStore: draftStore, makeIdentityRegistration: makeIdentityRegistration) }
            NavigationLink("publishModes.projects") { PublishingProjectsView(service: service, account: account, openResource: openResource) }
            NavigationLink("publishModes.identity") { PublishingIdentityStatusView(service: service, account: account) }
        }.navigationTitle(Text("publishModes.title")).accessibilityIdentifier("publishModes.home")
    }
}
@MainActor struct QuickPublishingView: View {
    @Environment(\.locale) private var locale
    var placeSearch: (any PublishingPlaceSearching)?
    var account: PublishingSession? = nil
    var draftStore: PublishingDraftStore? = nil
    var makeAIDraft: (() -> any PublishingAIDraftServing)? = nil
    var openProfessional: (ProjectEditDraft) -> Void
    @State private var showAI = false
    @State private var draft = QuickPublishDraft()
    @State private var selecting: UUID?
    @State private var problem = false
    @State private var draftID = UUID()
    @State private var storageMessage = ""
    var body: some View {
        Form {
            Section {
                Text("publishModes.aiNotice")
                Button("contextPublish.ai.title") { showAI = true }.accessibilityIdentifier("contextPublish.ai.open")
            }
            Section("publishModes.details") {
                TextField("publishModes.name", text: $draft.title).accessibilityIdentifier("publishModes.quick.name")
                TextField("publishModes.description", text: $draft.description, axis: .vertical).lineLimit(3...8)
                Picker("publishModes.product", selection: $draft.product) { Text("projectEdit.city").tag(ProjectEditProduct.city); Text("projectEdit.freeExplore").tag(ProjectEditProduct.freeExplore) }
            }
            ForEach($draft.nodes) { $node in
                Section {
                    TextField("publishModes.name", text: $node.name)
                    TextField("publishModes.description", text: $node.description, axis: .vertical)
                    Button { selecting = node.id } label: { Label(node.confirmedPlace?.name ?? appLocalized("publishModes.choosePlace", locale: locale), systemImage: "mappin.and.ellipse") }
                    if let place = node.confirmedPlace { Text(place.address).foregroundStyle(.secondary); Text("\(place.latitude), \(place.longitude)").font(.caption) }
                    Button("publishModes.remove", role: .destructive) { draft.nodes.removeAll { $0.id == node.id } }
                }
            }
            Section {
                Button("publishModes.saveLocal") {
                    guard let account, let draftStore else { return }
                    do { try draftStore.saveActive(PublishingLocalDraft(session: account, identity: draftID, quick: draft), session: account); storageMessage = "publishModes.savedLocal" }
                    catch { storageMessage = "publishModes.storageFailed" }
                }.disabled(account == nil || draftStore == nil)
                Button("publishModes.restoreLocal") {
                    guard let account, let draftStore else { return }
                    do {
                        if let saved = try draftStore.loadActive(activity: false, session: account), let quick = saved.quick { draft = quick; draftID = saved.identity; storageMessage = "publishModes.restoredLocal" }
                        else { storageMessage = "publishModes.noSavedLocal" }
                    } catch { storageMessage = "publishModes.storageFailed" }
                }.disabled(account == nil || draftStore == nil)
                if !storageMessage.isEmpty { Text(LocalizedStringKey(storageMessage)) }
            }
            Button("publishModes.addNode") { draft.nodes.append(.init()) }.accessibilityIdentifier("publishModes.quick.add")
            if problem { Text("publishModes.confirmEveryPlace").foregroundStyle(.red) }
            Button("publishModes.continueEditor") {
                do { openProfessional(try draft.professionalSeed()); problem = false } catch { problem = true }
            }.accessibilityIdentifier("publishModes.quick.continue")
        }.navigationTitle(Text("publishModes.quick"))
        .onChange(of: account) { _, _ in showAI = false; selecting = nil; draft = .init(); draftID = UUID(); storageMessage = "" }
        .sheet(isPresented: $showAI) {
            PublishingAIDraftSheet(client: makeAIDraft?(), product: draft.product) { value in
                draft = value; draftID = UUID(); problem = false; storageMessage = ""
            }
        }
        .sheet(isPresented: Binding(get: { selecting != nil }, set: { if !$0 { selecting = nil } })) {
            PublishingPlacePicker(provider: placeSearch) { place in
                if let index = draft.nodes.firstIndex(where: { $0.id == selecting }) { draft.nodes[index].confirmedPlace = place }; selecting = nil
            }
        }
    }
}
@MainActor struct ActivityPublishingView: View {
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var localClear = ActivityPublishingLocalClearOwner()
    @StateObject private var timeRange = ActivityPublishingTimeRangeOwner()
    @StateObject private var identityRegistration = PublisherIdentityRegistrationOwner()
    let service: PublishingService?
    let account: PublishingSession?
    var placeSearch: (any PublishingPlaceSearching)?
    var draftStore: PublishingDraftStore? = nil
    @State private var draftID = UUID()
    var makeIdentityRegistration: (() -> PublisherIdentityRegistrationService?)? = nil
    @State private var draft = ActivityPublishDraft()
    @State private var picker: String?
    @State private var review: PublishingReview?
    @State private var localReview = false
    @State private var busy = false
    @State private var message = ""
    @State private var acknowledged = false
    @State private var uncertain = false
    private var editable: Bool { !busy && !acknowledged && !uncertain && !identityRegistration.open }
    private var requiresIdentity: Bool {
        account?.region == .china && account?.role == "club" && draft.tickets.contains {
            Decimal(string: $0.price, locale: Locale(identifier: "en_US_POSIX")).map { $0 > 0 } == true
        }
    }
    var body: some View {
        let _ = identityRegistration.bind(account: account, draftID: draftID, draft: draft)
        let _ = localClear.bind(account: account, draftID: draftID, draft: draft, editable: mayClear)
        let _ = timeRange.bind(account: account, draftID: draftID, draft: draft, editable: mayEditTimeRange)
        Form {
            Section { Text("publishModes.clubOnly"); Text("publishModes.offlineNotice").foregroundStyle(.secondary) }
            Section("publishModes.details") {
                TextField("publishModes.name", text: $draft.name)
                clearButton(.name)
                TextField("publishModes.description", text: $draft.description, axis: .vertical).lineLimit(3...8)
                clearButton(.description)
                TextField("publishModes.cover", text: $draft.coverURL).textInputAutocapitalization(.never).autocorrectionDisabled()
                Text("publishModes.uploadDisabled").font(.caption).foregroundStyle(.secondary)
                TextField("publishModes.addressName", text: $draft.addressName)
                Button("publishModes.choosePlace") { picker = "place" }
                if let place = draft.place { Text(place.name); Text(place.address).font(.caption) }
                TextField("publishModes.start", text: $draft.start).accessibilityIdentifier("publishModes.activity.start")
                TextField("publishModes.end", text: $draft.end)
                Text("publishModes.dateFormat").font(.caption)
                Button {
                    localClear.invalidate()
                    timeRange.open(account: account, draftID: draftID, draft: draft, now: Date(), timeZoneID: TimeZone.autoupdatingCurrent.identifier)
                } label: { Text(verbatim: locale.language.languageCode?.identifier == "zh" ? "选择活动起止时间" : "Choose activity start and end") }
                    .disabled(!mayEditTimeRange || !timeRange.canOpen(account: account, draftID: draftID, draft: draft, now: Date()))
                    .accessibilityIdentifier("publishModes.activity.timeRange.open")
                Button("publishModes.categories") { picker = "category" }; Text(draft.categoryIDs.map(String.init).joined(separator: ", "))
                Button("publishModes.template") { picker = "template" }; Text(draft.playTemplateID.map { String($0.rawValue) } ?? "—")
                Button("publishModes.collaborators") { picker = "collaborator" }; Text(draft.collaboratorMemberIDs.map(String.init).joined(separator: ", "))
            }.disabled(!editable)
            ForEach($draft.tickets) { $ticket in
                Section("publishModes.ticket") {
                    TextField("publishModes.name", text: $ticket.name)
                    clearButton(.ticketName(ticket.id))
                    TextField("publishModes.price", text: $ticket.price).keyboardType(.decimalPad)
                    TextField("publishModes.stock", text: $ticket.stock).keyboardType(.numberPad)
                    clearButton(.ticketStock(ticket.id))
                    TextField("publishModes.start", text: $ticket.start)
                    TextField("publishModes.end", text: $ticket.end)
                    Button("publishModes.remove", role: .destructive) { draft.tickets.removeAll { $0.id == ticket.id } }
                }.disabled(!editable)
            }
            Section {
                Button("publishModes.saveLocal") {
                    guard let account, let draftStore else { return }
                    do { try draftStore.saveActive(PublishingLocalDraft(session: account, identity: draftID, activity: draft), session: account); message = "publishModes.savedLocal" }
                    catch { message = "publishModes.storageFailed" }
                }.disabled(!editable || account == nil || draftStore == nil)
                Button("publishModes.restoreLocal") {
                    localClear.invalidate(); timeRange.retire()
                    guard let account, let draftStore else { return }
                    do {
                        if let saved = try draftStore.loadActive(activity: true, session: account), let activity = saved.activity { draft = activity; draftID = saved.identity; message = "publishModes.restoredLocal" }
                        else { message = "publishModes.noSavedLocal" }
                    } catch { message = "publishModes.storageFailed" }
                }.disabled(!editable || account == nil || draftStore == nil)
            }
            if requiresIdentity {
                PublisherIdentityRegistrationSection(owner: identityRegistration, makeService: makeIdentityRegistration, enabled: mayClear)
            }
            Button("publishModes.addTicket") { draft.tickets.append(.init()) }.disabled(!editable)
            if !message.isEmpty { Text(LocalizedStringKey(message)).accessibilityIdentifier("publishModes.message") }
            Button("publishModes.review") { Task { await prepare() } }.disabled(!editable).accessibilityIdentifier("publishModes.activity.review")
        }.navigationTitle(Text("publishModes.activity"))
        .onChange(of: draft) { _, _ in timeRange.retire(); if let review { service?.cancel(review) }; review = nil; localReview = false }
        .onChange(of: account) { _, _ in localClear.invalidate(); timeRange.retire(); service?.invalidateReviews(); draft = .init(); draftID = UUID(); review = nil; localReview = false; acknowledged = false; uncertain = false; message = "" }
        .onAppear { localClear.appear(active: scenePhase == .active); timeRange.setActive(scenePhase == .active); identityRegistration.appear(active: scenePhase == .active) }
        .onChange(of: scenePhase) { _, phase in localClear.setActive(phase == .active); timeRange.setActive(phase == .active); identityRegistration.setActive(phase == .active) }
        .onDisappear { identityRegistration.disappear(); localClear.retire(); if let review { service?.cancel(review) }; review = nil }
        .background { ActivityPublishingTimeRangeLifetimeAnchor(owner: timeRange).frame(width: 0, height: 0) }
        .background {
            if let original = timeRange.presentation {
                ActivityPublishingTimeRangePresenter(owner: timeRange, original: original) { selected in
                    timeRange.apply(selected, original: original, draft: $draft, account: account, draftID: draftID,
                        timeZoneID: TimeZone.autoupdatingCurrent.identifier, allowed: mayEditTimeRange)
                }.id(original.id)
            }
        }
        .sheet(isPresented: Binding(get: { picker != nil }, set: { if !$0 { picker = nil } })) { pickerSheet }
        .sheet(isPresented: $localReview) {
            NavigationStack {
                List {
                    Text(draft.name); Text(draft.description); Text(draft.start + " → " + draft.end)
                    Text("\(draft.tickets.count) " + appLocalized("publishModes.ticket", locale: locale))
                    Text("publishModes.reviewNotice").foregroundStyle(.secondary)
                    Button("publishModes.confirm") { Task { await submit() } }.disabled(review == nil || service?.mutationsConfigured != true)
                    Button("publishModes.cancel", role: .cancel) { if let review { service?.cancel(review) }; review = nil; localReview = false }
                }.navigationTitle(Text("publishModes.review"))
            }
        }
    }
    private var mayClear: Bool { mayEditTimeRange && timeRange.presentation == nil }
    private var mayEditTimeRange: Bool {
        editable && review == nil && !localReview && picker == nil &&
            (service == nil || service?.currentSession == account)
    }
    private func clearButton(_ field: ActivityPublishingLocalClearOwner.Field) -> some View {
        let action = localClear.action(field, draft: $draft, account: account, draftID: draftID, allowed: { mayClear })
        return Button(action: action) {
            Text(verbatim: locale.language.languageCode?.identifier == "zh" ? "清空" : "Clear")
        }.buttonStyle(.borderless)
            .disabled(!mayClear || !localClear.canClear(field, draft: draft, account: account, draftID: draftID))
            .accessibilityIdentifier("publishModes.activity.clear." + field.id)
    }
    @ViewBuilder private var pickerSheet: some View {
        if picker == "place" {
            PublishingPlacePicker(provider: placeSearch) { place in draft.place = place; draft.addressName = place.name; picker = nil }
        } else {
            PublishingOptionsPicker(service: service, account: account, kind: picker ?? "category", selected: picker == "category" ? draft.categoryIDs : picker == "collaborator" ? draft.collaboratorMemberIDs : draft.playTemplateID.map { [$0.rawValue] } ?? []) { values in
                if picker == "category" { draft.categoryIDs = values }
                else if picker == "collaborator" { draft.collaboratorMemberIDs = values }
                else { draft.playTemplateID = values.first.flatMap { AuthoringPlayTemplateID(rawValue: $0) } }; picker = nil
            }
        }
    }
    private func prepare() async {
        localClear.invalidate(); timeRange.retire()
        busy = true; defer { busy = false }
        do {
            _ = try draft.wire()
            if let service, let account { review = try await service.prepareActivity(draft, session: account) }
            localReview = true; message = ""
        } catch { message = "publishModes.invalid" }
    }
    private func submit() async {
        guard let review, let service else { return }; localReview = false; busy = true
        let result = await service.submit(review); busy = false
        guard service.currentSession == account else { self.review = nil; return }
        self.review = nil
        switch result { case .acknowledged: acknowledged = true; message = "publishModes.acknowledged"
        case .unknown: uncertain = true; message = "publishModes.unknown"
        case .notSent: message = "publishModes.notSent"
        case .rejected(let reason): message = reason.isEmpty ? "publishModes.rejected" : reason }
    }
}
/// A local action lease for the full activity form, never a persistence or dispatch capability.
@MainActor final class ActivityPublishingLocalClearOwner: ObservableObject {
    enum Field {
        case name, description, ticketName(UUID), ticketStock(UUID)
        var id: String {
            switch self {
            case .name: return "name"
            case .description: return "description"
            case .ticketName(let id): return "ticketName." + id.uuidString
            case .ticketStock(let id): return "ticketStock." + id.uuidString
            }
        }
        func applying(to source: ActivityPublishDraft) -> ActivityPublishDraft? {
            var next = source
            switch self {
            case .name: guard !source.name.isEmpty else { return nil }; next.name = ""
            case .description: guard !source.description.isEmpty else { return nil }; next.description = ""
            case .ticketName(let id), .ticketStock(let id):
                guard source.tickets.filter({ $0.id == id }).count == 1,
                      let index = source.tickets.firstIndex(where: { $0.id == id }) else { return nil }
                if case .ticketName = self {
                    guard !source.tickets[index].name.isEmpty else { return nil }; next.tickets[index].name = ""
                } else {
                    guard source.tickets[index].stock != "0" else { return nil }; next.tickets[index].stock = "0"
                }
            }
            return next
        }
    }
    private struct Source: Encodable {
        let account: PublishingSession?
        let draftID: UUID
        let draft: ActivityPublishDraft
        let editable: Bool
    }
    private var source: Data?
    private var generation = UUID()
    private var visible = false
    private var active = false
    @Published private(set) var revision = 0
    private func bytes(account: PublishingSession?, draftID: UUID, draft: ActivityPublishDraft, editable: Bool = true) -> Data? {
        ProjectEditPendingMaterials.exactData(Source(account: account, draftID: draftID, draft: draft, editable: editable))
    }
    func bind(account: PublishingSession?, draftID: UUID, draft: ActivityPublishDraft, editable: Bool = true) {
        let next = bytes(account: account, draftID: draftID, draft: draft, editable: editable)
        if next != source { generation = UUID(); source = next }
    }
    func appear(active: Bool) {
        if !visible { invalidate(); visible = true }
        setActive(active)
    }
    func setActive(_ next: Bool) {
        guard next != active else { return }; invalidate(); active = next
    }
    func invalidate() { generation = UUID(); revision += 1 }
    func retire() { visible = false; invalidate() }
    func canClear(_ field: Field, draft: ActivityPublishDraft, account: PublishingSession?, draftID: UUID) -> Bool {
        visible && active && source != nil && source == bytes(account: account, draftID: draftID, draft: draft) &&
            field.applying(to: draft) != nil
    }
    func action(_ field: Field, draft: Binding<ActivityPublishDraft>, account: PublishingSession?, draftID: UUID,
                allowed: @escaping () -> Bool) -> () -> Void {
        let stamp = generation, expected = source
        return { [weak self] in
            guard let self, self.generation == stamp, self.source == expected, allowed(),
                  self.canClear(field, draft: draft.wrappedValue, account: account, draftID: draftID),
                  let next = field.applying(to: draft.wrappedValue) else { return }
            self.invalidate(); draft.wrappedValue = next
        }
    }
}


/// A local pair draft. Conversion reuses the existing publishing date codec.
struct ActivityPublishingTimeRangeDraft {
    var start: Date
    var end: Date
    private let originalStart: String
    private let originalEnd: String
    init?(source: ActivityPublishDraft, now: Date) {
        let first = ProjectEditDateSelection.date(source.start, ending: false)
        let last = ProjectEditDateSelection.date(source.end, ending: false)
        guard (source.start.isEmpty || first != nil), (source.end.isEmpty || last != nil),
              let fallback = ProjectEditDateSelection.beijingValue(now).flatMap({ ProjectEditDateSelection.date($0, ending: false) }) else { return nil }
        start = first ?? fallback; end = last ?? start.addingTimeInterval(3600)
        originalStart = source.start; originalEnd = source.end
    }
    func applying(to source: ActivityPublishDraft) -> ActivityPublishDraft? {
        guard source.start.utf8.elementsEqual(originalStart.utf8), source.end.utf8.elementsEqual(originalEnd.utf8),
              end > start, let first = ProjectEditDateSelection.beijingValue(start),
              let last = ProjectEditDateSelection.beijingValue(end), last > first else { return nil }
        var next = source
        if ProjectEditDateSelection.date(originalStart, ending: false) != start { next.start = first }
        if ProjectEditDateSelection.date(originalEnd, ending: false) != end { next.end = last }
        return next
    }
}


@MainActor final class ActivityPublishingTimeRangeOwner: ObservableObject {
    struct Presentation: Identifiable {
        let id = UUID()
        let generation: UUID
        let source: Data
        let draft: ActivityPublishingTimeRangeDraft
        let timeZoneID: String
    }
    private struct Source: Encodable {
        let account: PublishingSession?
        let draftID: UUID
        let draft: ActivityPublishDraft
        let editable: Bool
    }
    @Published private(set) var presentation: Presentation?
    private var source: Data?
    private var generation = UUID()
    @Published private var pageVisible = false
    private var sheetID: UUID?
    private var coveredByOwnSheet = false
    @Published private var active = false
    private func bytes(account: PublishingSession?, draftID: UUID, draft: ActivityPublishDraft, editable: Bool = true) -> Data? {
        ProjectEditPendingMaterials.exactData(Source(account: account, draftID: draftID, draft: draft, editable: editable))
    }
    func bind(account: PublishingSession?, draftID: UUID, draft: ActivityPublishDraft, editable: Bool) {
        let next = bytes(account: account, draftID: draftID, draft: draft, editable: editable)
        if source != next { source = next; generation = UUID() }
    }
    func appear(active: Bool) {
        if !pageVisible, sheetID == nil, presentation != nil { retire() }
        pageVisible = true; setActive(active)
    }
    func parentAppeared() { pageVisible = true; coveredByOwnSheet = false }
    func parentDisappeared(departing: Bool, coveredByPresentation: Bool) {
        // UIKit may report coverage before the new sheet's onAppear. The concrete
        // route may survive that order, but Apply still requires its own sheetID.
        guard !departing, coveredByPresentation, active, let presentation,
              generation == presentation.generation, source == presentation.source else { disappear(); return }
        coveredByOwnSheet = true; pageVisible = false
    }
    func disappear() { pageVisible = false; coveredByOwnSheet = false; retire() }
    func setActive(_ value: Bool) { active = value; if !value { retire() } }
    func retire() { generation = UUID(); presentation = nil; sheetID = nil; coveredByOwnSheet = false }
    func canOpen(account: PublishingSession?, draftID: UUID, draft: ActivityPublishDraft, now: Date) -> Bool {
        pageVisible && active && presentation == nil && source != nil &&
        source == bytes(account: account, draftID: draftID, draft: draft) && ActivityPublishingTimeRangeDraft(source: draft, now: now) != nil
    }
    func open(account: PublishingSession?, draftID: UUID, draft: ActivityPublishDraft, now: Date, timeZoneID: String) {
        guard canOpen(account: account, draftID: draftID, draft: draft, now: now), let source,
              let value = ActivityPublishingTimeRangeDraft(source: draft, now: now), TimeZone(identifier: timeZoneID) != nil else { return }
        presentation = .init(generation: generation, source: source, draft: value, timeZoneID: timeZoneID)
    }
    func current(_ value: Presentation, timeZoneID: String) -> Bool {
        active && (pageVisible || coveredByOwnSheet) && presentation?.id == value.id &&
        generation == value.generation && source == value.source && value.timeZoneID == timeZoneID
    }
    func sheetAppeared(_ value: Presentation, timeZoneID: String) {
        guard current(value, timeZoneID: timeZoneID) else { return }; sheetID = value.id
    }
    func close(_ value: Presentation) {
        guard presentation?.id == value.id else { return }; retire()
    }
    func binding(_ value: Presentation, timeZoneID: @escaping () -> String) -> Binding<Presentation?> {
        .init(get: {
            guard self.current(value, timeZoneID: timeZoneID()) else { return nil }; return value
        }, set: { if $0 == nil { self.close(value) } })
    }
    @discardableResult func apply(_ edited: ActivityPublishingTimeRangeDraft, original: Presentation,
                                  draft: Binding<ActivityPublishDraft>, account: PublishingSession?, draftID: UUID,
                                  timeZoneID: String, allowed: Bool) -> Bool {
        guard allowed, sheetID == original.id, current(original, timeZoneID: timeZoneID),
              source == bytes(account: account, draftID: draftID, draft: draft.wrappedValue),
              let next = edited.applying(to: draft.wrappedValue) else { return false }
        retire()
        if ProjectEditPendingMaterials.exactData(next) != ProjectEditPendingMaterials.exactData(draft.wrappedValue) { draft.wrappedValue = next }
        return true
    }
}

/// One already-open route owns its sheet binding; an initial nil body owns no presenter.
@MainActor struct ActivityPublishingTimeRangePresenter: View {
    @ObservedObject var owner: ActivityPublishingTimeRangeOwner
    let original: ActivityPublishingTimeRangeOwner.Presentation
    let apply: (ActivityPublishingTimeRangeDraft) -> Bool
    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .sheet(item: owner.binding(original, timeZoneID: { TimeZone.autoupdatingCurrent.identifier })) { offered in
                ActivityPublishingTimeRangeSheet(owner: owner, original: offered, apply: apply)
            }
    }
}

/// Keep modal coverage separate from the source controller leaving its hierarchy.
@MainActor struct ActivityPublishingTimeRangeLifetimeAnchor: UIViewControllerRepresentable {
    let owner: ActivityPublishingTimeRangeOwner
    func makeUIViewController(context: Context) -> ActivityPublishingTimeRangeLifetimeController {
        ActivityPublishingTimeRangeLifetimeController(owner: owner)
    }
    func updateUIViewController(_ controller: ActivityPublishingTimeRangeLifetimeController, context: Context) {}
    static func dismantleUIViewController(_ controller: ActivityPublishingTimeRangeLifetimeController, coordinator: ()) {
        controller.owner?.disappear()
    }
}
@MainActor final class ActivityPublishingTimeRangeLifetimeController: UIViewController {
    weak var owner: ActivityPublishingTimeRangeOwner?
    private var departing = false
    init(owner: ActivityPublishingTimeRangeOwner) { self.owner = owner; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { return nil }
    private var ancestry: [UIViewController] {
        var result: [UIViewController] = [], next: UIViewController? = self
        while let value = next { result.append(value); next = value.parent }
        return result
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated); departing = false; owner?.parentAppeared()
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        departing = ancestry.contains { $0.isMovingFromParent || $0.isBeingDismissed }
    }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated); let source = ancestry
        owner?.parentDisappeared(departing: departing || source.contains { $0.isMovingFromParent || $0.isBeingDismissed },
            coveredByPresentation: source.contains { $0.presentedViewController != nil })
    }
}

@MainActor private struct ActivityPublishingTimeRangeSheet: View {
    @ObservedObject var owner: ActivityPublishingTimeRangeOwner
    let original: ActivityPublishingTimeRangeOwner.Presentation
    let apply: (ActivityPublishingTimeRangeDraft) -> Bool
    @Environment(\.locale) private var locale
    @State private var draft: ActivityPublishingTimeRangeDraft
    @State private var editingEnd = false
    @State private var failure = false
    init(owner: ActivityPublishingTimeRangeOwner, original: ActivityPublishingTimeRangeOwner.Presentation,
         apply: @escaping (ActivityPublishingTimeRangeDraft) -> Bool) {
        self.owner = owner; self.original = original; self.apply = apply
        _draft = State(initialValue: original.draft)
    }
    private var current: Bool { owner.current(original, timeZoneID: TimeZone.autoupdatingCurrent.identifier) }
    private func text(_ en: String, _ zh: String) -> String { locale.language.languageCode?.identifier == "zh" ? zh : en }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(verbatim: text("Choose the start, then the end. Nothing changes until Apply.", "先选择开始，再选择结束。点击应用前不修改草稿。"))
                    Text(verbatim: text("Picker uses your phone time zone; the preview uses Beijing time.", "选择器使用手机时区；下方预览为北京时间。"))
                }
                Section {
                    DatePicker(selection: editingEnd ? $draft.end : $draft.start, displayedComponents: [.date, .hourAndMinute]) {
                        Text(LocalizedStringKey(editingEnd ? "publishModes.end" : "publishModes.start"))
                    }.environment(\.timeZone, TimeZone(identifier: original.timeZoneID) ?? .gmt)
                        .accessibilityIdentifier("publishModes.activity.timeRange.date")
                    LabeledContent("publishModes.start", value: ProjectEditDateSelection.beijingValue(draft.start) ?? "—")
                    LabeledContent("publishModes.end", value: ProjectEditDateSelection.beijingValue(draft.end) ?? "—")
                } header: { Text(LocalizedStringKey(editingEnd ? "publishModes.end" : "publishModes.start")) }
                if failure || (editingEnd && draft.end <= draft.start) {
                    Text(verbatim: text("The end must be later than the start. Reopen if the draft or account changed.", "结束时间必须晚于开始时间；草稿或账户改变后请重新打开。"))
                        .accessibilityIdentifier("publishModes.activity.timeRange.invalid")
                }
                if editingEnd {
                    Button { editingEnd = false; failure = false } label: { Text("publishModes.start") }
                    Button {
                        guard current else { return }; failure = !apply(draft)
                    } label: { Text(verbatim: text("Apply", "应用")) }
                        .disabled(!current || draft.end <= draft.start).accessibilityIdentifier("publishModes.activity.timeRange.apply")
                } else {
                    Button {
                        guard current else { return }
                        if draft.end <= draft.start { draft.end = draft.start.addingTimeInterval(3600) }
                        editingEnd = true; failure = false
                    } label: { Text(verbatim: text("Next: end time", "下一步：结束时间")) }
                        .accessibilityIdentifier("publishModes.activity.timeRange.next")
                }
            }.disabled(!current)
                .navigationTitle(Text(verbatim: text("Activity time", "活动时间")))
                .toolbar { ToolbarItem(placement: .cancellationAction) {
                    Button("publishModes.cancel") { owner.close(original) }.accessibilityIdentifier("publishModes.activity.timeRange.cancel")
                } }
        }.onAppear { owner.sheetAppeared(original, timeZoneID: TimeZone.autoupdatingCurrent.identifier) }
            .onDisappear { owner.close(original) }
    }
}

@MainActor struct PublishingOptionsPicker: View {
    let service: PublishingService?
    let account: PublishingSession?
    let kind: String
    @State var selected: [Int]
    var onConfirm: ([Int]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var keyword = ""
    @State private var rows: [PublishingOption] = []
    @State private var busy = false
    @State private var failed = false
    @State private var generation = 0
    var body: some View {
        NavigationStack {
            List {
                if busy { ProgressView() }
                if failed { Text("publishModes.readFailed"); Button("publishModes.retry") { Task { await load() } } }
                if !busy && !failed && rows.isEmpty { Text("publishModes.empty") }
                ForEach(rows) { row in
                    Button {
                        if selected.contains(row.id) { selected.removeAll { $0 == row.id } }
                        else if kind == "template" { selected = [row.id] } else { selected.append(row.id) }
                    } label: {
                        HStack { VStack(alignment: .leading) { Text(row.name); if !row.detail.isEmpty { Text(row.detail).font(.caption) } }; Spacer(); if selected.contains(row.id) { Image(systemName: "checkmark") } }
                    }.accessibilityValue(selected.contains(row.id) ? Text("publishModes.selected") : Text("publishModes.notSelected"))
                }
            }.searchable(text: $keyword).onSubmit(of: .search) { Task { await load() } }
            .onChange(of: keyword) { _, value in if value.isEmpty { Task { await load() } } }
            .navigationTitle(Text("publishModes.choose"))
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("publishModes.cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("publishModes.done") { onConfirm(selected) } } }
            .task { await load() }.onDisappear { generation += 1 }
        }
    }
    private func load() async {
        generation += 1; let stamp = generation; busy = true; failed = false
        guard let service, let account else { failed = true; busy = false; return }
        let query: PublishingRead = kind == "category" ? .categories(activity: true) : kind == "collaborator" ? .collaborators(keyword: keyword) : .templates(keyword: keyword, scope: "")
        do { let value = try await service.read(query, session: account); guard stamp == generation else { return }; rows = try PublishingContracts.options(value, kind: query); busy = false }
        catch { guard stamp == generation else { return }; rows = []; busy = false; failed = true }
    }
}
@MainActor struct PublishingPlacePicker: View {
    var provider: (any PublishingPlaceSearching)?
    var onConfirm: (PublishingPlace) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var keyword = ""
    @State private var rows: [PublishingPlace] = []
    @State private var selected: PublishingPlace?
    @State private var busy = false
    @State private var failed = false
    @State private var generation = 0
    var body: some View {
        NavigationStack {
            List {
                if busy { ProgressView() }
                if failed || provider == nil { Text("publishModes.mapUnavailable") }
                if let selected {
                    Map(initialPosition: .region(.init(center: .init(latitude: selected.latitude, longitude: selected.longitude), span: .init(latitudeDelta: 0.01, longitudeDelta: 0.01)))) {
                        Marker(selected.name, coordinate: .init(latitude: selected.latitude, longitude: selected.longitude))
                    }.frame(height: 240).id(selected.id).accessibilityLabel(Text(selected.name))
                    Text(selected.address); Text("\(selected.latitude), \(selected.longitude)")
                }
                ForEach(rows) { place in Button { selected = place } label: { VStack(alignment: .leading) { Text(place.name); Text(place.address).font(.caption) } } }
                if rows.isEmpty && !busy { Text("publishModes.searchPlace") }
            }.searchable(text: $keyword).onSubmit(of: .search) { Task { await search() } }
            .onChange(of: keyword) { _, value in if value.isEmpty { generation += 1; selected = nil; rows = []; busy = false } }
            .navigationTitle(Text("publishModes.choosePlace"))
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("publishModes.cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("publishModes.confirmPlace") { if let selected { onConfirm(selected) } }.disabled(selected == nil) } }
            .onDisappear { generation += 1 }
        }
    }
    private func search() async {
        generation += 1; let stamp = generation; selected = nil; rows = []; failed = false
        guard let provider, !keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { busy = false; return }; busy = true
        do { let result = try await provider.search(keyword); guard stamp == generation else { return }; rows = result; busy = false }
        catch { guard stamp == generation else { return }; busy = false; failed = true }
    }
}
