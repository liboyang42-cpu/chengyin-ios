import SwiftUI

@MainActor final class NearbyTeamScreenModel: ObservableObject {
    let coordinator: NearbyTeamCoordinator
    @Published private(set) var running = false
    init(_ coordinator: NearbyTeamCoordinator) { self.coordinator = coordinator }
    func run(_ work: () async -> Void) async { guard !running else { return }; running = true; await work(); running = false }
    func prepare(_ action: NearbyTeamAction) { coordinator.prepare(action); objectWillChange.send() }
    func cancel() { coordinator.cancelReview(); objectWillChange.send() }
    var review: Binding<NearbyTeamReview?> { .init(get: { self.coordinator.review }, set: { if $0 == nil { self.cancel() } }) }
}
/// Host supplies an account-scoped coordinator and optional manual map context. No device-location APIs.
@MainActor struct NearbyTeamsView: View {
    @StateObject private var model: NearbyTeamScreenModel
    @State private var latitude = ""
    @State private var longitude = ""
    @State private var radius = 3000
    @State private var tab = 0
    let initialContext: NearbyQueryContext?
    let joinedTeams: [OwnedTeam]
    let navigate: (NearbyTeamDestination) -> Void
    init(coordinator: NearbyTeamCoordinator, context: NearbyQueryContext? = nil, joinedTeams: [OwnedTeam] = [], navigate: @escaping (NearbyTeamDestination) -> Void = { _ in }) {
        _model = StateObject(wrappedValue: NearbyTeamScreenModel(coordinator)); initialContext = context; self.joinedTeams = joinedTeams; self.navigate = navigate
    }
    private var coordinator: NearbyTeamCoordinator { model.coordinator }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                notice
                Picker("nearby.section", selection: $tab) {
                    Text("nearby.title").tag(0); Text("nearby.mine").tag(1)
                }.pickerStyle(.segmented).accessibilityIdentifier("nearby.section")
                if tab == 0 {
                    contextControls
                    if model.running { ProgressView("nearby.loading") }
                    if !model.running && coordinator.teams.isEmpty {
                        ContentUnavailableView("nearby.empty", systemImage: "person.3", description: Text("nearby.empty.detail"))
                    }
                    LabeledContent("nearby.recruitingCount") { Text(verbatim: String(coordinator.teams.count)) }
                    ForEach(coordinator.teams) { team in teamCard(team) }
                    applicantSection
                } else { mineSection }
                Button("nearby.refresh") { Task { await refresh() } }.frame(minHeight: 44)
                    .disabled(model.running || !coordinator.authenticated).accessibilityIdentifier("nearby.refresh")
            }.padding()
        }.appNavigationTitle("nearby.title")
            .sheet(item: model.review) { review in NearbyTeamReviewView(model: model, snapshot: review) }
            .task {
                coordinator.resume()
                if let context = initialContext { latitude = String(context.latitude); longitude = String(context.longitude); radius = context.radius; await model.run { await coordinator.loadNearby(context) } }
            }
            .onChange(of: tab) { _, value in if value == 1 { Task { await model.run { await coordinator.loadMine() } } } }
            .onDisappear { coordinator.leave() }
    }
    private var notice: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(coordinator.synthetic ? "nearby.fixture" : coordinator.canSubmit ? "nearby.review.enabled" : "nearby.dormant", systemImage: coordinator.synthetic ? "testtube.2" : "lock.shield")
            Text("nearby.context.notice")
            if coordinator.uncertain { Label("nearby.unknown", systemImage: "exclamationmark.triangle") }
            if let key = coordinator.messageKey {
                Text(LocalizedStringKey(key)).accessibilityIdentifier("nearby.message")
            }
            if !coordinator.serverMessage.isEmpty { Text(verbatim: coordinator.serverMessage).accessibilityIdentifier("nearby.serverMessage") }
            if !coordinator.errorCode.isEmpty { Text(verbatim: coordinator.errorCode).font(.caption.monospaced()) }
        }.font(.footnote).fixedSize(horizontal: false, vertical: true).padding()
            .frame(maxWidth: .infinity, alignment: .leading).background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
    }
    private var contextControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("nearby.context.title").font(.headline)
            TextField("nearby.latitude", text: $latitude).textFieldStyle(.roundedBorder).accessibilityIdentifier("nearby.latitude")
            TextField("nearby.longitude", text: $longitude).textFieldStyle(.roundedBorder).accessibilityIdentifier("nearby.longitude")
            Picker("nearby.radius", selection: $radius) { ForEach(NearbyQueryContext.radii, id: \.self) { radius in Text(verbatim: "\(radius / 1000) km").tag(radius) } }
                .accessibilityIdentifier("nearby.radius")
            Button("nearby.search") { Task { await refresh() } }.frame(minHeight: 44).disabled(model.running).accessibilityIdentifier("nearby.search")
        }
    }
    private func refresh() async {
        if tab == 1 { await model.run { await coordinator.loadMine() }; return }
        guard let lat = Double(latitude), let lng = Double(longitude) else {
            await model.run { await coordinator.loadNearby(.init(latitude: .nan, longitude: .nan)) }; return
        }
        await model.run { await coordinator.loadNearby(.init(latitude: lat, longitude: lng, radius: radius)) }
    }
    private func teamCard(_ team: NearbyTeam) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if team.title.isEmpty { Text("nearby.untitled").font(.title2.bold()) } else { Text(verbatim: team.title).font(.title2.bold()) }
            if !team.activityName.isEmpty { Text(verbatim: team.activityName).font(.headline) }
            Label(LocalizedStringKey(team.viewerStatus.key), systemImage: team.viewerStatus == .pending ? "clock" : "person.3")
            Text(team.productType == 2 ? "nearby.freeExplore" : "nearby.urbanExplore").font(.caption)
            if !team.addressName.isEmpty {
                LabeledContent(team.coordSource == "GATHER" ? "nearby.gather" : "nearby.place") { Text(verbatim: team.addressName) }
            }
            if let distance = team.distance { LabeledContent("nearby.distance") { Text(verbatim: distance >= 1000 ? String(format: "%.1f km", distance / 1000) : String(format: "%.0f m", distance)) } }
            LabeledContent("nearby.leader") { if team.leaderName.isEmpty { Text("nearby.player") } else { Text(verbatim: team.leaderName) } }
            LabeledContent("nearby.members") { Text(verbatim: "\(team.joinedCount) / \(team.maxMembers)") }
            switch team.mode {
            case "leader":
                LabeledContent("nearby.applicants") { Text(verbatim: "\(team.pendingCount)") }
                Text("nearby.leader.foot").font(.footnote)
                Button("nearby.applicants") { Task { await model.run { await coordinator.loadApplicants(teamID: team.id) } } }.frame(minHeight: 44).disabled(model.running)
            case "joined": routeButton("nearby.enter", destination: .team(team.id))
            case "pending": expiry(team.applyExpireTime); actionButton(.withdraw(team.id))
            case "rejected": Text("nearby.rejected.foot").font(.footnote)
            case "apply": Text("nearby.apply.foot").font(.footnote); actionButton(.apply(team.id))
            case "buy":
                Text("nearby.ticket.foot").font(.footnote)
                if let destination = NearbyTeamBridge.purchaseDestination(team) { routeButton("nearby.buy", destination: destination) }
            default: Text("nearby.actionUnavailable").font(.footnote)
            }
        }.fixedSize(horizontal: false, vertical: true).padding().frame(maxWidth: .infinity, alignment: .leading)
            .background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 20))
            .accessibilityElement(children: .contain).accessibilityIdentifier("nearby.team.\(team.id.rawValue)")
    }
    @ViewBuilder private var applicantSection: some View {
        if let teamID = coordinator.applicantsTeamID {
            Text("nearby.applicants").font(.title2.bold()).accessibilityAddTraits(.isHeader)
            if coordinator.applicants.isEmpty { Text("nearby.applicants.empty") }
            ForEach(coordinator.applicants) { applicant in
                VStack(alignment: .leading, spacing: 10) {
                    if applicant.name.isEmpty { Text("nearby.player").font(.headline) } else { Text(verbatim: applicant.name).font(.headline) }
                    Label("nearby.applicant.ticket", systemImage: "ticket")
                    if let date = applicant.appliedAt?.date() { LabeledContent("nearby.appliedAt") { Text(date, style: .relative) } }
                    expiry(applicant.applyExpireTime)
                    if !applicant.message.isEmpty { Text(verbatim: "“\(applicant.message)”").fixedSize(horizontal: false, vertical: true) }
                    actionButton(.handle(team: teamID, applicant: applicant.id, approved: true))
                    actionButton(.handle(team: teamID, applicant: applicant.id, approved: false))
                }.padding().accessibilityIdentifier("nearby.applicant.\(applicant.id.rawValue)")
            }
        }
    }
    private var mineSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            if model.running { ProgressView("nearby.loading") }
            let rows = NearbyTeamBridge.myRows(joined: joinedTeams, applications: coordinator.myApplications)
            LabeledContent("nearby.activeCount") { Text(verbatim: String(NearbyTeamBridge.activeCount(rows))) }
            if rows.isEmpty && !model.running { Text("nearby.mine.empty") }
            ForEach(rows) { row in
                switch row {
                case .joined(let team):
                    Text(verbatim: team.title).font(.headline)
                    routeButton("nearby.enter", destination: .team(.init(team.id)))
                case .application(let application):
                    VStack(alignment: .leading, spacing: 10) {
                        if application.title.isEmpty { Text("nearby.untitled") } else { Text(verbatim: application.title).font(.headline) }
                        Text(LocalizedStringKey(application.status.key))
                        if !application.leaderName.isEmpty { LabeledContent("nearby.leader") { Text(verbatim: application.leaderName) } }
                        if application.status == .pending { expiry(application.applyExpireTime); actionButton(.withdraw(application.id)) }
                        else { Text("nearby.rejected.foot"); Button("nearby.lookNearby") { tab = 0 }.frame(minHeight: 44) }
                    }.accessibilityIdentifier("nearby.application.\(application.id.rawValue)")
                }
            }
        }
    }
    private func actionButton(_ action: NearbyTeamAction) -> some View {
        Button(LocalizedStringKey(action.key)) { model.prepare(action) }.frame(minHeight: 44)
            .disabled(model.running || !coordinator.allowed(action)).accessibilityIdentifier("nearby.\(action.operation).\(action.teamID.rawValue)")
    }
    private func routeButton(_ key: LocalizedStringKey, destination: NearbyTeamDestination) -> some View { Button(key) { navigate(destination) }.frame(minHeight: 44) }
    @ViewBuilder private func expiry(_ value: NearbyServerTime?) -> some View {
        if let minutes = value?.remainingMinutes(now: Date()) {
            LabeledContent("nearby.expiry") { Text(verbatim: "\(minutes < 60 ? minutes : minutes / 60)"); Text(minutes < 60 ? "nearby.minutes" : "nearby.hours") }
        } else { Text("nearby.expiry.rule").font(.footnote) }
    }
}
@MainActor private struct NearbyTeamReviewView: View {
    @ObservedObject var model: NearbyTeamScreenModel
    let snapshot: NearbyTeamReview
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(LocalizedStringKey(snapshot.action.key)).font(.title2.bold())
                    Text(verbatim: snapshot.team?.title ?? snapshot.application?.title ?? "").font(.headline)
                    LabeledContent("nearby.teamID") { Text(verbatim: String(snapshot.action.teamID.rawValue)) }
                    if let applicant = snapshot.applicant {
                        Text(verbatim: applicant.name)
                        LabeledContent("nearby.applicantID") { Text(verbatim: String(applicant.memberID.rawValue)) }
                    }
                    Text(model.coordinator.synthetic ? "nearby.review.consequence" : "nearby.review.liveConsequence").fixedSize(horizontal: false, vertical: true)
                    Text(model.coordinator.synthetic ? "nearby.fixture" : model.coordinator.canSubmit ? "nearby.review.enabled" : "nearby.dormant").font(.footnote)
                    Button(model.coordinator.synthetic ? "nearby.simulate" : "nearby.submitReviewed") { Task { await model.run { await model.coordinator.confirm(snapshot) } } }
                        .frame(minHeight: 44).disabled(model.running || !model.coordinator.canSubmit).accessibilityIdentifier("nearby.confirm")
                    Button("nearby.cancel", role: .cancel) { model.cancel() }.frame(minHeight: 44).accessibilityIdentifier("nearby.cancel")
                }.padding()
            }.navigationTitle("nearby.review")
        }
    }
}
