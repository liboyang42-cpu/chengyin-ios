import SwiftUI

/// Mini-program pages/club/join-requests + pages/club/notify copy. Display only; the existing
/// management/governance owners keep every read, confirmation, dispatch and uncertainty lock.
enum ClubOpsJoinNotifyCopy {
    static let table = "ClubOpsJoinNotify"
    static func text(_ key: String) -> Text { Text(LocalizedStringKey(key), tableName: table) }
    static func people(_ count: Int) -> Text { Text("clubOpsJN.notify.people \(count)", tableName: "ClubOpsJoinNotify") }
}

/// `N 条待审 · 可直接通过或拒绝`, or only the action line when nothing is pending.
struct ClubOpsJoinRequestsIntro: View {
    let count: Int
    var body: some View {
        Group {
            if let pending = ClubOpsJoinRequestPresentation.introPendingCount(count) {
                Text("clubOpsJN.join.intro.pending \(pending)", tableName: "ClubOpsJoinNotify")
            } else { Text("clubOpsJN.join.intro.none", tableName: "ClubOpsJoinNotify") }
        }
        .font(.footnote).foregroundStyle(.secondary)
        .accessibilityIdentifier("clubOpsJN.join.intro")
    }
}

/// Applicant name with the mini-program "城瘾玩家" fallback, and the quoted, decoded join message.
struct ClubOpsJoinRequestRowText: View {
    let request: ClubManagementRequest
    var body: some View {
        if let name = ClubOpsJoinRequestPresentation.displayName(request.nickname) { Text(verbatim: name) }
        else { Text("clubOpsJN.join.playerFallback", tableName: "ClubOpsJoinNotify") }
        if let quote = ClubOpsJoinRequestPresentation.quotedMessage(request.joinMessage) {
            Text(verbatim: quote).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                .accessibilityIdentifier("clubOpsJN.join.message.\(request.id)")
        }
    }
}

/// Mini-program confirmation consequences for approve and reject (`club.joinRequest.reject`).
struct ClubOpsJoinReviewNotes: View {
    let action: ClubManagementAction
    var body: some View {
        if action == .approve {
            Text("clubOpsJN.join.approve.body", tableName: "ClubOpsJoinNotify")
        } else {
            Label { Text("clubOpsJN.join.reject.notice", tableName: "ClubOpsJoinNotify") } icon: { Image(systemName: "bell") }
            Label { Text("clubOpsJN.join.reject.reapply", tableName: "ClubOpsJoinNotify") } icon: { Image(systemName: "clock") }
        }
    }
}

/// Optional reject reason, at most 500 characters after trimming (backend limit). Blank sends no reason.
struct ClubOpsJoinRejectReasonField: View {
    @Binding var text: String
    var body: some View {
        Section {
            TextField(text: $text, axis: .vertical) { Text("clubOpsJN.join.reason.placeholder", tableName: "ClubOpsJoinNotify") }
                .lineLimit(3...6)
                .accessibilityIdentifier("clubOpsJN.join.reason")
            HStack {
                if !ClubOpsJoinReviewReason.isValid(text) {
                    Text("clubOpsJN.join.reason.tooLong", tableName: "ClubOpsJoinNotify").foregroundStyle(.red)
                        .accessibilityIdentifier("clubOpsJN.join.reason.tooLong")
                }
                Spacer()
                Text(verbatim: "\(ClubOpsJoinReviewReason.count(text))/\(ClubOpsJoinReviewReason.maximumUTF16Count)")
                    .monospacedDigit().foregroundStyle(.secondary)
            }.font(.caption)
        } header: { Text("clubOpsJN.join.reason.title", tableName: "ClubOpsJoinNotify") }
    }
}
