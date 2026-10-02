import SwiftUI

struct ClubName: View {
    let value: String
    var body: some View {
        if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { Text("club.untitled") }
        else { Text(verbatim: value) }
    }
}

struct ClubRow: View {
    let club: ClubRecord
    var body: some View {
        QuestifyImageEntityCard(imageSource:club.cover,title:club.name,subtitle:club.style,
                                fallbackTitle:"club.untitled",fallbackSymbol:"person.3") {
            HStack(spacing:12) {
                Text("club.memberCount \(club.memberCount)")
                if club.isOwner { Text("club.role.creator") }
                else if club.isJoined { Text("club.membership.joined") }
            }.font(.caption.weight(.semibold))
            if let city=club.city,!city.isEmpty {
                QuestifyImageEntityMetadata(label:"club.city",value:city,systemImage:"mappin")
            }
        }
    }
}

struct ClubOptionalRow: View {
    let title: LocalizedStringKey
    let value: String?
    var body: some View {
        if let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            LabeledContent(title) { Text(verbatim: value).textSelection(.enabled) }
        }
    }
}

struct ClubEmptyState: View {
    let title: LocalizedStringKey
    let hint: LocalizedStringKey
    let identifier: String
    var body: some View {
        ContentUnavailableView {
            Label { Text(title).accessibilityIdentifier(identifier) } icon: { Image(systemName: "person.3") }
        } description: { Text(hint) }
    }
}
