import SwiftUI

/// Labels two different recorded facts without deriving either from the other.
struct ProfileInviteTimelineDates: View {
    let invitation: ProfileInviteTimestamp?
    let reward: ProfileInviteTimestamp?
    let hasReward: Bool
    @Environment(\.locale) private var locale
    @Environment(\.timeZone) private var timeZone
    init(invitationTime: String?, reward: SocialInviteReward?) {
        invitation = ProfileInviteTimeline.timestamp(invitationTime)
        self.reward = ProfileInviteTimeline.timestamp(reward?.createdAt)
        hasReward = reward != nil
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            LabeledContent("profile.inviteTimeline.invitationTime") {
                if let invitation { Text(verbatim: Self.display(invitation, locale: locale, timeZone: timeZone)) }
                else { Text("social.invites.timeUnknown") }
            }.accessibilityIdentifier("profile.inviteTimeline.invitationTime")
            // An available reward record never supplies a missing invitation date.
            if invitation == nil, hasReward {
                LabeledContent("profile.inviteTimeline.rewardTime") {
                    if let reward { Text(verbatim: Self.display(reward, locale: locale, timeZone: timeZone)) }
                    else { Text("profile.inviteTimeline.timeUnknown") }
                }.accessibilityIdentifier("profile.inviteTimeline.rewardTime")
            }
        }.font(.caption)
    }
    static func display(_ value: ProfileInviteTimestamp, locale: Locale, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = value.displayTimeZone(timeZone)
        formatter.dateStyle = .medium
        formatter.timeStyle = value.includesTime ? .short : .none
        return formatter.string(from: value.date)
    }
}
