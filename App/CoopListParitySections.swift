import SwiftUI

/// Source `pages/coop/list` chapter-application block, shown above both tabs. Owner leg always; the
/// merchant-only `mine` leg is skipped silently when the account is not a merchant (permission failure).
@MainActor struct CoopChapterApplicationSection: View {
    let reader: any CoopFlowReading
    let direction: CooperationDirection
    var operationScope: String? = nil
    var topicFilter: CoopTopicFilterSeed = .init()
    @State private var rows: [CoopChapterApplication] = []
    @State private var failed = false
    @State private var loading = false
    @State private var loadedSession: CoopFlowSession?
    @State private var refresh = UUID()
    var body: some View {
        let visible = loadedSession == reader.session ? topicFilter.filter(rows.filter { $0.direction == direction }, topic: \.topicID) : []
        Group {
            if loading || failed || !visible.isEmpty {
                Section("cooperation.list.chapter.title") {
                    if loading { Text("cooperation.list.chapter.loading").foregroundStyle(.secondary) }
                    if failed {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("cooperation.list.chapter.failed").font(.subheadline.weight(.semibold))
                            Button("cooperation.refresh") { refresh = UUID() }.accessibilityIdentifier("cooperation.list.chapter.retry")
                        }.accessibilityIdentifier("cooperation.list.chapter.failed")
                    }
                    ForEach(visible) { row in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(LocalizedStringKey("cooperation.list.chapter.status." + row.status.rawValue)).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            Text(verbatim: row.topicName ?? "#" + String(row.topicID ?? 0)).font(.headline)
                            if let chapter = row.chapterName {
                                Text(verbatim: row.leg == .owner && row.merchantName != nil ? chapter + " · " + (row.merchantName ?? "") : chapter).font(.subheadline)
                            }
                            Text(LocalizedStringKey("cooperation.list.chapter.action." + row.action.rawValue)).font(.footnote).foregroundStyle(.tint)
                        }.padding(.vertical, 2).accessibilityElement(children: .combine)
                            .accessibilityIdentifier("cooperation.list.chapter.\(row.id)")
                    }
                }
            }
        }
        .task(id: "\(reader.session?.accountID ?? 0):\(reader.session?.epoch ?? 0):\(refresh)") { await load() }
    }
    private func load() async {
        rows = []; failed = false; loadedSession = nil
        guard let session = reader.session else { return }
        loading = true
        defer { if reader.session == session { loading = false } }
        var collected: [CoopChapterApplication] = [], legFailed = false
        do { let owned = try await reader.read(.chapterApplicationsOwned(scope: operationScope)); collected += try CoopChapterApplication.rows(owned, leg: .owner) }
        catch { guard !Task.isCancelled, reader.session == session else { return }; legFailed = true }
        do { let mine = try await reader.read(.chapterApplicationsMine); collected += try CoopChapterApplication.rows(mine, leg: .mine) }
        catch {
            guard !Task.isCancelled, reader.session == session else { return }
            if !CoopListReadFailure.isPermission(error) { legFailed = true }
        }
        guard !Task.isCancelled, reader.session == session else { return }
        rows = collected; failed = legFailed; loadedSession = session
    }
}

/// Source `pages/coop/list` official merchant invites (received tab). Accept/decline open dormant reviews only.
@MainActor struct CoopOfficialInviteSection: View {
    let reader: any CoopFlowReading
    @Environment(\.locale) private var locale
    @State private var rows: [CoopOfficialInvite] = []
    @State private var failed = false
    @State private var loadedSession: CoopFlowSession?
    @State private var refresh = UUID()
    var body: some View {
        Group {
            if failed || (loadedSession == reader.session && !rows.isEmpty) {
                Section("cooperation.list.official.title") {
                    if failed {
                        Text("cooperation.list.official.failed").accessibilityIdentifier("cooperation.list.official.failed")
                        Button("cooperation.refresh") { refresh = UUID() }
                    }
                    ForEach(rows) { row in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(LocalizedStringKey("cooperation.list.official.stage." + row.stage.rawValue)).font(.caption.weight(.semibold)).foregroundStyle(row.actionable ? Color.orange : Color.secondary)
                            Text("cooperation.list.official.from").font(.footnote).foregroundStyle(.secondary)
                            Text(verbatim: row.title).font(.headline)
                            Text(verbatim: deadline(row.deadline)).font(.subheadline)
                            Text(verbatim: reward(row.reward)).font(.subheadline)
                            if row.actionable {
                                NavigationLink { CoopFlowRequestPreview(operation: .handle(inviteID: row.id, action: .accept, reason: "")) } label: { Text("cooperation.detail.accept") }
                                    .accessibilityIdentifier("cooperation.list.official.accept.\(row.id)")
                                NavigationLink { CoopFlowHandleEditor(inviteID: row.id, action: .reject, currentStatus: 0) } label: { Text("cooperation.detail.reject") }
                                    .accessibilityIdentifier("cooperation.list.official.reject.\(row.id)")
                            }
                        }.padding(.vertical, 4).opacity(row.actionable ? 1 : 0.6)
                            .accessibilityIdentifier("cooperation.list.official.\(row.id)")
                    }
                }
            }
        }
        .task(id: "\(reader.session?.accountID ?? 0):\(reader.session?.epoch ?? 0):\(refresh)") {
            rows = []; failed = false; loadedSession = nil
            guard let session = reader.session else { return }
            do {
                let value = try await reader.read(.officialMerchantInvites)
                guard !Task.isCancelled, reader.session == session else { return }
                rows = CoopOfficialInvite.rows(value); loadedSession = session
            } catch { guard !Task.isCancelled, reader.session == session else { return }; failed = true; loadedSession = session }
        }
    }
    private func deadline(_ value: CoopOfficialInvite.Deadline) -> String {
        switch value {
        case .unconfirmed: return appLocalized("cooperation.list.official.deadline.unconfirmed", locale: locale)
        case .monthDay(let month, let day): return appLocalized("cooperation.list.official.deadline \(month) \(day)", locale: locale)
        case .verbatim(let text): return text
        }
    }
    private func reward(_ value: CoopOfficialInvite.Reward) -> String {
        switch value {
        case .share(let rate): return appLocalized("cooperation.list.official.reward.share \(rate)", locale: locale)
        case .fixed(let fee): return appLocalized("cooperation.list.official.reward.fixed \(fee)", locale: locale)
        case .resources: return appLocalized("cooperation.list.official.reward.resources", locale: locale)
        case .unconfirmed: return appLocalized("cooperation.list.official.reward.unconfirmed", locale: locale)
        }
    }
}

/// Source list card summary lines: party direction, terms, viewer party, deposit due and an incomplete-decision notice.
struct CooperationInviteCardDetails: View {
    let view: CooperationInvitePresentation
    var body: some View {
        let invite = view.invite
        VStack(alignment: .leading, spacing: 4) {
            if let party = invite.viewerPartyName {
                Text(verbatim: party).font(.footnote).foregroundStyle(.secondary)
                    .accessibilityLabel(Text(LocalizedStringKey(view.direction == .received ? "cooperation.detail.receivingClub" : "cooperation.detail.sendingClub")) + Text(verbatim: " " + party))
            }
            if let name = invite.topicName { Text(verbatim: name).font(.subheadline.weight(.semibold)) }
            CooperationInvitePartyText(view: view).font(.footnote).foregroundStyle(.secondary)
            CooperationInviteTermsText(terms: view.terms).font(.footnote)
            if case .owed = view.deposit { CooperationInviteDepositText(deposit: view.deposit).font(.footnote) }
            if view.direction == .sent && invite.status == 2 { Text("cooperation.list.sent.declinedHint").font(.footnote).foregroundStyle(.secondary) }
            if invite.status == 0 && view.direction == .received && !invite.legacyReadonly && !view.decisionReady {
                Label("cooperation.list.incomplete", systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.orange)
            }
        }
    }
}
