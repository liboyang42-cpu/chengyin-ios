import SwiftUI

/// A readback ticket grants no write authority and survives only its detail visit.
struct OfficialDetailReturnLease {
    let eventID: Int
    let scope: UUID
    let visit: UUID
    func permits(eventID currentEventID: Int, scope currentScope: UUID, visit currentVisit: UUID,
                 visible: Bool, active: Bool) -> Bool {
        eventID == currentEventID && scope == currentScope && visit == currentVisit && visible && active
    }
}

/// `official.detail.*` leaf identifiers. Composed from the catalog-backed prefix so the
/// static localization scan never mistakes an identifier for user-facing copy.
enum OfficialDetailID {
    static let organizer = leaf("organizer"), facts = leaf("facts"), overview = leaf("overview")
    static let story = leaf("story"), cards = leaf("cards"), tasks = leaf("tasks"), rewards = leaf("rewards")
    static let collective = leaf("collective"), rewardFootnote = leaf("rewardFootnote"), cta = leaf("cta")
    static let unavailable = leaf("unavailable"), backToList = leaf("backToList"), network = leaf("network")
    static let service = leaf("service"), topicNameError = leaf("topicNameError"), ctaTopic = leaf("ctaTopic")
    private static func leaf(_ name: String) -> String { "official.detail" + "." + name }
}

@MainActor struct OfficialEventDetailView: View {
    let id: Int
    let reader: any OfficialEventReading
    var actions: OfficialActionCoordinator? = nil
    var onLogin: (() -> Void)? = nil
    /// Optional bound-topic names and route; without it THEME missions stay plain rows.
    var topicLinks: OfficialTopicLinks? = nil
    @State private var topicNames: [Int: String] = [:]
    @State private var topicNameFailed = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @State private var visit = UUID()
    @State private var readback = UUID()
    @State private var visible = false
    /// Source official-detail: a missing event exits to the list; a network failure keeps retry.
    nonisolated static func issueCopy(_ error: Error) -> OfficialIssueCopy? {
        switch OfficialDetailLoadFailure(error) {
        case .unavailable:
            return OfficialIssueCopy(title: "official.detailParity.unavailable.title", detail: "official.detailParity.unavailable.detail",
                                     identifier: OfficialDetailID.unavailable, backTitle: "official.detailParity.unavailable.back",
                                     backIdentifier: OfficialDetailID.backToList)
        case .network:
            return OfficialIssueCopy(title: "official.detailParity.network.title", detail: "official.detailParity.network.detail",
                                     identifier: OfficialDetailID.network)
        case .other:
            guard OfficialDetailServiceFailure.matches(error) else { return nil }
            return OfficialIssueCopy(title: "official.w206.detail.service.title", detail: "official.w206.detail.service.detail",
                                     identifier: OfficialDetailID.service)
        }
    }
    var body: some View {
        OfficialReadScreen(reader: reader, requestID: "event.\(id).\(readback)", onLogin: onLogin,
                           issueCopy: OfficialEventDetailView.issueCopy, onBack: { dismiss() },
                           load: { try await reader.detail(id: id) }) { event in
            let presentation = OfficialEventDetailPresentation(event: event, now: Date())
            List {
                OfficialEventCard(event: event).questifyCardListRow()
                HStack(spacing: 8) {
                    Text(LocalizedStringKey(presentation.categoryKey)).font(.caption.weight(.semibold)).foregroundStyle(.tint)
                    Text("official.detailParity.organizer").font(.subheadline).foregroundStyle(.secondary)
                }.accessibilityElement(children: .combine).accessibilityIdentifier(OfficialDetailID.organizer)
                Section("official.facts") {
                    OfficialDetailFactsStrip(facts: presentation.facts).accessibilityIdentifier(OfficialDetailID.facts)
                    LabeledContent("official.price") { Text("official.priceNotProvided") }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text("official.price"))
                        .accessibilityValue(Text("official.priceNotProvided"))
                        .accessibilityIdentifier("official.price")
                }
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(verbatim: event.title).font(.title3.weight(.semibold))
                        if let intro = presentation.intro { Text(verbatim: intro).textSelection(.enabled) }
                    }.fixedSize(horizontal: false, vertical: true).accessibilityIdentifier(OfficialDetailID.overview)
                }
                if let story = presentation.storyDetail {
                    Section("official.detailParity.storyHeading") {
                        Text(verbatim: story).textSelection(.enabled).accessibilityIdentifier(OfficialDetailID.story)
                    }
                }
                if !presentation.cards.isEmpty {
                    Section("official.detailParity.cardsHeading") {
                        ForEach(presentation.cards, id: \.index) { card in
                            VStack(alignment: .leading, spacing: 4) {
                                OfficialDetailTextView(value: card.title).font(.headline)
                                OfficialDetailTextView(value: card.description).foregroundStyle(.secondary)
                            }.accessibilityElement(children: .combine)
                        }
                    }.accessibilityIdentifier(OfficialDetailID.cards)
                }
                if event.isV2 {
                    Section {
                        if event.signed != true {
                            Text("official.detailParity.tasks.signupNote").font(.footnote).foregroundStyle(.secondary)
                        }
                        if event.paused {
                            if let reason = presentation.pausedReason { Text("official.detailParity.tasks.paused \(reason)").foregroundStyle(.red) }
                            else { Text("official.detailParity.tasks.pausedDefault").foregroundStyle(.red) }
                        }
                        if presentation.missions.isEmpty { Text("official.detailParity.tasks.empty") }
                        if topicNameFailed {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("official.w206.detail.topicName.failed").font(.subheadline)
                                Text("official.w206.detail.topicName.stillOpen").font(.footnote).foregroundStyle(.secondary)
                            }.accessibilityElement(children: .combine).accessibilityIdentifier(OfficialDetailID.topicNameError)
                        }
                        ForEach(presentation.missions, id: \.index) { mission in
                            let topicID = mission.binding?.themeTopicID
                            let linked = event.missions.indices.contains(mission.index)
                                ? OfficialDetailTopicLinks.linkedTopic(event.missions[mission.index], signed: event.signed == true) : nil
                            if let topicLinks, let linked {
                                NavigationLink { topicLinks.destination(linked) } label: {
                                    OfficialDetailMissionRow(mission: mission, topicName: topicID.flatMap { topicNames[$0] })
                                }.accessibilityIdentifier("official.mission.\(mission.index)")
                            } else {
                                OfficialDetailMissionRow(mission: mission, topicName: topicID.flatMap { topicNames[$0] })
                                    .accessibilityIdentifier("official.mission.\(mission.index)")
                            }
                        }
                    } header: {
                        HStack {
                            Text("official.detailParity.tasks.heading")
                            Spacer()
                            if let key = presentation.eligibilityKey { Text(LocalizedStringKey(key)) }
                        }.accessibilityIdentifier(OfficialDetailID.tasks)
                    }
                }
                Section("official.detailParity.rewards.heading") {
                    if event.rewards.isEmpty { Text("official.detailParity.rewards.empty") }
                    ForEach(Array(event.rewards.enumerated()), id: \.offset) { _, reward in
                        switch reward {
                        case .badge: Label("official.reward.badge", systemImage: "seal")
                        case .coupon: Label("official.reward.coupon", systemImage: "ticket")
                        case .experience(let amount): LabeledContent("official.reward.experience", value: amount)
                        case .collectiveCoupon: Label("official.reward.collective", systemImage: "person.3")
                        }
                    }
                }.accessibilityIdentifier(OfficialDetailID.rewards)
                if let collective = event.collective, collective.enabled {
                    Section("official.collective") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(verbatim: collective.detailPercentText).font(.title2.weight(.semibold))
                                    Text("official.detailParity.collective.lit").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(verbatim: collective.detailCountText).monospacedDigit()
                            }
                            ProgressView(value: collective.displayFraction ?? 0).accessibilityHidden(true)
                            Text(LocalizedStringKey(presentation.collectiveTipKey)).font(.footnote).foregroundStyle(.secondary)
                        }.accessibilityElement(children: .combine).accessibilityIdentifier(OfficialDetailID.collective)
                    }
                }
                if !event.rewards.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("official.detailParity.rewardFootnote.issue")
                            Text("official.detailParity.rewardFootnote.settlement")
                        }.font(.footnote).foregroundStyle(.secondary)
                            .accessibilityElement(children: .combine).accessibilityIdentifier(OfficialDetailID.rewardFootnote)
                    }
                }
                Section("official.participation") {
                    Text(LocalizedStringKey(reader.isAuthenticated ? event.participationKey : event.statusKey)).accessibilityIdentifier("official.participationState")
                    if event.paused, let reason = event.pausedReason, !reason.isEmpty { Text(verbatim: reason) }
                    if reader.isAuthenticated {
                        if event.signed == true {
                            if event.isV2 { LabeledContent("official.completedTasks", value: "\(event.completedMissionCount)/\(event.missions.count)") }
                            else if let progress = event.myProgress { LabeledContent("official.progress", value: String(progress)) }
                        }
                        if let eligible = event.eligible { Text(eligible ? "official.eligible" : "official.notEligible") }
                    } else {
                        Text("official.signInForProgress")
                        if let onLogin { Button("official.signIn", action: onLogin).frame(minHeight: 44) }
                    }
                    Text("official.actionsDeferred").font(.footnote).foregroundStyle(.secondary)
                }
                if reader.isAuthenticated, let actions {
                    let lease = OfficialDetailReturnLease(eventID: id, scope: reader.scope, visit: visit)
                    OfficialParticipationActions(coordinator: actions, event: event, onReturn: {
                        guard lease.permits(eventID: id, scope: reader.scope, visit: visit,
                                            visible: visible, active: scenePhase == .active) else { return }
                        // Reuse the existing detail GET. Never repeat the action or
                        // infer settlement from its acknowledgement/unknown result.
                        readback = UUID()
                    })
                }
                Section {
                    // Source CTA wording. Only the theme CTA navigates (to its bound topic);
                    // roam routes are not wired here and signup stays with OfficialParticipationActions.
                    if let topicLinks, let topic = OfficialDetailTopicLinks.ctaTopic(event, cta: presentation.cta) {
                        NavigationLink { topicLinks.destination(topic) } label: {
                            Text(LocalizedStringKey(presentation.cta.key)).font(.headline).frame(maxWidth: .infinity, minHeight: 44)
                        }.accessibilityIdentifier(OfficialDetailID.ctaTopic)
                    } else {
                        Text(LocalizedStringKey(presentation.cta.key)).font(.headline)
                            .foregroundStyle(presentation.cta.isSourceAction ? Color.accentColor : Color.secondary)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .accessibilityIdentifier(OfficialDetailID.cta)
                    }
                }
                if reader.isOfflineExample { Section { OfficialReadOnlyNotice(offline: true) } }
            }.accessibilityIdentifier("official.detail.content")
            .task(id: OfficialTopicNamesKey(eventID: event.id, ids: OfficialDetailTopicLinks.topicIDs(event),
                                             scope: reader.scope, topicScope: topicLinks?.reader.scope)) {
                await loadTopicNames(OfficialDetailTopicLinks.topicIDs(event))
            }
        }
        .appNavigationTitle("official.detail").navigationBarTitleDisplayMode(.inline)
        .onAppear { visible = true }
        .onDisappear { visible = false; visit = UUID() }
        .onChange(of: id) { _, _ in visit = UUID() }
        .onChange(of: reader.scope) { _, _ in visit = UUID() }
        .onChange(of: scenePhase) { _, _ in visit = UUID() }
    }
}
extension OfficialEventDetailView {
    /// Source _loadBoundTopicNames: signed-in viewers only; a stale or failed read never blocks the row.
    func loadTopicNames(_ ids: [Int]) async {
        topicNames = [:]; topicNameFailed = false
        guard let topicLinks, reader.isAuthenticated, !ids.isEmpty else { return }
        let scope = topicLinks.reader.scope
        var names: [Int: String] = [:], failed = false
        for id in ids {
            do {
                let name = try await topicLinks.reader.topicDetail(id: id).name.trimmingCharacters(in: .whitespacesAndNewlines)
                if name.isEmpty { failed = true } else { names[id] = name }
            } catch { if error is CancellationError { return }; failed = true }
            guard !Task.isCancelled, topicLinks.reader.scope == scope else { return }
        }
        topicNames = names; topicNameFailed = failed
    }
}
struct OfficialTopicNamesKey: Hashable {
    let eventID: Int
    let ids: [Int]
    let scope: UUID
    let topicScope: UUID?
}
/// Session-provided topic read and destination for missions bound to a topic.
struct OfficialTopicLinks {
    let reader: any TopicReading
    let destination: (Int) -> AnyView
}
/// Source facts strip: label, value and sub line per fact, scrolled horizontally.
struct OfficialDetailFactsStrip: View {
    let facts: [OfficialDetailFact]
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 20) {
                ForEach(facts) { fact in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(LocalizedStringKey(fact.labelKey)).font(.caption).foregroundStyle(.secondary)
                        value(fact.value).font(.headline)
                        sub(fact.sub).font(.caption).foregroundStyle(.secondary)
                    }.accessibilityElement(children: .combine)
                }
            }.padding(.vertical, 4)
        }
    }
    @ViewBuilder private func value(_ value: OfficialDetailFactValue) -> some View {
        switch value {
        case .verbatim(let text): Text(verbatim: text)
        case .key(let key): Text(LocalizedStringKey(key))
        case .days(let count): Text("official.detailParity.duration.days \(count)")
        case .hours(let count): Text("official.detailParity.duration.hours \(count)")
        }
    }
    @ViewBuilder private func sub(_ sub: OfficialDetailFactSub) -> some View {
        switch sub {
        case .key(let key): Text(LocalizedStringKey(key))
        case .countdown(let countdown): OfficialCountdownText(value: countdown)
        }
    }
}
struct OfficialDetailTextView: View {
    let value: OfficialDetailText
    var body: some View {
        switch value {
        case .verbatim(let text): Text(verbatim: text)
        case .key(let key): Text(LocalizedStringKey(key))
        case .numberedTask(let number): Text("official.detailParity.card.numbered \(number)")
        }
    }
}
struct OfficialDetailMissionRow: View {
    let mission: OfficialDetailMission
    var topicName: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            OfficialDetailTextView(value: mission.title).font(.headline)
            if let topicName { Text("official.w206.detail.boundTopic \(topicName)").font(.subheadline) }
            OfficialDetailTextView(value: mission.description)
            Label(LocalizedStringKey(mission.action.key), systemImage: symbol)
        }.accessibilityElement(children: .combine)
    }
    private var symbol: String {
        switch mission.action {
        case .verified: return "checkmark.circle"
        case .verify: return "location"
        case .automatic: return "arrow.triangle.2.circlepath"
        case .unsupported: return "nosign"
        }
    }
}
