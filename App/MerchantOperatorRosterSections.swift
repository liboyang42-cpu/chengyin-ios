import SwiftUI

/// No reads or retained roster state. The owning page supplies its exact row
/// renderer and existing action guards from the current authorized snapshot.
@MainActor struct MerchantOperatorRosterSections<RowContent: View>: View {
    let roster: MerchantOperatorRoster
    let access: MerchantBusinessAccess
    let rowContent: (MerchantBusinessRecord) -> RowContent

    init(roster: MerchantOperatorRoster, access: MerchantBusinessAccess,
         @ViewBuilder rowContent: @escaping (MerchantBusinessRecord) -> RowContent) {
        self.roster = roster; self.access = access; self.rowContent = rowContent
    }

    var body: some View {
        Group {
            if access.canManageOperators {
                Section {
                    Text("merchant.operatorRoster.loadedScope").font(.footnote).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Section("merchant.operatorRoster.members") {
                    LabeledContent("merchant.operatorRoster.loadedMembers", value: String(roster.activeMembers.count))
                        .accessibilityIdentifier("merchant.operatorRoster.memberCount")
                    if roster.activeMembers.isEmpty {
                        Text("merchant.operatorRoster.membersEmpty").foregroundStyle(.secondary)
                            .accessibilityIdentifier("merchant.operatorRoster.membersEmpty")
                    }
                    ForEach(roster.activeMembers) { row in rowContent(row) }
                }
                Section("merchant.operatorRoster.invites") {
                    LabeledContent("merchant.operatorRoster.loadedInvites", value: String(roster.pendingInvites.count))
                        .accessibilityIdentifier("merchant.operatorRoster.inviteCount")
                    if roster.pendingInvites.isEmpty {
                        Text("merchant.operatorRoster.invitesEmpty").foregroundStyle(.secondary)
                            .accessibilityIdentifier("merchant.operatorRoster.invitesEmpty")
                    }
                    ForEach(roster.pendingInvites) { row in rowContent(row) }
                }
                if roster.hasHistory {
                    Section("merchant.operatorRoster.history") {
                        Text("merchant.operatorRoster.historyScope").font(.footnote).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if !roster.previousMembers.isEmpty {
                            DisclosureGroup("merchant.operatorRoster.previousMembers") {
                                ForEach(roster.previousMembers) { row in rowContent(row) }
                            }.frame(minHeight: 44)
                                .accessibilityIdentifier("merchant.operatorRoster.previousMembers")
                        }
                        if !roster.previousInvites.isEmpty {
                            DisclosureGroup("merchant.operatorRoster.previousInvites") {
                                ForEach(roster.previousInvites) { row in rowContent(row) }
                            }.frame(minHeight: 44)
                                .accessibilityIdentifier("merchant.operatorRoster.previousInvites")
                        }
                    }
                }
            } else { Text("merchant.business.denied") }
        }
    }
}
