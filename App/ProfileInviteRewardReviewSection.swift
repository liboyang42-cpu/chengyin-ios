import SwiftUI

@MainActor struct ProfileInviteRewardReviewSection: View {
    let review: ProfileInviteRewardReview
    let isLoading: Bool
    let reload: () -> Void
    var body: some View {
        Section("profile.inviteRewards.title") {
            LabeledContent("profile.inviteRewards.total") {
                if let points = review.cumulativePoints {
                    Text(verbatim: NSDecimalNumber(decimal: points).stringValue)
                        .accessibilityIdentifier("profile.inviteRewards.cumulative")
                } else {
                    Text("social.invites.synchronizing").accessibilityIdentifier("profile.inviteRewards.pending")
                }
            }
            if review.ledgerState != .complete {
                Text("profile.inviteRewards.incomplete").font(.footnote)
                    .accessibilityIdentifier("profile.inviteRewards.incomplete")
                Button("profile.inviteRewards.reload", action: reload).disabled(isLoading)
                    .accessibilityIdentifier("profile.inviteRewards.reload")
            }
            Text("profile.inviteRewards.monthScope").font(.caption).foregroundStyle(.secondary)
        }
    }
}
struct ProfileInviteMonthReward: View {
    let month: ProfileInviteRewardReview.Month
    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            if month.displaysPoints, let points = month.earnedPoints {
                Text(verbatim: "+" + NSDecimalNumber(decimal: points).stringValue)
                Text(month.isPartial ? "profile.inviteRewards.partialPoints" : "social.invites.points")
            } else {
                Text(verbatim: String(month.loadedMemberCount))
                Text("profile.inviteRewards.loadedPeople")
            }
        }.font(.caption).accessibilityElement(children: .combine)
            .accessibilityIdentifier("profile.inviteRewards.month")
    }
}
