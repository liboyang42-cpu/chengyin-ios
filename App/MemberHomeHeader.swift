import SwiftUI

/// 我的 identity card (mini-program `cy-profile viewer=self` header). Only server
/// values are shown; a failed or dormant read falls back to the signed-in
/// account's own name and level with an explicit unavailable note.
@MainActor struct MemberIdentityCardSection: View {
    let account: Account
    let reader: any MemberHomeReading
    var growth: (any GrowthCenterReading)? = nil
    var onOpenTickets: (() -> Void)? = nil
    /// Bump from the owning screen's pull-to-refresh to reload identity and growth together.
    var refreshToken: Int = 0
    enum Phase: Equatable { case loading, ready(MemberIdentitySnapshot), failed(signedOut: Bool) }
    @State private var phase: Phase = .loading
    @State private var level: Int?
    @State private var streakDays: Int?

    var body: some View {
        Section {
            HStack(alignment: .top, spacing: 14) {
                avatar
                VStack(alignment: .leading, spacing: 6) {
                    name.font(.title3.weight(.semibold)).accessibilityIdentifier("member.card.name")
                    HStack(spacing: 6) {
                        Text(verbatim: "Lv.\(level ?? snapshot?.levelID ?? account.level)")
                        Text("member.card.levelTitle", tableName: "MemberProfile")
                    }.font(.subheadline).foregroundStyle(.secondary).accessibilityElement(children: .combine)
                    .accessibilityIdentifier("member.card.level")
                    HStack(spacing: 10) {
                        Label { city } icon: { Image(systemName: "mappin.and.ellipse") }
                            .accessibilityIdentifier("member.card.city")
                        if let streakDays {
                            HStack(spacing: 2) {
                                Text("member.card.streak", tableName: "MemberProfile")
                                Text(verbatim: "\(streakDays)")
                                Text("member.card.days", tableName: "MemberProfile")
                            }.accessibilityElement(children: .combine).accessibilityIdentifier("member.card.streak")
                        }
                    }.font(.footnote).foregroundStyle(.secondary)
                }
            }
            HStack {
                stat(snapshot?.friendCount, id: "friends") { Text("member.card.friends", tableName: "MemberProfile") }
                Divider()
                stat(snapshot?.followCount, id: "following") { Text("member.card.following", tableName: "MemberProfile") }
                Divider()
                stat(snapshot?.fansCount, id: "fans") { Text("member.card.fans", tableName: "MemberProfile") }
            }.frame(maxWidth: .infinity)
            LabeledContent {
                Text(verbatim: snapshot?.balancePreviewText ?? "—")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .accessibilityIdentifier("member.card.balanceValue")
            } label: {
                Text(verbatim: "我的资产").font(.subheadline)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("member.card.balance")
            if let onOpenTickets {
                Button(action: onOpenTickets) {
                    Label { Text("member.card.tickets", tableName: "MemberProfile") } icon: { Image(systemName: "ticket") }
                }.accessibilityIdentifier("member.card.tickets")
            }
            switch phase {
            case .loading:
                HStack { ProgressView(); Text("member.card.loading", tableName: "MemberProfile").foregroundStyle(.secondary) }
                    .accessibilityIdentifier("member.card.loading")
            case .failed(let signedOut):
                VStack(alignment: .leading, spacing: 6) {
                    Group {
                        if signedOut { Text("member.card.signedOut", tableName: "MemberProfile") }
                        else if reader.isConfigured, reader.roleInfoAvailable { Text("member.card.failed", tableName: "MemberProfile") }
                        else { Text("member.card.unavailable", tableName: "MemberProfile") }
                    }.font(.footnote).foregroundStyle(.secondary)
                    if reader.isConfigured, reader.roleInfoAvailable, !signedOut {
                        Button { Task { await load() } } label: { Text("member.card.retry", tableName: "MemberProfile") }
                            .accessibilityIdentifier("member.card.retry")
                    }
                }.accessibilityIdentifier("member.card.failed")
            case .ready: EmptyView()
            }
        }
        .task(id: TaskKey(scope: reader.scope, refresh: refreshToken)) { await load() }
    }
    private struct TaskKey: Equatable { let scope: UUID; let refresh: Int }

    private var snapshot: MemberIdentitySnapshot? { if case .ready(let value) = phase { return value }; return nil }

    @ViewBuilder private var name: some View {
        let nickname = snapshot?.nickname ?? account.nickname
        if nickname.isEmpty { Text("member.card.defaultName", tableName: "MemberProfile") } else { Text(verbatim: nickname) }
    }
    @ViewBuilder private var city: some View {
        if let value = snapshot?.city, !value.isEmpty { Text(verbatim: value) } else { Text(verbatim: "—") }
    }
    /// Remote avatar comes only from the already-loaded user-info `avatar` URL (https only);
    /// anything else, or a load failure, keeps the lettermark.
    static func remoteAvatarURL(_ raw: String?) -> URL? {
        let text = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.lowercased().hasPrefix("https://"), let url = URL(string: text), url.host != nil else { return nil }
        return url
    }
    private var lettermark: some View {
        let nickname = snapshot?.nickname ?? account.nickname
        return ZStack {
            Circle().fill(.tint.opacity(0.15))
            if let initial = nickname.first { Text(verbatim: String(initial)).font(.title2.weight(.semibold)) }
            else { Image(systemName: "person.fill").font(.title2) }
        }
    }
    private var avatar: some View {
        Group {
            if let url = Self.remoteAvatarURL(snapshot?.avatar) {
                AsyncImage(url: url) { image in
                    switch image {
                    case .success(let loaded): loaded.resizable().scaledToFill().clipShape(Circle())
                    default: lettermark
                    }
                }
            } else { lettermark }
        }.frame(width: 56, height: 56).accessibilityHidden(true)
    }
    private func stat(_ value: Int?, id: String, label: () -> Text) -> some View {
        VStack(spacing: 2) {
            Text(verbatim: value.map(String.init) ?? "—").font(.headline.monospacedDigit())
            label().font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity).accessibilityElement(children: .combine)
        .accessibilityIdentifier("member.card.\(id)")
    }

    private func load() async {
        let scope = reader.scope
        guard reader.isSignedIn else { phase = .failed(signedOut: true); return }
        guard reader.isConfigured, reader.roleInfoAvailable else { phase = .failed(signedOut: false); return }
        if snapshot == nil { phase = .loading }
        do {
            let value = try await reader.identity()
            guard scope == reader.scope else { return }
            phase = .ready(value)
            // Streak is shown only once the identity counters are ready, as the source does.
            if value.countersReady, let growth, growth.isConfigured, growth.isAuthenticated,
               let overview = try? await growth.overview(), scope == reader.scope {
                level = overview.center.value?.level ?? overview.progress.value?.level
                streakDays = overview.progress.value?.streakDays
            }
        } catch is CancellationError {
        } catch {
            guard scope == reader.scope else { return }
            phase = .failed(signedOut: error as? APIError == .unauthorized)
        }
    }
}

/// 关于 → 当前权益, built from `/api/role/info` like the source `buildBenefits`.
@MainActor struct MemberBenefitsSection: View {
    let reader: any MemberHomeReading
    var earningsDestination: (() -> AnyView)? = nil
    enum Phase: Equatable { case loading, ready([MemberBenefit]), unavailable, failed }
    @State private var phase: Phase = .loading

    var body: some View {
        Section {
            switch phase {
            case .loading:
                ProgressView().accessibilityIdentifier("member.benefits.loading")
            case .unavailable:
                Text("member.benefits.unavailable", tableName: "MemberProfile").foregroundStyle(.secondary)
                    .accessibilityIdentifier("member.benefits.unavailable")
            case .failed:
                VStack(alignment: .leading) {
                    Text("member.benefits.failed", tableName: "MemberProfile").foregroundStyle(.secondary)
                    Button { Task { await load() } } label: { Text("member.card.retry", tableName: "MemberProfile") }
                        .accessibilityIdentifier("member.benefits.retry")
                }.accessibilityIdentifier("member.benefits.failed")
            case .ready(let rows):
                ForEach(rows) { row in
                    if row.opensEarnings, let earningsDestination {
                        NavigationLink { earningsDestination() } label: { MemberBenefitRow(benefit: row) }
                            .accessibilityIdentifier("member.benefit.\(row.id)")
                    } else {
                        MemberBenefitRow(benefit: row).accessibilityIdentifier("member.benefit.\(row.id)")
                    }
                }
            }
        } header: { Text("member.benefits.title", tableName: "MemberProfile") }
        .task(id: reader.scope) { await load() }
    }

    private func load() async {
        let scope = reader.scope
        guard reader.isSignedIn, reader.roleInfoAvailable else { phase = .unavailable; return }
        phase = .loading
        do {
            let info = try await reader.roleInfo()
            guard scope == reader.scope else { return }
            phase = .ready(info.benefits)
        } catch is CancellationError {
        } catch {
            guard scope == reader.scope else { return }
            phase = error as? APIError == .notConfigured ? .unavailable : .failed
        }
    }
}

struct MemberBenefitRow: View {
    let benefit: MemberBenefit
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: benefit.unlocked ? "checkmark.circle.fill" : "lock.fill")
                .foregroundStyle(benefit.unlocked ? Color.accentColor : Color.secondary)
            label.foregroundStyle(benefit.unlocked ? Color.primary : Color.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(benefit.unlocked ? Text("member.benefit.unlocked", tableName: "MemberProfile")
                                              : Text("member.benefit.locked", tableName: "MemberProfile"))
    }
    @ViewBuilder private var label: some View {
        switch benefit.kind {
        case .publishRoutes:
            HStack(spacing: 4) {
                Text("member.benefit.publishRoutes", tableName: "MemberProfile")
                switch benefit.routeLimit {
                case .limited(let count): Text(verbatim: "\(count)")
                default: Text("member.benefit.unlimited", tableName: "MemberProfile")
                }
            }
        case .publishCoupons: Text("member.benefit.publishCoupons", tableName: "MemberProfile")
        case .redeemCoupons: Text("member.benefit.redeemCoupons", tableName: "MemberProfile")
        case .branching: Text("member.benefit.branching", tableName: "MemberProfile")
        case .gameMechanics: Text("member.benefit.gameMechanics", tableName: "MemberProfile")
        case .openAsNode: Text("member.benefit.openAsNode", tableName: "MemberProfile")
        case .medalDesign: Text("member.benefit.medalDesign", tableName: "MemberProfile")
        case .createGroup: Text("member.benefit.createGroup", tableName: "MemberProfile")
        case .earnings: Text("member.benefit.earnings", tableName: "MemberProfile")
        }
    }
}
