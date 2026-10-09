import SwiftUI

private struct ExploreCompletionProviderKey: EnvironmentKey {
    static let defaultValue: ExploreCompletionProvider? = nil
}
extension EnvironmentValues {
    var exploreCompletionProvider: ExploreCompletionProvider? {
        get { self[ExploreCompletionProviderKey.self] }
        set { self[ExploreCompletionProviderKey.self] = newValue }
    }
}
/// A configured host must explicitly bind both independently approved reads to the same full context.
/// This module does not construct or install an AppSession approval/provider.
struct ExploreCompletionProvider {
    struct Owner: Hashable {
        let originID: ObjectIdentifier
        let originIdentity: ProfileReadIdentity
        let readerID: ObjectIdentifier
        let readIdentity: ExploreCompletionReadIdentity
    }
    let owner: Owner
    let reader: any ExploreCompletionReading
    private let originSession: OwnedOrderReadSession
    private let currentOrigin: @MainActor () -> OwnedOrderReadSession?
    @MainActor init?(origin: any ProfileReading, originSession: OwnedOrderReadSession,
                     currentOrigin: @escaping @MainActor () -> OwnedOrderReadSession?, reader: any ExploreCompletionReading) {
        guard origin.isConfigured, origin.identity == originSession.identity, currentOrigin() == originSession,
              reader.matches(context: originSession.context), let readIdentity = reader.identity,
              readIdentity.accountID == originSession.identity.accountID, readIdentity.epoch == originSession.identity.epoch else { return nil }
        owner = .init(originID: ObjectIdentifier(origin), originIdentity: originSession.identity,
                      readerID: ObjectIdentifier(reader), readIdentity: readIdentity)
        self.reader = reader; self.originSession = originSession; self.currentOrigin = currentOrigin
    }
    @MainActor func matches(origin: any ProfileReading) -> Bool {
        ObjectIdentifier(origin) == owner.originID && origin.isConfigured && origin.identity == owner.originIdentity
            && currentOrigin() == originSession && reader.identity == owner.readIdentity && reader.isConfigured
            && ObjectIdentifier(reader) == owner.readerID && reader.matches(context: originSession.context)
    }
}

/// The parent supplies only its freshly accepted owned-order detail, never a list-row shortcut.
@MainActor struct ExploreCompletionEntry: View {
    let order: ProfileOrder
    let requestedID: Int
    let origin: any ProfileReading
    @Environment(\.exploreCompletionProvider) private var provider
    private struct Target: Hashable {
        let id = UUID()
        let request: ExploreCompletionTarget
        let owner: ExploreCompletionProvider.Owner
    }
    @State private var selected: Target?
    @State private var visible = false
    @State private var presentationID = UUID()
    var body: some View {
        Group {
            if let provider, provider.matches(origin: origin),
               let request = ExploreCompletionTarget(order: order, requestedID: requestedID, accountID: provider.owner.readIdentity.accountID) {
                let renderedPresentation = presentationID
                Section {
                    Button("exploreCompletion.open", systemImage: "checkmark.seal") {
                        guard visible, selected == nil, renderedPresentation == presentationID,
                              provider.matches(origin: origin) else { return }
                        selected = Target(request: request, owner: provider.owner)
                    }.disabled(!visible).accessibilityIdentifier("exploreCompletion.open")
                }
            }
        }
        .onAppear { visible = true; presentationID = UUID() }
        .onDisappear { visible = false; presentationID = UUID() }
        .onChange(of: order) { _, _ in retire() }
        .onChange(of: requestedID) { _, _ in retire() }
        .onChange(of: origin.identity) { _, _ in retire() }
        .onChange(of: origin.isConfigured) { _, _ in retire() }
        .onChange(of: ObjectIdentifier(origin)) { _, _ in retire() }
        .onChange(of: provider?.owner) { _, _ in retire() }
        .onChange(of: provider?.reader.identity) { _, _ in retire() }
        .navigationDestination(item: $selected) { target in
            if let provider, target.owner == provider.owner, provider.matches(origin: origin),
               target.request == ExploreCompletionTarget(order: order, requestedID: requestedID, accountID: provider.owner.readIdentity.accountID) {
                ExploreCompletionView(target: target.request, reader: provider.reader, identity: provider.owner.readIdentity,
                                      isCurrent: { provider.matches(origin: origin) })
                    .id(target.id)
            } else { ContentUnavailableView("exploreCompletion.changed", systemImage: "lock") }
        }
    }
    private func retire() { selected = nil; presentationID = UUID() }
}

@MainActor struct ExploreCompletionView: View {
    let target: ExploreCompletionTarget
    let reader: any ExploreCompletionReading
    let identity: ExploreCompletionReadIdentity
    let isCurrent: @MainActor () -> Bool
    @State private var model: ExploreCompletionReadModel
    init(target: ExploreCompletionTarget, reader: any ExploreCompletionReading, identity: ExploreCompletionReadIdentity,
         isCurrent: @escaping @MainActor () -> Bool) {
        self.target = target; self.reader = reader; self.identity = identity; self.isCurrent = isCurrent
        _model = State(initialValue: ExploreCompletionReadModel(reader: reader))
    }
    var body: some View {
        // Capture during rendering, before Retry/refresh can queue asynchronous work.
        let renderedPresentation = model.presentationID
        List {
            if !isCurrent() || reader.identity != identity || !reader.isConfigured {
                ContentUnavailableView("exploreCompletion.changed", systemImage: "lock")
            } else if model.isLoading { ProgressView("exploreCompletion.loading") }
            else if let error = model.error {
                Section {
                    if case ExploreCompletionFailure.rejected(_, let message) = error, let message, !message.isEmpty {
                        Text(verbatim: message)
                    } else if error as? APIError == .httpStatus(403) || error as? APIError == .businessCode(403) {
                        Text("exploreCompletion.denied")
                    } else { Text("exploreCompletion.failed") }
                    Button("exploreCompletion.retry") {
                        guard let ticket = renderedPresentation else { return }
                        Task { await load(presentationID: ticket) }
                    }
                        .accessibilityIdentifier("exploreCompletion.retry")
                }
            } else if let value = model.value {
                if value.hasTopic { facts(value) }
                else { ContentUnavailableView("exploreCompletion.noTopic", systemImage: "questionmark.folder") }
            } else { ProgressView("exploreCompletion.loading") }
            Section { Text("exploreCompletion.readOnly").font(.footnote).foregroundStyle(.secondary) }
        }
        .navigationTitle("exploreCompletion.title")
        .privacySensitive()
        .onAppear { model.beginPresentation() }
        .task(id: renderedPresentation) {
            guard let ticket = renderedPresentation else { return }
            await load(presentationID: ticket)
        }
        .refreshable {
            guard let ticket = renderedPresentation else { return }
            await load(presentationID: ticket)
        }
        .onChange(of: reader.identity) { _, _ in model.endPresentation() }
        .onDisappear { model.endPresentation() }
        .accessibilityIdentifier("exploreCompletion.view")
    }
    private func load(presentationID: UUID) async {
        guard !Task.isCancelled, model.matchesPresentation(presentationID) else { return }
        guard isCurrent(), reader.identity == identity else { model.invalidate(); return }
        await model.load(target, expectedIdentity: identity, presentationID: presentationID, isCurrent: {
            model.matchesPresentation(presentationID) && isCurrent()
        })
    }
    @ViewBuilder private func facts(_ value: ExploreCompletionSnapshot) -> some View {
        Section("exploreCompletion.progress") {
            Text(LocalizedStringKey(value.completed ? "exploreCompletion.completed" : "exploreCompletion.inProgress"))
            if value.requiredChapterCount > 0 {
                LabeledContent("exploreCompletion.collected", value: "\(value.redeemedChapterCount)/\(value.requiredChapterCount)")
            }
        }
        Section("exploreCompletion.stamps") {
            if value.stamps.isEmpty { Text("exploreCompletion.noStamps") }
            ForEach(Array(value.stamps.enumerated()), id: \.offset) { _, stamp in
                VStack(alignment: .leading, spacing: 6) {
                    if let title = stamp.title, !title.isEmpty { Text(verbatim: title).font(.headline) }
                    else { LabeledContent("exploreCompletion.chapter", value: String(stamp.chapterID)) }
                    Label(LocalizedStringKey(stamp.collected ? "exploreCompletion.collected" : "exploreCompletion.notCollected"),
                          systemImage: stamp.collected ? "checkmark.seal" : "circle")
                    if let time = stamp.obtainedAt { recordedTime(time).font(.caption).foregroundStyle(.secondary) }
                }.fixedSize(horizontal: false, vertical: true)
            }
        }
        Section("exploreCompletion.awards") {
            if !value.awards.credited || value.awards.items.isEmpty {
                Text(LocalizedStringKey(value.completed ? "exploreCompletion.awardsNotReported" : "exploreCompletion.notCompletedAwards"))
            }
            if let points = value.awards.points { LabeledContent("exploreCompletion.points", value: String(points)) }
            if let xp = value.awards.earnedXP { LabeledContent("exploreCompletion.xp", value: String(xp)) }
            if let coupon = value.awards.couponGranted {
                LabeledContent("exploreCompletion.coupon") { Text(LocalizedStringKey(coupon ? "exploreCompletion.granted" : "exploreCompletion.notGranted")) }
            }
            ForEach(Array(value.awards.items.enumerated()), id: \.offset) { _, award in
                VStack(alignment: .leading, spacing: 6) {
                    if let title = award.title, !title.isEmpty { Text(verbatim: title).font(.headline) }
                    else { Text(verbatim: award.kind).font(.headline) }
                    if let amount = award.amount { LabeledContent("exploreCompletion.amount", value: String(amount)) }
                    if let time = award.grantedAt { recordedTime(time).font(.caption).foregroundStyle(.secondary) }
                }.fixedSize(horizontal: false, vertical: true)
            }
        }
        if let revisit = value.revisit, let clubID = revisit.clubID {
            Section("exploreCompletion.revisit") {
                if let name = revisit.clubName, !name.isEmpty { Text(verbatim: name).font(.headline) }
                else { LabeledContent("exploreCompletion.club", value: String(clubID)) }
                Text(LocalizedStringKey(revisit.followed ? "exploreCompletion.followed" : "exploreCompletion.notFollowed"))
                Text(LocalizedStringKey(revisit.joined ? "exploreCompletion.joined" : "exploreCompletion.notJoined"))
                if let next = revisit.nextEdition {
                    LabeledContent("exploreCompletion.nextEdition", value: next.name ?? String(next.topicID))
                    if let date = next.startDate { recordedTime(date).font(.caption) }
                } else { Text("exploreCompletion.nextPending") }
            }
        }
    }
    @ViewBuilder private func recordedTime(_ time: ExploreCompletionTime) -> some View {
        switch time {
        case .text(let raw): if !raw.isEmpty { Text(verbatim: raw) }
        case .milliseconds(let value):
            let date = Date(timeIntervalSince1970: TimeInterval(value) / 1_000)
            Text(date, style: .date) + Text(verbatim: " ") + Text(date, style: .time)
        }
    }
}
