import SwiftUI

/// Mini pages/club/event-ops hub. It only orders existing governance reads; each pushed
/// read re-checks access/me and owns its own writes, review/confirm and return reads.
@MainActor struct ClubOpsEventView: View {
    let scope: ClubGovernanceScope
    let identity: ClubReadIdentity?
    let access: any ClubGovernanceAccess
    let coordinator: ClubGovernanceCoordinator
    struct Key: Equatable {
        let identity: ClubReadIdentity?
        let authorization: UUID?
        let reader: ObjectIdentifier
        let scope: ClubGovernanceScope
    }
    @State private var model: ClubOpsEventAccess?
    @State private var loadedKey: Key?
    @State private var failure: ClubGovernanceFailure?
    @State private var loading = false
    @State private var generation: UInt64 = 0
    private var key: Key { .init(identity: identity, authorization: access.authorizationGeneration, reader: ObjectIdentifier(access), scope: scope) }
    private var accessScope: ClubGovernanceScope { .init(clubID: scope.clubID, activityID: scope.activityID) }
    private var eventScope: ClubGovernanceScope { .init(clubID: scope.clubID, topicID: scope.topicID, activityID: scope.activityID) }
    var body: some View {
        List {
            if loading { ProgressView().accessibilityIdentifier("clubOpsEvent.loading") }
            else if failure == .forbidden || (loadedKey == key && model?.permitted == false) { denied }
            else if let failure {
                Section {
                    Text(LocalizedStringKey(failure.localizationKey)).accessibilityIdentifier("clubOpsEvent.error")
                    Button("action.retry") { Task { await load() } }.accessibilityIdentifier("clubOpsEvent.retry")
                }
            } else if loadedKey == key, let model {
                ForEach(model.sections, id: \.self) { section in self.section(section, model: model) }
            }
        }
        .navigationTitle(Text("clubOpsEvent.title", tableName: "ClubOpsEvent"))
        .accessibilityIdentifier("clubOpsEvent.root")
        .task(id: key) { await load() }
        .refreshable { await load() }
    }
    private var denied: some View {
        Section {
            Text("clubOpsEvent.denied.title", tableName: "ClubOpsEvent").font(.headline)
            Text("clubOpsEvent.denied.body", tableName: "ClubOpsEvent").font(.footnote).foregroundStyle(.secondary)
        }.accessibilityIdentifier("clubOpsEvent.denied")
    }
    @ViewBuilder private func section(_ section: ClubOpsEventSection, model: ClubOpsEventAccess) -> some View {
        switch section {
        case .occurrence:
            Section {
                if model.rosterHiddenForManager {
                    Text("clubOpsEvent.roster.hidden", tableName: "ClubOpsEvent").accessibilityIdentifier("clubOpsEvent.roster.hidden")
                }
                push(.occurrenceStatus, eventScope) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("club.gov.action.cancelOccurrence")
                        Text("clubOpsEvent.cancel.subtitle", tableName: "ClubOpsEvent").font(.footnote).foregroundStyle(.secondary)
                    }
                }
            } header: { Text("clubOpsEvent.section.occurrence", tableName: "ClubOpsEvent") }
        case .roster:
            Section {
                push(.roster, eventScope) { Text("clubOpsEvent.section.roster", tableName: "ClubOpsEvent") }
                Text("club.roster.privacy").font(.footnote).foregroundStyle(.secondary)
            } header: { Text("clubOpsEvent.section.roster", tableName: "ClubOpsEvent") }
        case .series:
            Section {
                push(.series, .init(clubID: scope.clubID)) { Text("clubOpsEvent.section.series", tableName: "ClubOpsEvent") }
                Text("clubOpsEvent.series.note", tableName: "ClubOpsEvent").font(.footnote).foregroundStyle(.secondary)
            } header: { Text("clubOpsEvent.section.series", tableName: "ClubOpsEvent") }
        case .recurrence:
            Section {
                push(.eventTopics, .init(clubID: scope.clubID, topicID: scope.topicID)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("clubOpsEvent.recurrence.add", tableName: "ClubOpsEvent")
                        Text("clubOpsEvent.recurrence.addHint", tableName: "ClubOpsEvent").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Text("clubOpsEvent.recurrence.note", tableName: "ClubOpsEvent").font(.footnote).foregroundStyle(.secondary)
                Text("clubOpsEvent.refundAnchor", tableName: "ClubOpsEvent").font(.footnote).foregroundStyle(.secondary)
            } header: { Text("clubOpsEvent.section.recurrence", tableName: "ClubOpsEvent") }
        case .capacity:
            Section {
                Text("clubOpsEvent.capacity.note", tableName: "ClubOpsEvent").font(.footnote)
                Text("clubOpsEvent.capacity.help", tableName: "ClubOpsEvent").font(.footnote).foregroundStyle(.secondary)
                Text("clubOpsEvent.offer.help", tableName: "ClubOpsEvent").font(.footnote).foregroundStyle(.secondary)
            } header: { Text("clubOpsEvent.section.capacity", tableName: "ClubOpsEvent") }
        }
    }
    private func push<RowLabel: View>(_ read: ClubGovernanceRead, _ target: ClubGovernanceScope, @ViewBuilder label: () -> RowLabel) -> some View {
        NavigationLink {
            ClubGovernanceReadView(operation: read, scope: target, identity: identity, access: access, coordinator: coordinator)
        } label: { label() }
            .accessibilityIdentifier("clubOpsEvent.open." + read.rawValue)
    }
    private func load() async {
        generation &+= 1
        let revision = generation, expected = key
        model = nil; loadedKey = nil; failure = nil; loading = true
        guard identity?.isSignedIn == true, identity == access.identity, (scope.clubID ?? 0) > 0 else {
            loading = false; failure = identity?.isSignedIn == true ? .invalidRequest : .signedOut; return
        }
        let check: () throws -> Void = {
            guard revision == generation, expected == key, !Task.isCancelled else { throw CancellationError() }
        }
        do {
            let snapshot = try await access.read(.access, scope: accessScope, options: [:], check: check)
            guard revision == generation, expected == key, !Task.isCancelled else { return }
            guard snapshot.operation == .access, snapshot.scope == accessScope, let permissions = snapshot.permissions else {
                throw ClubGovernanceFailure.malformed
            }
            model = ClubOpsEventAccess(permissions: permissions, scope: eventScope); loadedKey = expected
        } catch {
            guard revision == generation, expected == key else { return }
            if !(error is CancellationError) { failure = error as? ClubGovernanceFailure ?? .malformed }
        }
        if revision == generation { loading = false }
    }
}

/// Mini series row: "{topic} · {单次/每周/自定义日期}" plus collision-only suffix and waitlist meta.
@MainActor struct ClubOpsEventSeriesRowView: View {
    let row: ClubOpsEventSeriesRow
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            title.font(.headline)
            if let enabled = row.waitlistEnabled {
                Text(enabled ? "clubOpsEvent.series.waitlistOn" : "clubOpsEvent.series.waitlistOff", tableName: "ClubOpsEvent")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }.accessibilityIdentifier("clubOpsEvent.series.row.\(row.id)")
    }
    private var title: Text {
        var text = row.topicName.map { Text(verbatim: $0) } ?? Text("clubOpsEvent.series.topicID \(row.topicID)", tableName: "ClubOpsEvent")
        text = text + Text(verbatim: " · ") + Text(LocalizedStringKey("club.gov.choice." + row.recurrence))
        guard !row.suffix.isEmpty else { return text }
        text = text + Text(verbatim: "（")
        for (index, part) in row.suffix.enumerated() {
            if index > 0 { text = text + Text(verbatim: " · ") }
            switch part {
            case .firstDate(let month, let day): text = text + Text("clubOpsEvent.series.firstDate \(month) \(day)", tableName: "ClubOpsEvent")
            case .topic(let id): text = text + Text("clubOpsEvent.series.topicID \(id)", tableName: "ClubOpsEvent")
            case .series(let id): text = text + Text("clubOpsEvent.series.seriesID \(id)", tableName: "ClubOpsEvent")
            }
        }
        return text + Text(verbatim: "）")
    }
}

@MainActor struct ClubOpsEventSeriesHeader: View {
    let empty: Bool
    var body: some View {
        Section {
            Text("clubOpsEvent.series.note", tableName: "ClubOpsEvent").font(.footnote).foregroundStyle(.secondary)
            if empty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("clubOpsEvent.series.empty", tableName: "ClubOpsEvent").font(.headline)
                    Text("clubOpsEvent.series.emptyHint", tableName: "ClubOpsEvent").font(.footnote).foregroundStyle(.secondary)
                }.accessibilityIdentifier("clubOpsEvent.series.empty")
            }
        }
    }
}

struct ClubOpsEventOccurrenceBadgeText: View {
    let badge: ClubOpsEventOccurrenceBadge
    var body: some View {
        switch badge {
        case .cancelled: Text("clubOpsEvent.occurrences.cancelled", tableName: "ClubOpsEvent").foregroundStyle(.red)
        case .editable: Text("clubOpsEvent.occurrences.editable", tableName: "ClubOpsEvent").foregroundStyle(.green)
        case .lockReason(let reason): Text(verbatim: reason).foregroundStyle(.secondary)
        case .locked: Text("clubOpsEvent.occurrences.locked", tableName: "ClubOpsEvent").foregroundStyle(.secondary)
        }
    }
}

struct ClubOpsEventOccurrenceMetaText: View {
    let meta: ClubOpsEventOccurrenceMeta
    var body: some View {
        switch meta {
        case .refunded(let count): Text("clubOpsEvent.occurrences.refunded \(count)", tableName: "ClubOpsEvent")
        case .cancelled: Text("clubOpsEvent.occurrences.cancelled", tableName: "ClubOpsEvent")
        case .signupsPending: Text("clubOpsEvent.occurrences.signupsPending", tableName: "ClubOpsEvent")
        case .noSignups: Text("clubOpsEvent.occurrences.noSignups", tableName: "ClubOpsEvent")
        case .signups(let count, let locked):
            if locked { Text("clubOpsEvent.occurrences.signupsLocked \(count)", tableName: "ClubOpsEvent") }
            else { Text("clubOpsEvent.occurrences.signups \(count)", tableName: "ClubOpsEvent") }
        }
    }
}

/// Mini 本场管理 card over the validated occurrence/status read. Contradictions fail closed.
@MainActor struct ClubOpsEventOccurrenceStatusRows: View {
    let value: ClubGovernanceValue
    let activityID: Int?
    var body: some View {
        switch ClubOpsEventCancellation.state(value, activityID: activityID) {
        case .cancelled(let reason)?:
            VStack(alignment: .leading, spacing: 4) {
                Text("clubOpsEvent.occurrences.cancelled", tableName: "ClubOpsEvent").font(.headline).foregroundStyle(.red)
                if let reason { Text("clubOpsEvent.cancel.reason \(reason)", tableName: "ClubOpsEvent").font(.footnote) }
            }.accessibilityIdentifier("clubOpsEvent.cancel.cancelled")
        case .active?:
            Text("clubOpsEvent.cancel.subtitle", tableName: "ClubOpsEvent").font(.footnote).foregroundStyle(.secondary)
                .accessibilityIdentifier("clubOpsEvent.cancel.active")
        case nil:
            Text("clubOpsEvent.cancel.incomplete", tableName: "ClubOpsEvent").accessibilityIdentifier("clubOpsEvent.cancel.unknownState")
        }
    }
}

/// Mini cancellationSummary for the acknowledged cancel receipt, shown with the existing readback lock.
@MainActor struct ClubOpsEventCancellationReceipt: View {
    let receipt: ClubGovernanceValue
    let confirmed: Bool
    let reread: () -> Void
    var body: some View {
        if !confirmed {
            Text("clubOpsEvent.cancel.incomplete", tableName: "ClubOpsEvent").font(.headline)
                .accessibilityIdentifier("clubOpsEvent.cancel.incomplete")
            Button { reread() } label: { Text("clubOpsEvent.cancel.reread", tableName: "ClubOpsEvent") }
                .accessibilityIdentifier("clubOpsEvent.cancel.reread")
        }
        Text(LocalizedStringKey("clubOpsEvent.refund." + ClubOpsEventCancellation.refund(receipt).rawValue), tableName: "ClubOpsEvent")
            .accessibilityIdentifier("clubOpsEvent.cancel.refund")
        Text(LocalizedStringKey("clubOpsEvent.notify." + ClubOpsEventCancellation.notifications(receipt).rawValue), tableName: "ClubOpsEvent")
            .accessibilityIdentifier("clubOpsEvent.cancel.notify")
    }
}
