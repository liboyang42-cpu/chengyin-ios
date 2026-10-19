import SwiftUI

struct ClubNotificationAudienceOption: Identifiable, Equatable {
    let id: String
    let enabled: Bool
    let needsActivity: Bool
    let count: Int?
}

@MainActor final class ClubNotificationAudienceReadModel: ObservableObject {
    struct Context: Hashable { let read: ClubGovernanceReadContext; let namespace: String }
    struct Permit: Equatable { let context: Context; let visibility: UUID }
    static let audienceIDs = ["ALL_MEMBERS", "ADMINS", "REGISTERED", "WAITLIST", "NO_SHOW", "INACTIVE"]
    static let eventAudienceIDs: Set<String> = ["REGISTERED", "WAITLIST", "NO_SHOW"]
    @Published private(set) var options: [ClubNotificationAudienceOption]?
    @Published private(set) var loading = false
    @Published private(set) var failure: ClubGovernanceFailure?
    @Published private(set) var countsUnavailable = false
    private var bound: Context?
    private var loaded: Context?
    private var visibility: UUID?
    private var generation = UUID()
    private(set) var snapshotID = UUID()

    static func context(scope: ClubGovernanceScope, identity: ClubReadIdentity?, access: any ClubGovernanceAccess) -> Context {
        .init(read: .init(operation: .audienceCounts, scope: scope, identity: identity, viewerRevision: 0,
                         authorizationGeneration: access.authorizationGeneration, accessIdentity: ObjectIdentifier(access)),
              namespace: access.storageNamespace)
    }
    func bind(_ context: Context) {
        guard bound != context else { return }
        bound = context; visibility = nil; generation = UUID()
    }
    func activate(_ context: Context) -> Permit? {
        guard bound == context, !Task.isCancelled else { return nil }
        if visibility == nil { clear(); visibility = UUID() }
        return permit(in: context)
    }
    func permit(in context: Context) -> Permit? {
        guard bound == context, let visibility else { return nil }
        return .init(context: context, visibility: visibility)
    }
    private func accepts(_ permit: Permit) -> Bool { bound == permit.context && visibility == permit.visibility }
    private func live(_ context: Context, access: any ClubGovernanceAccess) -> Bool {
        let read = context.read
        return read.operation == .audienceCounts && (read.scope.clubID ?? 0) > 0 &&
            (read.scope.activityID.map { $0 > 0 } ?? true) && read.identity?.isSignedIn == true &&
            access.isConfigured && read.identity == access.identity && read.authorizationGeneration == access.authorizationGeneration &&
            read.accessIdentity == ObjectIdentifier(access) && context.namespace == access.storageNamespace
    }
    func accepted(_ context: Context, access: any ClubGovernanceAccess) -> [ClubNotificationAudienceOption]? {
        guard permit(in: context) != nil, loaded == context, !loading, live(context, access: access) else { return nil }
        return options
    }
    func canSelect(_ id: String, snapshotID: UUID, permit: Permit, access: any ClubGovernanceAccess) -> Bool {
        accepts(permit) && self.snapshotID == snapshotID &&
            accepted(permit.context, access: access)?.contains(where: { $0.id == id && $0.enabled }) == true
    }
    func canPrepare(_ id: String, context: Context, access: any ClubGovernanceAccess) -> Bool {
        accepted(context, access: access)?.contains(where: { $0.id == id && $0.enabled }) == true
    }
    func leave(_ context: Context) {
        guard bound == context else { return }
        visibility = nil; clear()
    }
    private func clear() {
        generation = UUID(); snapshotID = UUID(); loaded = nil; options = nil
        loading = false; failure = nil; countsUnavailable = false
    }
    static func project(_ snapshot: ClubGovernanceSnapshot, operation: ClubGovernanceRead,
                        scope: ClubGovernanceScope) throws -> [ClubNotificationAudienceOption] {
        guard snapshot.operation == operation, snapshot.scope == scope,
              let permissions = snapshot.permissions else { throw ClubGovernanceFailure.targetChanged }
        let clubAllowed = permissions.allows("club:notify:send", scope: scope)
        let eventAllowed = (scope.activityID ?? 0) > 0 && permissions.allows("club:event:operate", scope: scope)
        guard clubAllowed || eventAllowed else { throw ClubGovernanceFailure.forbidden }
        if operation == .audienceCounts, snapshot.value["counts"].object == nil { throw ClubGovernanceFailure.malformed }
        return audienceIDs.map { id in
            let eventOnly = eventAudienceIDs.contains(id)
            let enabled = eventOnly ? eventAllowed : clubAllowed
            let count: Int?
            if operation == .audienceCounts, enabled, case .integer(let value) = snapshot.value["counts"][id], value >= 0 {
                count = value
            } else { count = nil }
            return .init(id: id, enabled: enabled, needsActivity: eventOnly && scope.activityID == nil, count: count)
        }
    }
    func load(_ permit: Permit, access: any ClubGovernanceAccess, isCurrent: @escaping () -> Bool) async {
        guard accepts(permit), isCurrent(), !Task.isCancelled else { return }
        guard live(permit.context, access: access) else {
            clear(); failure = access.identity?.isSignedIn == true ? .notConfigured : .signedOut; return
        }
        clear(); let request = generation; loading = true
        defer { if generation == request && accepts(permit) { loading = false } }
        func check() throws {
            guard isCurrent(), accepts(permit), generation == request,
                  live(permit.context, access: access), !Task.isCancelled else { throw CancellationError() }
        }
        do {
            try check()
            let authority = try await access.read(.access, scope: permit.context.read.scope, options: [:], check: check)
            try check()
            let authorized = try Self.project(authority, operation: .access, scope: permit.context.read.scope)
            do {
                try check()
                let counts = try await access.read(.audienceCounts, scope: permit.context.read.scope, options: [:], check: check)
                try check()
                options = try Self.project(counts, operation: .audienceCounts, scope: permit.context.read.scope)
            } catch {
                try check()
                if let failure = error as? ClubGovernanceFailure,
                   [.forbidden, .signedOut, .notConfigured, .targetChanged, .staleReview].contains(failure) { throw failure }
                // Counts are optional display data. The existing preview still validates recipients before any send.
                options = authorized; countsUnavailable = true
            }
            try check(); loaded = permit.context
        } catch {
            do { try check() } catch { return }
            options = nil; loaded = nil; failure = error as? ClubGovernanceFailure ?? .malformed
        }
    }
}

@MainActor struct ClubNotificationAudienceView: View {
    let context: ClubNotificationAudienceReadModel.Context
    let access: any ClubGovernanceAccess
    @ObservedObject var model: ClubNotificationAudienceReadModel
    @Binding var selection: String
    let canEdit: () -> Bool
    let isCurrent: () -> Bool
    var body: some View {
        let expected = context
        let permit = model.permit(in: expected)
        let snapshot = model.snapshotID
        VStack(alignment: .leading, spacing: 12) {
            Text("club.gov.field.audienceType").font(.headline)
            if model.loading || permit == nil { ProgressView("club.loading").accessibilityIdentifier("club.audience.loading") }
            if isCurrent(), let permit, let options = model.accepted(expected, access: access) {
                ForEach(options) { option in
                    Button {
                        guard canEdit(), isCurrent(), model.canSelect(option.id, snapshotID: snapshot, permit: permit, access: access) else { return }
                        if selection != option.id { selection = option.id }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(LocalizedStringKey("club.gov.choice." + option.id))
                                Spacer()
                                if selection == option.id { Image(systemName: "checkmark") }
                            }
                            if option.needsActivity { Text("club.audience.chooseEvent").font(.footnote) }
                            else if !option.enabled {
                                if ClubNotificationAudienceReadModel.eventAudienceIDs.contains(option.id) { ClubOpsJoinNotifyCopy.text("clubOpsJN.notify.eventDenied").font(.footnote) }
                                else { Text("club.gov.denied").font(.footnote) }
                            }
                            else if let count = option.count {
                                LabeledContent("club.gov.field.totalCount", value: String(count)).font(.footnote)
                            } else { Text("club.gov.unknownValue").font(.footnote) }
                        }.contentShape(Rectangle())
                    }
                    .disabled(!canEdit() || !option.enabled)
                    .accessibilityAddTraits(selection == option.id ? .isSelected : [])
                    .accessibilityIdentifier("club.audience.choice." + option.id)
                }
            }
            if isCurrent(), permit != nil, let failure = model.failure {
                Text(LocalizedStringKey(failure.localizationKey)).accessibilityIdentifier("club.audience.error")
            }
            if model.countsUnavailable, isCurrent() { Text("club.gov.unknownValue").accessibilityIdentifier("club.audience.countsUnavailable") }
            if model.failure != .forbidden {
                Button(LocalizedStringKey(model.failure == nil && !model.countsUnavailable ? "club.gov.refresh" : "action.retry")) {
                    guard canEdit(), isCurrent(), let permit else { return }
                    Task { await model.load(permit, access: access, isCurrent: isCurrent) }
                }.disabled(!canEdit() || model.loading || permit == nil).accessibilityIdentifier("club.audience.reload")
            }
        }.buttonStyle(.borderless).accessibilityElement(children: .contain)
    }
}
