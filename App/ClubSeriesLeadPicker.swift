import SwiftUI

@MainActor final class ClubSeriesLeadReadModel: ObservableObject {
    struct Context: Hashable { let read: ClubGovernanceReadContext; let namespace: String }
    struct Permit: Equatable { let context: Context; let visibility: UUID }
    @Published private(set) var options: ClubSeriesLeadOptions?
    @Published private(set) var loading = false
    @Published private(set) var failure: ClubGovernanceFailure?
    private var bound: Context?
    private var loaded: Context?
    private var visibility: UUID?
    private var generation = UUID()
    private(set) var snapshotID = UUID()
    static func context(scope: ClubGovernanceScope, identity: ClubReadIdentity?, access: any ClubGovernanceAccess) -> Context {
        .init(read: .init(operation: .members, scope: scope, identity: identity, viewerRevision: 0,
                          authorizationGeneration: access.authorizationGeneration, accessIdentity: ObjectIdentifier(access)),
              namespace: access.storageNamespace)
    }
    func bind(_ context: Context) {
        guard bound != context else { return }
        bound = context; visibility = nil; generation = UUID()
    }
    func activate(_ context: Context) -> Permit? {
        guard bound == context, !Task.isCancelled else { return nil }
        if visibility == nil {
            visibility = UUID(); generation = UUID(); snapshotID = UUID()
            loaded = nil; options = nil; loading = false; failure = nil
        }
        return permit(in: context)
    }
    func permit(in context: Context) -> Permit? {
        guard bound == context, let visibility else { return nil }
        return .init(context: context, visibility: visibility)
    }
    private func accepts(_ permit: Permit) -> Bool { bound == permit.context && visibility == permit.visibility }
    private func live(_ context: Context, access: any ClubGovernanceAccess) -> Bool {
        let read = context.read
        return read.operation == .members && (read.scope.clubID ?? 0) > 0 && (read.scope.topicID ?? 0) > 0 &&
            read.identity?.isSignedIn == true && access.isConfigured && read.identity == access.identity &&
            read.authorizationGeneration == access.authorizationGeneration && read.accessIdentity == ObjectIdentifier(access) &&
            context.namespace == access.storageNamespace
    }
    func accepted(_ context: Context, access: any ClubGovernanceAccess) -> ClubSeriesLeadOptions? {
        guard permit(in: context) != nil, loaded == context, !loading, live(context, access: access) else { return nil }
        return options
    }
    func canSelect(_ options: ClubSeriesLeadOptions, snapshotID: UUID, permit: Permit, access: any ClubGovernanceAccess) -> Bool {
        accepts(permit) && self.snapshotID == snapshotID && accepted(permit.context, access: access) == options
    }
    func canPrepare(scope: ClubGovernanceScope, identity: ClubReadIdentity?, access: any ClubGovernanceAccess, memberID: String) -> Bool {
        accepted(Self.context(scope: scope, identity: identity, access: access), access: access)?.contains(memberID: Int(memberID)) == true
    }
    func leave(_ context: Context) {
        guard bound == context else { return }
        visibility = nil; generation = UUID(); snapshotID = UUID(); loaded = nil
        options = nil; loading = false; failure = nil
    }
    func load(_ permit: Permit, access: any ClubGovernanceAccess) async {
        guard accepts(permit), !Task.isCancelled else { return }
        guard live(permit.context, access: access) else {
            loaded = nil; options = nil; loading = false
            failure = access.identity?.isSignedIn == true ? .notConfigured : .signedOut; return
        }
        generation = UUID(); let request = generation
        loaded = nil; options = nil; snapshotID = UUID(); failure = nil; loading = true
        defer { if generation == request && accepts(permit) { loading = false } }
        func check() throws {
            guard accepts(permit), generation == request, live(permit.context, access: access), !Task.isCancelled else { throw CancellationError() }
        }
        do {
            try check()
            let snapshot = try await access.read(.members, scope: permit.context.read.scope, options: [:], check: check)
            try check()
            let projected = try ClubSeriesLeadOptions(snapshot: snapshot, context: permit.context.read)
            loaded = permit.context; options = projected
        } catch {
            guard accepts(permit), generation == request, live(permit.context, access: access), !Task.isCancelled else { return }
            failure = error as? ClubGovernanceFailure ?? .malformed
        }
    }
}

@MainActor struct ClubSeriesLeadPicker: View {
    let scope: ClubGovernanceScope
    let identity: ClubReadIdentity?
    let access: any ClubGovernanceAccess
    @ObservedObject var model: ClubSeriesLeadReadModel
    @Binding var memberID: String
    let canEdit: () -> Bool
    @State private var expanded = false
    private var context: ClubSeriesLeadReadModel.Context { ClubSeriesLeadReadModel.context(scope: scope, identity: identity, access: access) }
    var body: some View {
        let expected = context, permit = model.permit(in: expected)
        VStack(alignment: .leading, spacing: 12) {
            Text("club.seriesLead.explanation").font(.footnote)
            if model.loading || permit == nil { ProgressView("club.loading").accessibilityIdentifier("club.seriesLead.loading") }
            if permit != nil, let failure = model.failure { Text(LocalizedStringKey(failure.localizationKey)).accessibilityIdentifier("club.seriesLead.error") }
            if let options = model.accepted(expected, access: access), let permit {
                let readID = model.snapshotID
                if options.members.isEmpty { Text("club.seriesLead.empty").accessibilityIdentifier("club.seriesLead.empty") }
                else {
                    DisclosureGroup(isExpanded: $expanded) {
                        ForEach(options.members) { member in
                            Button {
                                guard canEdit(), model.canSelect(options, snapshotID: readID, permit: permit, access: access) else { return }
                                memberID = String(member.id); expanded = false
                            } label: {
                                HStack {
                                    memberName(member)
                                    Spacer()
                                    if memberID == String(member.id) { Image(systemName: "checkmark").accessibilityLabel("club.seriesLead.selected") }
                                }.contentShape(Rectangle())
                            }.accessibilityIdentifier("club.seriesLead.member.\(member.id)")
                        }
                        Button("action.cancel") { expanded = false }.accessibilityIdentifier("club.seriesLead.cancel")
                    } label: {
                        LabeledContent("club.seriesLead.choose") {
                            if let selected = options.members.first(where: { String($0.id) == memberID }) { memberName(selected) }
                            else { Text("club.seriesLead.unselected") }
                        }
                    }.accessibilityIdentifier("club.seriesLead.open")
                }
                if !memberID.isEmpty && !options.contains(memberID: Int(memberID)) { Text("club.seriesLead.changed").accessibilityIdentifier("club.seriesLead.changed") }
            }
            if model.failure != .forbidden {
                Button(LocalizedStringKey(model.failure == nil ? "club.gov.refresh" : "action.retry")) {
                    guard canEdit(), let permit else { return }
                    expanded = false
                    Task { guard canEdit() else { return }; await model.load(permit, access: access) }
                }.disabled(model.loading || permit == nil).accessibilityIdentifier("club.seriesLead.reload")
            }
        }
        .buttonStyle(.borderless)
        .onChange(of: expected) { _, _ in expanded = false }
    }
    private func memberName(_ member: ClubSeriesLeadMember) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let name = member.nickname { Text(verbatim: name) } else { Text("club.seriesLead.unnamed") }
            Text("club.memberNumber \(member.id)").font(.caption).foregroundStyle(.secondary)
        }
    }
}
