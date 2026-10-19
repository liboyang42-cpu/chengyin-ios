import SwiftUI

/// Copy for pages/merchant/coop-center lives in its own table.
func mcc(_ key: String, _ locale: Locale) -> String {
    String(localized: LocalizedStringResource(String.LocalizationValue(stringLiteral: key), table: "MerchantCoopCenter", locale: locale))
}

/// Read-only cooperation center. Both tab reads start together on first appearance, each with
/// its own in-flight guard; switching tabs never refetches. Opening a card never applies or accepts.
@MainActor final class MerchantCoopCenterModel: ObservableObject {
    enum Issue: Equatable { case signIn, denied, failed(String?) }
    @Published private(set) var routes: [MerchantCoopCenterRoute] = []
    @Published private(set) var routeScope: MerchantCoopCenterPlaza.Scope?
    @Published private(set) var routesLoading = true
    @Published private(set) var routesIssue: Issue?
    @Published private(set) var events: [OfficialEvent] = []
    @Published private(set) var eventsLoading = true
    @Published private(set) var eventsIssue: Issue?
    @Published private(set) var focusedRouteID: String?
    let content: MerchantContentService
    let official: any OfficialEventReading
    private let now: () -> Date
    private let focusTopicID: String?
    private var routesInFlight = false, eventsInFlight = false, started = false

    init(content: MerchantContentService, official: any OfficialEventReading, focusTopicID: Int?, now: @escaping () -> Date) {
        self.content = content; self.official = official; self.now = now
        self.focusTopicID = focusTopicID.flatMap { $0 > 0 ? String($0) : nil }
    }
    func start() { guard !started else { return }; started = true; loadAll() }
    func loadAll() { loadRoutes(); loadEvents() }

    func loadRoutes() {
        guard !routesInFlight else { return }
        routesInFlight = true; routesLoading = true; routesIssue = nil
        let scope = content.scope, service = content, clock = now
        Task { [weak self] in
            let result: Result<MerchantCoopCenterPlaza, Error>
            do {
                let snapshot = try await service.loadRecruitingHome()
                result = .success(try MerchantCoopCenterPlaza(home: snapshot.value, now: clock()))
            } catch { result = .failure(error) }
            guard let self else { return }
            self.routesInFlight = false; self.routesLoading = false
            guard service.scope == scope else {
                // Logout or account change: never show the previous merchant's routes.
                self.routes = []; self.routeScope = nil; self.focusedRouteID = nil; self.routesIssue = .signIn; return
            }
            switch result {
            case .success(let plaza):
                self.routes = plaza.routes; self.routeScope = plaza.scope; self.locateFocus()
            case .failure(let error):
                if error as? MerchantCoopCenterFailure == .malformed { self.routeScope = nil }
                self.routesIssue = Self.issue(error)
            }
        }
    }

    func loadEvents() {
        guard !eventsInFlight else { return }
        eventsInFlight = true; eventsLoading = true; eventsIssue = nil
        let reader = official, scope = official.scope
        Task { [weak self] in
            let result: Result<[OfficialEvent], Error>
            do { result = .success(MerchantOfficialRecruitment.visible(try await reader.events(city: nil))) }
            catch { result = .failure(error) }
            guard let self else { return }
            self.eventsInFlight = false; self.eventsLoading = false
            guard reader.scope == scope else { self.events = []; self.eventsIssue = .signIn; return }
            switch result {
            case .success(let rows): self.events = rows
            case .failure(let error): self.eventsIssue = Self.issue(error)
            }
        }
    }

    /// Source CU-M-85: mark and scroll to the recommended topic; absent means stay quietly on the list.
    private func locateFocus() {
        guard let focusTopicID, routes.contains(where: { $0.id == focusTopicID }) else { return }
        focusedRouteID = focusTopicID
    }

    static func issue(_ error: Error) -> Issue {
        if let error = error as? APIError, error == .unauthorized { return .signIn }
        if let error = error as? MerchantContentFailure {
            switch error {
            case .denied: return .denied
            case .rejected(_, let message):
                let text = message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return .failed(text.isEmpty ? nil : text)
            default: return .failed(nil)
            }
        }
        if let error = error as? OfficialReadFailure, error == .forbidden || error == .noPublisherPermission { return .denied }
        return .failed(nil)
    }
}

@MainActor struct MerchantCoopCenterView: View {
    @StateObject private var model: MerchantCoopCenterModel
    @State private var tab: MerchantCoopCenterTab
    @State private var showsInbox = false
    @Environment(\.locale) private var locale
    private let officialActions: OfficialActionCoordinator?
    private let inboxDestination: ((@escaping () -> Void) -> AnyView)?

    init(content: MerchantContentService, official: any OfficialEventReading, initialTab: MerchantCoopCenterTab = .plaza,
         focusTopicID: Int? = nil, officialActions: OfficialActionCoordinator? = nil, now: @escaping () -> Date = { Date() },
         inboxDestination: ((@escaping () -> Void) -> AnyView)? = nil) {
        _model = StateObject(wrappedValue: MerchantCoopCenterModel(content: content, official: official, focusTopicID: focusTopicID, now: now))
        _tab = State(initialValue: initialTab)
        self.officialActions = officialActions; self.inboxDestination = inboxDestination
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker(selection: $tab) {
                Text(mcc("merchantCoopCenter.tab.official", locale)).tag(MerchantCoopCenterTab.official)
                Text(mcc("merchantCoopCenter.tab.plaza", locale)).tag(MerchantCoopCenterTab.plaza)
            } label: { Text(mcc("merchantCoopCenter.title", locale)) }
            .pickerStyle(.segmented).padding(.horizontal, 16).padding(.vertical, 8)
            .accessibilityIdentifier("merchantCoopCenter.tabs")
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        switch tab {
                        case .plaza: plaza
                        case .official: officialList
                        }
                    }.padding(16)
                }
                .onChange(of: model.focusedRouteID) { _, id in
                    guard let id, tab == .plaza else { return }
                    withAnimation { proxy.scrollTo("route." + id, anchor: .top) }
                }
            }
        }
        .navigationTitle(mcc("merchantCoopCenter.title", locale))
        .toolbar {
            if inboxDestination != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showsInbox = true } label: { Image(systemName: "bell") }
                        .accessibilityLabel(mcc("merchantCoopCenter.inbox", locale))
                        .accessibilityIdentifier("merchantCoopCenter.inbox")
                }
            }
        }
        .sheet(isPresented: $showsInbox) { inboxDestination?({ showsInbox = false }) }
        .task { model.start() }
    }

    // MARK: 广场
    @ViewBuilder private var plaza: some View {
        if model.routesLoading && model.routes.isEmpty {
            MerchantCoopCenterSkeleton()
        } else if let issue = model.routesIssue, model.routes.isEmpty {
            issueView(issue, title: mcc("merchantCoopCenter.plaza.error.title", locale), fallback: mcc("merchantCoopCenter.plaza.error.fallback", locale),
                      id: "merchantCoopCenter.plaza.error") { model.loadRoutes() }
        } else {
            if model.routesLoading {
                Text(mcc("merchantCoopCenter.plaza.refreshing", locale)).font(.footnote).foregroundStyle(.secondary)
                    .accessibilityIdentifier("merchantCoopCenter.plaza.refreshing")
            }
            ForEach(Array(model.routes.enumerated()), id: \.offset) { _, route in
                MerchantCoopCenterRouteCard(route: route, focused: model.focusedRouteID == route.id, content: model.content)
                    .id("route." + route.id)
            }
            if let scope = model.routeScope {
                Text(String(format: mcc("merchantCoopCenter.plaza.scope", locale), scope.openCount, scope.shownCount))
                    .font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                    .accessibilityIdentifier("merchantCoopCenter.plaza.scope")
            }
            if model.routes.isEmpty {
                emptyView(mcc("merchantCoopCenter.plaza.empty", locale), id: "merchantCoopCenter.plaza.empty")
            }
        }
    }

    // MARK: 官方活动
    @ViewBuilder private var officialList: some View {
        if model.eventsLoading && model.events.isEmpty {
            MerchantCoopCenterSkeleton()
        } else if let issue = model.eventsIssue, model.events.isEmpty {
            issueView(issue, title: mcc("merchantCoopCenter.official.error.title", locale), fallback: mcc("merchantCoopCenter.official.error.fallback", locale),
                      id: "merchantCoopCenter.official.error") { model.loadEvents() }
        } else {
            if model.eventsLoading {
                Text(mcc("merchantCoopCenter.official.refreshing", locale)).font(.footnote).foregroundStyle(.secondary)
                    .accessibilityIdentifier("merchantCoopCenter.official.refreshing")
            }
            ForEach(model.events) { event in
                NavigationLink {
                    OfficialEventDetailView(id: event.id, reader: model.official, actions: officialActions)
                } label: { MerchantCoopCenterEventCard(event: event) }
                .buttonStyle(.plain)
                .accessibilityHint(String(format: mcc("merchantCoopCenter.official.openLabel", locale), event.title))
                .accessibilityIdentifier("merchantCoopCenter.event." + String(event.id))
            }
            if model.events.isEmpty {
                emptyView(mcc("merchantCoopCenter.official.empty", locale), id: "merchantCoopCenter.official.empty")
            }
        }
    }

    private func emptyView(_ title: String, id: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "tray").font(.largeTitle).foregroundStyle(.secondary)
            Text(title).font(.headline)
            Button(mcc("merchantCoopCenter.refresh", locale)) { model.loadAll() }
                .buttonStyle(.borderedProminent).accessibilityIdentifier("merchantCoopCenter.refresh")
        }
        .frame(maxWidth: .infinity).padding(.vertical, 48)
        .accessibilityElement(children: .contain).accessibilityIdentifier(id)
    }

    /// The source veils load failures; native keeps a visible reason and an explicit retry.
    @ViewBuilder private func issueView(_ issue: MerchantCoopCenterModel.Issue, title: String, fallback: String, id: String,
                                        retry: @escaping () -> Void) -> some View {
        VStack(spacing: 10) {
            switch issue {
            case .signIn:
                Image(systemName: "person.crop.circle.badge.exclamationmark").font(.largeTitle).foregroundStyle(.secondary)
                Text(mcc("merchantCoopCenter.signIn.title", locale)).font(.headline)
                Text(mcc("merchantCoopCenter.signIn.reason", locale)).font(.subheadline).foregroundStyle(.secondary)
            case .denied:
                Image(systemName: "lock").font(.largeTitle).foregroundStyle(.secondary)
                Text(mcc("merchantCoopCenter.denied.title", locale)).font(.headline)
                Text(mcc("merchantCoopCenter.denied.reason", locale)).font(.subheadline).foregroundStyle(.secondary)
            case .failed(let message):
                Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(.secondary)
                Text(title).font(.headline)
                Text(message ?? fallback).font(.subheadline).foregroundStyle(.secondary)
                Button(mcc("merchantCoopCenter.retry", locale), action: retry)
                    .buttonStyle(.bordered).accessibilityIdentifier("merchantCoopCenter.retry")
            }
        }
        .multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.vertical, 48)
        .accessibilityElement(children: .contain).accessibilityIdentifier(id)
    }
}

private struct MerchantCoopCenterSkeleton: View {
    @Environment(\.locale) private var locale
    var body: some View {
        VStack(spacing: 12) {
            ForEach(0..<2, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 16).fill(.quaternary).frame(height: 148)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(mcc("merchantCoopCenter.loading", locale))
        .accessibilityIdentifier("merchantCoopCenter.loading")
    }
}

/// 稿 234:276 route card: 模式 / 余席 / 档期 / 地点 / 结算方式 / 招商截止 + 看详情.
struct MerchantCoopCenterRouteCard: View {
    let route: MerchantCoopCenterRoute
    let focused: Bool
    let content: MerchantContentService
    @Environment(\.locale) private var locale
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                if let mode = modeText {
                    Text(mode).font(.caption.weight(.semibold)).padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                }
                Spacer()
                if let seat = seatText {
                    Text(seat.text).font(.caption.weight(.semibold)).foregroundStyle(seat.tight ? Color.orange : Color.green)
                        .accessibilityIdentifier("merchantCoopCenter.route.seat." + route.id)
                }
            }
            HStack(alignment: .top, spacing: 12) {
                cover
                VStack(alignment: .leading, spacing: 4) {
                    if let date = dateText { Text(date).font(.caption).foregroundStyle(.secondary) }
                    Text(route.title).font(.headline).fixedSize(horizontal: false, vertical: true)
                    if let meta = metaText { Text("◎  " + meta).font(.caption).foregroundStyle(.secondary) }
                }
            }
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    if let terms = termsText { Text(terms).font(.subheadline) }
                    if let deadline = deadlineText {
                        Text(deadline).font(.caption).foregroundStyle(.secondary)
                            .accessibilityIdentifier("merchantCoopCenter.route.deadline." + route.id)
                    }
                }
                Spacer()
                if let topicID = route.topicID {
                    NavigationLink {
                        MerchantContentDocumentView(service: content, query: .chapters(topicID: topicID))
                    } label: { Text(mcc("merchantCoopCenter.detail", locale)) }
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel(String(format: mcc("merchantCoopCenter.detail.label", locale), route.title))
                    .accessibilityIdentifier("merchantCoopCenter.route.detail." + route.id)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay { if focused { RoundedRectangle(cornerRadius: 16).stroke(Color.accentColor, lineWidth: 2) } }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("merchantCoopCenter.route." + route.id + (focused ? ".focused" : ""))
    }
    @ViewBuilder private var cover: some View {
        let shape = RoundedRectangle(cornerRadius: 10)
        if let url = QuestifyCardArtwork.safeURL(route.cover) {
            AsyncImage(url: url) { phase in
                if let image = phase.image { image.resizable().scaledToFill() } else { shape.fill(.quaternary) }
            }.frame(width: 72, height: 72).clipShape(shape).accessibilityHidden(true)
        } else { shape.fill(.quaternary).frame(width: 72, height: 72).accessibilityHidden(true) }
    }
    private var modeText: String? {
        switch route.mode {
        case .cityOrienteering: return mcc("merchantCoopCenter.mode.city", locale)
        case .freeExploration: return mcc("merchantCoopCenter.mode.free", locale)
        case nil: return nil
        }
    }
    private var seatText: (text: String, tight: Bool)? {
        switch route.seat {
        case .full: return (mcc("merchantCoopCenter.seat.full", locale), true)
        case .remaining(let count, let tight): return (String(format: mcc("merchantCoopCenter.seat.remaining", locale), count), tight)
        case nil: return nil
        }
    }
    private func monthDay(_ value: MerchantCoopCenterMonthDay) -> String {
        String(format: mcc("merchantCoopCenter.date.monthDay", locale), value.month, value.day)
    }
    private var dateText: String? {
        guard let range = route.dateRange else { return nil }
        guard let end = range.1 else { return monthDay(range.0) }
        return String(format: mcc("merchantCoopCenter.date.range", locale), monthDay(range.0), monthDay(end))
    }
    private var metaText: String? {
        let parts = [route.city, route.stationCount.map { String(format: mcc("merchantCoopCenter.meta.stations", locale), $0) }].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
    private func shortTerms(_ mode: MerchantCoopCenterRoute.TermsMode) -> String {
        switch mode {
        case .perk: return mcc("merchantCoopCenter.terms.perk", locale)
        case .revshare: return mcc("merchantCoopCenter.terms.revshare", locale)
        case .traffic: return mcc("merchantCoopCenter.terms.trafficShort", locale)
        }
    }
    private var termsText: String? {
        switch route.terms {
        case .none: return nil
        case .mixed(let modes): return modes.map(shortTerms).joined(separator: " / ")
        case .single(let mode, let amount):
            switch mode {
            case .perk:
                guard let amount else { return mcc("merchantCoopCenter.terms.perk", locale) }
                return String(format: mcc("merchantCoopCenter.terms.perkAmount", locale), amount)
            case .revshare:
                guard let amount else { return mcc("merchantCoopCenter.terms.revshare", locale) }
                return String(format: mcc("merchantCoopCenter.terms.revshareAmount", locale), amount)
            case .traffic: return mcc("merchantCoopCenter.terms.traffic", locale)
            }
        }
    }
    private var deadlineText: String? {
        switch route.deadline {
        case .open(let day): return String(format: mcc("merchantCoopCenter.deadline.open", locale), monthDay(day))
        case .closed: return mcc("merchantCoopCenter.deadline.closed", locale)
        case nil: return nil
        }
    }
}

/// Official recruitment card with the source copy (全城 fallback, 信息不全 gap marker, 查看活动).
struct MerchantCoopCenterEventCard: View {
    let event: OfficialEvent
    @Environment(\.locale) private var locale
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(cityText).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(event.title).font(.headline).fixedSize(horizontal: false, vertical: true)
            if let subtitle = event.subtitle, !subtitle.isEmpty { Text(subtitle).font(.subheadline).foregroundStyle(.secondary) }
            if event.recruitmentBlocked == true {
                VStack(alignment: .leading, spacing: 2) {
                    Label(mcc("merchantCoopCenter.official.gap", locale), systemImage: "exclamationmark.triangle").font(.subheadline.weight(.semibold))
                    Text(event.recruitmentWarningReason ?? mcc("merchantCoopCenter.official.gapFallback", locale)).font(.caption)
                }
                .foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("merchantCoopCenter.event.gap." + String(event.id))
            }
            HStack(spacing: 4) {
                Text(mcc("merchantCoopCenter.official.open", locale))
                Image(systemName: "chevron.right").accessibilityHidden(true)
            }.font(.subheadline.weight(.semibold)).foregroundStyle(Color.accentColor)
        }
        .padding().frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
    private var cityText: String {
        if let city = event.city, !city.isEmpty { return city }
        return mcc("merchantCoopCenter.official.cityAll", locale)
    }
}
