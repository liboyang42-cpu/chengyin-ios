import SwiftUI
import UIKit

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
            NavigationLink { RoamMonthlyRecapView(reader: reader, routeDestination: routeDestination) } label: {
                Label("roam.tools.recap", systemImage: "chart.bar")
            }.accessibilityIdentifier("roam.tools.recap.open")
            NavigationLink { RoamExplorationExportView(tools: privateTools) } label: {
                Label("roam.export.title", systemImage: "square.and.arrow.down")
            }.accessibilityIdentifier("roam.export.open")
        }
    }
}

/// The original reader's selected read grant, not a new capability. Non-session examples
/// retain their existing identity contract; live pages cannot inherit another grant's rows.
struct RoamPassportToolsPageOwner: Hashable {
    let readerID: ObjectIdentifier?
    let identity: RoamExperienceIdentity?
    let readScope: UUID?
    @MainActor init(_ reader: (any RoamPassportToolsReading)?) {
        readerID = reader.map { ObjectIdentifier($0) }; identity = reader?.identity
        readScope = (reader as? RoamPassportToolsSessionReader)?.readScope
    }
    @MainActor func matches(_ reader: (any RoamPassportToolsReading)?) -> Bool { self == Self(reader) }
}

@MainActor struct RoamAnniversaryView: View {
    let reader: (any RoamPassportToolsReading)?
    var routeDestination: ((String) -> AnyView)? = nil
    var body: some View {
        let owner = RoamPassportToolsPageOwner(reader)
        RoamAnniversaryContent(reader: reader, routeDestination: routeDestination, pageOwner: owner).id(owner)
            .appNavigationTitle("roam.tools.anniversary")
    }
}

/// Frozen UI read intent. Existing Core generations still own pagination and request completion.
struct RoamAnniversaryReadIntent {
    let intent: RoamAnniversaryListState.Intent
    private let readerID: ObjectIdentifier?
    private let owner: RoamExperienceIdentity?
    private let pageOwner: RoamPassportToolsPageOwner
    private let listGeneration: UInt64
    private let routeGeneration: UInt64
    private let visit: UUID
    @MainActor init(intent: RoamAnniversaryListState.Intent, reader: (any RoamPassportToolsReading)?,
                    state: RoamAnniversaryListState, navigation: RoamAnniversaryNavigationState, visit: UUID) {
        self.intent = intent; readerID = reader.map { ObjectIdentifier($0) }; owner = reader?.identity
        pageOwner = RoamPassportToolsPageOwner(reader)
        listGeneration = state.generation; routeGeneration = navigation.generation; self.visit = visit
    }
    @MainActor func matches(reader: (any RoamPassportToolsReading)?, state: RoamAnniversaryListState,
                            navigation: RoamAnniversaryNavigationState, visit: UUID) -> Bool {
        pageOwner.matches(reader) && self.visit == visit && readerID == reader.map { ObjectIdentifier($0) } && owner == reader?.identity &&
        listGeneration == state.generation && routeGeneration == navigation.generation
    }
}

@MainActor private struct RoamAnniversaryContent: View {
    let pageOwner: RoamPassportToolsPageOwner
    let reader: (any RoamPassportToolsReading)?
    let routeDestination: ((String) -> AnyView)?
    @Environment(\.scenePhase) private var scenePhase
    @State private var isVisible = false
    @State private var visit = UUID()
    @State private var pickerDate = Date()
    @State private var state = RoamAnniversaryListState()
    @State private var navigation = RoamAnniversaryNavigationState()
    init(reader: (any RoamPassportToolsReading)?, routeDestination: ((String) -> AnyView)?,
         pageOwner: RoamPassportToolsPageOwner) {
        self.reader = reader; self.routeDestination = routeDestination; self.pageOwner = pageOwner
    }
    private static let shanghai: Calendar = {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: RoamShanghaiCalendar.offsetSeconds)!; return calendar
    }()
    private var dateLabel: String {
        if let day = state.displayedDay { return "\(day.month)." + String(format: "%02d", day.day) }
        let today = RoamShanghaiCalendar.today()
        return "\(today.month)." + String(format: "%02d", today.day)
    }
    private var unavailableError: Error? {
        guard let reader else { return APIError.notConfigured }
        guard reader.identity != nil else { return APIError.unauthorized }
        return reader.isConfigured && pageOwner.matches(reader) ? nil : APIError.notConfigured
    }
    var body: some View {
        let retry = readIntent(state.retryIntent), more = readIntent(.more), refresh = readIntent(.refresh)
        List {
            Section {
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: dateLabel).font(.largeTitle.bold()).monospacedDigit()
                        .accessibilityIdentifier("roam.tools.anniversary.date")
                    Spacer()
                    DatePicker("roam.tools.anniversary.change", selection: $pickerDate, displayedComponents: .date)
                        .environment(\.timeZone, Self.shanghai.timeZone)
                        .environment(\.calendar, Self.shanghai)
                        .labelsHidden()
                        .disabled(state.isLoading || unavailableError != nil)
                        .accessibilityLabel(Text("roam.tools.anniversary.change"))
                        .accessibilityIdentifier("roam.tools.anniversary.change")
                }
            }
            if let reader, reader.isOfflineExample { Section { RoamExperienceNotice(offline: true) } }
            if let error = unavailableError ?? state.error {
                Section { RoamExperienceIssue(error: error) { enqueue(retry) } }
                    .accessibilityIdentifier("roam.tools.anniversary.error")
            }
            if state.isLoading {
                Section { ProgressView("roam.tools.anniversary.loading") }
            }
            ForEach(unavailableError == nil ? state.rows : []) { item in
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("roam.tools.anniversary.yearsAgo \(item.yearsAgo)").font(.headline).foregroundStyle(.tint)
                        Text(verbatim: item.title ?? "").font(.title3.bold())
                        Text("roam.tools.anniversary.completed \(item.completedMinuteText)").font(.subheadline).foregroundStyle(.secondary)
                    }.accessibilityElement(children: .combine)
                        .accessibilityIdentifier("roam.tools.anniversary.row")
                    switch RoamAnniversaryRouteAvailability.resolve(memory: item, hasDestination: routeDestination != nil) {
                    case .available(let target):
                        if routeDestination != nil {
                            Button {
                                guard isVisible, scenePhase == .active, unavailableError == nil else { return }
                                _ = navigation.open(target, memory: item, currentRows: state.rows, owner: reader?.identity)
                            } label: { Text("roam.tools.anniversary.openRoute") }
                                .disabled(state.isLoading)
                                .accessibilityIdentifier("roam.tools.anniversary.openRoute")
                        }
                    case .invalidTopicID, .noDestination:
                        Label("topic.unavailable", systemImage: "exclamationmark.circle")
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("roam.tools.anniversary.routeUnavailable")
                    }
                }
            }
            if unavailableError == nil && state.page != nil && !state.isLoading && state.rows.isEmpty && state.error == nil {
                Section { Text("roam.tools.anniversary.empty").foregroundStyle(.secondary) }
                    .accessibilityIdentifier("roam.tools.anniversary.empty")
            }
            if unavailableError == nil, let page = state.page, page.hasMore, !state.isLoading, state.error == nil {
                Button("roam.tools.loadMore") { enqueue(more) }
                    .accessibilityIdentifier("roam.tools.anniversary.more")
            }
        }
        .navigationDestination(item: routeBinding(navigation.openedPresentation, owner: reader?.identity)) { lease in
            if let routeDestination {
                RoamAnniversaryRouteHost(presentation: lease, owner: reader?.identity,
                                         reader: reader, pageOwner: pageOwner, destination: routeDestination, navigation: $navigation)
            }
        }
        .onAppear {
            isVisible = true; visit = UUID()
            navigation.bind(to: reader?.identity)
            state.bind(to: reader?.identity)
            if state.page == nil, navigation.openedPresentation == nil { state.requestRefresh() }
            enqueueRefreshIfNeeded()
        }
        .onChange(of: reader.map { ObjectIdentifier($0) }) { _, _ in
            // A replacement reader with the same account cannot inherit the old reader's rows/tasks.
            navigation.invalidate(); state.bind(to: nil); state.bind(to: reader?.identity)
            enqueueRefreshIfNeeded()
        }
        .onChange(of: reader?.identity) { _, newOwner in
            navigation.bind(to: newOwner)
            state.bind(to: newOwner)
            enqueueRefreshIfNeeded()
        }
        .onChange(of: reader?.isConfigured) { _, configured in
            if configured != true {
                navigation.invalidate()
                state.revokeAccess(unavailableError ?? APIError.notConfigured)
            } else {
                state.requestRefresh()
                enqueueRefreshIfNeeded()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                visit = UUID()
                state.requestRefresh()
                state.suspend()
            } else {
                enqueueRefreshIfNeeded()
            }
        }
        .onChange(of: state.displayedDay) { _, day in
            if let date = day?.pickerDate(referenceYear: state.page?.referenceYear ?? RoamShanghaiCalendar.today().year) {
                pickerDate = date
            }
        }
        .onChange(of: pickerDate) { _, value in
            let parts = Self.shanghai.dateComponents([.month, .day], from: value)
            guard let month = parts.month, let day = parts.day else { return }
            guard let selected = RoamAnniversaryListState.Day(month: month, day: day), state.select(selected) else { return }
            navigation.invalidate()
            enqueue(readIntent(.refresh))
        }
        .refreshable { await load(refresh) }
        .onDisappear { isVisible = false; visit = UUID(); state.suspend() }
        .accessibilityIdentifier("roam.tools.anniversary")
    }
    /// Capture the lease in the binding, not when a delayed pop callback runs.
    /// SwiftUI sets this item to nil for the actual pop, not for child coverage.
    private func routeBinding(_ lease: RoamAnniversaryRoutePresentation?,
                              owner: RoamExperienceIdentity?) -> Binding<RoamAnniversaryRoutePresentation?> {
        Binding(get: {
            unavailableError == nil && navigation.mayRemainOpen(lease, owner: owner) ? lease : nil
        }, set: { value in
            guard value == nil, pageOwner.matches(reader), owner == reader?.identity,
                  navigation.completeReturn(presentation: lease, owner: owner) else { return }
            state.requestRefresh()
            // The exact original pop lease already earned this refresh. Its queued read must
            // also keep the same source list generation and visit until dispatch.
            enqueueRefreshIfNeeded()
        })
    }
    private func readIntent(_ intent: RoamAnniversaryListState.Intent) -> RoamAnniversaryReadIntent {
        .init(intent: intent, reader: reader, state: state, navigation: navigation, visit: visit)
    }
    private func enqueue(_ offered: RoamAnniversaryReadIntent) {
        Task { await load(offered) }
    }
    private func enqueueRefreshIfNeeded() {
        guard state.needsRefresh else { return }
        enqueue(readIntent(.refresh))
    }
    private func load(_ offered: RoamAnniversaryReadIntent) async {
        guard !Task.isCancelled, isVisible, scenePhase == .active, navigation.openedPresentation == nil,
              pageOwner.matches(reader), offered.matches(reader: reader, state: state, navigation: navigation, visit: visit) else { return }
        guard unavailableError == nil else {
            state.revokeAccess(unavailableError ?? APIError.notConfigured)
            return
        }
        guard let reader, let request = state.begin(offered.intent, owner: reader.identity) else { return }
        do {
            var pages: [RoamAnniversaryPage] = []
            var query = request.query
            var boundary = request.boundary
            while pages.count < request.pageCount {
                guard pageOwner.matches(reader), state.isCurrent(request, owner: reader.identity) else { return }
                let value = try await reader.anniversary(query, boundary: boundary)
                try Task.checkCancellation()
                guard pageOwner.matches(reader), state.isCurrent(request, owner: reader.identity) else { return }
                guard reader.isConfigured else {
                    state.revokeAccess(APIError.notConfigured)
                    return
                }
                pages.append(value)
                guard value.hasMore else { break }
                query = RoamAnniversaryQuery(month: value.month, day: value.day, limit: request.query.limit,
                    cursor: value.nextCursor, referenceYear: value.referenceYear)
                boundary = value.items.last
            }
            _ = try state.accept(pages, for: request, owner: reader.identity)
        } catch {
            guard pageOwner.matches(reader) else { return }
            state.fail(error, for: request, owner: reader.identity, isConfigured: reader.isConfigured)
        }
    }
}

/// Pushes the host's existing topic detail for one validated card, under the
/// lease minted when the card was tapped. Disappearing is NOT a return: the
/// detail may only be covered (e.g. it drilled into a child page), so it just
/// notes the cover and keeps the lease. Only the navigation item's pop binding
/// completes the return, carrying this same immutable lease.
@MainActor private struct RoamAnniversaryRouteHost: View {
    let presentation: RoamAnniversaryRoutePresentation?
    let owner: RoamExperienceIdentity?
    let reader: (any RoamPassportToolsReading)?
    let pageOwner: RoamPassportToolsPageOwner
    let destination: (String) -> AnyView
    @Binding var navigation: RoamAnniversaryNavigationState
    var body: some View {
        Group {
            if let presentation, pageOwner.matches(reader), reader?.identity == owner, reader?.isConfigured == true,
               navigation.mayRemainOpen(presentation, owner: owner) {
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
    @Environment(\.themeDomain) private var domain
    let reader: (any RoamPassportToolsReading)?
    var routeDestination: ((String) -> AnyView)? = nil
    var body: some View {
        RoamMonthlyRecapContent(reader: reader, routeDestination: routeDestination).id(RoamPassportToolsPageOwner(reader))
            .font(Theme.Font.body)
            .tint(Theme.Color.accent(in: domain))
            .scrollContentBackground(.hidden)
            .background(Theme.Color.bgPage(in: domain))
            .themeDomain(domain)
            .appNavigationTitle("roam.tools.recap")
    }
}

@MainActor private struct RoamMonthlyRecapContent: View {
    let reader: (any RoamPassportToolsReading)?
    let routeDestination: ((String) -> AnyView)?
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var lifetime: Lifetime
    private var model: RoamMonthlyRecapCoordinator { lifetime.model }
    private var readerID: ObjectIdentifier? { reader.map { ObjectIdentifier($0) } }
    @State private var pickedWeek: Int?
    init(reader: (any RoamPassportToolsReading)?, routeDestination: ((String) -> AnyView)?) {
        self.reader = reader; self.routeDestination = routeDestination
        _lifetime = StateObject(wrappedValue: Lifetime(reader: reader))
    }
    /// Scope and UI epoch only. The existing coordinator remains the sole query/cursor/detail owner.
    @MainActor private final class Lifetime: ObservableObject {
        @Published private(set) var model: RoamMonthlyRecapCoordinator
        @Published private(set) var active = false
        @Published private(set) var foreground = false
        @Published private(set) var ready = false
        private var source: (any RoamPassportToolsReading)?
        private var identity: RoamExperienceIdentity?
        private var readScope: UUID?
        private var mounted = false
        private var ticket = UUID()
        private var readTask: Task<Void, Never>?
        private var deferredReturn: RoamMonthlyRecapPresentation?
        init(reader: (any RoamPassportToolsReading)?) {
            source = reader; identity = reader?.identity
            readScope = (reader as? RoamPassportToolsSessionReader)?.readScope
            model = RoamMonthlyRecapCoordinator(reader: reader)
        }
        func matches(_ reader: (any RoamPassportToolsReading)?) -> Bool {
            source.map { ObjectIdentifier($0) } == reader.map { ObjectIdentifier($0) } && identity == reader?.identity &&
            readScope == (reader as? RoamPassportToolsSessionReader)?.readScope
        }
        func canPresent(_ reader: (any RoamPassportToolsReading)?) -> Bool { active && foreground && matches(reader) }
        func bind(_ reader: (any RoamPassportToolsReading)?) {
            guard !matches(reader) else { return }
            suspend(); deferredReturn = nil
            source = reader; identity = reader?.identity
            readScope = (reader as? RoamPassportToolsSessionReader)?.readScope
            model = RoamMonthlyRecapCoordinator(reader: reader)
        }
        func appear(_ reader: (any RoamPassportToolsReading)?, foreground: Bool) {
            mounted = true; bind(reader); resume(reader, foreground: foreground)
        }
        func resume(_ reader: (any RoamPassportToolsReading)?, foreground: Bool) {
            self.foreground = foreground
            guard mounted, foreground, !active else { return }
            active = true
            // A background detail dismissal is not permission to read while hidden. Finish that
            // exact original return only now, before allowing a fresh selection from the list.
            let returning = deferredReturn ?? model.presentation; deferredReturn = nil
            if let returning, model.isCurrent(returning) { run(reader) { await $0.completeReturn(returning) } }
            else { run(reader) { await $0.activate() } }
        }
        func suspend() {
            active = false; foreground = false; ready = false; ticket = UUID()
            readTask?.cancel(); readTask = nil; model.suspend()
        }
        func disappear() {
            // A sheet cover must not cancel its queued exact-return read. The attachment below
            // independently catches real parent pop/dismiss/dismantle, including while covered.
            if model.presentation != nil { return }
            leave()
        }
        func leave() { mounted = false; deferredReturn = nil; suspend() }
        func run(_ reader: (any RoamPassportToolsReading)?, _ work: @escaping @MainActor (RoamMonthlyRecapCoordinator) async -> Void) {
            let offered = ticket
            readTask = Task { [self] in
                guard offered == ticket, canPresent(reader), !Task.isCancelled else { return }
                await perform(reader, work)
            }
        }
        func perform(_ reader: (any RoamPassportToolsReading)?, _ work: @MainActor (RoamMonthlyRecapCoordinator) async -> Void) async {
            guard canPresent(reader), !Task.isCancelled else { return }
            ticket = UUID(); let offered = ticket, original = model
            ready = false; original.suspend()
            await work(original)
            guard offered == ticket, canPresent(reader), model === original, !Task.isCancelled else { return }
            ready = true
        }
        func returnFrom(_ lease: RoamMonthlyRecapPresentation, reader: (any RoamPassportToolsReading)?) {
            guard matches(reader), model.isCurrent(lease) else { return }
            if canPresent(reader) { run(reader) { await $0.completeReturn(lease) } }
            else { deferredReturn = lease }
        }
        func accessChanged(_ reader: (any RoamPassportToolsReading)?, foreground: Bool) {
            bind(reader); suspend(); model.synchronizeAccess(); resume(reader, foreground: foreground)
        }
    }
    @MainActor private struct LifetimeAttachment: UIViewControllerRepresentable {
        let lifetime: Lifetime
        func makeUIViewController(context: Context) -> Controller { Controller(lifetime: lifetime) }
        func updateUIViewController(_ controller: Controller, context: Context) {}
        static func dismantleUIViewController(_ controller: Controller, coordinator: ()) { controller.lifetime.leave() }
        @MainActor final class Controller: UIViewController {
            let lifetime: Lifetime
            init(lifetime: Lifetime) { self.lifetime = lifetime; super.init(nibName: nil, bundle: nil) }
            required init?(coder: NSCoder) { return nil }
            override func viewWillDisappear(_ animated: Bool) {
                super.viewWillDisappear(animated)
                var current: UIViewController? = self
                while let value = current {
                    if value.isBeingDismissed || value.isMovingFromParent { lifetime.leave(); return }
                    current = value.parent
                }
            }
        }
    }
    private var month: String { model.month }
    private var kind: RoamRecapKind { model.kind }
    private var page: RoamMonthlyRecapPage? { lifetime.canPresent(reader) && lifetime.ready && model.isLive ? model.page : nil }
    private var error: Error? { model.error }
    private var loading: Bool { model.isLoading }
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
            if lifetime.canPresent(reader) {
            Section {
                HStack {
                    Button { lifetime.run(reader) { await $0.shiftMonth(by: -1) } } label: { Image(systemName: "chevron.left") }
                        .buttonStyle(.borderless).disabled(!model.canGoPrevious)
                        .accessibilityLabel(Text("roam.tools.recap.previous"))
                        .accessibilityIdentifier("roam.tools.recap.previous")
                    Spacer()
                    Text(monthDate, format: .dateTime.year().month(.wide)).font(.headline)
                        .accessibilityIdentifier("roam.tools.recap.month")
                    Spacer()
                    Button { lifetime.run(reader) { await $0.shiftMonth(by: 1) } } label: { Image(systemName: "chevron.right") }
                        .buttonStyle(.borderless).disabled(!model.canGoNext)
                        .accessibilityLabel(Text("roam.tools.recap.next"))
                        .accessibilityIdentifier("roam.tools.recap.next")
                }
            }
            if let reader, reader.isOfflineExample { Section { RoamExperienceNotice(offline: true) } }
            if let error {
                Section { RoamExperienceIssue(error: error) { lifetime.run(reader) { await $0.retry() } } }
                    .accessibilityIdentifier("roam.tools.recap.error")
            }
            if (loading || !lifetime.ready) && page == nil { Section { ProgressView("roam.tools.recap.loading") } }
            if let page {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(page.counts.routes, format: .number).font(Theme.Font.pageTitle).monospacedDigit()
                        Text("roam.tools.recap.routesDone").foregroundStyle(.secondary)
                    }.accessibilityElement(children: .combine).accessibilityIdentifier("roam.tools.recap.routes")
                    LabeledContent("roam.tools.recap.kind.places") { Text(page.counts.places, format: .number) }
                        .accessibilityIdentifier("roam.tools.recap.places")
                    LabeledContent("roam.tools.recap.kind.stamps") { Text(page.counts.stamps, format: .number) }
                        .accessibilityIdentifier("roam.tools.recap.stamps")
                }
            }
            Section {
                Picker("roam.tools.recap.kind", selection: Binding(get: { model.kind }, set: { value in lifetime.run(reader) { await $0.select(kind: value) } })) {
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
                            Button {
                                guard lifetime.canPresent(reader), lifetime.ready else { return }
                                _ = model.open(item)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(verbatim: item.title)
                                    (Text(verbatim: item.dateText + " · ") + Text(kindKey(kind))).font(.caption).foregroundStyle(.secondary)
                                }
                            }.accessibilityElement(children: .combine)
                                .accessibilityIdentifier("roam.tools.recap.row")
                        }
                    }
                }
                if page.hasMore, !loading {
                    Button("roam.tools.recap.nextPage") { lifetime.run(reader) { await $0.nextPage() } }
                        .accessibilityIdentifier("roam.tools.recap.more")
                }
            }
            }
        }
        .disabled(!lifetime.canPresent(reader))
        .privacySensitive()
        .background(LifetimeAttachment(lifetime: lifetime).frame(width: 0, height: 0))
        .sheet(item: detailBinding(model.presentation)) { presentation in
            RoamMonthlyRecapDetailView(model: model, presentation: presentation, routeDestination: routeDestination)
        }
        .onAppear { lifetime.appear(reader, foreground: scenePhase == .active) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { lifetime.resume(reader, foreground: true) }
            else { lifetime.suspend() }
        }
        .onChange(of: (reader as? RoamPassportToolsSessionReader)?.readScope) { _, _ in lifetime.bind(reader); lifetime.resume(reader, foreground: scenePhase == .active) }
        .onChange(of: readerID) { _, _ in lifetime.bind(reader); lifetime.resume(reader, foreground: scenePhase == .active) }
        .onChange(of: model.month) { _, _ in pickedWeek = nil }
        .onChange(of: model.kind) { _, _ in pickedWeek = nil }
        .onChange(of: reader?.identity) { _, _ in lifetime.bind(reader); lifetime.resume(reader, foreground: scenePhase == .active) }
        .onChange(of: reader?.isConfigured) { _, _ in lifetime.accessChanged(reader, foreground: scenePhase == .active) }
        .refreshable { pickedWeek = nil; await lifetime.perform(reader) { await $0.refresh() } }
        .onDisappear { lifetime.disappear() }
        .accessibilityIdentifier("roam.tools.recap.screen")
    }
    private func detailBinding(_ lease: RoamMonthlyRecapPresentation?) -> Binding<RoamMonthlyRecapPresentation?> {
        Binding(get: {
            lease.flatMap { model.isCurrent($0) ? $0 : nil }
        }, set: { value in
            guard value == nil, let lease else { return }
            lifetime.returnFrom(lease, reader: reader)
        })
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
