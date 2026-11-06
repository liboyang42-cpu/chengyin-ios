import SwiftUI

@MainActor struct NativeChannelCheckinLaunchView: View {
    let makeFlow: () -> NativeChannelCheckinFlow?
    let current: () -> Bool
    var reminderDate: String? = nil
    @State private var flow: NativeChannelCheckinFlow?
    @State private var attempted = false
    var body: some View {
        Group {
            if let flow { NativeChannelCheckinView(flow: flow, current: current, reminderDate: reminderDate) }
            else if attempted { ContentUnavailableView("d7.checkin.unavailable", systemImage: "calendar.badge.checkmark") }
            else { ProgressView() }
        }.task { guard !attempted else { return }; attempted = true; if current() { flow = makeFlow() } }
    }
}
@MainActor private struct NativeChannelCheckinView: View {
    @Bindable var flow: NativeChannelCheckinFlow
    let current: () -> Bool
    let reminderDate: String?
    @Environment(\.scenePhase) private var scene
    @State private var operation = NativeChannelActivityScreenTask()
    @State private var retry = false
    private var available: Bool { current() && scene == .active }
    var body: some View {
        Form {
            if !flow.isCurrent { ContentUnavailableView("d7.checkin.unavailable", systemImage: "calendar.badge.checkmark") }
            else {
                notice
                if let reminderDate { LabeledContent("d7.checkin.reminderDate", value: reminderDate) }
                if let pending = flow.pending {
                    Section("d7.checkin.pending.title") {
                        LabeledContent("d7.checkin.date", value: pending.checkinDate)
                        Button("d7.checkin.pending.check") { run { current in await flow.recover(); guard current() else { return }; await refreshSettled() } }.font(Theme.Font.button).frame(minHeight: 44).disabled(flow.busy || !flow.service.canRecover)
                        Button("d7.checkin.pending.retry") { retry = true }.font(Theme.Font.button).frame(minHeight: 44).disabled(flow.busy || !flow.service.canRecover || !flow.service.canWrite)
                    }
                }
                if let review = flow.review {
                    Section("d7.checkin.review.title") {
                        LabeledContent("d7.checkin.date", value: review.checkinDate)
                        Button("d7.checkin.review.confirm") { run { current in await flow.confirm(); guard current() else { return }; await refreshSettled() } }.nativeChannelPrimaryAction().disabled(flow.busy)
                        Button("d7.channelActivity.cancel", role: .cancel) { flow.cancelReview() }.font(Theme.Font.button).frame(minHeight: 44).disabled(flow.busy)
                    }
                }
                if let status = flow.status {
                    Section {
                        QuestifyHeroValue(value: Text("d7.checkin.streak.value \(status.streak)"), caption: Text("d7.checkin.streak.caption"))
                            .monospacedDigit()
                        if status.checked { Label("d7.checkin.checkedToday", systemImage: "checkmark.seal.fill").fixedSize(horizontal: false, vertical: true) }
                        else { Label("d7.checkin.notCheckedToday", systemImage: "calendar").fixedSize(horizontal: false, vertical: true) }
                        LabeledContent("d7.checkin.date", value: status.checkinDate)
                        if let fact = status.fact {
                            LabeledContent("d7.checkin.checkedAt") { Text(Date(timeIntervalSince1970: Double(fact.checkedAt) / 1000), style: .time) }
                        }
                        if !status.checked, flow.review == nil, flow.pending == nil {
                            Button("d7.checkin.checkIn") { flow.prepare() }.nativeChannelPrimaryAction().disabled(!flow.canCheckin)
                        }
                        Button("d7.channelActivity.refresh") { run { _ in await flow.refresh() } }.font(Theme.Font.button).frame(minHeight: 44).disabled(flow.busy || flow.review != nil)
                    }
                    if status.makeupPolicy.configured, status.makeupPolicy.enabled, let days = status.makeupPolicy.windowDays, status.makeupPolicy.version != nil {
                        Section { Text("d7.checkin.makeup \(days)").fixedSize(horizontal: false, vertical: true) }
                    }
                    Section("d7.checkin.history") {
                        if status.history.isEmpty { Text("d7.checkin.history.empty").foregroundStyle(.secondary) }
                        ForEach(status.history) { day in
                            LabeledContent {
                                if day.kind == "MAKEUP" { Text("d7.checkin.history.makeup") } else { Text("d7.checkin.history.checked") }
                            } label: { Text(verbatim: day.checkinDate) }
                        }
                    }
                } else if !flow.busy, flow.phase != .redacted {
                    ContentUnavailableView {
                        Label("d7.checkin.loadFailed", systemImage: "calendar.badge.exclamationmark")
                    } actions: {
                        Button("d7.channelActivity.retry") { run { _ in await flow.refresh() } }.font(Theme.Font.button).frame(minHeight: 44).disabled(!flow.service.canRead || flow.review != nil)
                    }
                }
                if flow.service.canRank {
                    NavigationLink("d7.checkin.leaderboard") { NativeChannelCheckinRankView(service: flow.service, current: current) }
                        .disabled(flow.busy || flow.review != nil)
                }
            }
        }
        .font(Theme.Font.body)
        .nativeChannelScreen()
        .navigationTitle("d7.checkin.title").privacySensitive()
        .task(id: available) { if available { await flow.activate(current: current) } else { stop() } }
        .onChange(of: current()) { _, valid in if !valid { stop() } }
        .onChange(of: scene) { _, value in if value != .active { stop() } }
        .onDisappear { stop() }
        .confirmationDialog("d7.checkin.retry.title", isPresented: $retry, titleVisibility: .visible) {
            Button("d7.channelActivity.retry") { run { current in await flow.retryOriginal(); guard current() else { return }; await refreshSettled() } }
            Button("d7.channelActivity.cancel", role: .cancel) {}
        }
    }
    @ViewBuilder private var notice: some View {
        switch flow.phase {
        case .reading: ProgressView("d7.channelActivity.loading").font(Theme.Font.body)
        case .submitting: ProgressView("d7.checkin.submitting").font(Theme.Font.body)
        case .unknown: Text("d7.checkin.notice.unknown").nativeChannelNotice(systemImage: "clock")
        case .applied: Text("d7.checkin.notice.applied").font(Theme.Font.body).fixedSize(horizontal: false, vertical: true)
        case .redacted: Text("d7.checkin.notice.redacted").nativeChannelNotice(systemImage: "checkmark.seal")
        case .expiredUnapplied: Text("d7.checkin.notice.expired").nativeChannelNotice(systemImage: "calendar.badge.exclamationmark")
        case .rejected(let code):
            if code == "SCREENING_PENDING" { Text("d7.channelActivity.rulesPending").nativeChannelNotice(systemImage: "exclamationmark.circle") }
            else { Text("d7.checkin.notice.rejected").nativeChannelNotice(systemImage: "exclamationmark.circle") }
        case .persistenceFailed: Text("d7.channelActivity.saveFailed").nativeChannelNotice(systemImage: "exclamationmark.circle")
        default: EmptyView()
        }
    }
    private func run(_ action: @escaping NativeChannelActivityScreenWork) { operation.start(current: { available && flow.isCurrent }, work: action) }
    private func refreshSettled() async { if flow.isCurrent, flow.pending == nil, flow.phase != .redacted, flow.phase != .persistenceFailed { await flow.refresh() } }
    private func stop() { operation.retire(); flow.deactivate(); retry = false }
}

@MainActor private struct NativeChannelCheckinRankView: View {
    let service: NativeChannelCheckinService
    let current: () -> Bool
    @Environment(\.scenePhase) private var scene
    @State private var page: NativeChannelCheckinRank?
    @State private var busy = false
    @State private var failed = false
    @State private var generation: UInt64 = 0
    @State private var active = false
    private var available: Bool { current() && service.isCurrent && scene == .active }
    var body: some View {
        List {
            if !available { ContentUnavailableView("d7.checkinRank.unavailable", systemImage: "list.number") }
            else {
                if busy { ProgressView("d7.channelActivity.loading") }
                if failed { ContentUnavailableView("d7.checkinRank.loadFailed", systemImage: "exclamationmark.circle") }
                if let page {
                    Section("d7.checkinRank.me") { row(page.me) }
                    if page.othersVisible {
                        Section("d7.checkinRank.top \(page.limit)") {
                            ForEach(page.list) { row($0) }
                            if page.list.isEmpty { Text("d7.checkin.history.empty").foregroundStyle(.secondary) }
                            if page.hasMore { Button("d7.checkinRank.showTop50") { Task { await load(50) } }.font(Theme.Font.button).frame(minHeight: 44).disabled(busy) }
                        }
                    }
                }
                Button("d7.channelActivity.refresh") { Task { await load(10) } }.font(Theme.Font.button).frame(minHeight: 44).disabled(busy)
            }
        }.font(Theme.Font.body).nativeChannelScreen().listStyle(.insetGrouped).navigationTitle("d7.checkinRank.title").privacySensitive()
        .task(id: available) { if available { active = true; await load(10) } else { stop() } }
        .onChange(of: current()) { _, valid in if !valid { stop() } }
        .onChange(of: scene) { _, value in if value != .active { stop() } }
        .onDisappear { stop() }
    }
    private func row(_ row: NativeChannelCheckinRankRow) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s3) {
            Text(verbatim: row.rank.map { String($0) } ?? "—").font(Theme.Font.body.weight(.semibold)).monospacedDigit().frame(minWidth: 28, alignment: .leading)
            VStack(alignment: .leading, spacing: Theme.Space.s1) {
                Group {
                    if row.memberId == service.actorID { Text("d7.checkinRank.me") }
                    else if let nickname = row.nickname { Text(verbatim: nickname) }
                    else { Text("d7.checkinRank.member") }
                }.font(Theme.Font.body.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                Text("d7.checkinRank.detail \(row.streak) \(row.makeupDays)").font(Theme.Font.label).foregroundStyle(.secondary).monospacedDigit().fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Theme.Space.s2)
            Text("d7.checkinRank.days \(row.days)").monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
    private func load(_ limit: Int) async {
        guard active, available, !busy else { return }; generation &+= 1; let run = generation; busy = true; page = nil; failed = false
        defer { if generation == run { busy = false } }
        do { let value = try await service.rank(limit: limit, source: { active && available && generation == run }); guard active, available, generation == run else { return }; page = value }
        catch { if active, available, generation == run { page = nil; failed = true } }
    }
    private func stop() { active = false; generation &+= 1; page = nil; busy = false; failed = false }
}
