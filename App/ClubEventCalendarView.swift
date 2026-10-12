import SwiftUI

/// Read-only P045 calendar. It uses the existing service's access/me preflight;
/// it neither creates a new transport nor enables any dormant write capability.
@MainActor final class ClubEventCalendarReadModel: ObservableObject {
    @Published private(set) var snapshot: ClubEventCalendarSnapshot?
    @Published private(set) var activityOverview: ClubActivityOverview?
    @Published private(set) var context: ClubGovernanceReadContext?
    @Published private(set) var loading = false
    @Published private(set) var failure: ClubGovernanceFailure?
    private(set) var generation: UInt64 = 0
    private(set) var snapshotGeneration: UInt64 = 0
    private var active = true

    func invalidate() {
        generation &+= 1; snapshot = nil; activityOverview = nil; context = nil; loading = false; failure = nil
    }
    func suspend() {
        active = false; generation &+= 1; loading = false
    }
    func resume() { active = true }
    func live(_ expected: ClubGovernanceReadContext, access: any ClubGovernanceAccess) -> Bool {
        expected.operation == .topics && (expected.scope.clubID ?? 0) > 0 &&
        (expected.identity?.accountID ?? 0) > 0 && access.isConfigured &&
        expected.identity == access.identity && expected.authorizationGeneration == access.authorizationGeneration &&
        expected.accessIdentity == ObjectIdentifier(access)
    }
    func accepted(_ expected: ClubGovernanceReadContext, access: any ClubGovernanceAccess) -> Bool {
        context == expected && snapshot != nil && live(expected, access: access)
    }
    func canSelect(_ expected: ClubGovernanceReadContext, access: any ClubGovernanceAccess) -> Bool {
        active && !loading && accepted(expected, access: access)
    }
    func load(_ expected: ClubGovernanceReadContext, access: any ClubGovernanceAccess, now: () -> Date = Date.init) async {
        invalidate(); let revision = generation
        guard active, !Task.isCancelled else { return }
        guard (expected.identity?.accountID ?? 0) > 0 else { failure = .signedOut; return }
        guard live(expected, access: access) else { failure = .notConfigured; return }
        loading = true
        defer { if revision == generation { loading = false } }
        func check() throws {
            guard active, revision == generation, live(expected, access: access), !Task.isCancelled else { throw CancellationError() }
        }
        do {
            // This check occurs before the first dispatch and after each await.
            try check()
            let response = try await access.read(.topics, scope: expected.scope, options: [:], check: check)
            try check()
            let projected = try ClubActivityOverview(snapshot: response, context: expected, now: now())
            context = expected; snapshotGeneration = revision; snapshot = projected.calendar; activityOverview = projected
        } catch {
            guard active, revision == generation, live(expected, access: access), !Task.isCancelled else { return }
            failure = error as? ClubGovernanceFailure ?? .malformed
        }
    }
}

@MainActor struct ClubEventCalendarView: View {
    let clubID: Int
    let identity: ClubReadIdentity
    let governance: ClubGovernanceContext
    @StateObject private var model = ClubEventCalendarReadModel()
    @State private var month = ClubEventMonth()
    @State private var calendarMode = false
    @State private var selectedDay: ClubEventDay?
    @State private var destination: ClubEventTopicRoute?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var readContext: ClubGovernanceReadContext {
        .init(operation: .topics, scope: .init(clubID: clubID), identity: identity,
              viewerRevision: governance.viewerRevision, authorizationGeneration: governance.access.authorizationGeneration,
              accessIdentity: ObjectIdentifier(governance.access))
    }
    private var accepted: ClubEventCalendarSnapshot? {
        model.accepted(readContext, access: governance.access) ? model.snapshot : nil
    }
    var body: some View {
        List {
            Picker("club.calendar.display", selection: $calendarMode) {
                Text("club.calendar.list").tag(false)
                Text("club.calendar.monthView").tag(true)
            }.pickerStyle(.segmented).accessibilityIdentifier("club.calendar.mode")
            if model.loading { ProgressView().accessibilityIdentifier("club.calendar.loading") }
            if let failure = model.failure {
                Text(LocalizedStringKey(failure.localizationKey)).accessibilityIdentifier("club.calendar.error")
            }
            if let snapshot = accepted {
                if calendarMode { calendar(snapshot) }
                else if let overview = model.activityOverview {
                    let renderedContext = readContext, renderedGeneration = model.snapshotGeneration
                    ClubActivityListContent(overview: overview, canOpen: governance.topicDestination != nil && model.canSelect(readContext, access: governance.access)) { row in
                        guard overview == model.activityOverview, renderedContext == readContext, renderedGeneration == model.snapshotGeneration,
                              overview.rows.contains(row) else { return }
                        select(row.id)
                    }
                }
            }
            Button("club.gov.refresh") { refresh() }.disabled(model.loading)
                .accessibilityIdentifier("club.calendar.refresh")
        }
        .navigationTitle("club.calendar.title")
        .navigationDestination(item: $destination) { target in
            if current(target), let detail = governance.topicDestination {
                detail(target.topicID).id(target.id)
            } else {
                Color.clear.onAppear { if destination?.id == target.id { destination = nil } }
            }
        }
        .task(id: readContext) {
            let expected = readContext
            destination = nil; selectedDay = nil; model.resume()
            await model.load(expected, access: governance.access)
        }
        .onChange(of: readContext) { _, _ in destination = nil; selectedDay = nil; model.invalidate() }
        .onAppear { model.resume() }
        .onDisappear { model.suspend() }
        .refreshable { destination = nil; await model.load(readContext, access: governance.access) }
    }
    @ViewBuilder private func calendar(_ snapshot: ClubEventCalendarSnapshot) -> some View {
        Section {
            HStack {
                Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.borderless).disabled(month.shifted(by: -1) == nil)
                    .accessibilityLabel("club.calendar.previous").accessibilityIdentifier("club.calendar.previous")
                Spacer()
                Text(verbatim: month.key).font(.headline).accessibilityIdentifier("club.calendar.month")
                Spacer()
                Button { shift(1) } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.borderless).disabled(month.shifted(by: 1) == nil)
                    .accessibilityLabel("club.calendar.next").accessibilityIdentifier("club.calendar.next")
            }
            Text("club.calendar.startDates").font(.footnote).foregroundStyle(.secondary)
            let cells = month.cells(events: snapshot.events)
            if dynamicTypeSize.isAccessibilitySize {
                // Keep long names and every event reachable with large text.
                ForEach(cells.filter { !$0.events.isEmpty }) { cell in
                    Text(verbatim: cell.day.id).font(.headline)
                    ForEach(cell.events) { event in eventRow(event, showDate: false) }
                }
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 8) {
                    ForEach(1...7, id: \.self) { day in
                        Text(LocalizedStringKey("club.calendar.weekday." + String(day))).font(.caption).accessibilityHidden(true)
                    }
                    ForEach(cells) { cell in
                        Button { selectedDay = cell.day } label: {
                            VStack(spacing: 3) {
                                Text(cell.day.day, format: .number).fontWeight(selectedDay == cell.day ? .bold : .regular)
                                if !cell.events.isEmpty { Text(cell.events.count, format: .number).font(.caption2).foregroundStyle(.tint) }
                                else { Text(" ").font(.caption2) }
                            }
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .foregroundStyle(cell.inMonth ? Color.primary : Color.secondary)
                            .background(selectedDay == cell.day ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(Text("club.calendar.day \(cell.day.id) \(cell.events.count)"))
                        .accessibilityAddTraits(selectedDay == cell.day ? .isSelected : [])
                        .accessibilityIdentifier("club.calendar.day.\(cell.day.id)")
                    }
                }
                if let selectedDay {
                    Text(verbatim: selectedDay.id).font(.headline)
                    let events = snapshot.events.filter { $0.startDay == selectedDay }
                    if events.isEmpty { Text("club.calendar.noDayEvents") }
                    ForEach(events) { event in eventRow(event, showDate: false) }
                } else { Text("club.calendar.pickDay").font(.footnote).foregroundStyle(.secondary) }
            }
            if !cells.contains(where: { $0.inMonth && !$0.events.isEmpty }) {
                Text("club.calendar.noMonthEvents").accessibilityIdentifier("club.calendar.monthEmpty")
            }
        }
        if !snapshot.undated.isEmpty {
            Section("club.calendar.undated") {
                Text("club.calendar.undatedHint").font(.footnote).foregroundStyle(.secondary)
                ForEach(snapshot.undated) { event in eventRow(event, showDate: false) }
            }
        }
    }
    @ViewBuilder private func eventRow(_ event: ClubCalendarEvent, showDate: Bool) -> some View {
        if governance.topicDestination != nil {
            Button { select(event.id) } label: { eventLabel(event, showDate: showDate) }
                .accessibilityIdentifier("club.calendar.topic.\(event.id)")
        } else { eventLabel(event, showDate: showDate) }
    }
    private func eventLabel(_ event: ClubCalendarEvent, showDate: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let name = event.name { Text(verbatim: name) } else { Text("club.calendar.untitled") }
            if showDate {
                if let day = event.startDay { Text(verbatim: day.id).font(.caption).foregroundStyle(.secondary) }
                else { Text("club.calendar.dateUnknown").font(.caption).foregroundStyle(.secondary) }
            }
        }.padding(.vertical, 4)
    }
    private func shift(_ delta: Int) {
        guard let next = month.shifted(by: delta) else { return }
        month = next; selectedDay = nil
    }
    private func refresh() {
        destination = nil
        Task { await model.load(readContext, access: governance.access) }
    }
    private func select(_ topicID: Int) {
        guard destination == nil, governance.topicDestination != nil,
              model.canSelect(readContext, access: governance.access), let snapshot = accepted else { return }
        destination = .init(topicID: topicID, snapshot: snapshot, context: readContext, snapshotGeneration: model.snapshotGeneration)
    }
    private func current(_ route: ClubEventTopicRoute) -> Bool {
        governance.topicDestination != nil && model.accepted(readContext, access: governance.access) &&
        route.isCurrent(snapshot: accepted, context: readContext, snapshotGeneration: model.snapshotGeneration)
    }
}
