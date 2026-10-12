import SwiftUI

@MainActor enum ClubTopicMerchantReadGate {
    enum State: Equatable { case stale, failed(ClubGovernanceFailure), ready(ClubTopicMerchantList) }
    /// The parent owns read/retry/visibility. This child retains no response or route.
    static func state(snapshot: ClubGovernanceSnapshot, context: ClubGovernanceReadContext,
                      snapshotGeneration: UInt64, readGeneration: UInt64, access: any ClubGovernanceAccess) -> State {
        guard snapshotGeneration == readGeneration, context.identity?.isSignedIn == true,
              access.isConfigured, context.identity == access.identity,
              context.authorizationGeneration == access.authorizationGeneration,
              context.accessIdentity == ObjectIdentifier(access) else { return .stale }
        do { return .ready(try ClubTopicMerchantList(snapshot: snapshot, context: context)) }
        catch { return .failed(error as? ClubGovernanceFailure ?? .malformed) }
    }
}

@MainActor struct ClubTopicMerchantContent: View {
    let snapshot: ClubGovernanceSnapshot
    let context: ClubGovernanceReadContext
    let snapshotGeneration: UInt64
    let readGeneration: UInt64
    let access: any ClubGovernanceAccess
    var body: some View {
        switch ClubTopicMerchantReadGate.state(snapshot: snapshot, context: context,
                                               snapshotGeneration: snapshotGeneration, readGeneration: readGeneration, access: access) {
        case .stale: EmptyView()
        case .failed(let failure):
            Text(LocalizedStringKey(failure.localizationKey)).accessibilityIdentifier("club.topicMerchants.invalid")
        case .ready(let list):
            Section("club.topicMerchants.title") {
                Text("club.topicMerchants.contactBoundary").font(.footnote).foregroundStyle(.secondary)
                if list.rows.isEmpty {
                    Text("club.topicMerchants.empty").accessibilityIdentifier("club.topicMerchants.empty")
                }
                ForEach(list.rows) { row in
                    HStack(alignment: .top, spacing: 12) {
                        Text(verbatim: row.initial ?? "?").font(.title2).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 6) {
                            if let name = row.merchantName { Text(verbatim: name).font(.headline) }
                            else { Text("club.topicMerchants.unnamedMerchant").font(.headline) }
                            if let station = row.stationName { Text(verbatim: station) }
                            else { Text("club.topicMerchants.unnamedStation") }
                            if let state = row.state { LabeledContent("club.topicMerchants.returnedState", value: state) }
                            else { Text("club.topicMerchants.unknownState").foregroundStyle(.secondary) }
                        }
                    }.fixedSize(horizontal: false, vertical: true).accessibilityElement(children: .combine)
                        .accessibilityIdentifier("club.topicMerchants.node.\(row.id)")
                }
            }
        }
    }
}
