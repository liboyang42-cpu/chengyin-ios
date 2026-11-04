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
            else if attempted { ContentUnavailableView("频道日签当前不可用", systemImage: "calendar.badge.checkmark", description: Text("需要当前频道身份与独立接口授权。")) }
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
            if !flow.isCurrent { Text("当前身份或频道已不可用。").fixedSize(horizontal: false, vertical: true) }
            else {
                notice
                if let reminderDate { Text("原提醒日期：\(reminderDate)。签到须按本页服务器日期重新核对，不按旧卡补签。").fixedSize(horizontal: false, vertical: true) }
                if let pending = flow.pending {
                    Section("原签到请求待确认") {
                        Text("原服务器日期：\(pending.checkinDate)").fixedSize(horizontal: false, vertical: true)
                        Text("不会自动重发，也不会把原请求改成今天的签到。").fixedSize(horizontal: false, vertical: true)
                        Button("只查询原结果") { run { current in await flow.recover(); guard current() else { return }; await refreshSettled() } }.font(Theme.Font.button).frame(minHeight: 44).disabled(flow.busy || !flow.service.canRecover)
                        Button("核对并重试同一原请求…") { retry = true }.font(Theme.Font.button).frame(minHeight: 44).disabled(flow.busy || !flow.service.canRecover || !flow.service.canWrite)
                    }
                }
                if let review = flow.review {
                    Section("核对签到") {
                        Text("频道日签 · \(review.checkinDate) · Asia/Shanghai").fixedSize(horizontal: false, vertical: true)
                        Text("这是频道日签，不是到场核销，不改玩法成长，不承诺积分或奖励。").fixedSize(horizontal: false, vertical: true)
                        Button("确认原日期签到") { run { current in await flow.confirm(); guard current() else { return }; await refreshSettled() } }.nativeChannelPrimaryAction().disabled(flow.busy)
                        Button("取消", role: .cancel) { flow.cancelReview() }.font(Theme.Font.button).frame(minHeight: 44).disabled(flow.busy)
                    }
                }
                if let status = flow.status {
                    Section("我的频道日签") {
                        Text("服务器日期：\(status.checkinDate)").fixedSize(horizontal: false, vertical: true)
                        Text("日界：\(status.timezone)").fixedSize(horizontal: false, vertical: true)
                        Text(status.checked ? "今日已签" : "今日尚未签到").fixedSize(horizontal: false, vertical: true)
                        if let through = status.streakThrough { Text("截至 \(through)，连续 \(status.streak) 天").fixedSize(horizontal: false, vertical: true) }
                        else { Text("当前没有连续签到记录").fixedSize(horizontal: false, vertical: true) }
                        if let fact = status.fact { Text(Date(timeIntervalSince1970: Double(fact.checkedAt) / 1000), style: .time).fixedSize(horizontal: false, vertical: true) }
                        Button("核对并签到…") { flow.prepare() }.font(Theme.Font.button).frame(minHeight: 44).disabled(!flow.canCheckin)
                        Button("刷新原状态") { run { _ in await flow.refresh() } }.font(Theme.Font.button).frame(minHeight: 44).disabled(flow.busy || flow.review != nil)
                    }
                    Section("补签说明") {
                        Text("补签仅由运营后台办理，成员不能自助补签；补签不增加连续天数。").fixedSize(horizontal: false, vertical: true)
                        if !status.makeupPolicy.configured { Text("尚无已发布补签政策，当前不可补签。").fixedSize(horizontal: false, vertical: true) }
                        else if !status.makeupPolicy.enabled { Text("当前已发布政策未启用补签。").fixedSize(horizontal: false, vertical: true) }
                        else if let days = status.makeupPolicy.windowDays, let version = status.makeupPolicy.version {
                            Text("已发布政策版本 \(version)：运营可处理此前 \(days) 天内的日期，不含今天。").fixedSize(horizontal: false, vertical: true)
                        }
                        Text("签到奖励规则尚未配置，不显示或承诺奖励到账。").fixedSize(horizontal: false, vertical: true)
                    }
                    Section("最近 30 天原记录") {
                        if status.history.isEmpty { Text("当前可读范围没有记录").fixedSize(horizontal: false, vertical: true) }
                        ForEach(status.history) { day in
                            LabeledContent(day.checkinDate, value: day.kind == "MAKEUP" ? "运营补签 · 不增加连续天数" : "已签到")
                        }
                    }
                } else if !flow.busy, flow.phase != .redacted {
                    Text("日签原状态尚不可读；不推断为未签到。").fixedSize(horizontal: false, vertical: true)
                    Button("读取原状态") { run { _ in await flow.refresh() } }.font(Theme.Font.button).frame(minHeight: 44).disabled(!flow.service.canRead || flow.review != nil)
                }
                if flow.service.canRank {
                    NavigationLink("频道打卡榜 · 最近 30 天") { NativeChannelCheckinRankView(service: flow.service, current: current) }
                        .disabled(flow.busy || flow.review != nil)
                }
            }
        }
        .font(Theme.Font.body)
        .nativeChannelScreen()
        .navigationTitle("频道日签").privacySensitive()
        .task(id: available) { if available { await flow.activate(current: current) } else { stop() } }
        .onChange(of: current()) { _, valid in if !valid { stop() } }
        .onChange(of: scene) { _, value in if value != .active { stop() } }
        .onDisappear { stop() }
        .confirmationDialog("先读取原结果，再重试同一请求与同一日期", isPresented: $retry, titleVisibility: .visible) {
            Button("核对并重试原请求") { run { current in await flow.retryOriginal(); guard current() else { return }; await refreshSettled() } }
            Button("取消", role: .cancel) {}
        }
    }
    @ViewBuilder private var notice: some View {
        switch flow.phase {
        case .reading: ProgressView("读取原状态…").font(Theme.Font.body)
        case .submitting: ProgressView("原签到已提交，等待结果…").font(Theme.Font.body)
        case .unknown: Text("原请求结果待确认；没有宣称签到失败或成功。").nativeChannelNotice(systemImage: "clock")
        case .applied: Text("原签到请求已完成，正在读取当前状态。").font(Theme.Font.body).fixedSize(horizontal: false, vertical: true)
        case .redacted: Text("原签到已完成；当前权限不允许展示结果。").nativeChannelNotice(systemImage: "lock")
        case .expiredUnapplied: Text("服务端在原会话锁内确认：原请求未写入且原日期已结束，不能再执行。今天签到仍需重新核对。").font(Theme.Font.body).fixedSize(horizontal: false, vertical: true)
        case .rejected(let code): Text(code == "SCREENING_PENDING" ? "请返回频道逐条确认规则；不会自动重发。" : "原日期或状态已变，或请求未获允许。请刷新后重新核对。").font(Theme.Font.body).fixedSize(horizontal: false, vertical: true)
        case .failed: Text("原状态读取失败，未推断为未签到。").nativeChannelNotice(systemImage: "exclamationmark.circle")
        case .persistenceFailed: Text("原请求记录无法安全保存或核对，已停止写入；请勿清除原记录。").nativeChannelNotice(systemImage: "exclamationmark.circle")
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
            if !available { Text("当前频道榜不可用").fixedSize(horizontal: false, vertical: true) }
            else {
                if busy { ProgressView("读取原签到事实…") }
                if failed { Text("原榜读取失败，不显示旧榜或空榜成功。").fixedSize(horizontal: false, vertical: true) }
                if let page {
                    Section("我的记录") { row(page.me); Text("截至服务器日期 \(page.checkinDate) · \(page.timezone)").fixedSize(horizontal: false, vertical: true) }
                    if page.othersVisible {
                        Section("最近 30 天 · 前 \(page.limit)") {
                            ForEach(page.list) { row($0) }
                            if page.list.isEmpty { Text("当前可见成员没有签到记录").fixedSize(horizontal: false, vertical: true) }
                            if page.hasMore { Button("明确展开前 50 位") { Task { await load(50) } }.font(Theme.Font.button).frame(minHeight: 44).disabled(busy) }
                        }
                    } else { Text("原成员列表权限不允许展示他人，保留我的记录；未推断他人名次。").fixedSize(horizontal: false, vertical: true) }
                    Text("只统计本频道日期；连续天数不参与排序，MAKEUP 单独标记，不代表积分、成长或到场。").fixedSize(horizontal: false, vertical: true)
                }
                Button("刷新原榜（默认前 10）") { Task { await load(10) } }.font(Theme.Font.button).frame(minHeight: 44).disabled(busy)
            }
        }.font(Theme.Font.body).nativeChannelScreen().listStyle(.insetGrouped).navigationTitle("频道打卡榜").privacySensitive()
        .task(id: available) { if available { active = true; await load(10) } else { stop() } }
        .onChange(of: current()) { _, valid in if !valid { stop() } }
        .onChange(of: scene) { _, value in if value != .active { stop() } }
        .onDisappear { stop() }
    }
    private func row(_ row: NativeChannelCheckinRankRow) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s1) {
            Text("\(row.rank.map { "第 \($0) 位 · " } ?? "")\(row.memberId == service.actorID ? "我" : (row.nickname ?? "频道成员"))").font(Theme.Font.body.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            Text("\(row.days) 天 · 其中 MAKEUP \(row.makeupDays) 天 · 原最近连续 \(row.streak) 天").fixedSize(horizontal: false, vertical: true).font(Theme.Font.label).monospacedDigit()
        }
    }
    private func load(_ limit: Int) async {
        guard active, available, !busy else { return }; generation &+= 1; let run = generation; busy = true; page = nil; failed = false
        defer { if generation == run { busy = false } }
        do { let value = try await service.rank(limit: limit, source: { active && available && generation == run }); guard active, available, generation == run else { return }; page = value }
        catch { if active, available, generation == run { page = nil; failed = true } }
    }
    private func stop() { active = false; generation &+= 1; page = nil; busy = false; failed = false }
}
