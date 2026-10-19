import SwiftUI

/// Mini-program `pages/team/detail` / `pages/team/join` header, state shell and notes.
/// Presentation only; every action still goes through `TeamScreenModel` and the review sheet.
struct TeamPageHeader: View {
    let detail: TeamDetail
    let kind: TeamPageKind
    var confirmedJoinMode: TeamJoinMode? = nil
    @Environment(\.locale) private var locale
    private var chinese: Bool { locale.language.languageCode?.identifier == "zh" }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if kind == .invitation {
                Text("team.page.eyebrow").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text("team.page.inviteExplainer").fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("teamPage.inviteExplainer")
            } else {
                Text(LocalizedStringKey(detail.team.status.key)).font(.caption.weight(.semibold))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(TeamPagePresentation.statusIsLive(detail.team.status) ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12), in: Capsule())
                    .accessibilityIdentifier("teamPage.status")
                HStack(spacing: 4) {
                    Text(LocalizedStringKey(TeamPagePresentation.modeKey(confirmedJoinMode ?? detail.team.joinMode)))
                    Text(verbatim: "·").accessibilityHidden(true)
                    Text("team.page.noEffectOnActivity")
                }.font(.footnote).foregroundStyle(.secondary).accessibilityElement(children: .combine)
                    .accessibilityIdentifier("teamPage.subtitle")
            }
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 2) {
                    if let joined = detail.team.joinedCount, let max = detail.team.maxMembers { Text(verbatim: "\(joined) / \(max)").font(.headline) }
                    else { Text(verbatim: "—").font(.headline) }
                    Text("team.members.count").font(.caption).foregroundStyle(.secondary)
                }.accessibilityElement(children: .combine)
                VStack(alignment: .leading, spacing: 2) {
                    if kind == .invitation { Text("team.page.inviteOnlyMethod").font(.headline) }
                    else if let start = TeamPagePresentation.startText(detail.team.expireTime, chinese: chinese) { Text(verbatim: start).font(.headline) }
                    else { Text("team.page.startPending").font(.headline) }
                    Text(kind == .invitation ? "team.mode.title" : "team.sessionStart").font(.caption).foregroundStyle(.secondary)
                }.accessibilityElement(children: .combine).accessibilityIdentifier("teamPage.meta")
            }
            if kind == .invitation {
                Text("team.join.consequence").font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TeamPageStateView: View {
    let state: TeamPageState
    var signIn: (() -> Void)?
    var reload: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: state.kind == .signIn ? "person.crop.circle.badge.questionmark" : "exclamationmark.triangle")
                .font(.largeTitle).foregroundStyle(.secondary).accessibilityHidden(true)
            Text(LocalizedStringKey(state.titleKey)).font(.headline).multilineTextAlignment(.center)
                .accessibilityIdentifier("teamPage.state.title")
            Text(LocalizedStringKey(state.detailKey)).font(.footnote).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            if let key = state.actionKey, let action = handler {
                Button(LocalizedStringKey(key), action: action).buttonStyle(.borderedProminent).frame(minHeight: 44)
                    .accessibilityIdentifier("teamPage.state.action")
            }
        }.padding().frame(maxWidth: .infinity)
    }
    private var handler: (() -> Void)? {
        switch state.action {
        case .goBack: return { dismiss() }
        case .signIn: return signIn
        case .reload: return reload
        case .none: return nil
        }
    }
}

struct TeamStaleBanner: View {
    let title: String
    let detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(LocalizedStringKey(title), systemImage: "arrow.clockwise.circle").font(.subheadline.weight(.semibold))
            Text(LocalizedStringKey(detail)).font(.footnote).foregroundStyle(.secondary)
        }.padding().frame(maxWidth: .infinity, alignment: .leading)
            .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            .accessibilityElement(children: .combine).accessibilityIdentifier("teamPage.stale")
    }
}

/// The source join page's disabled CTA for a full or ended team.
struct TeamClosedInvitationButton: View {
    let cta: TeamInvitationCTA
    var body: some View {
        Button {} label: { Text(LocalizedStringKey(cta.key)).frame(maxWidth: .infinity, minHeight: 44) }
            .buttonStyle(.bordered).disabled(true).accessibilityIdentifier("teamPage.closedInvitation")
    }
}
