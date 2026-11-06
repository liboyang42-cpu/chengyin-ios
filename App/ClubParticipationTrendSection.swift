import SwiftUI

struct ClubParticipationTrendContext: Hashable {
    let clubID: Int
    let topicID: Int
    let identity: ClubReadIdentity?
    let viewerRevision: UInt64
    let namespace: String
    let authorization: UUID?
    let accessID: ObjectIdentifier
    let active: Bool
    let visible: Bool
    @MainActor func isCurrent(_ access: any ClubGovernanceAccess) -> Bool {
        active && visible && identity == access.identity && namespace == access.storageNamespace
            && authorization == access.authorizationGeneration && accessID == ObjectIdentifier(access)
    }
}

@MainActor final class ClubParticipationTrendModel: ObservableObject {
    @Published private(set) var context: ClubParticipationTrendContext?
    @Published private(set) var result: ClubParticipationTrend?
    @Published private(set) var loading = false
    @Published private(set) var failure: ClubGovernanceFailure?
    @Published private(set) var remoteMessage: String?
    private var generation: UInt64 = 0

    func retire() {
        generation &+= 1; context = nil; result = nil; loading = false; failure = nil; remoteMessage = nil
    }
    @discardableResult func retry(_ expected: ClubParticipationTrendContext, access: any ClubGovernanceAccess) -> Task<Void, Never>? {
        guard !loading, context == expected, expected.isCurrent(access) else { return nil }
        let captured = generation
        return Task { [weak self] in
            guard let self, self.generation == captured, self.context == expected,
                  expected.isCurrent(access), !Task.isCancelled else { return }
            await self.load(expected, access: access)
        }
    }
    func load(_ expected: ClubParticipationTrendContext, access: any ClubGovernanceAccess) async {
        // A cancelled task from the previous SwiftUI identity must not clear a newer result.
        guard !Task.isCancelled else { return }
        generation &+= 1; let ticket = generation
        context = expected; result = nil; failure = nil; remoteMessage = nil; loading = false
        guard expected.isCurrent(access), !Task.isCancelled else { return }
        guard expected.identity?.isSignedIn == true else { failure = .signedOut; return }
        guard expected.clubID > 0, expected.topicID > 0 else { failure = .invalidRequest; return }
        guard access.isConfigured else { failure = .notConfigured; return }
        loading = true
        defer { if generation == ticket { loading = false } }
        let check: @MainActor () throws -> Void = { [weak self] in
            guard let self, self.generation == ticket, self.context == expected,
                  expected.isCurrent(access), !Task.isCancelled else { throw CancellationError() }
        }
        do {
            let value = try await access.readParticipationTrend(topicID: expected.topicID, check: check)
            try check()
            guard value.topicID == expected.topicID else { throw ClubGovernanceFailure.targetChanged }
            result = value
        } catch {
            do { try check() } catch { return }
            // No old result survives a failed/denied refresh. Unknown reads are not writes.
            result = nil
            if let denial = error as? ClubParticipationTrendDenied {
                failure = .forbidden; remoteMessage = denial.message
            } else {
                let issue = error as? ClubGovernanceFailure ?? .malformed
                failure = issue; remoteMessage = issue.message
            }
        }
    }
}

struct ClubParticipationTrendSection: View {
    let clubID: Int
    let topicID: Int
    let identity: ClubReadIdentity?
    let viewerRevision: UInt64
    let access: any ClubGovernanceAccess
    @Environment(\.scenePhase) private var scenePhase
    @State private var visible = false
    @StateObject private var model = ClubParticipationTrendModel()
    private var context: ClubParticipationTrendContext {
        .init(clubID: clubID, topicID: topicID, identity: identity,
              viewerRevision: viewerRevision, namespace: access.storageNamespace, authorization: access.authorizationGeneration,
              accessID: ObjectIdentifier(access), active: scenePhase == .active, visible: visible)
    }
    var body: some View {
        Section {
            if context.isCurrent(access), model.context == context {
                if model.loading {
                    ProgressView { Text("club.trend.loading", tableName: "ClubParticipationTrend") }.accessibilityIdentifier("club.trend.loading")
                } else if let failure = model.failure {
                    VStack(alignment: .leading, spacing: 8) {
                        if failure == .forbidden { Text("club.trend.denied", tableName: "ClubParticipationTrend") }
                        else if failure == .signedOut { Text("club.trend.signedOut", tableName: "ClubParticipationTrend") }
                        else if failure == .notConfigured { Text("club.trend.unavailable", tableName: "ClubParticipationTrend") }
                        else { Text("club.trend.error", tableName: "ClubParticipationTrend") }
                        if let message = model.remoteMessage, !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(verbatim: message).textSelection(.enabled)
                        }
                        Button { model.retry(context, access: access) } label: {
                            Text("club.trend.retry", tableName: "ClubParticipationTrend").frame(minHeight: 44)
                        }.accessibilityIdentifier("club.trend.retry")
                    }.fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("club.trend.failure")
                } else if let result = model.result {
                    if result.rows.isEmpty {
                        Text("club.trend.empty", tableName: "ClubParticipationTrend").fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("club.trend.empty")
                    } else {
                        ForEach(Array(result.rows.enumerated()), id: \.offset) { index, row in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(verbatim: row.date)
                                HStack { Text("club.trend.count", tableName: "ClubParticipationTrend"); Text(row.count, format: .number) }
                                    .font(.subheadline)
                            }.fixedSize(horizontal: false, vertical: true)
                                .accessibilityElement(children: .combine)
                                .accessibilityIdentifier("club.trend.row.\(index)")
                        }
                    }
                }
            }
        } header: { Text("club.trend.title", tableName: "ClubParticipationTrend") }
          footer: { Text("club.trend.scope", tableName: "ClubParticipationTrend").fixedSize(horizontal: false, vertical: true) }
        .onAppear { visible = true }
        .onDisappear { visible = false; model.retire() }
        .onChange(of: scenePhase) { _, value in if value != .active { model.retire() } }
        .task(id: context) {
            let expected = context
            guard expected.active, expected.visible else { model.retire(); return }
            await model.load(expected, access: access)
        }
    }
}
