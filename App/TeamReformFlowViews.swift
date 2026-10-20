import SwiftUI
import CoreImage.CIFilterBuiltins
import UIKit

/// Dormant reform-plan team flows (U02 friend invites, U05–U07 team-first meeting).
/// Hosts inject nothing by default, so release and session builds never show these entries.
/// Only DEBUG fixtures supply synthetic ports with `ReformWorldCapabilities.syntheticFixture`.
struct TeamReformHooks {
    var capabilities: ReformWorldCapabilities
    var inviteSender: @MainActor () -> (any TeamFriendInviteSending)?
    var meetingService: @MainActor () -> (any TeamMeetingServing)?
    /// Fixture stand-in for a decoded camera scan. Camera capture itself is not wired.
    var simulatedPeerCode: (@MainActor (Int) -> TeamMeetingChallenge?)? = nil
}
private struct TeamReformHooksKey: EnvironmentKey { static let defaultValue: TeamReformHooks? = nil }
extension EnvironmentValues {
    var teamReformHooks: TeamReformHooks? {
        get { self[TeamReformHooksKey.self] }
        set { self[TeamReformHooksKey.self] = newValue }
    }
}

enum TeamReformSheet: Identifiable {
    case invite(teamID: Int), meeting(teamID: Int)
    var id: String { switch self { case .invite(let id): return "invite-\(id)"; case .meeting(let id): return "meeting-\(id)" } }
}

/// Redraws after each flow step; the flows themselves are plain main-actor classes.
@MainActor final class TeamReformFlowBox<Flow: AnyObject>: ObservableObject {
    let flow: Flow
    init(_ flow: Flow) { self.flow = flow }
    func step(_ operation: (Flow) -> Void) { operation(flow); objectWillChange.send() }
    func run(_ operation: (Flow) async -> Void) async { objectWillChange.send(); await operation(flow); objectWillChange.send() }
}

struct TeamReformEntries: View {
    let detail: TeamDetail
    let hooks: TeamReformHooks?
    let open: (TeamReformSheet) -> Void
    var body: some View {
        if let hooks {
            if hooks.capabilities.allows(.friendMultiInvite), TeamFriendInviteFlow.eligible(detail) {
                Button { open(.invite(teamID: detail.team.id)) } label: { Label("teamReform.invite.open", systemImage: "person.2.badge.plus").frame(maxWidth: .infinity, minHeight: 44) }
                    .buttonStyle(.bordered).accessibilityIdentifier("teamReform.invite.open")
            }
            if hooks.capabilities.allows(.teamFirstMeeting), TeamMeetingFlow.mayOffer(detail) {
                Button { open(.meeting(teamID: detail.team.id)) } label: { Label("teamReform.meeting.open", systemImage: "person.line.dotted.person").frame(maxWidth: .infinity, minHeight: 44) }
                    .buttonStyle(.bordered).accessibilityIdentifier("teamReform.meeting.open")
            }
        }
    }
}

struct TeamReformSheetHost: View {
    let sheet: TeamReformSheet
    let hooks: TeamReformHooks
    var body: some View {
        switch sheet {
        case .invite(let teamID):
            TeamFriendInviteSheet(flow: TeamFriendInviteFlow(teamID: teamID, sender: hooks.inviteSender(), capabilities: hooks.capabilities))
        case .meeting(let teamID):
            TeamMeetingSheet(flow: TeamMeetingFlow(teamID: teamID, service: hooks.meetingService(), capabilities: hooks.capabilities),
                             simulatedPeerCode: hooks.simulatedPeerCode.map { make in { @MainActor in make(teamID) } })
        }
    }
}

@MainActor struct TeamFriendInviteSheet: View {
    @StateObject private var box: TeamReformFlowBox<TeamFriendInviteFlow>
    @Environment(\.dismiss) private var dismiss
    init(flow: TeamFriendInviteFlow) { _box = StateObject(wrappedValue: TeamReformFlowBox(flow)) }
    private var flow: TeamFriendInviteFlow { box.flow }
    var body: some View {
        NavigationStack {
            List {
                Section { Text("teamReform.dormantNotice").font(.footnote).foregroundStyle(.secondary) }
                switch flow.phase {
                case .closed: Text("teamReform.unavailable").accessibilityIdentifier("teamReform.invite.unavailable")
                case .loading: ProgressView("teamReform.loading")
                case .failed:
                    Text("teamReform.invite.loadFailed").accessibilityIdentifier("teamReform.invite.loadFailed")
                    Button("action.retry") { Task { await box.run { await $0.open() } } }.frame(minHeight: 44)
                case .ready: content
                }
            }.appNavigationTitle("teamReform.invite.title")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("team.close") { box.step { $0.close() }; dismiss() }.disabled(flow.busy) } }
                .interactiveDismissDisabled(flow.busy)
        }.task { await box.run { await $0.open() } }
    }
    @ViewBuilder private var content: some View {
        if let batch = flow.batch {
            Section {
                ForEach(flow.friends) { friend in
                    Button { box.step { $0.toggle(friend) } } label: {
                        HStack {
                            Text(verbatim: friend.displayName).foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: flow.isSelected(friend) ? "checkmark.circle.fill" : "circle").accessibilityHidden(true)
                        }.frame(minHeight: 44)
                    }.disabled(flow.busy || batch.phase == .sending || batch.phase == .finished)
                        .accessibilityAddTraits(flow.isSelected(friend) ? .isSelected : [])
                        .accessibilityIdentifier("teamReform.invite.friend.\(friend.friendId)")
                }
            } header: { Text("teamReform.invite.choose") } footer: {
                Text(verbatim: "\(batch.selected.count) / \(batch.maximum)").accessibilityIdentifier("teamReform.invite.count")
            }
            if flow.issue == .overLimit { Text("teamReform.invite.overLimit").foregroundStyle(.orange) }
            if let reviewed = flow.reviewed {
                Section("teamReform.invite.review") {
                    Text(verbatim: "\(reviewed.count)").font(.headline).accessibilityIdentifier("teamReform.invite.reviewCount")
                    ForEach(reviewed.names, id: \.self) { Text(verbatim: $0) }
                    Text("teamReform.invite.reviewNote").font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section {
                if batch.phase == .selecting {
                    Button("teamReform.invite.reviewAction") { box.step { $0.review() } }.frame(minHeight: 44)
                        .disabled(batch.selected.isEmpty || flow.busy).accessibilityIdentifier("teamReform.invite.reviewAction")
                }
                if batch.phase == .reviewed {
                    Button("teamReform.invite.send") { Task { await box.run { await $0.send() } } }.frame(minHeight: 44)
                        .buttonStyle(.borderedProminent).disabled(flow.busy).accessibilityIdentifier("teamReform.invite.send")
                }
                if flow.busy { ProgressView() }
            }
            if batch.phase == .finished { summary(batch) }
        }
    }
    @ViewBuilder private func summary(_ batch: FriendMultiInvite) -> some View {
        let summary = batch.summary
        Section("teamReform.invite.summary") {
            LabeledContent("teamReform.invite.sent") { Text(verbatim: "\(summary.sent)") }.accessibilityIdentifier("teamReform.invite.summary.sent")
            LabeledContent("teamReform.invite.rejected") { Text(verbatim: "\(summary.rejected)") }
            LabeledContent("teamReform.invite.retryable") { Text(verbatim: "\(summary.retryable)") }.accessibilityIdentifier("teamReform.invite.summary.retryable")
            LabeledContent("teamReform.invite.unknown") { Text(verbatim: "\(summary.unknown)") }.accessibilityIdentifier("teamReform.invite.summary.unknown")
            LabeledContent("teamReform.invite.revoked") { Text(verbatim: "\(summary.revoked)") }.accessibilityIdentifier("teamReform.invite.summary.revoked")
            if summary.unknown > 0 {
                Text("teamReform.invite.unknownNote").font(.footnote)
                Button("teamReform.invite.checkUnknown") { Task { await box.run { await $0.readBackUnknown() } } }
                    .frame(minHeight: 44).disabled(flow.busy).accessibilityIdentifier("teamReform.invite.checkUnknown")
            }
            if summary.retryable > 0 && summary.unknown == 0 {
                Button("teamReform.invite.retryFailed") { Task { await box.run { await $0.send() } } }
                    .frame(minHeight: 44).disabled(flow.busy).accessibilityIdentifier("teamReform.invite.retryFailed")
            }
        }
        Section("teamReform.invite.sentList") {
            ForEach(flow.friends.filter { batch.selected.contains($0) }) { friend in
                HStack {
                    Text(verbatim: friend.displayName)
                    Spacer()
                    switch batch.deliveries[friend.friendId] ?? .notSent {
                    case .sent:
                        if flow.revokeUnknown.contains(friend.friendId) { Text("teamReform.invite.revokeUnknown").font(.caption) }
                        Button("teamReform.invite.revoke", role: .destructive) { Task { await box.run { await $0.revoke(friendId: friend.friendId) } } }
                            .disabled(flow.busy).accessibilityIdentifier("teamReform.invite.revoke.\(friend.friendId)")
                    case .revoked: Text("teamReform.invite.revokedState").font(.caption).accessibilityIdentifier("teamReform.invite.revoked.\(friend.friendId)")
                    case .rejected: Text("teamReform.invite.rejected").font(.caption)
                    case .unknown: Text("teamReform.invite.unknown").font(.caption)
                    case .failed, .notSent: Text("teamReform.invite.retryable").font(.caption)
                    }
                }.frame(minHeight: 44)
            }
        }
    }
}

@MainActor struct TeamMeetingSheet: View {
    @StateObject private var box: TeamReformFlowBox<TeamMeetingFlow>
    let simulatedPeerCode: (@MainActor () -> TeamMeetingChallenge?)?
    @Environment(\.dismiss) private var dismiss
    init(flow: TeamMeetingFlow, simulatedPeerCode: (@MainActor () -> TeamMeetingChallenge?)?) {
        _box = StateObject(wrappedValue: TeamReformFlowBox(flow)); self.simulatedPeerCode = simulatedPeerCode
    }
    private var flow: TeamMeetingFlow { box.flow }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("teamReform.dormantNotice").font(.footnote).foregroundStyle(.secondary)
                    Text("teamReform.meeting.scope").font(.footnote).fixedSize(horizontal: false, vertical: true)
                }
                switch flow.phase {
                case .closed: Text("teamReform.unavailable").accessibilityIdentifier("teamReform.meeting.unavailable")
                case .loading: ProgressView("teamReform.loading")
                case .notEligible: Text("teamReform.meeting.notEligible").accessibilityIdentifier("teamReform.meeting.notEligible")
                case .failed:
                    Text("teamReform.meeting.loadFailed")
                    Button("action.retry") { Task { await box.run { await $0.open() } } }.frame(minHeight: 44)
                case .active: if let meeting = flow.meeting { active(meeting) }
                }
            }.appNavigationTitle("teamReform.meeting.title")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("team.close") { box.step { $0.close() }; dismiss() }.disabled(flow.busy) } }
                .interactiveDismissDisabled(flow.busy)
        }.task { await box.run { await $0.open() } }
    }
    @ViewBuilder private func active(_ meeting: TeamFirstMeeting) -> some View {
        Section {
            switch meeting.phase {
            case .realNameRequired:
                Text("teamReform.meeting.realName").fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("teamReform.meeting.realName")
                Button("teamReform.meeting.recheckRealName") { Task { await box.run { await $0.recheckRealName() } } }
                    .frame(minHeight: 44).disabled(flow.busy).accessibilityIdentifier("teamReform.meeting.recheckRealName")
            case .readyToMeet:
                Text("teamReform.meeting.ready")
                Button("teamReform.meeting.start") { Task { await box.run { await $0.startHandshake() } } }
                    .buttonStyle(.borderedProminent).frame(minHeight: 44).disabled(flow.busy).accessibilityIdentifier("teamReform.meeting.start")
            case .handshaking:
                handshake
            case .confirmationPending:
                Text("teamReform.meeting.pending").accessibilityIdentifier("teamReform.meeting.pending")
                Button("teamReform.meeting.checkResult") { Task { await box.run { await $0.readBackConfirmation() } } }
                    .frame(minHeight: 44).disabled(flow.busy).accessibilityIdentifier("teamReform.meeting.checkResult")
            case .met: Label("teamReform.meeting.met", systemImage: "checkmark.seal").accessibilityIdentifier("teamReform.meeting.met")
            case .cancelled:
                Label("teamReform.meeting.cancelled", systemImage: "xmark.octagon").accessibilityIdentifier("teamReform.meeting.cancelled")
                if flow.cancelUnknown { Text("teamReform.meeting.cancelUnknown").font(.footnote) }
            case .expired: Label("teamReform.meeting.expired", systemImage: "clock.badge.xmark")
            }
            if let issue = flow.scanIssue { Text(LocalizedStringKey(scanIssueKey(issue))).foregroundStyle(.orange).accessibilityIdentifier("teamReform.meeting.issue") }
        }
        if ![.met, .cancelled, .expired].contains(meeting.phase) {
            Section {
                Button("teamReform.meeting.cancel", role: .destructive) { Task { await box.run { await $0.cancel() } } }
                    .frame(minHeight: 44).disabled(flow.busy).accessibilityIdentifier("teamReform.meeting.cancel")
                Text("teamReform.meeting.cancelNote").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
    @ViewBuilder private var handshake: some View {
        Text("teamReform.meeting.showCode").fixedSize(horizontal: false, vertical: true)
        if let challenge = flow.myChallenge, !flow.myCodeExpired() {
            TeamMeetingCodeImage(payload: [challenge.meetingId, challenge.issuerMemberId, challenge.nonce, challenge.keyVersion, challenge.signature].joined(separator: "."))
                .frame(maxWidth: .infinity)
        } else { Text("teamReform.meeting.codeExpired") }
        Button("teamReform.meeting.refreshCode") { Task { await box.run { await $0.refreshMyCode() } } }
            .frame(minHeight: 44).disabled(flow.busy).accessibilityIdentifier("teamReform.meeting.refreshCode")
        ForEach(flow.handshakes, id: \.self) { method in
            Text(LocalizedStringKey(method == .dynamicQR ? "teamReform.meeting.methodQR" : "teamReform.meeting.methodNFC")).font(.footnote)
        }
        Text("teamReform.meeting.scannerNotWired").font(.footnote).foregroundStyle(.secondary)
        if let simulatedPeerCode {
            Button("teamReform.meeting.simulateScan") {
                Task { await box.run { flow in if let code = simulatedPeerCode() { await flow.submitScanned(code) } } }
            }.frame(minHeight: 44).disabled(flow.busy).accessibilityIdentifier("teamReform.meeting.simulateScan")
        }
    }
    private func scanIssueKey(_ issue: TeamMeetingFlow.ScanIssue) -> String {
        switch issue {
        case .wrongCode: return "teamReform.meeting.issue.wrongCode"
        case .expired: return "teamReform.meeting.issue.expired"
        case .replayed: return "teamReform.meeting.issue.replayed"
        case .malformed: return "teamReform.meeting.issue.malformed"
        case .outcomeUnknown: return "teamReform.meeting.issue.unknown"
        }
    }
}

/// Renders the server-issued opaque code locally; nothing is cached or shared.
private struct TeamMeetingCodeImage: View {
    let payload: String
    private var image: UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8); filter.correctionLevel = "M"
        guard let output = filter.outputImage,
              let bitmap = CIContext(options: [.cacheIntermediates: false]).createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: bitmap)
    }
    var body: some View {
        if let image {
            Image(uiImage: image).resizable().interpolation(.none).scaledToFit()
                .frame(maxWidth: 240).padding(16).background(.white)
                .accessibilityLabel(Text("teamReform.meeting.codeImage")).accessibilityIdentifier("teamReform.meeting.code")
        } else { Text("teamReform.meeting.codeExpired") }
    }
}
