import SwiftUI

/// Source `pages/coop/invite-detail` "合作操作" card and bottom action bar. Every action opens the existing
/// dormant request review (`CoopFlowRequestPreview` / handle, perk and review editors); none dispatches.
@MainActor struct CooperationInviteActionSections: View {
    let view: CooperationInvitePresentation
    let peerReader: (any CoopFlowReading)?
    private var invite: CooperationInvite { view.invite }
    var body: some View {
        if view.showsContactPartner, let peerReader { accepted(peerReader) }
        Section {
            switch view.footer {
            case .legacy: Text("cooperation.detail.footer.legacy").foregroundStyle(.secondary)
            case .decide:
                handle(.accept, label: "cooperation.detail.accept")
                handle(.reject, label: "cooperation.detail.reject")
                Text("cooperation.detail.reply.hint").font(.footnote).foregroundStyle(.secondary)
            case .withdraw:
                handle(.cancel, label: "cooperation.detail.withdraw")
                Text("cooperation.detail.withdraw.hint").font(.footnote).foregroundStyle(.secondary)
            case .deposit:
                Button("cooperation.detail.deposit.pay") {}.disabled(true).accessibilityIdentifier("cooperation.detail.deposit.pay")
                Text("cooperation.financeUnavailable").font(.footnote).foregroundStyle(.secondary)
            case .ongoing(let frozen):
                Text(LocalizedStringKey(frozen ? "cooperation.detail.footer.ongoingFrozen" : "cooperation.detail.footer.ongoing")).foregroundStyle(.secondary)
            case .inactive: Text("cooperation.detail.footer.inactive").foregroundStyle(.secondary)
            }
        }.accessibilityIdentifier("cooperation.detail.footer")
    }

    @ViewBuilder private func accepted(_ reader: any CoopFlowReading) -> some View {
        Section("cooperation.detail.actions") {
            if let scope = view.projectScope, let topic = invite.topicId {
                LabeledContent { Text(verbatim: "#" + String(topic)) } label: { Text("cooperation.detail.project") }
                    .accessibilityIdentifier("cooperation.detail.project.\(scope.rawValue)")
            }
            NavigationLink { CoopFlowRequestPreview(operation: .contact(inviteID: invite.id)) } label: { Text("cooperation.detail.contactPartner") }
                .accessibilityIdentifier("cooperation.detail.contactPartner")
            if view.showsPerkDeclaration {
                NavigationLink { CoopFlowPerkPicker(reader: reader, inviteID: invite.id) } label: { Text("cooperation.detail.declarePerks") }
                    .accessibilityIdentifier("cooperation.detail.declarePerks")
            }
            if view.showsReview, let member = view.revieweeID, let topic = invite.topicId, member != reader.session?.accountID {
                CooperationInviteReviewRow(reader: reader, memberID: member, topicID: topic, partnerName: invite.partner?.name)
            }
            if view.cancelLocked {
                VStack(alignment: .leading, spacing: 2) {
                    Text("cooperation.detail.cancelAccepted").foregroundStyle(.secondary)
                    Text("cooperation.detail.cancelLocked").font(.footnote).foregroundStyle(.secondary)
                }.accessibilityElement(children: .combine).accessibilityIdentifier("cooperation.detail.cancelLocked")
            } else {
                NavigationLink { CoopFlowHandleEditor(inviteID: invite.id, action: .cancel, currentStatus: 1) } label: {
                    Text("cooperation.detail.cancelAccepted").foregroundStyle(.red)
                }.accessibilityIdentifier("cooperation.detail.cancelAccepted")
            }
        }
    }
    private func handle(_ action: CoopFlowHandle, label: String) -> some View {
        NavigationLink { CoopFlowHandleEditor(inviteID: invite.id, action: action, currentStatus: invite.status ?? 0) } label: { Text(LocalizedStringKey(label)) }
            .accessibilityIdentifier("cooperation.detail.handle.\(action.rawValue)")
    }
}

/// Shows "已评价 ★…" when this viewer already reviewed the topic (source `loadMyReview`), else the review editor.
@MainActor struct CooperationInviteReviewRow: View {
    let reader: any CoopFlowReading
    let memberID: Int
    let topicID: Int
    let partnerName: String?
    @State private var rating: Int?
    @State private var loadedSession: CoopFlowSession?
    var body: some View {
        Group {
            if let rating, loadedSession == reader.session {
                LabeledContent { Text(verbatim: String(repeating: "★", count: rating)) } label: { Text("cooperation.detail.reviewed") }
                    .accessibilityIdentifier("cooperation.detail.reviewed")
            } else {
                NavigationLink { CoopFlowReviewEditor(topicID: topicID, memberID: memberID, partnerName: partnerName ?? "") } label: { Text("cooperation.detail.review") }
                    .accessibilityIdentifier("cooperation.detail.review")
            }
        }
        .task(id: "\(reader.session?.accountID ?? 0):\(reader.session?.epoch ?? 0):\(memberID):\(topicID)") {
            rating = nil; loadedSession = nil
            guard let session = reader.session else { return }
            // A failed summary read only leaves the review entry available; it never claims a rating.
            guard let summary = try? await reader.read(.reviewSummary(memberID: memberID)), !Task.isCancelled, reader.session == session else { return }
            rating = CooperationInvitePresentation.myRating(summary: summary, me: session.accountID, topicID: topicID); loadedSession = session
        }
    }
}
