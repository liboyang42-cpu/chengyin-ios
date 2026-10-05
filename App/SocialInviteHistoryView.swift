import SwiftUI

@MainActor struct SocialInviteHistoryView: View {
    let reader: any SocialAccountReading
    let squareReader: any SquareReading
    var actions: SocialActionCoordinator? = nil
    @State private var pagination = SocialInvitePagination()
    @State private var scan: SocialRewardScan?
    @State private var loading = false
    @State private var error: Error?
    @State private var generation = 0
    @State private var loadedIdentity: SocialAccountIdentity?
    private var groups: [(String, [SocialInvitedMember])] {
        var keys: [String] = [], rows: [String: [SocialInvitedMember]] = [:]
        for member in pagination.members {
            let raw = String((member.createdAt ?? "").prefix(7))
            let key = raw.range(of: "^[0-9]{4}-(0[1-9]|1[0-2])$", options: .regularExpression) == nil ? "" : raw
            if rows[key] == nil { keys.append(key) }; rows[key, default: []].append(member)
        }
        return keys.map { ($0, rows[$0] ?? []) }
    }
    var body: some View {
        List {
            if reader.isOfflineExample { Text("social.offline").font(.caption) }
            if reader.identity.accountID == nil { SocialIssueView(error: APIError.unauthorized) }
            else if !reader.isConfigured { SocialIssueView(error: APIError.notConfigured) }
            else if loadedIdentity != reader.identity { ProgressView("social.loading") }
            else {
                if let error { SocialIssueView(error: error) { Task { await load(reset: pagination.members.isEmpty) } } }
                Section {
                    SocialOptionalCount(title: "social.invites.total", count: pagination.total)
                    LabeledContent("social.invites.loaded", value: String(pagination.members.count))
                    if scan?.isComplete != true { Text("social.invites.partial").font(.footnote).accessibilityIdentifier("social.invites.partial") }
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
                if !loading && pagination.members.isEmpty && error == nil { Text("social.invites.empty") }
                if loading { ProgressView("social.loading") }
                if pagination.continuationInvalid { Text("social.invites.continuationInvalid") }
                if pagination.hasMore && !loading && error == nil {
                    Button("square.loadMore") { Task { await load(reset: false) } }.accessibilityIdentifier("social.invites.more")
                }
            }
        }.appNavigationTitle("social.invites.title").privacySensitive()
            .task(id: reader.identity) { await load(reset: true) }.refreshable { await load(reset: true) }
            .onDisappear { generation += 1; loading = false }
            .accessibilityIdentifier("social.invites")
    }
    private func memberRow(_ member: SocialInvitedMember) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            if let nickname = member.nickname { Text(verbatim: nickname).font(.headline) }
            else { Text("square.unknownAuthor").font(.headline) }
            if let date = member.createdAt { Text(verbatim: date).font(.caption) }
            else { Text("social.invites.timeUnknown").font(.caption) }
            if let reward = scan?.rewards[String(member.id)] {
                Text("social.invites.earned").font(.subheadline)
                LabeledContent("social.invites.points", value: NSDecimalNumber(decimal: reward.points).stringValue)
            } else { Text(LocalizedStringKey(scan?.isComplete == true ? "social.invites.pending" : "social.invites.synchronizing")).font(.subheadline) }
        }.accessibilityElement(children: .combine)
    }
    private func load(reset: Bool) async {
        guard !loading || reset else { return }
        generation += 1; let run = generation, identity = reader.identity
        if reset { pagination = SocialInvitePagination(); scan = nil }; error = nil; loadedIdentity = identity
        guard identity.accountID != nil, reader.isConfigured else { loading = false; return }
        loading = true
        defer { if generation == run { loading = false } }
        do {
            let value = try await reader.invitationHistory(page: pagination.nextPage)
            try Task.checkCancellation()
            guard run == generation, identity == reader.identity else { return }
            try pagination.accept(value.page); scan = value.rewardScan
        } catch is CancellationError { }
        catch {
            if run == generation, identity == reader.identity {
                if error as? APIError == .unauthorized { pagination = SocialInvitePagination(); scan = nil }
                self.error = error
            }
        }
    }
}
