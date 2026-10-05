import SwiftUI

@MainActor struct ActivityPeopleProfileContext {
    let reader: any SocialAccountReading
    let squareReader: any SquareReading
    var actions: SocialActionCoordinator? = nil
}

/// Uses only the people projection in the allowed detail; never requests an
/// administrative roster or infers participants from tickets or orders.
@MainActor struct ActivityPeopleSection: View {
    let people: ActivityPeople
    var onOpenProfile: ((Int) -> Void)? = nil

    var body: some View {
        if let host = people.host, host.name != nil {
            Section("activity.people.host") {
                personRow(host, identifier: "activity.people.host")
            }
        }
        if !people.participants.isEmpty || people.registrationCount != nil {
            Section("activity.people.participants") {
                LabeledContent("activity.people.total") {
                    if let count = people.registrationCount {
                        Text(verbatim: String(count)).accessibilityIdentifier("activity.people.count")
                    }
                    else { Text("activity.people.countUnknown") }
                }.accessibilityIdentifier("activity.people.total")
                ForEach(Array(people.participants.enumerated()), id: \.offset) { index, person in
                    personRow(person, identifier: "activity.people.participant.\(index)")
                }
            }
        }
    }

    @ViewBuilder private func personRow(_ person: ActivityPerson, identifier: String) -> some View {
        if let memberID = person.memberID, let onOpenProfile {
            Button { onOpenProfile(memberID) } label: { label(person) }
                .buttonStyle(.plain)
                .accessibilityHint(Text("social.profile"))
                .accessibilityIdentifier(identifier)
        } else {
            label(person).accessibilityIdentifier(identifier + ".readOnly")
        }
    }
    private func label(_ person: ActivityPerson) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "person.crop.circle.fill").font(.title2)
                .foregroundStyle(.secondary).accessibilityHidden(true)
            if let name = person.name { Text(verbatim: name) }
            else { Text("activity.people.unnamed") }
            Spacer(minLength: 8)
            if person.memberID != nil, onOpenProfile != nil {
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary).accessibilityHidden(true)
            }
        }.frame(minHeight: 44).contentShape(Rectangle())
            .accessibilityElement(children: .combine)
    }
}
