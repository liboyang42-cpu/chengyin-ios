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
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "person.3.fill").font(.title2).foregroundStyle(.tint)
                .frame(width: 38, height: 38).background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                ClubName(value: club.name).font(.headline)
                if let style = club.style, !style.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(verbatim: style).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
                HStack(spacing: 8) {
                    Text("club.memberCount \(club.memberCount)")
                    if club.isOwner { Text("club.role.creator") }
                    else if club.isJoined { Text("club.membership.joined") }
                }.font(.caption).foregroundStyle(.secondary)
                if let city = club.city, !city.isEmpty {
                    Label { Text(verbatim: city) } icon: { Image(systemName: "mappin") }
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }.padding(.vertical, 5)
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
