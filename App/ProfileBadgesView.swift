import SwiftUI

@MainActor
struct ProfileBadgesView: View {
    let reader: any ProfileReading
    var body: some View {
        ProfileReadScreen(reader: reader, accessibilityPrefix: "profile.badges", load: { try await reader.profileBadges() }) { wall in
            if wall.isEmpty {
                ProfileEmptyState(title: "profile.badges.empty", hint: "profile.badges.emptyHint", symbol: "medal", identifier: "profile.badges.empty")
            } else {
                List {
                    if wall.isPartial {
                        Section {
                            Label {
                                Text("profile.badges.partial").accessibilityIdentifier("profile.badges.partial")
                            } icon: { Image(systemName: "exclamationmark.triangle") }
                            if let message = wall.medalFailureMessage, !message.isEmpty { Text(verbatim: message) }
                            Text("profile.badges.partialHint").foregroundStyle(.secondary)
                        }
                    }
                    if !wall.identities.isEmpty {
                        Section("profile.badges.identities") {
                            ForEach(Array(wall.identities.enumerated()), id: \.offset) { index, badge in
                                badgeLink(.identity(badge), identifier: "profile.badge.identity.\(index)")
                            }
                        }
                    }
                    if let medals = wall.medals {
                        let city = medals.filter { !$0.isAchievement }
                        let achievements = medals.filter(\.isAchievement)
                        if !city.isEmpty {
                            Section("profile.badges.medals") {
                                ForEach(Array(city.enumerated()), id: \.offset) { index, badge in
                                    badgeLink(.medal(badge), identifier: "profile.badge.medal.\(index)")
                                }
                            }
                        }
                        if !achievements.isEmpty {
                            Section("profile.badges.achievements") {
                                ForEach(Array(achievements.enumerated()), id: \.offset) { index, badge in
                                    badgeLink(.medal(badge), identifier: "profile.badge.achievement.\(index)")
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("profile.badges.title")
    }
    private func badgeLink(_ badge: ProfileBadgeSelection, identifier: String) -> some View {
        NavigationLink { ProfileBadgeDetailView(badge: badge) } label: {
            HStack(alignment: .center, spacing: 12) {
                ProfileBadgeImage(rawURL: badge.image, size: 44)
                VStack(alignment: .leading, spacing: 5) {
                    ProfileBadgeTitle(badge: badge).font(.headline)
                    Label {
                        Text(badge.isLocked ? LocalizedStringKey("profile.badges.locked") : LocalizedStringKey("profile.badges.unlocked"))
                    } icon: { Image(systemName: badge.isLocked ? "lock" : "checkmark.seal") }
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }.padding(.vertical, 5)
        }.accessibilityIdentifier(identifier)
    }
}

enum ProfileBadgeSelection {
    case identity(ProfileIdentityBadge), medal(ProfileMedal)
    var image: String {
        switch self { case .identity(let value): return value.iconURL; case .medal(let value): return value.medalImage }
    }
    var name: String {
        switch self { case .identity(let value): return value.badgeName; case .medal(let value): return value.medalName }
    }
    var isLocked: Bool {
        if case .identity(let value) = self { return !value.unlocked }
        return false
    }
    var familyKey: LocalizedStringKey {
        switch self {
        case .identity: return "profile.badges.identities"
        case .medal(let value): return value.isAchievement ? "profile.badges.achievements" : "profile.badges.medals"
        }
    }
}

struct ProfileBadgeDetailView: View {
    let badge: ProfileBadgeSelection
    var body: some View {
        List {
            Section {
                VStack(spacing: 16) {
                    ProfileBadgeImage(rawURL: badge.image, size: 110)
                    ProfileBadgeTitle(badge: badge).font(.title2)
                    Label {
                        Text(badge.isLocked ? LocalizedStringKey("profile.badges.locked") : LocalizedStringKey("profile.badges.unlocked"))
                    } icon: { Image(systemName: badge.isLocked ? "lock" : "checkmark.seal") }
                }.frame(maxWidth: .infinity).padding(.vertical, 12)
            }
            Section("profile.badges.details") {
                LabeledContent("profile.badges.family") { Text(badge.familyKey) }
                switch badge {
                case .identity(let value):
                    ProfileOptionalRow(key: "profile.badges.category", value: value.category)
                    ProfileOptionalRow(key: "profile.badges.statement", value: value.statement)
                    ProfileOptionalRow(key: "profile.badges.unlockHint", value: value.unlockHint)
                    if value.unlocked { ProfileOptionalRow(key: "profile.badges.obtained", value: value.unlockTime) }
                case .medal(let value):
                    ProfileOptionalRow(key: "profile.badges.condition", value: value.displayCondition)
                    ProfileOptionalRow(key: "profile.badges.obtained", value: value.getTime)
                }
            }
        }
        .navigationTitle("profile.badges.detail")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ProfileBadgeTitle: View {
    let badge: ProfileBadgeSelection
    var body: some View {
        if badge.name.isEmpty { Text(badge.familyKey) }
        else { Text(verbatim: badge.name) }
    }
}

private struct ProfileBadgeImage: View {
    let rawURL: String
    let size: CGFloat
    private var url: URL? {
        guard let parts = URLComponents(string: rawURL), parts.scheme == "https",
              parts.host?.isEmpty == false, parts.user == nil, parts.password == nil else { return nil }
        return parts.url
    }
    var body: some View {
        AsyncImage(url: url) { image in image.resizable().scaledToFit() } placeholder: {
            Image(systemName: "medal").resizable().scaledToFit().foregroundStyle(.secondary)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
