import SwiftUI

@MainActor struct SocialInviteHistoryView: View {
    let reader: any SocialAccountReading
    let squareReader: any SquareReading
    var actions: SocialActionCoordinator? = nil
    @StateObject private var model = SocialInviteHistoryModel()
    private var groups: [(String, [SocialInvitedMember])] {
        var keys: [String] = [], rows: [String: [SocialInvitedMember]] = [:]
        for member in model.pagination.members {
            let raw = String((member.createdAt ?? "").prefix(7))
            let key = raw.range(of: "^[0-9]{4}-(0[1-9]|1[0-2])$", options: .regularExpression) == nil ? "" : raw
            if rows[key] == nil { keys.append(key) }; rows[key, default: []].append(member)
        }
        return keys.map { ($0, rows[$0] ?? []) }
    }
    var body: some View {
        let binding = model.bind(reader)
        let permit = model.permit(reader)
        List {
            if reader.isOfflineExample { Text("social.offline").font(.caption) }
            if reader.identity.accountID == nil { SocialIssueView(error: APIError.unauthorized) }
            else if !reader.isConfigured { SocialIssueView(error: APIError.notConfigured) }
            else if !model.matches(reader) { ProgressView("social.loading") }
            else {
                if let error = model.error { SocialIssueView(error: error) { model.start(reader, permit: permit, reset: model.pagination.members.isEmpty) } }
                Section {
                    SocialOptionalCount(title: "social.invites.total", count: model.pagination.total)
                    LabeledContent("social.invites.loaded", value: String(model.pagination.members.count))
                    if model.scan?.isComplete != true { Text("social.invites.partial").font(.footnote).accessibilityIdentifier("social.invites.partial") }
                }
                ForEach(groups, id: \.0) { group in
                    Section {
                        ForEach(group.1) { member in
                            NavigationLink {
                                SocialPublicProfileView(memberID: member.id, reader: reader, squareReader: squareReader, actions: actions)
                            } label: { memberRow(member) }.accessibilityIdentifier("social.invite.\(member.id)")
                        }
                    } header: {
                        if group.0.isEmpty { Text("social.invites.otherMonth") }
                        else { Text(verbatim: group.0) }
                    }
                }
                if !model.loading && model.pagination.members.isEmpty && model.error == nil { Text("social.invites.empty") }
                if model.loading { ProgressView("social.loading") }
                if model.pagination.continuationInvalid { Text("social.invites.continuationInvalid") }
                if model.pagination.hasMore && !model.loading && model.error == nil {
                    Button("square.loadMore") { model.start(reader, permit: permit, reset: false) }.accessibilityIdentifier("social.invites.more")
                }
            }
        }.appNavigationTitle("social.invites.title").privacySensitive()
            .onAppear { model.appear(reader) }
            .onChange(of: binding) { _, _ in model.replaceReader(reader) }
            .refreshable { await model.refresh(reader, permit: permit) }
            .onDisappear { model.suspend() }
            .accessibilityIdentifier("social.invites")
    }
    private func memberRow(_ member: SocialInvitedMember) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            if let nickname = member.nickname { Text(verbatim: nickname).font(.headline) }
            else { Text("square.unknownAuthor").font(.headline) }
            if let date = member.createdAt { Text(verbatim: date).font(.caption) }
            else { Text("social.invites.timeUnknown").font(.caption) }
            if let reward = model.scan?.rewards[String(member.id)] {
                Text("social.invites.earned").font(.subheadline)
                LabeledContent("social.invites.points", value: NSDecimalNumber(decimal: reward.points).stringValue)
            } else { Text(LocalizedStringKey(model.scan?.isComplete == true ? "social.invites.pending" : "social.invites.synchronizing")).font(.subheadline) }
        }.accessibilityElement(children: .combine)
    }
}

/// Every request belongs to one model, one visible presentation, one reader and
/// one request generation. Cancellation is useful but never the only fence.
@MainActor final class SocialInviteHistoryModel: ObservableObject {
    struct ReaderBinding: Equatable {
        let id = UUID()
        let key: SocialReadPresentationKey
    }
    struct LoadPermit: Equatable {
        let owner: UUID
        let presentation: UUID
        let binding: ReaderBinding
    }
    @Published private(set) var pagination = SocialInvitePagination()
    @Published private(set) var scan: SocialRewardScan?
    @Published private(set) var loading = false
    @Published private(set) var error: Error?
    @Published private var presentation: LoadPermit?
    @Published private var loadedBinding: ReaderBinding?
    private var boundReader: ReaderBinding?
    private let owner = UUID()
    private var requestID: UUID?
    private var task: Task<Void, Never>?

    static func key(_ reader: any SocialAccountReading) -> SocialReadPresentationKey {
        .init(reader: reader, request: "invitation-history", requiresSignIn: true)
    }
    /// Bind during body evaluation, before onChange or old async completions can
    /// run. Only non-published fencing state changes here; UI state reloads later.
    /// A new ID also retires an observed reader A-B-A before lifecycle callbacks.
    @discardableResult
    func bind(_ reader: any SocialAccountReading) -> ReaderBinding {
        let key = Self.key(reader)
        if let boundReader, boundReader.key == key { return boundReader }
        let current = ReaderBinding(key: key)
        boundReader = current
        task?.cancel()
        return current
    }
    func matches(_ reader: any SocialAccountReading) -> Bool {
        reader.identity.accountID != nil && reader.isConfigured && loadedBinding == boundReader
            && loadedBinding?.key == Self.key(reader)
    }
    func permit(_ reader: any SocialAccountReading) -> LoadPermit? {
        guard let presentation, presentation.owner == owner, presentation.binding == boundReader,
              presentation.binding.key == Self.key(reader), reader.identity.accountID != nil, reader.isConfigured else { return nil }
        return presentation
    }
    /// Called synchronously by appearance, not by a potentially queued Task.
    @discardableResult
    func appear(_ reader: any SocialAccountReading) -> Task<Void, Never>? {
        let key = Self.key(reader)
        if boundReader == nil { bind(reader) }
        guard let binding = boundReader, binding.key == key, presentation?.binding != binding else { return nil }
        suspend()
        let current = LoadPermit(owner: owner, presentation: UUID(), binding: binding)
        presentation = current; loadedBinding = binding
        pagination = SocialInvitePagination(); scan = nil; error = nil
        return start(reader, permit: current, reset: true)
    }
    @discardableResult
    func replaceReader(_ reader: any SocialAccountReading) -> Task<Void, Never>? {
        guard presentation != nil else { return nil } // A covered/closed screen cannot restart itself.
        return appear(reader)
    }
    /// Keep scoped rows that own pushed NavigationLinks. Reappearance starts a
    /// new presentation and resets them; hidden work has no right to change them.
    func suspend() {
        presentation = nil; requestID = nil
        task?.cancel(); task = nil; loading = false
    }
    @discardableResult
    func start(_ reader: any SocialAccountReading, permit: LoadPermit?, reset: Bool) -> Task<Void, Never>? {
        guard let permit, self.permit(reader) == permit, !loading || reset,
              reset || pagination.hasMore else { return nil }
        task?.cancel()
        let request = UUID(); requestID = request
        if reset { pagination = SocialInvitePagination(); scan = nil }
        error = nil; loading = true
        let page = pagination.nextPage
        let work = Task { [weak self] in
            guard let self else { return }
            await self.load(reader, permit: permit, request: request, page: page)
        }
        task = work
        return work
    }
    func refresh(_ reader: any SocialAccountReading, permit: LoadPermit?) async {
        guard !Task.isCancelled, let work = start(reader, permit: permit, reset: true) else { return }
        await withTaskCancellationHandler {
            await work.value
        } onCancel: {
            work.cancel()
        }
    }
    private func owns(_ reader: any SocialAccountReading, permit: LoadPermit, request: UUID) -> Bool {
        self.permit(reader) == permit && requestID == request
    }
    private func load(_ reader: any SocialAccountReading, permit: LoadPermit, request: UUID, page: Int) async {
        defer {
            if owns(reader, permit: permit, request: request) {
                loading = false; requestID = nil; task = nil
            }
        }
        do {
            try Task.checkCancellation()
            guard owns(reader, permit: permit, request: request) else { return }
            let value = try await reader.invitationHistory(page: page)
            try Task.checkCancellation()
            guard owns(reader, permit: permit, request: request) else { return }
            try pagination.accept(value.page); scan = value.rewardScan
        } catch is CancellationError { }
        catch {
            guard !Task.isCancelled, owns(reader, permit: permit, request: request) else { return }
            if error as? APIError == .unauthorized { pagination = SocialInvitePagination(); scan = nil }
            self.error = error
        }
    }
}
