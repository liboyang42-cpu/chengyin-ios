import SwiftUI
import MapKit

/// Additive composition surface. Parent supplies professional-editor routing and the current
/// account epoch. No production mutation approval, map provider or token is created here.
@MainActor struct PublishingModesView: View {
    let service: PublishingService?
    let account: PublishingSession?
    var placeSearch: (any PublishingPlaceSearching)? = nil
    var draftStore: PublishingDraftStore? = nil
    var openProfessional: (ProjectEditDraft) -> Void
    var openResource: (PublishedResource) -> Void
    var body: some View {
        List {
            Section { Text("publishModes.offlineNotice").foregroundStyle(.secondary) }
            NavigationLink("publishModes.quick") { QuickPublishingView(placeSearch: placeSearch, account: account, draftStore: draftStore, openProfessional: openProfessional).id(account?.epoch) }
            NavigationLink("publishModes.activity") { ActivityPublishingView(service: service, account: account, placeSearch: placeSearch, draftStore: draftStore) }
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
    var openProfessional: (ProjectEditDraft) -> Void
    @State private var draft = QuickPublishDraft()
    @State private var selecting: UUID?
    @State private var problem = false
    @State private var draftID = UUID()
    @State private var storageMessage = ""
    var body: some View {
        Form {
            Section { Text("publishModes.aiNotice"); Text("publishModes.aiDisabled").foregroundStyle(.secondary) }
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
        .sheet(isPresented: Binding(get: { selecting != nil }, set: { if !$0 { selecting = nil } })) {
            PublishingPlacePicker(provider: placeSearch) { place in
                if let index = draft.nodes.firstIndex(where: { $0.id == selecting }) { draft.nodes[index].confirmedPlace = place }; selecting = nil
            }
        }
    }
}
@MainActor struct ActivityPublishingView: View {
    @Environment(\.locale) private var locale
    let service: PublishingService?
    let account: PublishingSession?
    var placeSearch: (any PublishingPlaceSearching)?
    var draftStore: PublishingDraftStore? = nil
    @State private var draftID = UUID()
    @State private var draft = ActivityPublishDraft()
    @State private var picker: String?
    @State private var review: PublishingReview?
    @State private var localReview = false
    @State private var busy = false
    @State private var message = ""
    @State private var acknowledged = false
    @State private var uncertain = false
    private var editable: Bool { !busy && !acknowledged && !uncertain }
    var body: some View {
        Form {
            Section { Text("publishModes.clubOnly"); Text("publishModes.offlineNotice").foregroundStyle(.secondary) }
            Section("publishModes.details") {
                TextField("publishModes.name", text: $draft.name)
                TextField("publishModes.description", text: $draft.description, axis: .vertical).lineLimit(3...8)
                TextField("publishModes.cover", text: $draft.coverURL).textInputAutocapitalization(.never).autocorrectionDisabled()
                Text("publishModes.uploadDisabled").font(.caption).foregroundStyle(.secondary)
                TextField("publishModes.addressName", text: $draft.addressName)
                Button("publishModes.choosePlace") { picker = "place" }
                if let place = draft.place { Text(place.name); Text(place.address).font(.caption) }
                TextField("publishModes.start", text: $draft.start).accessibilityIdentifier("publishModes.activity.start")
                TextField("publishModes.end", text: $draft.end)
                Text("publishModes.dateFormat").font(.caption)
                Button("publishModes.categories") { picker = "category" }; Text(draft.categoryIDs.map(String.init).joined(separator: ", "))
                Button("publishModes.template") { picker = "template" }; Text(draft.playTemplateID.map { String($0.rawValue) } ?? "—")
                Button("publishModes.collaborators") { picker = "collaborator" }; Text(draft.collaboratorMemberIDs.map(String.init).joined(separator: ", "))
            }.disabled(!editable)
            ForEach($draft.tickets) { $ticket in
                Section("publishModes.ticket") {
                    TextField("publishModes.name", text: $ticket.name)
                    TextField("publishModes.price", text: $ticket.price).keyboardType(.decimalPad)
                    TextField("publishModes.stock", text: $ticket.stock).keyboardType(.numberPad)
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
                    guard let account, let draftStore else { return }
                    do {
                        if let saved = try draftStore.loadActive(activity: true, session: account), let activity = saved.activity { draft = activity; draftID = saved.identity; message = "publishModes.restoredLocal" }
                        else { message = "publishModes.noSavedLocal" }
                    } catch { message = "publishModes.storageFailed" }
                }.disabled(!editable || account == nil || draftStore == nil)
            }
            Button("publishModes.addTicket") { draft.tickets.append(.init()) }.disabled(!editable)
            if !message.isEmpty { Text(LocalizedStringKey(message)).accessibilityIdentifier("publishModes.message") }
            Button("publishModes.review") { Task { await prepare() } }.disabled(!editable).accessibilityIdentifier("publishModes.activity.review")
        }.navigationTitle(Text("publishModes.activity"))
        .onChange(of: draft) { _, _ in if let review { service?.cancel(review) }; review = nil; localReview = false }
        .onChange(of: account) { _, _ in service?.invalidateReviews(); draft = .init(); draftID = UUID(); review = nil; localReview = false; acknowledged = false; uncertain = false; message = "" }
        .onDisappear { if let review { service?.cancel(review) }; review = nil }
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
