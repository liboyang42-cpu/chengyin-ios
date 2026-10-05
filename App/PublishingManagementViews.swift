import SwiftUI

@MainActor struct PublishingProjectsView: View {
    @Environment(\.locale) private var locale
    let service: PublishingService?
    let account: PublishingSession?
    var openResource: (PublishedResource) -> Void
    @State private var type = "all"
    @State private var state = "all"
    @State private var owner = "all"
    @State private var rows: [PublishingProject] = []
    @State private var total = 0
    @State private var unknown = 0
    @State private var busy = false
    @State private var failed = false
    @State private var review: PublishingReview?
    @State private var message = ""
    @State private var generation = 0
    private var query: PublishingRead { .projects(type: type, state: state, ownerType: owner, scope: "", pageSize: 200) }
    var body: some View {
        List {
            Section {
                Picker("publishModes.type", selection: $type) { ForEach(["all", "topic", "activity", "template"], id: \.self) { Text(LocalizedStringKey("publishModes.filter." + $0)).tag($0) } }
                Picker("publishModes.state", selection: $state) { ForEach(["all", "draft", "pending", "rejected", "running", "notStarted", "offline", "completed"], id: \.self) { Text(LocalizedStringKey("publishModes.filter." + $0)).tag($0) } }
                Picker("publishModes.owner", selection: $owner) { ForEach(["all", "member", "club", "merchant"], id: \.self) { Text(LocalizedStringKey("publishModes.filter." + $0)).tag($0) } }
            }.disabled(busy)
            if busy { ProgressView() }
            if failed { Text("publishModes.readFailed"); Button("publishModes.retry") { Task { await load() } } }
            if rows.isEmpty && !busy && !failed { Text("publishModes.empty") }
            if total > rows.count + unknown { Text("publishModes.truncated").foregroundStyle(.secondary) }
            if unknown > 0 { Text("publishModes.unknownTypes").foregroundStyle(.secondary) }
            ForEach(rows) { project in
                Section {
                    Button { openResource(project.resource) } label: { VStack(alignment: .leading) { Text(project.title); if let state = project.stateText { Text(state).font(.caption) } } }
                    if project.signupCount > 0 { Text("\(project.signupCount) " + appLocalized("publishModes.signups", locale: locale)) }
                    if project.canToggle { Button(LocalizedStringKey(project.online ? "publishModes.takeOffline" : "publishModes.putOnline")) { Task { await prepare(project, action: .toggle) } }.disabled(busy) }
                    if project.canDelete { Button("publishModes.remove", role: .destructive) { Task { await prepare(project, action: .remove) } }.disabled(busy) }
                    if project.canCancelWithRefund { Text("publishModes.refundHandoff").font(.caption).foregroundStyle(.secondary) }
                }
            }
            if !message.isEmpty { Text(message).accessibilityIdentifier("publishModes.management.message") }
        }.navigationTitle(Text("publishModes.projects"))
        .task { await load() }.refreshable { await load() }
        .onChange(of: type) { _, _ in Task { await load() } }
        .onChange(of: state) { _, _ in Task { await load() } }
        .onChange(of: owner) { _, _ in Task { await load() } }
        .onChange(of: account) { _, _ in generation += 1; service?.invalidateReviews(); review = nil; rows = []; total = 0; Task { await load() } }
        .onDisappear { generation += 1; if let review { service?.cancel(review) }; review = nil }
        .sheet(item: $review) { snapshot in
            NavigationStack {
                List {
                    Text(snapshot.baseline?.title ?? "")
                    Text(LocalizedStringKey(snapshot.action == .remove ? "publishModes.deleteReview" : "publishModes.statusReview"))
                    Text("publishModes.reviewNotice").foregroundStyle(.secondary)
                    Button("publishModes.confirm", role: snapshot.action == .remove ? .destructive : nil) { Task { await submit(snapshot) } }.disabled(service?.mutationsConfigured != true || busy)
                    Button("publishModes.cancel", role: .cancel) { service?.cancel(snapshot); review = nil }
                }.navigationTitle(Text("publishModes.review"))
            }
        }
    }
    private func load() async {
        generation += 1; let stamp = generation; if let review { service?.cancel(review) }; review = nil; busy = true; failed = false; rows = []
        guard let service, let account else { busy = false; failed = true; return }
        do { let page = try PublishingContracts.decodeProjects(await service.read(query, session: account)); guard stamp == generation else { return }; rows = page.rows; total = page.total; unknown = page.unknownRows.count; busy = false }
        catch { guard stamp == generation else { return }; busy = false; failed = true }
    }
    private func prepare(_ project: PublishingProject, action: PublishingProjectAction) async {
        guard let service, let account else { return }; let stamp = generation; busy = true
        do { let value = try await service.prepareProject(project, action: action, query: query, session: account); guard stamp == generation else { service.cancel(value); return }; review = value; busy = false }
        catch { guard stamp == generation else { return }; busy = false; message = appLocalized("publishModes.conflict", locale: locale) }
    }
    private func submit(_ snapshot: PublishingReview) async {
        guard let service else { return }; busy = true; review = nil
        let outcome = await service.submit(snapshot); guard service.currentSession == account else { busy = false; return }; busy = false
        switch outcome {
        case .acknowledged: message = appLocalized("publishModes.acknowledged", locale: locale); await load()
        case .rejected(let text): message = text.isEmpty ? appLocalized("publishModes.rejected", locale: locale) : text
        case .notSent: message = appLocalized("publishModes.notSent", locale: locale)
        case .unknown: message = appLocalized("publishModes.unknown", locale: locale)
        }
    }
}
@MainActor struct PublishingIdentityStatusView: View {
    let service: PublishingService?
    let account: PublishingSession?
    private enum Status { case unconfigured, loading, failed, registered, notRegistered }
    @State private var status: Status = .unconfigured
    var body: some View {
        List {
            if account?.region == .unitedStates { Text("publishModes.identityUSUnsupported") }
            else {
                switch status {
                case .unconfigured: Text("publishModes.offlineNotice")
                case .loading: ProgressView()
                case .failed: Text("publishModes.readFailed")
                case .registered:
                    Text("publishModes.registered")
                    Text("publishModes.identityChange").foregroundStyle(.secondary)
                case .notRegistered:
                    Text("publishModes.notRegistered")
                    Text("publishModes.identityHandoff").foregroundStyle(.secondary)
                }
                Text("publishModes.identityPrivacy").font(.caption)
            }
        }.navigationTitle(Text("publishModes.identity"))
        .task(id: account?.epoch) {
            status = .unconfigured
            guard let account, let service, account.region == .china else { return }
            status = .loading
            do {
                let registered = try await service.identityRegistered(session: account)
                guard !Task.isCancelled, service.currentSession == account else { return }
                status = registered ? .registered : .notRegistered
            } catch {
                guard !Task.isCancelled, service.currentSession == account else { return }
                status = .failed
            }
        }
    }
}
/// Embed in full-scope ProjectEdit forms only. Existing whitelist locks remain authoritative.
struct PublishingTopicRewardsForm: View {
    @Binding var rewards: PublishingTopicRewards
    var fullEdit: Bool
    var body: some View {
        Section("publishModes.rewards") {
            Toggle("publishModes.selfPlay", isOn: $rewards.selfPlay)
            if rewards.selfPlay {
                TextField("publishModes.price", text: $rewards.selfPlayPrice).keyboardType(.decimalPad)
                TextField("publishModes.quota", text: $rewards.selfPlayQuota).keyboardType(.numberPad)
            }
            TextField("publishModes.medalName", text: $rewards.medalName)
            TextField("publishModes.medalImage", text: $rewards.medalImage).textInputAutocapitalization(.never).autocorrectionDisabled()
            Text("publishModes.uploadDisabled").font(.caption)
            TextField("publishModes.coupon", value: $rewards.couponID, format: .number).keyboardType(.numberPad)
            Text("publishModes.couponNotice").font(.caption).foregroundStyle(.secondary)
        }.disabled(!fullEdit)
    }
}
