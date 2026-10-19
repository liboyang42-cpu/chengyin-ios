import SwiftUI

/// Source 邀请记录 failure states. Server messages stay with the generic social issue view;
/// this view only chooses the page's own title and hint and offers retry for ordinary failures.
struct ProfileInviteHistoryIssueView: View {
    let error: Error
    var retry: (() -> Void)? = nil
    var body: some View {
        let kind = ProfileInviteHistoryIssueKind(error)
        VStack(alignment: .leading, spacing: 6) {
            Label(LocalizedStringKey(kind.titleKey), systemImage: "exclamationmark.circle").font(.subheadline.weight(.semibold))
            if let detail = kind.detailKey { Text(LocalizedStringKey(detail)).font(.footnote).foregroundStyle(.secondary) }
            if kind.canRetry, let retry { Button("action.retry", action: retry) }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("profile.inviteHistory.issue")
    }
}

/// Source empty state: 还没有人接受你的邀请 with its hint.
struct ProfileInviteHistoryEmptyView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("profile.inviteHistory.empty").font(.subheadline.weight(.semibold))
            Text("profile.inviteHistory.emptyHint").font(.footnote).foregroundStyle(.secondary)
        }.accessibilityElement(children: .combine).accessibilityIdentifier("profile.inviteHistory.empty")
    }
}

/// Source summary 累计邀请 {total} 人; absent until the server reports a total.
struct ProfileInviteHistorySummaryLine: View {
    let total: Int?
    var body: some View {
        if let total {
            Text("profile.inviteHistoryP2.summary \(total)").font(.headline)
                .accessibilityIdentifier("profile.inviteHistory.summary")
        }
    }
}
