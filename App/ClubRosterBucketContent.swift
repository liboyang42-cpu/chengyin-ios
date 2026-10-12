import SwiftUI

@MainActor enum ClubRosterInteraction {
    static func formRoute(_ target: ClubRosterCorrectionRoute, snapshot: ClubGovernanceSnapshot?, context: ClubGovernanceReadContext,
                          snapshotGeneration: UInt64, readGeneration: UInt64, access: any ClubGovernanceAccess) -> ClubGovernanceFormRoute? {
        guard access.isConfigured, context.identity?.isSignedIn == true, context.identity == access.identity,
              context.authorizationGeneration == access.authorizationGeneration, context.accessIdentity == ObjectIdentifier(access),
              snapshotGeneration == readGeneration,
              target.isCurrent(snapshot: snapshot, context: context, snapshotGeneration: snapshotGeneration, namespace: access.storageNamespace) else { return nil }
        return .init(operation: .correctAttendance, scope: target.scope, seed: ["expectedVersion": .integer(target.version)])
    }
}

@MainActor struct ClubRosterBucketContent: View {
    let roster: ClubRosterPresentation
    let context: ClubGovernanceReadContext
    let snapshotGeneration: UInt64
    let namespace: String
    @Binding var selected: ClubRosterBucket
    let openCorrection: (ClubRosterCorrectionRoute) -> Void
    var body: some View {
        Section {
            LabeledContent("club.roster.total", value: String(roster.rosterTotal)).accessibilityIdentifier("club.roster.total")
            Text("club.roster.totalNote").font(.footnote).foregroundStyle(.secondary)
            Text("club.roster.privacy").font(.footnote)
            ForEach(ClubRosterBucket.allCases, id: \.self) { bucket in
                LabeledContent(LocalizedStringKey(bucket.localizationKey), value: String(roster.count(in: bucket)))
                    .accessibilityIdentifier("club.roster.count." + bucket.rawValue)
            }
            Picker("club.gov.filter", selection: $selected) {
                ForEach(ClubRosterBucket.allCases, id: \.self) { bucket in Text(LocalizedStringKey(bucket.localizationKey)).tag(bucket) }
            }.pickerStyle(.segmented).accessibilityIdentifier("club.roster.filter")
            if roster.correctionOperable == false { Text("club.roster.windowClosed").accessibilityIdentifier("club.roster.windowClosed") }
            if roster.correctionStart != nil || roster.correctionEnd != nil {
                Text("club.roster.serverWindow").font(.footnote)
                if let start = roster.correctionStart { LabeledContent("club.roster.windowStart", value: start) }
                if let end = roster.correctionEnd { LabeledContent("club.roster.windowEnd", value: end) }
            }
        }
        Section(LocalizedStringKey(selected.localizationKey)) {
            if roster.members(in: selected).isEmpty { Text("club.roster.emptyBucket").accessibilityIdentifier("club.roster.emptyBucket") }
            ForEach(roster.members(in: selected)) { member in
                VStack(alignment: .leading, spacing: 8) {
                    if let name = member.nickname { Text(verbatim: name).font(.headline) } else { Text("club.roster.unnamed").font(.headline) }
                    Text("club.memberNumber \(member.id)").font(.caption).foregroundStyle(.secondary)
                    if let state = member.waitlistState { Text(verbatim: state) }
                    if let route = roster.correctionRoute(memberID: member.id, bucket: selected, context: context,
                                                          snapshotGeneration: snapshotGeneration, namespace: namespace) {
                        Button("club.gov.action.correctAttendance") { openCorrection(route) }
                            .buttonStyle(.borderless).accessibilityIdentifier("club.roster.correct.\(member.id)")
                    } else if selected != .waitlist && member.correctionVersion == nil {
                        Text("club.roster.versionUnknown").font(.footnote).accessibilityIdentifier("club.roster.versionUnknown")
                    }
                }.accessibilityIdentifier("club.roster.member.\(member.id)")
            }
        }
    }
}
