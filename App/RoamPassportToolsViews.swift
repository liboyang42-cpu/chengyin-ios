import SwiftUI

/// Mini-program subpackageTools/anniversary and monthly-recap. Read-only; identity changes reset all private rows.
@MainActor struct RoamPassportToolsSection: View {
    let reader: (any RoamPassportToolsReading)?
    var routeDestination: ((String) -> AnyView)? = nil
    /// 导出探索记录 (scene-roam-history tools `export`).
    var privateTools: (any RoamPrivateToolsServing)? = nil
    var body: some View {
        Section("roam.tools.title") {
            NavigationLink { RoamAnniversaryView(reader: reader, routeDestination: routeDestination) } label: {
                Label("roam.tools.anniversary", systemImage: "calendar")
            }.accessibilityIdentifier("roam.tools.anniversary.open")
            NavigationLink { RoamMonthlyRecapView(reader: reader) } label: {
                Label("roam.tools.recap", systemImage: "chart.bar")
            }.accessibilityIdentifier("roam.tools.recap.open")
            NavigationLink { RoamExplorationExportView(tools: privateTools) } label: {
                Label("roam.export.title", systemImage: "square.and.arrow.down")
            }.accessibilityIdentifier("roam.export.open")
        }
    }
}

@MainActor struct RoamAnniversaryView: View {
    let reader: (any RoamPassportToolsReading)?
    var routeDestination: ((String) -> AnyView)? = nil
    var body: some View {
        RoamAnniversaryContent(reader: reader, routeDestination: routeDestination).id(reader?.identity)
            .appNavigationTitle("roam.tools.anniversary")
    }
}

@MainActor private struct RoamAnniversaryContent: View {
    let reader: (any RoamPassportToolsReading)?
    let routeDestination: ((String) -> AnyView)?
    /// nil = "today" by the archive contract, until the player picks another day.
    @State private var selected: (month: Int, day: Int)? = nil
    @State private var pickerDate = Date()
    @State private var page: RoamAnniversaryPage?
    @State private var rows: [RoamAnniversaryMemory] = []
    @State private var error: Error?
    @State private var loading = false
    @State private var generation = 0
    @State private var navigation = RoamAnniversaryNavigationState()
    private static let shanghai: Calendar = {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: RoamShanghaiCalendar.offsetSeconds)!; return calendar
    }()
    private var dateLabel: String {
        if let selected { return "\(selected.month)." + String(format: "%02d", selected.day) }
        if let page { return "\(page.month)." + String(format: "%02d", page.day) }
        let today = RoamShanghaiCalendar.today()
        return "\(today.month)." + String(format: "%02d", today.day)
    }
    var body: some View {
        List {
            Section {
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: dateLabel).font(.largeTitle.bold()).monospacedDigit()
                        .accessibilityIdentifier("roam.tools.anniversary.date")
                    Spacer()
                    DatePicker("roam.tools.anniversary.change", selection: $pickerDate, displayedComponents: .date)
                        .environment(\.timeZone, Self.shanghai.timeZone)
                        .labelsHidden()
                        .disabled(loading || reader?.identity == nil)
                        .accessibilityLabel(Text("roam.tools.anniversary.change"))
                        .accessibilityIdentifier("roam.tools.anniversary.change")
                }
            }
            if let reader, reader.isOfflineExample { Section { RoamExperienceNotice(offline: true) } }
            if let error {
                Section { RoamExperienceIssue(error: error) { Task { await load(cursor: nil) } } }
                    .accessibilityIdentifier("roam.tools.anniversary.error")
            }
            if loading && rows.isEmpty {
                Section { ProgressView("roam.tools.anniversary.loading") }
            }
            ForEach(rows) { item in
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("roam.tools.anniversary.yearsAgo \(item.yearsAgo)").font(.headline).foregroundStyle(.tint)
                        Text(verbatim: item.title ?? "").font(.title3.bold())
                        Text("roam.tools.anniversary.completed \(item.completedMinuteText)").font(.subheadline).foregroundStyle(.secondary)
                    }.accessibilityElement(children: .combine)
                        .accessibilityIdentifier("roam.tools.anniversary.row")
                    switch RoamAnniversaryRouteAvailability.resolve(memory: item, hasDestination: routeDestination != nil) {
                    case .available(let target):
                        if let routeDestination {
                            NavigationLink {
                                RoamAnniversaryRouteHost(presentation: navigation.openedPresentation, owner: reader?.identity,
                                                         destination: routeDestination, navigation: $navigation)
                            } label: { Text("roam.tools.anniversary.openRoute") }
                                .accessibilityIdentifier("roam.tools.anniversary.openRoute")
                                .simultaneousGesture(TapGesture().onEnded {
                                    _ = navigation.open(target, memory: item, currentRows: rows, owner: reader?.identity)
                                })
                        }
                    case .invalidTopicID, .noDestination:
                        Label("topic.unavailable", systemImage: "exclamationmark.circle")
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("roam.tools.anniversary.routeUnavailable")
                    }
                }
            }
            if page != nil && !loading && rows.isEmpty && error == nil {
                Section { Text("roam.tools.anniversary.empty").foregroundStyle(.secondary) }
                    .accessibilityIdentifier("roam.tools.anniversary.empty")
            }
            if let page, page.hasMore, !loading {
                Button("roam.tools.loadMore") { Task { await load(cursor: page.nextCursor) } }
                    .accessibilityIdentifier("roam.tools.anniversary.more")
            }
        }
        .task { navigation.bind(to: reader?.identity); await load(cursor: nil) }
        .onAppear {
            navigation.bind(to: reader?.identity)
            // Only this screen becoming visible again is a true pop/close of
            // the route. It must carry the original lease, and refreshes the
            // same selected date exactly once; a stale lease changes nothing.
            if let lease = navigation.openedPresentation,
               navigation.completeReturn(presentation: lease, owner: reader?.identity) { Task { await load(cursor: nil) } }
        }
        .onChange(of: reader?.identity) { _, newOwner in
            navigation.bind(to: newOwner)
            generation += 1; loading = false; rows = []; page = nil; error = nil; selected = nil
        }
        .onChange(of: pickerDate) { _, value in
            let parts = Self.shanghai.dateComponents([.month, .day], from: value)
            guard let month = parts.month, let day = parts.day else { return }
            if let selected, selected.month == month, selected.day == day { return }
            selected = (month, day)
            navigation.invalidate()
            Task { await load(cursor: nil) }
        }
        .refreshable { await load(cursor: nil) }
        .onDisappear { generation += 1; loading = false }
        .accessibilityIdentifier("roam.tools.anniversary")
    }
    private func load(cursor: String?) async {
        guard let reader else { error = APIError.notConfigured; return }
        generation += 1; let ticket = generation
        let owner = reader.identity
        if cursor == nil { rows = []; page = nil }
        error = nil; loading = true
        let query = RoamAnniversaryQuery(month: selected?.month, day: selected?.day, limit: 20, cursor: cursor,
                                         referenceYear: cursor == nil ? nil : page?.referenceYear)
        do {
            let value = try await reader.anniversary(query, boundary: cursor == nil ? nil : rows.last)
            guard ticket == generation, owner == reader.identity else { return }
            if cursor == nil { rows = value.items } else { rows += value.items }
            page = value
        } catch {
            guard ticket == generation, owner == reader.identity else { return }
            // Cancellation is a result, not an error: keep the confirmed rows and show no error.
            if error is CancellationError { loading = false; return }
            // A failed continuation keeps nothing unconfirmed: the old page stays, the new one is not merged.
            self.error = error
        }
        loading = false
    }
}

/// Pushes the host's existing topic detail for one validated card, under the
/// lease minted when the card was tapped. Disappearing is NOT a return: the
/// detail may only be covered (e.g. it drilled into a child page), so it just
/// notes the cover and keeps the lease. Only the anniversary screen becoming
/// visible again completes the return, carrying this same lease.
@MainActor private struct RoamAnniversaryRouteHost: View {
    let presentation: RoamAnniversaryRoutePresentation?
    let owner: RoamExperienceIdentity?
    let destination: (String) -> AnyView
    @Binding var navigation: RoamAnniversaryNavigationState
    var body: some View {
        Group {
            if let presentation, navigation.mayRemainOpen(presentation, owner: owner) {
                destination(presentation.target.topicID)
            } else {
                Label("topic.unavailable", systemImage: "exclamationmark.circle")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("roam.tools.anniversary.routeUnavailable")
            }
        }
        .onDisappear { navigation.noteCovered(presentation, owner: owner) }
    }
}

@MainActor struct RoamMonthlyRecapView: View {
    let reader: (any RoamPassportToolsReading)?
    var body: some View {
        RoamMonthlyRecapContent(reader: reader).id(reader?.identity)
            .appNavigationTitle("roam.tools.recap")
    }
}

@MainActor private struct RoamMonthlyRecapContent: View {
    let reader: (any RoamPassportToolsReading)?
    @State private var month: String
    @State private var kind: RoamRecapKind = .routes
    @State private var page: RoamMonthlyRecapPage?
    @State private var error: Error?
    @State private var loading = false
    @State private var generation = 0
    @State private var pickedWeek: Int?
    private let currentMonth: String
    init(reader: (any RoamPassportToolsReading)?) {
        self.reader = reader
        let now = reader?.isOfflineExample == true
            ? Date(timeIntervalSince1970: TimeInterval(RoamPassportToolsFixtureReader.asOfMs) / 1000) : Date()
        currentMonth = RoamShanghaiCalendar.month(now: now)
        _month = State(initialValue: currentMonth)
    }
    private var isCurrentMonth: Bool { month >= currentMonth }
    private var monthDate: Date {
        let (year, value) = RoamShanghaiCalendar.parseMonth(month) ?? (2000, 1)
        return Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: value, day: 15, hour: 12)) ?? Date()
    }
    private func kindKey(_ value: RoamRecapKind) -> LocalizedStringKey {
        switch value { case .routes: return "roam.tools.recap.kind.routes"; case .places: return "roam.tools.recap.kind.places"; case .stamps: return "roam.tools.recap.kind.stamps" }
    }
    private func weeklyKey(_ value: RoamRecapKind) -> LocalizedStringKey {
        switch value { case .routes: return "roam.tools.recap.weekly.routes"; case .places: return "roam.tools.recap.weekly.places"; case .stamps: return "roam.tools.recap.weekly.stamps" }
    }
    var body: some View {
        List {
            Section {
                HStack {
                    Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                        .buttonStyle(.borderless).disabled(loading)
                        .accessibilityLabel(Text("roam.tools.recap.previous"))
                        .accessibilityIdentifier("roam.tools.recap.previous")
                    Spacer()
                    Text(monthDate, format: .dateTime.year().month(.wide)).font(.headline)
                        .accessibilityIdentifier("roam.tools.recap.month")
                    Spacer()
                    Button { shift(1) } label: { Image(systemName: "chevron.right") }
                        .buttonStyle(.borderless).disabled(loading || isCurrentMonth)
                        .accessibilityLabel(Text("roam.tools.recap.next"))
                        .accessibilityIdentifier("roam.tools.recap.next")
                }
            }
            if let reader, reader.isOfflineExample { Section { RoamExperienceNotice(offline: true) } }
            if let error {
                Section { RoamExperienceIssue(error: error) { Task { await load(beforeID: nil) } } }
                    .accessibilityIdentifier("roam.tools.recap.error")
            }
            if loading && page == nil { Section { ProgressView("roam.tools.recap.loading") } }
            if let page {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(page.counts.routes, format: .number).font(.system(size: 56, weight: .bold)).monospacedDigit()
                        Text("roam.tools.recap.routesDone").foregroundStyle(.secondary)
                    }.accessibilityElement(children: .combine).accessibilityIdentifier("roam.tools.recap.routes")
                    LabeledContent("roam.tools.recap.kind.places") { Text(page.counts.places, format: .number) }
                        .accessibilityIdentifier("roam.tools.recap.places")
                    LabeledContent("roam.tools.recap.kind.stamps") { Text(page.counts.stamps, format: .number) }
                        .accessibilityIdentifier("roam.tools.recap.stamps")
                }
            }
            Section {
                Picker("roam.tools.recap.kind", selection: $kind) {
                    ForEach(RoamRecapKind.allCases) { value in Text(kindKey(value)).tag(value) }
                }.pickerStyle(.segmented).disabled(loading)
                    .accessibilityIdentifier("roam.tools.recap.kindPicker")
            }
            if let page, !page.weeks.isEmpty {
                Section(header: Text(weeklyKey(kind)).textCase(nil)) {
                    RoamRecapWeekChart(weeks: page.weeks, picked: $pickedWeek)
                }
            }
            if let page {
                if page.items.isEmpty && !loading && error == nil {
                    Section { Text("roam.tools.recap.empty").foregroundStyle(.secondary) }
                        .accessibilityIdentifier("roam.tools.recap.empty")
                } else {
                    Section {
                        ForEach(page.items) { item in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: item.title)
                                (Text(verbatim: item.dateText + " · ") + Text(kindKey(kind))).font(.caption).foregroundStyle(.secondary)
                            }.accessibilityElement(children: .combine)
                                .accessibilityIdentifier("roam.tools.recap.row")
                        }
                    }
                }
                if page.hasMore, !loading {
                    Button("roam.tools.recap.nextPage") { Task { await load(beforeID: page.nextBeforeID) } }
                        .accessibilityIdentifier("roam.tools.recap.more")
                }
            }
        }
        .task { await load(beforeID: nil) }
        .onChange(of: kind) { _, _ in Task { await load(beforeID: nil) } }
        .refreshable { await load(beforeID: nil) }
        .onDisappear { generation += 1; loading = false }
        .accessibilityIdentifier("roam.tools.recap.screen")
    }
    private func shift(_ delta: Int) {
        guard !loading, let next = RoamShanghaiCalendar.shift(month, by: delta), next <= currentMonth else { return }
        month = next
        Task { await load(beforeID: nil) }
    }
    private func load(beforeID: String?) async {
        guard let reader else { error = APIError.notConfigured; return }
        generation += 1; let ticket = generation
        let owner = reader.identity
        if beforeID == nil { page = nil }
        error = nil; loading = true; pickedWeek = nil
        do {
            // A next page replaces the visible rows: earlier titles are not re-authorized by the new response.
            let value = try await reader.monthlyRecap(RoamMonthlyRecapQuery(month: month, kind: kind, beforeID: beforeID))
            guard ticket == generation, owner == reader.identity else { return }
            page = value
        } catch {
            guard ticket == generation, owner == reader.identity, !(error is CancellationError) else { return }
            page = nil; self.error = error
        }
        loading = false
    }
}

private struct RoamRecapWeekChart: View {
    let weeks: [RoamRecapWeek]
    @Binding var picked: Int?
    var body: some View {
        let top = max(weeks.map(\.count).max() ?? 0, 1)
        HStack(alignment: .bottom, spacing: 12) {
            ForEach(weeks) { week in
                Button { picked = week.index } label: {
                    VStack(spacing: 6) {
                        Text(week.count, format: .number).font(.caption.bold())
                            .opacity(week.isMax || picked == week.index ? 1 : 0)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(week.isMax ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary.opacity(0.4)))
                            .frame(width: 14, height: max(4, CGFloat(week.count) / CGFloat(top) * 110))
                        Text("roam.tools.recap.week \(week.index)").font(.caption2).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity)
                }.buttonStyle(.plain)
                    .accessibilityLabel(Text("roam.tools.recap.weekCount \(week.index) \(week.count)"))
            }
        }.frame(height: 170).accessibilityIdentifier("roam.tools.recap.weeks")
    }
}
