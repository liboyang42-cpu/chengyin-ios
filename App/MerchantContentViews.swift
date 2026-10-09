import SwiftUI

@MainActor struct MerchantContentHomeView: View {
    let service: any MerchantContentServing
    var topicID: Int? = nil
    private var routes: [MerchantContentQuery] {
        var routes: [MerchantContentQuery] = [.recruiting, .projects, .applications, .registrations(filter: 0), .city, .gameEntries]
        if let topicID, topicID > 0 { routes.insert(.chapters(topicID: topicID), at: 0) }
        return routes
    }
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                MerchantContentBoundary()
                ForEach(routes) { query in
                    NavigationLink {
                        MerchantContentDocumentView(service: service, query: query)
                    } label: {
                        QuestifyImageEntityCard(imageSource: nil, title: "", fallbackTitle: LocalizedStringKey("merchant.content." + query.key), fallbackSymbol: "map", minimumHeight: 180) {
                            Text("merchant.content.entryHint")
                        }
                    }.buttonStyle(.plain).accessibilityIdentifier("merchant.content.entry." + query.key)
                }
            }.padding()
        }.appNavigationTitle("merchant.content.title")
    }
}
@MainActor final class MerchantContentViewModel: ObservableObject {
    let coordinator: MerchantContentCoordinator
    @Published var revision = 0
    init(service: any MerchantContentServing, query: MerchantContentQuery) { coordinator = .init(service: service, query: query) }
    func load() async { revision += 1; await coordinator.load(); revision += 1 }
    func prepare(_ c: MerchantContentCommand) { coordinator.prepare(c); revision += 1 }
    func cancel() { coordinator.cancelReview(); revision += 1 }
    func confirm(_ r: MerchantContentReview) async { revision += 1; await coordinator.confirm(r); revision += 1 }
    func reconcile() async { revision += 1; await coordinator.reconcile(); revision += 1 }
    func retryStation() async { revision += 1; await coordinator.retryStation(); revision += 1 }
    func suspend() { coordinator.suspend(); revision += 1 }
    func invalidate() { coordinator.invalidate(); revision += 1 }
}
struct MerchantContentBoundary: View {
    var body: some View { Label("merchant.content.disabled", systemImage: "lock.shield").font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("merchant.content.boundary") }
}
@MainActor struct MerchantContentDocumentView: View {
    @Environment(\.merchantCouponManagementDestination) private var couponManagementDestination
    let service: any MerchantContentServing
    let query: MerchantContentQuery
    let focusedTopicID: Int?
    let focusedMerchantID: Int?
    @StateObject private var model: MerchantContentViewModel
    init(service: any MerchantContentServing, query: MerchantContentQuery, focusedTopicID: Int? = nil, focusedMerchantID: Int? = nil) { self.service = service; self.query = query; self.focusedTopicID = focusedTopicID; self.focusedMerchantID = focusedMerchantID; _model = StateObject(wrappedValue: .init(service: service, query: query)) }
    private var c: MerchantContentCoordinator { model.coordinator }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                MerchantContentBoundary()
                MerchantContentStatus(model: model)
                if c.isCurrent, let snapshot = c.snapshot {
                    if query == .recruiting, let focusedMerchantID, snapshot.access.merchantID != focusedMerchantID {
                        Text("merchantMarketing.stale").accessibilityIdentifier("merchant.insightNavigation.storeChanged")
                    } else { content(snapshot) }
                } else if c.busy { ProgressView("merchant.loading") }
            }.padding()
        }
        .appNavigationTitle(key: "merchant.content." + query.key)
        .task(id: service.scope) { await model.load() }
        .refreshable { await model.load() }
        // Clearing the source rows here would remove the pushed NavigationLink's owner.
        // Scope changes still invalidate via load(), and isCurrent rejects stale display data.
        .onDisappear { model.suspend() }
        .sheet(item: Binding(get: { c.isCurrent ? c.review : nil }, set: { if $0 == nil { model.cancel() } })) { MerchantContentReviewView(model: model, review: $0) }
    }
    @ViewBuilder private func content(_ s: MerchantContentSnapshot) -> some View {
        switch query {
        case .recruiting:
            // Source marketing-home, available only after fresh marketing:read access.
            if let couponManagementDestination {
                NavigationLink { couponManagementDestination() } label: { Label("couponManagement.title", systemImage: "ticket") }
                    .accessibilityIdentifier("couponManagement.marketing.entry")
            }
            let focus = MerchantInsightRecruitingFocus(rows: s.rows, topicID: focusedTopicID)
            if focus.unavailable { Text("merchant.insightNavigation.notLoaded").font(.footnote).accessibilityIdentifier("merchant.insightNavigation.notLoaded") }
            MerchantContentRows(service: service, model: model, rows: focus.rows, kind: .query(query), focusedTopicID: focus.matchedID)
        case .chapters(let topic): MerchantContentRecruitView(service: service, snapshot: s, topicID: topic)
        case .project(let topic): MerchantContentProjectView(service: service, model: model, value: s.value, topicID: topic)
        case .city:
            let quota = MerchantCityQuota(catalog: s.value)
            MerchantCityQuotaSummary(quota: quota, canRetry: !c.busy && !c.locked && c.review == nil) {
                Task {
                    guard c.isCurrent, !c.busy, !c.locked, c.review == nil,
                          c.snapshot == s, c.snapshot?.observedAt == s.observedAt else { return }
                    await model.load()
                }
            }
            NavigationLink("merchant.content.placement") { MerchantContentEditView(service: service, query: .cityPlacement, kind: .placement) }
                .disabled(!quota.canPlace || c.busy || c.locked)
                .accessibilityIdentifier("merchant.cityQuota.placement")
            NavigationLink("merchant.content.claimable") { MerchantContentClaimSearch(service: service) }
            MerchantContentRows(service: service, model: model, rows: s.value["nodes"].array ?? [], kind: .city)
            Text("merchant.content.cityApplications").font(.headline)
            MerchantContentRows(service: service, model: model, rows: s.value["applications"].array ?? [], kind: .cityApplication)
        case .registration(let id):
            MerchantContentFields(value: s.value, names: ["topicName", "nodeName", "chapterName", "status", "auditStatus", "reason", "addressName", "address", "activityDesc", "limitNum", "startDate", "endDate"])
            if [0, 2].contains(s.value["status"].integer ?? -1), s.value["auditStatus"].integer != 1 {
                NavigationLink("merchant.content.edit") { MerchantContentEditView(service: service, query: query, kind: .registrationEdit(id)) }.accessibilityIdentifier("merchant.content.edit")
            }
            if [0, 1, 2].contains(s.value["status"].integer ?? -1), s.value["auditStatus"].integer.map({ $0 != 1 }) == true { Button("merchant.content.cancelRegistration", role: .destructive) { model.prepare(.cancelRegistration(id: id)) } }
        case .players:
            if let hint = s.value["contactHint"].text { Text(verbatim: hint).font(.footnote).accessibilityIdentifier("merchant.content.contactHint") }
            MerchantContentFields(value: s.value["summary"], names: ["paidCount", "arrivedCount", "pendingCount", "refundedCount"])
            MerchantContentRows(service: service, model: model, rows: s.rows, kind: .player)
        case .npc(let node):
            if s.value == .null { Text("merchant.content.npcUnconfigured") }
            MerchantContentFields(value: s.value, names: ["name", "avatar", "greeting", "voiceStatus"])
            NavigationLink("merchant.content.saveNPC") { MerchantContentEditView(service: service, query: query, kind: .npc(node)) }
            NavigationLink("merchant.content.voice") { MerchantContentDocumentView(service: service, query: .voice(nodeID: node)) }
            NavigationLink("merchant.content.enrollVoice") { MerchantContentEditView(service: service, query: .npc(nodeID: node), kind: .voice(node)) }
            Text("merchant.content.voiceBoundary").font(.footnote).foregroundStyle(.secondary)
        case .voice: MerchantContentFields(value: s.value, names: ["voiceStatus", "voiceSample"])
        case .game: MerchantContentStationView(service: service, snapshot: s)
        case .poster, .liveCode: MerchantContentCodeView(snapshot: s)
        case .cityPlacement, .nodeAuthoring: EmptyView()
        default:
            if case .registrations = query { MerchantContentRegistrationFilters(service: service) }
            MerchantContentRows(service: service, model: model, rows: s.rows, kind: .query(query))
            if let total = s.value["total"].integer, total > s.rows.count { Text("merchant.content.firstPageOnly").font(.footnote) }
        }
    }
}
@MainActor struct MerchantContentStatus: View {
    @ObservedObject var model: MerchantContentViewModel
    @State private var confirmsRetry = false
    var allowsReload = true
    var body: some View {
        let c = model.coordinator
        if c.loadedScope == c.service.scope {
            if let message = c.serverMessage { Text(verbatim: message).accessibilityIdentifier("merchant.content.serverMessage") }
            if let issue = c.issue { Text(LocalizedStringKey(issue)).font(.footnote).accessibilityIdentifier("merchant.content.issue") }
            if c.locked {
                Button("merchant.content.reconcile") { Task { await model.reconcile() } }.disabled(c.busy)
                Button("merchant.content.retryOriginal") { confirmsRetry = true }.disabled(c.busy || !c.service.permitsWrites)
                    .confirmationDialog("merchant.content.retryOriginalWarning", isPresented: $confirmsRetry, titleVisibility: .visible) {
                        Button("merchant.content.retryOriginal") { Task { await model.retryStation() } }
                        Button("action.cancel", role: .cancel) { }
                    }
            }
        }
        if !c.busy && allowsReload { Button("action.retry") { Task { await model.load() } }.accessibilityIdentifier("merchant.content.reload") }
    }
}
struct MerchantContentFields: View {
    let value: MerchantContentValue
    let names: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(names, id: \.self) { name in
                if let text = value[name].display, !text.isEmpty {
                    LabeledContent(LocalizedStringKey("merchant.content.field." + name)) { Text(verbatim: text).textSelection(.enabled) }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(Text(LocalizedStringKey("merchant.content.field." + name)))
                        .accessibilityValue(Text(verbatim: text))
                        .accessibilityIdentifier("merchant.content.readField." + name)
                }
            }
        }.font(.subheadline)
    }
}
@MainActor private struct MerchantContentRegistrationFilters: View {
    let service: any MerchantContentServing
    var body: some View {
        Menu("merchant.content.filter") {
            ForEach(0..<5) { filter in NavigationLink { MerchantContentDocumentView(service: service, query: .registrations(filter: filter)) } label: { Text(LocalizedStringKey("merchant.content.filter." + String(filter))) } }
        }
    }
}
@MainActor private struct MerchantContentClaimSearch: View {
    let service: any MerchantContentServing
    @State private var keyword = ""
    var body: some View {
        Form {
            TextField("merchant.content.search", text: $keyword)
            NavigationLink("merchant.content.search") { MerchantContentDocumentView(service: service, query: .claimable(keyword: keyword)) }
        }.appNavigationTitle("merchant.content.claimable")
    }
}
@MainActor struct MerchantContentRows: View {
    enum Kind { case query(MerchantContentQuery), city, cityApplication, player }
    let service: any MerchantContentServing
    @ObservedObject var model: MerchantContentViewModel
    let rows: [MerchantContentValue]
    let kind: Kind
    var focusedTopicID: Int? = nil
    private var rowNamespace: String {
        switch kind { case .city: return "city"; case .cityApplication: return "cityApplication"; case .player: return "player"; case .query(let query): return query.key }
    }
    var body: some View {
        // Keep each row collection in its own concrete identity scope. City nodes and
        // city applications otherwise flatten two offset-zero rows into one lazy parent.
        VStack(alignment: .leading, spacing: 18) {
            if rows.isEmpty { ContentUnavailableView("merchant.content.empty", systemImage: "tray") }
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                VStack(alignment: .leading, spacing: 12) {
                    if case .query(.recruiting) = kind, let focusedTopicID, row["id"].integer == focusedTopicID {
                        Label("merchant.insightNavigation.located", systemImage: "scope")
                            .accessibilityIdentifier("merchant.insightNavigation.located." + String(focusedTopicID))
                    }
                    Text(verbatim: row["merchantName"].text ?? row["name"].text ?? row["title"].text ?? row["topicName"].text ?? row["activityName"].text ?? row["poiName"].text ?? "—").font(.headline)
                    MerchantContentFields(value: row, names: fields)
                    actions(row)
                }.padding().frame(maxWidth: .infinity, alignment: .leading)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("merchant.content.row." + rowNamespace + "." + String(index))
            }
        }.id(rowNamespace)
    }
    private var fields: [String] {
        switch kind {
        case .player: return ["ticketName", "state", "phone"]
        case .city: return ["address", "status", "templateTitle"]
        case .cityApplication: return ["auditStatus", "status", "auditReason", "rejectReason", "applicationType"]
        case .query(let query):
            switch query { case .recruiting: return ["merchantSignUpEndDate"]
            case .upcoming: return ["startTime", "clubName", "paidCount", "teamStatus", "arrivalStart", "arrivalEnd"]
            case .applications, .ownerApplications: return ["chapterName", "status", "source", "message", "auditRemark", "circleSupplyCheckedAt"]
            case .pendingNodes, .chapterNodes: return ["address", "nodeAuditStatus", "nodeAuditReason"]
            default: return ["chapterName", "stateText", "status", "reason", "address", "startAt", "endAt", "stationCount"] }
        }
    }
    @ViewBuilder private func actions(_ row: MerchantContentValue) -> some View {
        switch kind {
        case .player: EmptyView()
        case .city:
            if let id = row["poiId"].integer ?? row["id"].integer, id > 0 {
                if let status = row["status"].integer, [0, 1].contains(status) { Button { model.prepare(.cityStatus(poiID: id, online: status != 1)) } label: { Text(LocalizedStringKey(status == 1 ? "merchant.content.offline" : "merchant.content.online")) } }
            }
        case .cityApplication:
            if let snapshot = model.coordinator.snapshot,
               let target = MerchantCityClaimWithdrawal(row: row, snapshot: snapshot) {
                Button("merchant.content.cancelClaim") {
                    guard model.coordinator.isCurrent, model.coordinator.snapshot == snapshot,
                          model.coordinator.snapshot?.observedAt == snapshot.observedAt else { return }
                    model.prepare(.cancelClaim(poiID: target.poiID))
                }.disabled(model.coordinator.busy || model.coordinator.locked || model.coordinator.review != nil)
                    .accessibilityIdentifier("merchant.cityClaim.withdraw." + String(target.poiID))
            } else if row["applicationType"].integer == 2, row["auditStatus"].integer == 0 {
                Text("merchant.cityClaim.unavailable").font(.footnote).accessibilityIdentifier("merchant.content.claimIDMissing")
            }
        case .query(let query): queryActions(row, query: query)
        }
    }
    @ViewBuilder private func queryActions(_ row: MerchantContentValue, query: MerchantContentQuery) -> some View {
        switch query {
        case .recruiting: if let id = row["id"].integer, id > 0 { link(.chapters(topicID: id), key: "chapters") }
        case .projects:
            if row["bizType"].text == "topic", let id = row["id"].integer, id > 0 { link(.project(topicID: id), key: "project") }
        case .applications:
            if let topic = row["topicId"].integer, topic > 0 { link(.chapters(topicID: topic), key: "chapters") }
            if let id = row["id"].integer, row["status"].integer == 0, row["source"].integer == 0 { Button("merchant.content.withdraw") { model.prepare(.withdraw(applicationID: id)) }.accessibilityIdentifier("merchant.content.withdraw") }
            if let chapter = row["chapterId"].integer, [0, 1].contains(row["status"].integer ?? -1) {
                NavigationLink("merchant.content.submitNode") { MerchantContentEditView(service: service, query: .nodeAuthoring(chapterID: chapter), kind: .chapterNode(chapter)) }
                Text("merchant.content.supplyBoundary").font(.footnote)
            }
        case .registrations: if let id = row["id"].integer, id > 0 { link(.registration(id: id), key: "registration") }
        case .chapterNodes:
            if let id = row["id"].integer, id > 0 { link(.npc(nodeID: id), key: "npc"); if row["nodeAuditStatus"].integer == 1 { link(.poster(nodeID: id), key: "poster") } }
        case .ownerApplications:
            if let id = row["id"].integer, row["status"].integer == 0 {
                NavigationLink("merchant.content.auditApplication") { MerchantContentEditView(service: service, query: query, kind: .auditApplication(id)) }
            }
        case .pendingNodes:
            if let id = row["id"].integer, id > 0 { NavigationLink("merchant.content.auditNode") { MerchantContentEditView(service: service, query: query, kind: .auditNode(id)) } }
        case .invitable:
            if let chapter = row["chapterId"].integer, let member = row["memberId"].integer, chapter > 0, member > 0 {
                Button("merchant.content.invite") { model.prepare(.invite(chapterID: chapter, merchantMemberID: member)) }
                Text("merchant.content.inviteWarning").font(.footnote)
            }
        case .claimable:
            if let poi = row["poiId"].integer ?? row["id"].integer, poi > 0 { Button("merchant.content.claim") { model.prepare(.claim(poiID: poi)) } }
        case .gameEntries: if let id = row["activityId"].integer, id > 0 { link(.game(activityID: id), key: "game") }
        default: EmptyView()
        }
    }
    private func link(_ query: MerchantContentQuery, key: String) -> some View {
        NavigationLink { MerchantContentDocumentView(service: service, query: query) } label: { Text(LocalizedStringKey("merchant.content." + key)) }.accessibilityIdentifier("merchant.content.open." + key)
    }
}

@MainActor struct MerchantContentRecruitView: View {
    let service: any MerchantContentServing
    let snapshot: MerchantContentSnapshot
    let topicID: Int
    var body: some View {
        Text(verbatim: snapshot.value["topic"]["name"].text ?? "—").font(.title2)
        if let message = snapshot.value["message"].text { Text(verbatim: message) }
        if snapshot.value["mode"].text == "chapters" {
            let rows = snapshot.value["chapters"].array ?? []
            if rows.isEmpty { Text("merchant.content.noChapters") }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                VStack(alignment: .leading, spacing: 12) {
                    Text(verbatim: row["name"].text ?? "—").font(.headline)
                    MerchantContentFields(value: row, names: ["description", "category", "required"])
                    MerchantContentFields(value: row["recruitStatus"], names: ["termsMode", "perkMinValue", "allowedValidationMethods", "maxNodeXp", "maxMerchant", "remainingMerchantCount", "state"])
                    if row["recruitStatus"]["remainingMerchantCount"] == .null { Text("merchant.content.unlimitedSlots").font(.footnote) }
                    if let id = row["id"].integer, id > 0 { NavigationLink("merchant.content.apply") { MerchantContentEditView(service: service, query: snapshot.query, kind: .apply(id)) }.accessibilityIdentifier("merchant.content.apply") }
                }.padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            }
        } else if snapshot.value["mode"].text == "registration" {
            if snapshot.value["registered"].flag == true { Text("merchant.content.alreadyRegistered") }
            else {
                if snapshot.value["registered"].flag == nil { Text("merchant.content.registrationUnknown") }
                let nodes = (snapshot.value["topic"]["chaptersList"].array ?? []).flatMap { $0["nodes"].array ?? [] }
                ForEach(Array(nodes.enumerated()), id: \.offset) { _, node in
                    if let id = node["id"].integer, id > 0 {
                        NavigationLink { MerchantContentEditView(service: service, query: snapshot.query, kind: .registrationCreate(topicID: topicID, nodeID: id)) } label: {
                            VStack(alignment: .leading) { Text(verbatim: node["name"].text ?? "—"); Text("merchant.content.register").font(.caption) }
                        }
                    }
                }
            }
        }
        if snapshot.value["mode"].text == "chapters" { MerchantContentRecruitSupplyView(service: service, topicID: topicID, chapters: snapshot.value["chapters"].array ?? []) }
        NavigationLink("merchant.content.applications") { MerchantContentDocumentView(service: service, query: .applications) }
        NavigationLink("merchant.content.nodes") { MerchantContentDocumentView(service: service, query: .chapterNodes(topicID: topicID)) }
        NavigationLink("merchant.content.upcoming") { MerchantContentDocumentView(service: service, query: .upcoming(topicID: topicID)) }
    }
}
@MainActor struct MerchantContentProjectView: View {
    let service: any MerchantContentServing
    @ObservedObject var model: MerchantContentViewModel
    let value: MerchantContentValue
    let topicID: Int?
    var body: some View {
        MerchantContentFields(value: value["topic"], names: ["name", "title", "city"])
        // Host and participant are independent source projections; both can be present.
        if value["host"].object != nil {
            Text("merchant.content.hosting").font(.headline)
            MerchantContentFields(value: value["host"]["recruit"], names: ["nodeFilled", "nodeTotal", "pendingCount"])
            NavigationLink("merchant.content.players") { MerchantContentDocumentView(service: service, query: .players(topicID: topicID)) }
            if let topicID {
                NavigationLink("merchant.content.reviews") { MerchantContentDocumentView(service: service, query: .ownerApplications(topicID: topicID)) }
                NavigationLink("merchant.content.nodeReviews") { MerchantContentDocumentView(service: service, query: .pendingNodes(topicID: topicID)) }
                NavigationLink("merchant.content.invitable") { MerchantContentDocumentView(service: service, query: .invitable(topicID: topicID)) }
                if !(value["topic"]["circleThemeCode"].text ?? "").isEmpty {
                    MerchantContentFields(value: value["topic"], names: ["circleReviewedAt"])
                    Button("merchant.content.reviewCircle") { model.prepare(.reviewCircle(topicID: topicID, scope: "MERCHANT")) }
                    Text("merchant.content.circleRules").font(.footnote)
                }
            }
        }
        if value["join"].object != nil {
            Text("merchant.content.joining").font(.headline)
            MerchantContentFields(value: value["join"]["registration"], names: ["addressName", "status", "auditStatus"])
            NavigationLink("merchant.content.registrations") { MerchantContentDocumentView(service: service, query: .registrations(filter: 0)) }
        }
        if value["host"].object == nil && value["join"].object == nil { Text("merchant.content.noWorkspace") }
    }
}
@MainActor struct MerchantContentStationView: View {
    let service: any MerchantContentServing
    let snapshot: MerchantContentSnapshot
    var body: some View {
        if let projection = try? MerchantStationProjection(snapshot.value) {
            MerchantContentFields(value: snapshot.value, names: ["status", "revision"])
            ForEach(Array(projection.stations.enumerated()), id: \.offset) { _, station in
                if let node = station["nodeId"].safeInteger {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(verbatim: station["nodeName"].text ?? "—").font(.headline)
                        MerchantContentFields(value: station, names: ["stationCode", "status", "merchantInstruction", "hiddenInfoReminder", "capacity", "serviceStartAt", "serviceEndAt", "pendingVerificationCount"])
                        if let prompt = station["playerTask"]["prompt"].text { Text(verbatim: prompt) }
                        ForEach(MerchantStationAction.allCases) { action in
                            if projection.allows(action, nodeID: node) {
                                NavigationLink { MerchantContentEditView(service: service, query: snapshot.query, kind: .station(nodeID: node, action: action)) } label: { Text(LocalizedStringKey("merchant.content." + action.rawValue)) }.accessibilityIdentifier("merchant.content." + action.rawValue)
                            }
                        }
                        if projection.allowsLiveCode(nodeID: node) {
                            NavigationLink("merchant.content.liveCode") { MerchantContentDocumentView(service: service, query: .liveCode(activityID: projection.activityID, nodeID: node)) }
                        }
                        if station["recap"]["contentPolicy"].text == "NO_PUBLIC_CONTENT" {
                            MerchantContentFields(value: station["recap"], names: ["arrivedPlayers", "submissionCount", "approvedCount", "rejectedCount", "recordedCount", "normalCompletedCount", "fallbackCompletedCount", "pauseEventCount"])
                        }
                    }.padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                }
            }
        }
    }
}
struct MerchantContentCodeView: View {
    let snapshot: MerchantContentSnapshot
        var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let ttl = snapshot.value["ttlMs"].integer
            let expired = ttl.map { context.date.timeIntervalSince(snapshot.observedAt) * 1000 >= Double($0) } ?? false
            if expired { Text("merchant.content.codeExpired").accessibilityIdentifier("merchant.content.codeExpired") }
            else {
                MerchantContentFields(value: snapshot.value, names: ["nodeName", "code"])
                Text(LocalizedStringKey(snapshot.query.key == "liveCode" ? "merchant.content.liveCodeWarning" : "merchant.content.posterWarning")).font(.footnote)
            }
        }
    }
}
@MainActor struct MerchantContentReviewView: View {
    @ObservedObject var model: MerchantContentViewModel
    let review: MerchantContentReview
    @Environment(\.dismiss) private var dismiss
    private var bodyText: String {
        guard let request = try? review.command.request() else { return "" }
        let value: MerchantContentValue
        switch request.body { case .json(let f): value = .object(f); case .form(let f): value = .object(f.mapValues { .string($0) }) }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(value)).map { String(decoding: $0, as: UTF8.self) } ?? ""
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    MerchantContentBoundary()
                    Text(LocalizedStringKey("merchant.content." + review.command.key)).font(.title2)
                    Text("merchant.content.immutableReview").font(.footnote)
                    LabeledContent("merchant.content.field.merchantID", value: String(review.baseline.access.merchantID ?? 0))
                    Text(verbatim: review.command.scopeKey).font(.caption)
                    Text(verbatim: bodyText).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                    if case .cancelClaim(let poiID) = review.command,
                       let target = MerchantCityClaimWithdrawal(poiID: poiID, snapshot: review.baseline) {
                        if let name = target.name, !name.isEmpty { Text(verbatim: name).font(.headline) }
                        Text("merchant.cityClaim.withdrawConsequence")
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("merchant.cityClaim.reviewNotice")
                    }
                    if case .station(let command) = review.command, command.pausesWithoutFallback {
                        Label("merchant.stationPause.reviewTitle", systemImage: "exclamationmark.triangle")
                            .font(.headline)
                        Text("merchant.stationPause.noFallbackConsequence")
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("merchant.stationPause.reviewNotice")
                    }
                    Text("merchant.content.reviewWarning").font(.footnote)
                    Button("merchant.content.confirm") { Task { await model.confirm(review); dismiss() } }
                        .buttonStyle(.borderedProminent).disabled(model.coordinator.busy || !model.coordinator.service.permitsWrites)
                        .accessibilityIdentifier("merchant.content.confirm")
                    Button("action.cancel") { model.cancel(); dismiss() }.accessibilityIdentifier("merchant.content.review.cancel")
                }.padding()
            }.appNavigationTitle("merchant.content.review")
        }.interactiveDismissDisabled(model.coordinator.busy)
    }
}

private struct MerchantContentSupplyDestinationKey: EnvironmentKey {
    static let defaultValue: (@MainActor (MerchantContentSupplyContext) -> AnyView)? = nil
}
extension EnvironmentValues {
    /// Integrator supplies Cooperation's own view; this module never submits a supply mutation.
    var merchantContentSupplyDestination: (@MainActor (MerchantContentSupplyContext) -> AnyView)? {
        get { self[MerchantContentSupplyDestinationKey.self] }
        set { self[MerchantContentSupplyDestinationKey.self] = newValue }
    }
}
@MainActor private struct MerchantContentRecruitSupplyView: View {
    let service: any MerchantContentServing
    let topicID: Int
    let chapters: [MerchantContentValue]
    @Environment(\.merchantContentSupplyDestination) private var destination
    @State private var snapshot: MerchantContentSnapshot?
    @State private var error = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("merchant.content.actualSupply").font(.headline)
            if let snapshot, snapshot.scope == service.scope {
                ForEach(Array(snapshot.rows.filter { $0["topicId"].integer == topicID }.enumerated()), id: \.offset) { _, row in
                    if let context = try? MerchantContentSupplyContext(application: row, recruitmentChapters: chapters) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(verbatim: row["chapterName"].text ?? "—")
                            Text(LocalizedStringKey(!context.offerStateKnown ? "merchant.content.supplyUnknown" : context.offerActive ? "merchant.content.supplyActive" : "merchant.content.supplyInactive"))
                            if let id = context.offerID { LabeledContent("merchant.content.field.offerId", value: String(id)) }
                            if let term = context.termsMode { LabeledContent("merchant.content.field.termsMode", value: term) }
                            if (context.canEnroll || context.canReconfirmOrPause), let destination {
                                NavigationLink { destination(context) } label: { Text("merchant.content.manageSupply") }
                            } else if !context.offerActive && context.termsMode == nil { Text("merchant.content.supplyTermsUnknown").font(.footnote) }
                        }
                    }
                }
            } else if error { Text("merchant.content.supplyLoadFailed").font(.footnote) }
            else { ProgressView("merchant.loading") }
            Text("merchant.content.supplyBoundary").font(.footnote)
        }.task(id: service.scope) {
            let captured = service.scope; snapshot = nil; error = false
            do { let result = try await service.load(.applications); guard !Task.isCancelled, captured == service.scope else { return }; snapshot = result }
            catch { if !Task.isCancelled, captured == service.scope { self.error = true } }
        }
    }
}
