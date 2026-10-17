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
    var makeActivityTemplate: (() -> AnyView)? = nil
    var makeActivityCover: (() -> ActivityCoverService?)? = nil
    var placeSearch: (any PublishingPlaceSearching)? = nil
    var draftStore: PublishingDraftStore? = nil
    var openProfessional: (ProjectEditDraft) -> Void
    var openResource: (PublishedResource) -> Void
    var body: some View {
        List {
            Section { Text("publishModes.offlineNotice").foregroundStyle(.secondary) }
            NavigationLink("publishModes.quick") { QuickPublishingView(placeSearch: placeSearch, account: account, draftStore: draftStore, makeAIDraft: makeAIDraft, openProfessional: openProfessional).id(account?.epoch) }
            NavigationLink("publishModes.activity") { ActivityPublishingView(service: service, account: account, placeSearch: placeSearch, draftStore: draftStore, makeIdentityRegistration: makeIdentityRegistration, makeActivityTemplate: makeActivityTemplate, makeActivityCover: makeActivityCover, openResource: openResource) }
            NavigationLink("publishModes.projects") { PublishingProjectsView(service: service, account: account, openResource: openResource) }
            NavigationLink("publishModes.identity") { PublishingIdentityStatusView(service: service, account: account) }
        }.navigationTitle(Text("publishModes.title")).accessibilityIdentifier("publishModes.home")
    }
}
@MainActor struct QuickPublishingView: View {
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var journey = QuickPublishingJourneyOwner()
    var placeSearch: (any PublishingPlaceSearching)?
    var account: PublishingSession? = nil
    var draftStore: PublishingDraftStore? = nil
    var makeAIDraft: (() -> any PublishingAIDraftServing)? = nil
    var openProfessional: (ProjectEditDraft) -> Void
    var body: some View {
        let _ = journey.bind(account: account)
        let draft = journey.draftBinding()
        Form {
            Section {
                Text("publishModes.aiNotice")
                Button("contextPublish.ai.title", action: journey.openAIAction(makeClient: makeAIDraft))
                    .accessibilityIdentifier("contextPublish.ai.open")
            }
            Section("publishModes.details") {
                TextField("publishModes.name", text: draft.title).accessibilityIdentifier("publishModes.quick.name")
                TextField("publishModes.description", text: draft.description, axis: .vertical).lineLimit(3...8)
                Picker("publishModes.product", selection: draft.product) { Text("projectEdit.city").tag(ProjectEditProduct.city); Text("projectEdit.freeExplore").tag(ProjectEditProduct.freeExplore) }
            }
            ForEach(draft.nodes) { $node in
                Section {
                    TextField("publishModes.name", text: $node.name)
                    TextField("publishModes.description", text: $node.description, axis: .vertical)
                    Button(action: journey.openPlaceAction(node.id)) { Label(node.confirmedPlace?.name ?? appLocalized("publishModes.choosePlace", locale: locale), systemImage: "mappin.and.ellipse") }
                    if let place = node.confirmedPlace { Text(place.address).foregroundStyle(.secondary); Text("\(place.latitude), \(place.longitude)").font(.caption) }
                    Button("publishModes.remove", role: .destructive, action: journey.removeNodeAction(node.id))
                }
            }
            Section {
                Button("publishModes.saveLocal", action: journey.saveAction(store: draftStore))
                    .disabled(account == nil || draftStore == nil)
                Button("publishModes.restoreLocal", action: journey.restoreAction(store: draftStore))
                    .disabled(account == nil || draftStore == nil)
                if !journey.storageMessage.isEmpty { Text(LocalizedStringKey(journey.storageMessage)) }
            }
            Button("publishModes.addNode", action: journey.addNodeAction()).accessibilityIdentifier("publishModes.quick.add")
            if journey.problem { Text("publishModes.confirmEveryPlace").foregroundStyle(.red) }
            Button("publishModes.continueEditor", action: journey.handoffAction(openProfessional))
                .accessibilityIdentifier("publishModes.quick.continue")
        }.disabled(!journey.canEdit).navigationTitle(Text("publishModes.quick"))
        .onAppear { journey.appear(active: scenePhase == .active) }
        .onChange(of: scenePhase) { _, phase in journey.setActive(phase == .active) }
        .background { QuickPublishingJourneyLifetime(owner: journey).frame(width: 0, height: 0) }
        .background {
            if let original = journey.presentation {
                QuickPublishingJourneyPresenter(owner: journey, original: original, placeSearch: placeSearch).id(original.id)
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
    @StateObject private var templateSelection = ActivityTemplateSelectionOwner()
    @StateObject private var cover = ActivityCoverAuthoringOwner()
    @StateObject private var submission = ActivityPublishingSubmissionOwner()
    let service: PublishingService?
    let account: PublishingSession?
    var placeSearch: (any PublishingPlaceSearching)?
    var draftStore: PublishingDraftStore? = nil
    @State private var draftID = UUID()
    var makeIdentityRegistration: (() -> PublisherIdentityRegistrationService?)? = nil
    var makeActivityTemplate: (() -> AnyView)? = nil
    var makeActivityCover: (() -> ActivityCoverService?)? = nil
    var openResource: ((PublishedResource) -> Void)? = nil
    @State private var draft = ActivityPublishDraft()
    @State private var picker: String?
    @State private var review: PublishingReview?
    @State private var localReview = false
    private var busy: Bool { submission.busy }
    @State private var message = ""
    private var acknowledged: Bool { submission.outcome == .acknowledged }
    private var uncertain: Bool { submission.outcome == .unknown || submission.lockUnavailable }
    private var coverEditable: Bool { !busy && !acknowledged && !uncertain && !identityRegistration.open && !templateSelection.open && review == nil && !localReview && picker == nil && timeRange.presentation == nil && (service == nil || service?.currentSession == account) }
    private var editable: Bool { !busy && !acknowledged && !uncertain && !identityRegistration.open && !templateSelection.open && !cover.isOpen }
    private var requiresIdentity: Bool {
        account?.region == .china && account?.role == "club" && draft.tickets.contains {
            Decimal(string: $0.price, locale: Locale(identifier: "en_US_POSIX")).map { $0 > 0 } == true
        }
    }
    var body: some View {
        let _ = submission.bind(account: account, draftID: draftID, draft: draft, service: service)
        let _ = cover.bind(read: { .init(session: account, target: .newDraft(draftID), draft: ProjectEditPendingMaterials.exactData(draft), reference: draft.coverURL, editable: coverEditable) }, apply: { value in
            guard coverEditable else { return false }; draft.coverURL = value; return true
        }, service: { makeActivityCover?() })
        let _ = templateSelection.bind(session: account, draftID: draftID, draft: draft)
        let templateSelectionAction = templateSelection.actionID
        let templateReadID = templateSelection.readID
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
                Button("publishModes.template") {
                    localClear.invalidate(); timeRange.retire()
                    templateSelection.begin(service: service, expected: templateSelectionAction, allowed: mayEditTimeRange)
                }.accessibilityIdentifier("activityTemplate.open")
                Text(draft.playTemplateID.map { String($0.rawValue) } ?? "—")
                Button("publishModes.collaborators") { picker = "collaborator" }; Text(draft.collaboratorMemberIDs.map(String.init).joined(separator: ", "))
            }.disabled(!editable)
            Section { ActivityCoverAuthoringSection(owner: cover) }
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
            if templateSelection.open {
                ActivityTemplateSelectionSection(owner: templateSelection, apply: { stamp in
                    templateSelection.apply(expected: stamp, draft: $draft, session: account, draftID: draftID,
                        allowed: !busy && !acknowledged && !uncertain && !identityRegistration.open)
                }, createAvailable: makeActivityTemplate != nil)
            }
            if requiresIdentity {
                PublisherIdentityRegistrationSection(owner: identityRegistration, makeService: makeIdentityRegistration, enabled: mayClear)
            }
            Button("publishModes.addTicket") { draft.tickets.append(.init()) }.disabled(!editable)
            if !message.isEmpty { Text(LocalizedStringKey(message)).accessibilityIdentifier("publishModes.message") }
            submissionResult
            Button("publishModes.review") { Task { await prepare() } }.disabled(!editable).accessibilityIdentifier("publishModes.activity.review")
        }.navigationTitle(Text("publishModes.activity"))
        .onChange(of: draft) { _, _ in timeRange.retire(); if let review { service?.cancel(review) }; review = nil; localReview = false }
        .onChange(of: account) { _, _ in cover.accountChanged(); localClear.invalidate(); timeRange.retire(); service?.invalidateReviews(); draft = .init(); draftID = UUID(); review = nil; localReview = false; message = "" }
        .onAppear { submission.setActive(scenePhase == .active); cover.appear(active: scenePhase == .active); localClear.appear(active: scenePhase == .active); timeRange.setActive(scenePhase == .active); identityRegistration.appear(active: scenePhase == .active); templateSelection.setActive(scenePhase == .active) }
        .onChange(of: scenePhase) { _, phase in
            submission.setActive(phase == .active)
            if phase != .active { if let review { service?.cancel(review) }; review = nil; localReview = false }
            cover.setActive(phase == .active); localClear.setActive(phase == .active); timeRange.setActive(phase == .active); identityRegistration.setActive(phase == .active); templateSelection.setActive(phase == .active) }
        .onDisappear { identityRegistration.disappear(); localClear.retire(); if let review { service?.cancel(review) }; review = nil }
        .background { ActivityCoverLifetime(owner: cover).frame(width: 0, height: 0) }
        .background { ActivityPublishingSubmissionLifetime(owner: submission).frame(width: 0, height: 0) }
        .background { RetainedImagePresenterHost(host: cover.pickerHost).frame(width: 0, height: 0) }
        .background { ActivityPublishingTimeRangeLifetimeAnchor(owner: timeRange).frame(width: 0, height: 0) }
        .background { ActivityTemplateSelectionLifetimeAnchor(owner: templateSelection).frame(width: 0, height: 0) }
        .background {
            if let creation = templateSelection.creation, let makeActivityTemplate {
                ActivityTemplateCreationPresenter(owner: templateSelection, original: creation, content: makeActivityTemplate).id(creation.id)
            }
        }
        .task(id: templateReadID) { await templateSelection.read(templateReadID) }
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
                    let snapshot = review
                    Button("publishModes.confirm") { if let snapshot { Task { await submit(snapshot) } } }
                        .disabled(snapshot == nil || busy || service?.mutationsConfigured != true)
                    Button("publishModes.cancel", role: .cancel) {
                        guard review == snapshot else { return }
                        if let snapshot { service?.cancel(snapshot) }; review = nil; localReview = false
                    }
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
    @ViewBuilder private var submissionResult: some View {
        if let outcome = submission.outcome {
            Section {
                switch outcome {
                case .acknowledged:
                    Text("publishModes.acknowledged")
                    Text(verbatim: locale.language.languageCode?.identifier == "zh"
                        ? "请求已受理，发布状态仍需核实。请在我的项目查看服务端记录。"
                        : "Request acknowledged. Publication still needs verification in My projects.")
                case .unknown:
                    Text("publishModes.unknown")
                    Text(verbatim: locale.language.languageCode?.identifier == "zh"
                        ? "结果未知，原请求保持锁定。查看项目不会确认本次请求，也不会重新发送。"
                        : "The outcome is unknown and the original request stays locked. Viewing projects does not resolve or resend it.")
                case .notSent: Text("publishModes.notSent")
                case .rejected(let reason):
                    Text("publishModes.rejected")
                    if !reason.isEmpty { Text(verbatim: reason) }
                }
                if let account, let service, let openResource,
                   submission.canReadProjects, service.currentSession == account {
                    NavigationLink {
                        PublishingProjectsView(service: service, account: account, openResource: { resource in
                            guard service.currentSession == account else { return }; openResource(resource)
                        }, readOnly: true).id(account.epoch)
                    } label: { Text("publishModes.projects") }
                    .accessibilityIdentifier("publishModes.activity.result.projects")
                }
            }.accessibilityIdentifier("publishModes.activity.result")
        } else if submission.lockUnavailable {
            Text("publishModes.readFailed").accessibilityIdentifier("publishModes.activity.result.lockUnavailable")
        }
    }
    private func prepare() async {
        guard let operation = submission.begin(allowCovered: false) else { return }
        localClear.invalidate(); timeRange.retire()
        defer { submission.finish(operation) }
        do {
            _ = try draft.wire()
            let value: PublishingReview?
            if let service, let account { value = try await service.prepareActivity(draft, session: account) }
            else { value = nil }
            guard submission.isCurrent(operation) else { if let value { service?.cancel(value) }; return }
            review = value; localReview = true; message = ""
        } catch {
            guard submission.isCurrent(operation), let key = ActivityPublishingSubmissionOwner.preparationMessage(error) else { return }; message = key
        }
    }
    private func submit(_ snapshot: PublishingReview) async {
        guard let review, review == snapshot, let service, review.session == account,
              let operation = submission.begin(allowCovered: true, submitting: true) else { return }
        localReview = false
        let result = await service.submit(review)
        guard submission.receive(result, operation: operation) else { return }
        self.review = nil; message = ""
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

/// A view occurrence owns presentation only. The existing service and persistent journal
/// retain write approval, dispatch and uncertain-outcome authority.
@MainActor final class ActivityPublishingSubmissionOwner: ObservableObject {
    struct Context: Equatable {
        let account: PublishingSession?
        let draftID: UUID
        let draft: Data
        let serviceID: ObjectIdentifier?
    }
    struct Operation: Equatable { let visit: UUID; let id: UUID; let context: Context; let submitting: Bool }
    @Published private(set) var busy = false
    @Published private(set) var outcome: PublishingWriteOutcome?
    @Published private(set) var lockUnavailable = false
    private var context: Context?
    private var service: PublishingService?
    private var visit = UUID()
    private var operation: Operation?
    private var visible = false
    private var covered = false
    private var active = true
    private var current: Bool {
        active && (visible || covered) && context != nil &&
            (service == nil || service?.currentSession == context?.account)
    }
    var canReadProjects: Bool { current && visible && !busy && context?.account != nil && outcome != nil }
    func bind(account: PublishingSession?, draftID: UUID, draft: ActivityPublishDraft, service: PublishingService?) {
        guard let bytes = ProjectEditPendingMaterials.exactData(draft) else { retire(); context = nil; return }
        let next = Context(account: account, draftID: draftID, draft: bytes, serviceID: service.map(ObjectIdentifier.init))
        if context != next {
            let preserveUnknown = context?.account == account && (outcome == .unknown || operation?.submitting == true)
            retire(); context = next; self.service = service
            if preserveUnknown { outcome = .unknown }
            refreshLock()
        }
    }
    func appeared() { visible = true; covered = false; refreshLock() }
    func disappeared(departing: Bool, coveredByPresentation: Bool) {
        visible = false
        if !departing && coveredByPresentation && active { covered = true; return }
        covered = false; invalidateOperation()
    }
    func setActive(_ value: Bool) { active = value; if !value { invalidateOperation() } else { refreshLock() } }
    func retire() { invalidateOperation(); outcome = nil; lockUnavailable = false }
    private func invalidateOperation() {
        // An interrupted submission cannot become a fresh editable form just because
        // its presentation callback was retired. Never clear the service journal here.
        if operation?.submitting == true { outcome = .unknown }
        visit = UUID(); operation = nil; busy = false
    }
    private func refreshLock() {
        guard let account = context?.account, let service, service.currentSession == account else { return }
        do {
            let pending = try service.hasUncertainOutcome(targetKey: "publishModes:activity:create", session: account)
            lockUnavailable = false
            if pending { outcome = .unknown }
        } catch { lockUnavailable = true }
    }
    static func preparationMessage(_ error: Error) -> String? {
        if error is CancellationError { return nil }
        guard let failure = error as? PublishModesError else { return "publishModes.readFailed" }
        switch failure {
        case .invalidDraft: return "publishModes.invalid"
        case .changedSession: return nil
        case .forbidden: return "publishModes.clubOnly"
        case .staleReview, .conflict: return "publishModes.conflict"
        case .storage: return "publishModes.storageFailed"
        case .rejected: return "publishModes.rejected"
        case .invalidContract, .unavailable, .uncertain: return "publishModes.readFailed"
        }
    }
    func begin(allowCovered: Bool, submitting: Bool = false) -> Operation? {
        refreshLock()
        guard current, (visible || allowCovered), !busy, !lockUnavailable,
              outcome != .acknowledged, outcome != .unknown, let context else { return nil }
        let value = Operation(visit: visit, id: UUID(), context: context, submitting: submitting)
        operation = value; busy = true; outcome = nil; return value
    }
    func isCurrent(_ value: Operation) -> Bool {
        current && busy && operation == value && value.visit == visit && value.context == context
    }
    func finish(_ value: Operation) {
        guard isCurrent(value) else { return }; operation = nil; busy = false
    }
    @discardableResult func receive(_ result: PublishingWriteOutcome, operation value: Operation) -> Bool {
        guard isCurrent(value) else { return false }
        operation = nil; busy = false; outcome = result; return true
    }
}

/// Modal review coverage is distinct from leaving the creator navigation hierarchy.
@MainActor struct ActivityPublishingSubmissionLifetime: UIViewControllerRepresentable {
    let owner: ActivityPublishingSubmissionOwner
    func makeUIViewController(context: Context) -> ActivityPublishingSubmissionLifetimeController { .init(owner: owner) }
    func updateUIViewController(_ controller: ActivityPublishingSubmissionLifetimeController, context: Context) {}
    static func dismantleUIViewController(_ controller: ActivityPublishingSubmissionLifetimeController, coordinator: ()) {
        controller.owner?.disappeared(departing: true, coveredByPresentation: false)
    }
}
@MainActor final class ActivityPublishingSubmissionLifetimeController: UIViewController {
    weak var owner: ActivityPublishingSubmissionOwner?
    private var departing = false
    init(owner: ActivityPublishingSubmissionOwner) { self.owner = owner; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { return nil }
    private var ancestry: [UIViewController] {
        var result: [UIViewController] = [], next: UIViewController? = self
        while let value = next { result.append(value); next = value.parent }; return result
    }
    override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); departing = false; owner?.appeared() }
    override func viewWillDisappear(_ animated: Bool) { super.viewWillDisappear(animated); departing = ancestry.contains { $0.isMovingFromParent || $0.isBeingDismissed } }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        let source = ancestry
        owner?.disappeared(departing: departing || parent == nil || source.contains { $0.isMovingFromParent || $0.isBeingDismissed },
                           coveredByPresentation: source.contains { $0.presentedViewController != nil })
    }
}
