import SwiftUI

/// Mini-program pages/club/governance + pages/club/roles presentation. Every action is an
/// existing `edit` route handed in by the read view; nothing here reads, writes or authorizes.
enum ClubOpsGovernanceCopy {
    static func text(_ key: String) -> Text { Text(LocalizedStringKey(key), tableName: "ClubOpsGovernance") }
    static func source(_ source: ClubOpsBanSource) -> Text { text(source == .platform ? "clubOpsGov.source.platform" : "clubOpsGov.source.club") }
    static func time(_ value: String?) -> Text {
        if let value { return Text(verbatim: value) }
        return text("clubOpsGov.timeUnknown")
    }
    static func expiry(_ expiry: ClubOpsBanExpiry) -> Text {
        switch expiry {
        case .until(let value): return Text("clubOpsGov.until \(value)", tableName: "ClubOpsGovernance")
        case .platformPermanent: return text("clubOpsGov.platformPermanent")
        case .unknown: return text("clubOpsGov.timeUnknown")
        }
    }
    static func member(_ name: String?, id: Int) -> Text {
        if let name { return Text(verbatim: name) }
        return Text("clubOpsGov.memberNumber \(id)", tableName: "ClubOpsGovernance")
    }
    static let separator = Text(verbatim: " · ")
    /// `{来源} · {时间} · {至…|平台永久封禁}[ · 仅平台可解封]`, one description line as in the mini-program row.
    static func banLine(source: ClubOpsBanSource, bannedAt: String?, expiry: ClubOpsBanExpiry, platformOnly: Bool = false) -> Text {
        var line: Text = self.source(source)
        line = line + separator + time(bannedAt)
        line = line + separator + self.expiry(expiry)
        if platformOnly { line = line + separator + text("clubOpsGov.platformOnly") }
        return line
    }
}

private struct ClubOpsTag: View {
    let label: Text
    var tint: Color = .accentColor
    var body: some View {
        label.font(.caption.weight(.semibold)).foregroundStyle(tint)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

struct ClubOpsBanSection: View {
    let list: ClubOpsBanList
    let unban: (ClubOpsBanRow) -> AnyView
    var body: some View {
        Section {
            if list.rows.isEmpty {
                ClubOpsGovernanceCopy.text("clubOpsGov.bans.empty").foregroundStyle(.secondary).accessibilityIdentifier("clubOpsGov.bans.empty")
            }
            ForEach(list.rows) { row in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("clubOpsGov.banTarget \(ClubOpsGovernanceCopy.member(row.nickname, id: row.targetMemberID))", tableName: "ClubOpsGovernance").font(.headline)
                        Spacer()
                        ClubOpsTag(label: ClubOpsGovernanceCopy.text("clubOpsGov.banStatus." + row.status.rawValue), tint: row.status == .active ? .red : .secondary)
                    }
                    ClubOpsGovernanceCopy.banLine(source: row.source, bannedAt: row.bannedAt, expiry: row.expiry, platformOnly: row.platformOnly)
                        .font(.footnote).foregroundStyle(.secondary)
                    if let note = row.unbanReason {
                        Text("clubOpsGov.unbanNote \(note)", tableName: "ClubOpsGovernance").font(.footnote).foregroundStyle(.secondary)
                    }
                    if row.unbanSeed != nil { unban(row) }
                }.accessibilityIdentifier("clubOpsGov.ban.\(row.id)")
            }
        } header: { Text("club.gov.bans") }
    }
}

struct ClubOpsGovernanceMembersSection: View {
    let roster: ClubOpsGovernanceMembers
    let ban: (ClubOpsGovernanceMember) -> AnyView
    let transfer: (ClubOpsGovernanceMember) -> AnyView
    var body: some View {
        Section {
            if roster.members.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ClubOpsGovernanceCopy.text("clubOpsGov.members.empty").font(.headline)
                    ClubOpsGovernanceCopy.text("clubOpsGov.members.emptyBody").font(.footnote).foregroundStyle(.secondary)
                }.accessibilityIdentifier("clubOpsGov.members.empty")
            }
            ForEach(roster.members) { member in
                VStack(alignment: .leading, spacing: 6) {
                    ClubOpsGovernanceCopy.member(member.nickname, id: member.id).font(.headline)
                    ban(member)
                    if roster.viewerIsOwner {
                        transfer(member)
                        ClubOpsGovernanceCopy.text("clubOpsGov.transfer.hint").font(.footnote).foregroundStyle(.secondary)
                    }
                }.accessibilityIdentifier("clubOpsGov.member.\(member.id)")
            }
        } header: { ClubOpsGovernanceCopy.text("clubOpsGov.members.title") }
    }
}

struct ClubOpsCaseSection: View {
    let list: ClubOpsCaseList
    let report: AnyView?
    let appeal: AnyView?
    var body: some View {
        if list.appealMode {
            // Mini governance `mode=appeal` page title, reached by a viewer this club has banned.
            Section {
                ClubOpsGovernanceCopy.text("clubOpsGov.appeal.mode").font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader).accessibilityIdentifier("clubOpsGov.appeal.mode")
            }
        }
        if list.canReport, let report {
            Section {
                ClubOpsGovernanceCopy.text("clubOpsGov.report.note").font(.footnote).foregroundStyle(.secondary)
                report
            } header: { ClubOpsGovernanceCopy.text("clubOpsGov.report.title") }
        }
        switch list.appeal {
        case .none:
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    ClubOpsGovernanceCopy.text("clubOpsGov.appeal.empty").font(.headline)
                    ClubOpsGovernanceCopy.text("clubOpsGov.appeal.emptyBody").font(.footnote).foregroundStyle(.secondary)
                }.accessibilityIdentifier("clubOpsGov.appeal.empty")
            } header: { ClubOpsGovernanceCopy.text("clubOpsGov.appeal.title") }
        case .ban(let ban):
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    ClubOpsGovernanceCopy.text("clubOpsGov.appeal.current").font(.headline)
                    ClubOpsGovernanceCopy.banLine(source: ban.source, bannedAt: ban.bannedAt, expiry: ban.expiry).font(.footnote).foregroundStyle(.secondary)
                    if let reason = ban.reason {
                        Text("clubOpsGov.banReason \(reason)", tableName: "ClubOpsGovernance").font(.footnote).foregroundStyle(.secondary)
                    }
                }.accessibilityIdentifier("clubOpsGov.appeal.ban")
                ClubOpsGovernanceCopy.text("clubOpsGov.appeal.note").font(.footnote).foregroundStyle(.secondary)
                if let appeal { appeal }
            } header: { ClubOpsGovernanceCopy.text("clubOpsGov.appeal.title") }
        case .unknown: EmptyView()
        }
        Section {
            if list.rows.isEmpty {
                ClubOpsGovernanceCopy.text("clubOpsGov.cases.empty").foregroundStyle(.secondary).accessibilityIdentifier("clubOpsGov.cases.empty")
            }
            ForEach(list.rows) { row in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Self.type(row.kind).font(.headline)
                        if let reason = row.reason { Text(verbatim: reason).font(.subheadline) }
                        Text("clubOpsGov.submittedAt \(ClubOpsGovernanceCopy.time(row.submittedAt))", tableName: "ClubOpsGovernance").font(.footnote).foregroundStyle(.secondary)
                        if let decision = row.decisionReason {
                            Text("clubOpsGov.decision \(decision)", tableName: "ClubOpsGovernance").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    ClubOpsTag(label: ClubOpsGovernanceCopy.text("clubOpsGov.caseStatus." + row.status.rawValue))
                }.accessibilityIdentifier("clubOpsGov.case.\(row.id)")
            }
        } header: { Text("club.gov.cases") }
    }
    static func type(_ kind: ClubOpsCaseKind) -> Text {
        switch kind {
        case .appeal: return ClubOpsGovernanceCopy.text("clubOpsGov.caseType.APPEAL")
        case .report(let target): return ClubOpsGovernanceCopy.text("clubOpsGov.caseType.REPORT_" + target)
        }
    }
}

/// Display-only names for the roles page. A failed or stale member read only loses names.
@MainActor final class ClubOpsRoleMemberNames: ObservableObject {
    @Published private(set) var snapshot: ClubGovernanceSnapshot?
    private var context: ClubGovernanceReadContext?
    func accepted(_ expected: ClubGovernanceReadContext) -> ClubGovernanceSnapshot? { context == expected ? snapshot : nil }
    func load(context expected: ClubGovernanceReadContext, access: any ClubGovernanceAccess) async {
        guard context != expected || snapshot == nil else { return }
        context = expected; snapshot = nil
        guard expected.identity?.isSignedIn == true, expected.identity == access.identity, access.isConfigured else { return }
        func check() throws {
            guard context == expected, expected.identity == access.identity,
                  expected.authorizationGeneration == access.authorizationGeneration, !Task.isCancelled else { throw CancellationError() }
        }
        guard let result = try? await access.read(.members, scope: expected.scope, options: [:], check: check),
              (try? check()) != nil, result.operation == .members, result.scope == expected.scope else { return }
        snapshot = result
    }
}

struct ClubOpsRoleSection: View {
    let roles: ClubGovernanceSnapshot
    let context: ClubGovernanceReadContext
    let access: any ClubGovernanceAccess
    let assign: AnyView
    let revoke: (ClubOpsRoleAssignmentRow) -> AnyView
    @StateObject private var names = ClubOpsRoleMemberNames()
    var body: some View {
        Group {
            if let roster = try? ClubOpsRoleRoster(roles: roles, members: names.accepted(context)) {
                content(roster)
            } else { Text("club.gov.malformed").accessibilityIdentifier("clubOpsGov.roles.malformed") }
        }
        .task(id: context) { await names.load(context: context, access: access) }
    }
    /// `{角色说明}[ · 至 MM-DD]`; the summary keys are the existing role-picker copy.
    static func summary(_ row: ClubOpsRoleAssignmentRow) -> Text {
        let summary = Text(LocalizedStringKey(row.summaryKey))
        guard let day = row.expiresMonthDay else { return summary }
        return summary + Text("clubOpsGov.roles.until \(day)", tableName: "ClubOpsGovernance")
    }
    @ViewBuilder private func content(_ roster: ClubOpsRoleRoster) -> some View {
        Section {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    if let owner = roster.ownerName { Text(verbatim: owner).font(.headline) }
                    else { Text("club.gov.role.CLUB_OWNER").font(.headline) }
                    ClubOpsGovernanceCopy.text("clubOpsGov.roles.ownerSummary").font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                ClubOpsTag(label: Text("club.gov.role.CLUB_OWNER"))
            }.accessibilityIdentifier("clubOpsGov.roles.owner")
            ForEach(roster.assignments) { row in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        ClubOpsGovernanceCopy.member(row.memberName, id: row.targetMemberID).font(.headline)
                        Spacer()
                        ClubOpsTag(label: row.roleName.map { Text(verbatim: $0) } ?? ClubOpsGovernanceCopy.text("clubOpsGov.roles.roleFallback"))
                    }
                    Self.summary(row).font(.footnote).foregroundStyle(.secondary)
                    revoke(row)
                }.accessibilityIdentifier("clubOpsGov.roles.assignment.\(row.id)")
            }
        } header: { Text("club.gov.assignments") }
        Section {
            if roster.delegableMemberCount == 0 {
                VStack(alignment: .leading, spacing: 4) {
                    ClubOpsGovernanceCopy.text("clubOpsGov.roles.empty").font(.headline)
                    ClubOpsGovernanceCopy.text("clubOpsGov.roles.emptyBody").font(.footnote).foregroundStyle(.secondary)
                }.accessibilityIdentifier("clubOpsGov.roles.empty")
            } else {
                ClubOpsGovernanceCopy.text("clubOpsGov.roles.assign.caption").font(.footnote).foregroundStyle(.secondary)
                assign
            }
        } header: { ClubOpsGovernanceCopy.text("clubOpsGov.roles.assign.title") }
        Section { ClubOpsGovernanceCopy.text("clubOpsGov.roles.footer").font(.footnote).foregroundStyle(.secondary) }
    }
}

/// Page-specific denial copy shown beside the generic failure; `.access` offers the own-case read a banned member keeps.
struct ClubOpsGovernanceDeniedNote: View {
    let operation: ClubGovernanceRead
    let cases: AnyView?
    var body: some View {
        switch operation {
        case .bans, .members:
            note("clubOpsGov.denied.title", "clubOpsGov.denied.body")
        case .roles:
            note("clubOpsGov.roles.denied.title", "clubOpsGov.roles.denied.body")
        case .audienceCounts:
            Section { ClubOpsNotifyDeniedText() }
        case .access:
            if let cases { Section { ClubOpsGovernanceCopy.text("clubOpsGov.appeal.entry").font(.footnote); cases } }
        default: EmptyView()
        }
    }
    private func note(_ title: String, _ body: String) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                ClubOpsGovernanceCopy.text(title).font(.headline)
                ClubOpsGovernanceCopy.text(body).font(.footnote).foregroundStyle(.secondary)
            }.accessibilityIdentifier("clubOpsGov.denied." + operation.rawValue)
        }
    }
}

/// Copy that frames the existing review form; it never changes fields, anchors or gates.
struct ClubOpsGovernanceFormNotes: View {
    let operation: ClubGovernanceMutation
    let seed: [String: ClubGovernanceValue]
    static func applies(_ operation: ClubGovernanceMutation) -> Bool { [.ban, .unban, .transferOwner, .report, .appeal, .revokeRole].contains(operation) }
    var body: some View {
        let nickname = seed["targetNickname"]?.string
        switch operation {
        case .ban:
            if let nickname { Text("clubOpsGov.ban.title \(nickname)", tableName: "ClubOpsGovernance").font(.headline) }
            ClubOpsGovernanceCopy.text("clubOpsGov.ban.consequence")
            ClubOpsGovernanceCopy.text("clubOpsGov.ban.reasonHint").font(.footnote).foregroundStyle(.secondary)
        case .unban:
            ClubOpsGovernanceCopy.text("clubOpsGov.unban.reasonHint").font(.footnote).foregroundStyle(.secondary)
        case .transferOwner:
            if let nickname { Text("clubOpsGov.transfer.title \(nickname)", tableName: "ClubOpsGovernance").font(.headline) }
            ClubOpsGovernanceCopy.text("clubOpsGov.transfer.hint")
            ClubOpsGovernanceCopy.text("clubOpsGov.transfer.reasonHint").font(.footnote).foregroundStyle(.secondary)
        case .report:
            ClubOpsGovernanceCopy.text("clubOpsGov.report.note")
        case .appeal:
            ClubOpsGovernanceCopy.text("clubOpsGov.appeal.note")
        case .revokeRole:
            if let role = seed["roleName"]?.string { Text("clubOpsGov.roles.revoke.title \(role)", tableName: "ClubOpsGovernance").font(.headline) }
            ClubOpsGovernanceCopy.text("clubOpsGov.roles.revoke.body")
            ForEach(["clubOpsGov.roles.revoke.consequence1", "clubOpsGov.roles.revoke.consequence2", "clubOpsGov.roles.revoke.consequence3"], id: \.self) { key in
                Label { ClubOpsGovernanceCopy.text(key).font(.footnote) } icon: { Image(systemName: "exclamationmark.triangle") }
            }
        default: EmptyView()
        }
    }
}

/// 7/30/90-day ban term. The draft turns the selection into an absolute epoch only when a review is prepared.
struct ClubOpsBanDurationPicker: View {
    @Binding var days: String
    var body: some View {
        Picker(selection: $days) {
            ForEach(ClubGovernanceFormDraft.banDayChoices, id: \.self) { value in
                Text("clubOpsGov.days \(value)", tableName: "ClubOpsGovernance").tag(String(value))
            }
        } label: { ClubOpsGovernanceCopy.text("clubOpsGov.duration") }
        .accessibilityIdentifier("club.gov.input.banDays")
    }
}

struct ClubOpsBanExpiryReview: View {
    let fields: [String: ClubGovernanceValue]
    var body: some View {
        if let value = fields["expiresAtEpochMs"], let text = ClubOpsGovernanceClock.minute(value) {
            LabeledContent { Text("clubOpsGov.until \(text)", tableName: "ClubOpsGovernance") } label: { ClubOpsGovernanceCopy.text("clubOpsGov.duration") }
                .accessibilityIdentifier("clubOpsGov.review.expiry")
        }
    }
}

/// Shown only inside the acknowledged receipt section, i.e. after a confirmed server acknowledgement.
struct ClubOpsGovernanceSuccess: View {
    let operation: ClubGovernanceMutation
    var body: some View {
        if let key = Self.key(operation) {
            ClubOpsGovernanceCopy.text(key).font(.headline).accessibilityIdentifier("clubOpsGov.success")
        }
    }
    static func key(_ operation: ClubGovernanceMutation) -> String? {
        switch operation {
        case .ban: return "clubOpsGov.success.ban"
        case .unban: return "clubOpsGov.success.unban"
        case .transferOwner: return "clubOpsGov.success.transfer"
        case .report, .appeal: return "clubOpsGov.success.case"
        case .assignRole: return "clubOpsGov.roles.success.assign"
        case .revokeRole: return "clubOpsGov.roles.success.revoke"
        default: return nil
        }
    }
}
