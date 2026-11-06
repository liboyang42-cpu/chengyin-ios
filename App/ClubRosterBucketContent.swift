import SwiftUI

@MainActor enum ClubRosterInteraction {
    static func formRoute(_ target: ClubRosterCorrectionRoute, snapshot: ClubGovernanceSnapshot?, context: ClubGovernanceReadContext,
                          snapshotGeneration: UInt64, readGeneration: UInt64, access: any ClubGovernanceAccess) -> ClubGovernanceFormRoute? {
        guard access.isConfigured, context.identity?.isSignedIn == true, context.identity == access.identity,
              context.authorizationGeneration == access.authorizationGeneration, context.accessIdentity == ObjectIdentifier(access),
              snapshotGeneration == readGeneration,
              target.isCurrent(snapshot: snapshot, context: context, snapshotGeneration: snapshotGeneration, namespace: access.storageNamespace) else { return nil }
        return .init(operation: .correctAttendance, scope: target.scope,
                     seed: ["expectedVersion": .integer(target.version), "arrived": .bool(target.arrived)])
    }
}

@MainActor struct ClubRosterBucketContent: View {
    let roster: ClubRosterPresentation
    let context: ClubGovernanceReadContext
    let snapshotGeneration: UInt64
    let namespace: String
    @Binding var selected: ClubRosterBucket
    let openCorrection: (ClubRosterCorrectionRoute) -> Void
    @Environment(\.locale) private var locale
    var body: some View {
        Section {
            Text("clubOpsEvent.roster.title \(roster.rosterTotal)", tableName: "ClubOpsEvent").font(.headline)
                .accessibilityIdentifier("club.roster.total")
            Text("club.roster.totalNote").font(.footnote).foregroundStyle(.secondary)
            Text("club.roster.privacy").font(.footnote)
            ForEach(ClubRosterBucket.allCases, id: \.self) { bucket in
                LabeledContent(LocalizedStringKey(bucket.localizationKey), value: String(roster.count(in: bucket)))
                    .accessibilityIdentifier("club.roster.count." + bucket.rawValue)
            }
            Picker("club.gov.filter", selection: $selected) {
                ForEach(ClubRosterBucket.allCases, id: \.self) { bucket in Text(LocalizedStringKey(bucket.localizationKey)).tag(bucket) }
            }.pickerStyle(.segmented).accessibilityIdentifier("club.roster.filter")
            // Mini CU-C-73: the operable window is stated in place only while corrections are closed.
            if roster.correctionOperable == false {
                Group {
                    if let range = ClubOpsEventClock.correctionRange(start: roster.correctionStart, end: roster.correctionEnd, locale: locale) {
                        Text("clubOpsEvent.roster.window \(range)", tableName: "ClubOpsEvent")
                    } else { Text("clubOpsEvent.roster.windowGeneric", tableName: "ClubOpsEvent") }
                }.font(.footnote).foregroundStyle(.orange).accessibilityIdentifier("club.roster.windowClosed")
            }
        }
        Section(LocalizedStringKey(selected.localizationKey)) {
            if roster.members(in: selected).isEmpty { Text("clubOpsEvent.roster.emptyBucket", tableName: "ClubOpsEvent").accessibilityIdentifier("club.roster.emptyBucket") }
            ForEach(roster.members(in: selected)) { member in
                VStack(alignment: .leading, spacing: 8) {
                    if let name = member.nickname { Text(verbatim: name).font(.headline) } else { Text("club.roster.unnamed").font(.headline) }
                    Text("club.memberNumber \(member.id)").font(.caption).foregroundStyle(.secondary)
                    if let state = member.waitlistState { Text(verbatim: state) }
                    if let route = roster.correctionRoute(memberID: member.id, bucket: selected, context: context,
                                                          snapshotGeneration: snapshotGeneration, namespace: namespace) {
                        Button { openCorrection(route) } label: { correctionLabel(route.arrived) }
                            .buttonStyle(.borderless).accessibilityIdentifier("club.roster.correct.\(member.id)")
                    } else if let arrived = ClubOpsEventAttendance.arrivedTarget(selected), roster.correctionOperable == false {
                        Button {} label: { correctionLabel(arrived) }.buttonStyle(.borderless).disabled(true)
                            .accessibilityIdentifier("club.roster.correct.\(member.id)")
                        Text("clubOpsEvent.roster.closed", tableName: "ClubOpsEvent").font(.caption).foregroundStyle(.secondary)
                    } else if selected != .waitlist && member.correctionVersion == nil {
                        Text("club.roster.versionUnknown").font(.footnote).accessibilityIdentifier("club.roster.versionUnknown")
                    }
                }.accessibilityIdentifier("club.roster.member.\(member.id)")
            }
        }
    }
    private func correctionLabel(_ arrived: Bool) -> Text {
        Text(arrived ? "clubOpsEvent.roster.markArrived" : "clubOpsEvent.roster.markAbsent", tableName: "ClubOpsEvent")
    }
}
