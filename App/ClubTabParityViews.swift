import SwiftUI

/// Mini-program 俱乐部 tab (`pages/talent/list`) details layered on `ClubHomeView`.
struct ClubTabTagLine: View {
    let club: ClubRecord
    let section: ClubTabPresentation.Section
    var body: some View {
        let tags = ClubTabPresentation.tags(club, in: section)
        let level = ClubTabPresentation.levelKey(club.level)
        if !tags.labels.isEmpty || tags.freeToJoin || level.key != nil || level.fallback != nil {
            HStack(spacing: 6) {
                if let key = level.key { Text(LocalizedStringKey(key)) } else if let fallback = level.fallback { Text(verbatim: fallback) }
                ForEach(tags.labels.prefix(3), id: \.self) { Text(verbatim: $0) }
                if tags.freeToJoin { Text("club.tab.freeToJoin") }
            }.font(.caption2.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1)
                .accessibilityElement(children: .combine).accessibilityIdentifier("clubTab.tags.\(club.id)")
        }
    }
}

struct ClubTabEmptyState: View {
    let merchant: Bool
    var body: some View {
        let keys = ClubTabPresentation.emptyKeys(merchant: merchant)
        VStack(alignment: .leading, spacing: 6) {
            Text(LocalizedStringKey(keys.title)).font(.headline)
            Text(LocalizedStringKey(keys.detail)).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.accessibilityElement(children: .combine).accessibilityIdentifier("clubTab.empty")
    }
}
