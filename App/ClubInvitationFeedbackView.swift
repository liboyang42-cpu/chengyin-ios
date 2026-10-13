import SwiftUI

struct ClubInvitationFeedbackTerms: Equatable {
    let shareMode: Int?
    let shareRate: Double?
    let fixedFee: Double?
    let handleReason: String?
    let termsFrozen: Bool

    init(_ value: CoopFlowJSON) throws {
        let fields = ["id", "shareMode", "shareRate", "fixedFee", "handleReason", "termsFrozen"]
        let safeValue = CoopFlowJSON.object(Dictionary(uniqueKeysWithValues: fields.map { ($0, value[$0]) }))
        let decoded = try JSONDecoder().decode(CooperationInvite.self, from: safeValue.canonical())
        shareMode = decoded.shareMode; shareRate = decoded.shareRate; fixedFee = decoded.fixedFee
        handleReason = decoded.handleReason; termsFrozen = decoded.termsFrozen
    }
    static func project(_ snapshot: ClubInvitationFeedbackSnapshot,
                        invitations: CoopFlowJSON) throws -> [ClubInvitationFeedbackKey: Self] {
        var result: [ClubInvitationFeedbackKey: Self] = [:]
        for row in snapshot.rows {
            guard let rows = invitations[row.id.direction.rawValue].rows else { throw ClubGovernanceFailure.malformed }
            let matches = rows.filter { raw in
                guard raw["id"].integer == row.id.invitationID,
                      raw["topicId"].integer.flatMap({ $0 > 0 ? $0 : nil }) == row.topicID else { return false }
                return row.id.direction == .received
                    ? raw["toType"].text == "club" && raw["toId"].integer == snapshot.clubID
                    : row.topicID != nil
            }
            guard matches.count == 1, let raw = matches.first else { throw ClubGovernanceFailure.malformed }
            result[row.id] = try Self(raw)
        }
        return result
    }
}

@MainActor final class ClubInvitationFeedbackReadModel: ObservableObject {
    struct Permit: Equatable { let context: ClubInvitationFeedbackContext; let visibility: UUID }
    enum Phase: Equatable { case idle, loading, ready, failed, denied }
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var snapshot: ClubInvitationFeedbackSnapshot?
    private var bound: ClubInvitationFeedbackContext?
    private var loaded: ClubInvitationFeedbackContext?
    private var termSnapshots: [ClubInvitationFeedbackKey: ClubInvitationFeedbackTerms] = [:]
    private var visibility: UUID?
    private var generation = UUID()
    private(set) var snapshotID = UUID()
    func bind(_ context: ClubInvitationFeedbackContext) {
        guard bound != context else { return }; bound = context; visibility = nil; generation = UUID(); termSnapshots = [:]
    }
    func activate(_ context: ClubInvitationFeedbackContext) -> Permit? {
        guard bound == context, context.canRead, !Task.isCancelled else { return nil }
        if visibility == nil { visibility = UUID(); generation = UUID(); snapshotID = UUID(); loaded = nil; snapshot = nil; termSnapshots = [:]; phase = .idle }
        return permit(in: context)
    }
    func permit(in context: ClubInvitationFeedbackContext) -> Permit? {
        guard bound == context, context.canRead, let visibility else { return nil }; return .init(context: context, visibility: visibility)
    }
    private func accepts(_ permit: Permit) -> Bool { bound == permit.context && visibility == permit.visibility && permit.context.canRead }
    func accepted(_ context: ClubInvitationFeedbackContext, clubReader: any ClubReading, reader: any CoopFlowReading, access: any ClubGovernanceAccess) -> ClubInvitationFeedbackSnapshot? {
        guard permit(in: context) != nil, loaded == context, phase == .ready,
              context.matches(clubReader: clubReader, reader: reader, access: access) else { return nil }; return snapshot
    }
    func terms(for target: ClubInvitationFeedbackTarget, in context: ClubInvitationFeedbackContext,
               clubReader: any ClubReading, reader: any CoopFlowReading,
               access: any ClubGovernanceAccess) -> ClubInvitationFeedbackTerms? {
        guard let snapshot = accepted(context, clubReader: clubReader, reader: reader, access: access),
              target.isCurrent(snapshot: snapshot, context: context, snapshotID: snapshotID) else { return nil }
        return termSnapshots[target.row.id]
    }
    func leave(_ context: ClubInvitationFeedbackContext) {
        guard bound == context else { return }; visibility = nil; generation = UUID(); snapshotID = UUID(); loaded = nil; snapshot = nil; termSnapshots = [:]; phase = .idle
    }
    func load(_ permit: Permit, clubReader: any ClubReading, reader: any CoopFlowReading, access: any ClubGovernanceAccess) async {
        guard accepts(permit), permit.context.matches(clubReader: clubReader, reader: reader, access: access), !Task.isCancelled else { return }
        generation = UUID(); let request = generation
        snapshot = nil; loaded = nil; termSnapshots = [:]; snapshotID = UUID(); phase = .loading
        let current = { [self] in
            accepts(permit) && generation == request && !Task.isCancelled && permit.context.matches(clubReader: clubReader, reader: reader, access: access)
        }
        defer { if generation == request, accepts(permit), phase == .loading { phase = .idle } }
        do {
            let freshClub = try await clubReader.clubDetail(id: permit.context.clubID, isCurrent: current)
            guard current() else { return }
            guard freshClub.id == permit.context.clubID, freshClub.isOwner else { phase = .denied; return }
            let topics = try await access.read(.topics, scope: .init(clubID: permit.context.clubID), options: [:]) {
                guard current() else { throw CancellationError() }
            }
            guard current(), permit.context.topicsContext.accepts(topics) else { throw CancellationError() }
            let invitations = try await reader.read(.invitations, isCurrent: current)
            guard current() else { return }
            let projected = try ClubInvitationFeedbackSnapshot(context: permit.context, topics: topics, invitations: invitations)
            let projectedTerms = try ClubInvitationFeedbackTerms.project(projected, invitations: invitations)
            guard current() else { return }
            termSnapshots = projectedTerms
            loaded = permit.context; snapshot = projected; phase = .ready
        } catch {
            guard current() else { return }; phase = .failed
        }
    }
}

@MainActor struct ClubInvitationFeedbackEntry<ClubReader: ClubReading & ObservableObject>: View {
    let club: ClubRecord
    @ObservedObject var clubReader: ClubReader
    let reader: any CoopFlowReading
    let access: any ClubGovernanceAccess
    var body: some View {
        let context = ClubInvitationFeedbackContext(club: club, clubReader: clubReader, reader: reader, access: access)
        if context.canRead {
            Section {
                NavigationLink {
                    ClubInvitationFeedbackView(club: club, clubReader: clubReader, reader: reader, access: access)
                } label: { Label("club.inviteFeedback.title", systemImage: "envelope.open") }
                    .accessibilityIdentifier("club.inviteFeedback.entry")
            }
        }
    }
}

@MainActor struct ClubInvitationFeedbackView<ClubReader: ClubReading & ObservableObject>: View {
    let club: ClubRecord
    @ObservedObject var clubReader: ClubReader
    let reader: any CoopFlowReading
    let access: any ClubGovernanceAccess
    @StateObject private var model = ClubInvitationFeedbackReadModel()
    @State private var direction = ClubInvitationFeedbackDirection.received
    @State private var selected: ClubInvitationFeedbackTarget?
    init(club: ClubRecord, clubReader: ClubReader, reader: any CoopFlowReading,
         access: any ClubGovernanceAccess, initialDirection: ClubInvitationFeedbackDirection = .received) {
        self.club = club; self.clubReader = clubReader; self.reader = reader; self.access = access
        _direction = State(initialValue: initialDirection)
    }
    private var context: ClubInvitationFeedbackContext { .init(club: club, clubReader: clubReader, reader: reader, access: access) }
    private func accepted(_ scope: ClubInvitationFeedbackContext) -> ClubInvitationFeedbackSnapshot? { model.accepted(scope, clubReader: clubReader, reader: reader, access: access) }
    var body: some View {
        let scope = context
        let _ = model.bind(scope)
        List {
            Text("club.inviteFeedback.readOnly").font(.footnote)
            if !scope.canRead || model.phase == .denied { Text("club.inviteFeedback.ownerRequired").accessibilityIdentifier("club.inviteFeedback.denied") }
            else {
                Picker("club.inviteFeedback.direction", selection: $direction) {
                    Text("club.inviteFeedback.received").tag(ClubInvitationFeedbackDirection.received)
                    Text("club.inviteFeedback.sent").tag(ClubInvitationFeedbackDirection.sent)
                }.pickerStyle(.segmented).accessibilityIdentifier("club.inviteFeedback.direction")
                if model.phase == .loading { ProgressView("club.loading").accessibilityIdentifier("club.inviteFeedback.loading") }
                if model.phase == .failed { Text("club.inviteFeedback.failed").accessibilityIdentifier("club.inviteFeedback.failed") }
                if let snapshot = accepted(scope) {
                    let rows = snapshot.rows(in: direction)
                    if rows.isEmpty { Text(LocalizedStringKey(direction == .received ? "club.inviteFeedback.receivedEmpty" : "club.inviteFeedback.sentEmpty")).accessibilityIdentifier("club.inviteFeedback.empty") }
                    ForEach(rows) { row in
                        if let target = snapshot.target(key: row.id, context: scope, snapshotID: model.snapshotID) {
                            Button {
                                guard selected == nil, current(target) else { return }; selected = target
                            } label: { ClubInvitationFeedbackRowLabel(row: row) }
                                .buttonStyle(.borderless).accessibilityIdentifier("club.inviteFeedback.row.\(row.id.direction.rawValue).\(row.id.invitationID)")
                        }
                    }
                }
                Button(LocalizedStringKey(model.phase == .failed ? "action.retry" : "club.refresh")) { reload(scope) }
                    .disabled(model.phase == .loading || model.permit(in: scope) == nil).accessibilityIdentifier("club.inviteFeedback.reload")
            }
        }
        .navigationTitle("club.inviteFeedback.title")
        .task(id: scope) {
            selected = nil
            guard let permit = model.activate(scope) else { return }
            await model.load(permit, clubReader: clubReader, reader: reader, access: access)
        }
        .onChange(of: scope) { _, _ in selected = nil }
        .onDisappear { selected = nil; model.leave(scope) }
        .sheet(item: $selected, onDismiss: { reload(scope) }) { target in
            NavigationStack {
                Group {
                    if current(target) {
                        List {
                            ClubInvitationFeedbackRowLabel(row: target.row)
                            LabeledContent("club.inviteFeedback.invitationID", value: String(target.row.id.invitationID))
                            if let topicID = target.row.topicID { LabeledContent("club.gov.field.topicId", value: String(topicID)) }
                            if let message = target.row.message { Section("club.inviteFeedback.message") { Text(verbatim: message).textSelection(.enabled) } }
                            if let terms = model.terms(for: target, in: context,
                                clubReader: clubReader, reader: reader, access: access) {
                                ClubInvitationFeedbackTermsView(terms: terms)
                            }
                            Text("club.inviteFeedback.readOnly").font(.footnote)
                        }
                    } else { Color.clear }
                }
                .navigationTitle("club.inviteFeedback.detail")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("club.gov.close") { selected = nil } } }
                .onChange(of: current(target), initial: true) { _, valid in if !valid { selected = nil } }
            }
        }
    }
    private func reload(_ scope: ClubInvitationFeedbackContext) {
        guard context == scope, scope.matches(clubReader: clubReader, reader: reader, access: access), let permit = model.permit(in: scope) else { return }
        Task { await model.load(permit, clubReader: clubReader, reader: reader, access: access) }
    }
    private func current(_ target: ClubInvitationFeedbackTarget) -> Bool {
        target.isCurrent(snapshot: accepted(context), context: context, snapshotID: model.snapshotID)
    }
}

private struct ClubInvitationFeedbackRowLabel: View {
    let row: ClubInvitationFeedbackRow
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let name = row.partnerName { Text(verbatim: name).font(.headline) }
            else { Text("club.inviteFeedback.partnerUnknown").font(.headline) }
            Text(LocalizedStringKey(row.statusKey))
            if let topic = row.topicName { Text(verbatim: topic) }
            else if row.id.direction == .sent { Text("club.inviteFeedback.topicUnknown") }
            if let date = row.createdAt { LabeledContent("club.inviteFeedback.serverTime") { Text(verbatim: date) } }
            Label("club.inviteFeedback.detail", systemImage: "info.circle")
        }
    }
}

private struct ClubInvitationFeedbackTermsView: View {
    let terms: ClubInvitationFeedbackTerms
    var body: some View {
        Section("cooperation.terms") {
            switch terms.shareMode {
            case 0: Text("cooperation.terms.traffic")
            case 1:
                Text("cooperation.terms.share")
                if let rate = terms.shareRate {
                    LabeledContent("cooperation.shareRate", value: "\(number(rate))%")
                        .accessibilityIdentifier("club.inviteFeedback.shareRate")
                } else { Text("cooperation.amountUnknown") }
            case 2:
                Text("cooperation.terms.fixed")
                if let fee = terms.fixedFee {
                    LabeledContent("cooperation.fixedFee", value: number(fee))
                        .accessibilityIdentifier("club.inviteFeedback.fixedFee")
                    Text("cooperation.currencyUnknown").font(.footnote)
                } else { Text("cooperation.amountUnknown") }
            default: Text("cooperation.termsUnknown")
            }
            if terms.termsFrozen { Label("cooperation.termsFrozen", systemImage: "lock") }
            if let reason = terms.handleReason, !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                LabeledContent("cooperation.handleReason") { Text(verbatim: reason).textSelection(.enabled) }
                    .accessibilityIdentifier("club.inviteFeedback.handleReason")
            }
        }
    }
    private func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...8)))
    }
}
