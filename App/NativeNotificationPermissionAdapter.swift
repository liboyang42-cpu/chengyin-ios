import Foundation
import Combine
import UIKit
import UserNotifications

/// Reads notification settings and handles explicit in-app user actions only.
/// It neither registers remote notifications nor requests a device token.
@MainActor final class NativeNotificationPermissionAdapter: NativeNotificationPermissionProviding {
    private let center: UNUserNotificationCenter
    init(center: UNUserNotificationCenter = .current()) { self.center = center }
    func read() async throws -> NativeNotificationPermissionSnapshot {
        let settings = await center.notificationSettings()
        let authorization: NativeNotificationPermissionAuthorization
        switch settings.authorizationStatus {
        case .notDetermined: authorization = .notDetermined
        case .denied: authorization = .denied
        case .authorized: authorization = .authorized
        case .provisional: authorization = .provisional
        case .ephemeral: authorization = .ephemeral
        @unknown default: authorization = .unknown(settings.authorizationStatus.rawValue)
        }
        return .init(authorization: authorization, alerts: map(settings.alertSetting),
                     sounds: map(settings.soundSetting), badges: map(settings.badgeSetting))
    }
    func requestFromUserAction() async throws {
        // Re-read to handle a permission changed outside this screen.
        guard await center.notificationSettings().authorizationStatus == .notDetermined else { return }
        _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
    }
    func openSettingsFromUserAction() async throws {
        guard let url = URL(string: UIApplication.openNotificationSettingsURLString),
              await UIApplication.shared.open(url) else { throw NativeChannelNotificationError.accessClosed }
    }
    private func map(_ value: UNNotificationSetting) -> NativeNotificationPermissionSetting {
        switch value { case .enabled: return .enabled; case .disabled: return .disabled; case .notSupported: return .unsupported
        @unknown default: return .unknown(value.rawValue) }
    }
}


/// N19 foreground projection of the SAME original summary used by the APNs writer.
/// No private counter, persistence, push-attempt counting, ACK, device binding or permission prompt.
@MainActor final class NativeOriginalUnreadBadgeState: ObservableObject {
    enum Status: Equatable {
        case suspended, reading, unavailable, systemDisabled, applied(Int64, serverGeneration: Int64?), systemFailed
        var explanation: String {
            switch self {
            case .suspended: return "当前未同步图标角标；没有把未知未读当作零。"
            case .reading: return "正在回读原服务器未读与系统角标设置。"
            case .unavailable: return "原未读结果或授权不可用；保留现有系统角标，没有标记消息已读。"
            case .systemDisabled: return "系统角标未启用或权限状态未知；原消息与未读不变，不会自动请求权限。"
            case .applied(let total, let serverGeneration):
                return "已按原服务器未读绝对数 \(total) 提交系统角标设置；" +
                    (serverGeneration.map { "原已读代际 \($0)。" } ?? "服务器代际未启用，仅原前台回读恢复。") +
                    "不代表桌面显示或推送送达，也不能撤回已提交的旧 APNs 角标。"
            case .systemFailed: return "系统角标设置结果未确认；未清零、未标记已读，可从原服务重新读取。"
            }
        }
    }
    @Published private var storedStatus: Status = .suspended
    @Published private var working = false
    private var flow: NativeChannelNotificationCoordinator?
    private var makeFlow: (() -> NativeChannelNotificationCoordinator?)?
    private var stillActive: () -> Bool = { false }
    private var active = false
    private var generation: UInt64 = 0
    private var requestRevision: UInt64 = 0
    // Current authorized lifecycle only, never persisted as a second count/epoch authority.
    private var lastServerGeneration: Int64?
    private var refreshAgain = false
    private var worker: Task<Void, Never>?
    private var timer: Task<Void, Never>?
    private let permission = NativeNotificationPermissionAdapter()
    var status: Status {
        guard active, stillActive() else { return .suspended }
        if case .applied = storedStatus, flow?.unread == nil { return .unavailable }
        return storedStatus
    }
    var isBusy: Bool { active && working }
    var canRefresh: Bool { active && stillActive() }

    /// Called by the one existing app lifecycle, not by a second settings owner.
    func resume(makeFlow: @escaping () -> NativeChannelNotificationCoordinator?, stillActive: @escaping () -> Bool) {
        suspend()
        self.makeFlow = makeFlow; self.stillActive = stillActive; active = true
        requestRefresh()
        let ticket = generation
        timer = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 60_000_000_000) } catch { return }
                guard let self, self.active, self.generation == ticket, self.stillActive() else { return }
                self.requestRefresh()
            }
        }
    }
    /// Explicit authenticated lock-screen action: reuse this SAME serialized original-summary owner once.
    /// No second counter/setter, new polling, permission request or unknown->zero fallback.
    func synchronizeFromExplicitNotificationAction(makeFlow: @escaping () -> NativeChannelNotificationCoordinator?,
                                                   stillCurrent: @escaping () -> Bool) async {
        guard stillCurrent(), !Task.isCancelled else { return }
        if active, stillActive() {
            let ticket = generation; requestRefresh()
            while generation == ticket, stillCurrent(), !Task.isCancelled, let currentWorker = worker { await currentWorker.value }
            return
        }
        suspend()
        self.makeFlow = makeFlow; self.stillActive = stillCurrent; active = true
        let ticket = generation; requestRefresh()
        // A retiring OS setter keeps its slot; wait until its own drain transfers that slot to this request.
        while generation == ticket, stillCurrent(), !Task.isCancelled, let currentWorker = worker { await currentWorker.value }
        if generation == ticket { suspend() }
    }
    func suspend() {
        active = false; generation &+= 1; requestRevision &+= 1; refreshAgain = false
        timer?.cancel(); timer = nil; worker?.cancel()
        // Keep the worker slot until an already-submitted OS call returns. A new
        // account must not race a second setter against that retiring operation.
        flow?.deactivate(); flow = nil; makeFlow = nil; stillActive = { false }
        storedStatus = .suspended; lastServerGeneration = nil
        // Missing authority / background / logout is NOT proof that unread == 0.
    }
    func requestRefresh() {
        guard active, stillActive() else { return }
        requestRevision &+= 1; refreshAgain = true
        guard worker == nil else { return }
        working = true
        worker = Task { [weak self] in
            guard let self else { return }
            await self.drain()
        }
    }
    private func drain() async {
        defer {
            worker = nil; working = false
            // A replacement lifecycle queued while the old OS setter was awaiting
            // its result resumes only now, and always fetches its OWN fresh summary.
            if active, refreshAgain, stillActive() { requestRefresh() }
        }
        while active, refreshAgain, !Task.isCancelled {
            refreshAgain = false
            let ticket = generation; let revision = requestRevision
            if flow?.isCurrent != true { flow?.deactivate(); flow = makeFlow?() }
            guard let source = flow else { storedStatus = .unavailable; continue }
            storedStatus = .reading
            await source.activateUnreadRecovery() // only .unread; never restores/replays journal writes
            guard lifecycleCurrent(ticket, revision) else { continue }
            guard source === flow, source.isCurrent, let summary = source.unread,
                  let count = Int(exactly: summary.total) else {
                storedStatus = .unavailable; continue
            }
            do { try summary.validate() } catch { storedStatus = .unavailable; continue }
            if let observed = lastServerGeneration {
                guard let returned = summary.badgeGeneration, returned >= observed else {
                    storedStatus = .unavailable; continue // stale/missing generation is not authority to clear zero
                }
            }
            if let returned = summary.badgeGeneration { lastServerGeneration = returned }
            do {
                let settings = try await permission.read()
                guard authorizedResult(ticket, revision, source, summary) else { continue }
                guard [.authorized, .provisional, .ephemeral].contains(settings.authorization),
                      settings.badges == .enabled else { storedStatus = .systemDisabled; continue }
                // Final current-owner/operation fence is immediately before the OS effect.
                // Only an actually returned total of zero can clear the badge. No cap at 99.
                if #available(iOS 16.0, *) {
                    try await UNUserNotificationCenter.current().setBadgeCount(count)
                } else {
                    UIApplication.shared.applicationIconBadgeNumber = count
                }
                guard authorizedResult(ticket, revision, source, summary) else { continue }
                storedStatus = .applied(summary.total, serverGeneration: summary.badgeGeneration)
            } catch {
                if lifecycleCurrent(ticket, revision) { storedStatus = .systemFailed }
            }
        }
    }
    private func lifecycleCurrent(_ ticket: UInt64, _ revision: UInt64) -> Bool {
        active && generation == ticket && requestRevision == revision && stillActive() && !Task.isCancelled
    }
    private func authorizedResult(_ ticket: UInt64, _ revision: UInt64,
                                  _ source: NativeChannelNotificationCoordinator,
                                  _ summary: NativeChannelNotificationUnreadSummary) -> Bool {
        guard lifecycleCurrent(ticket, revision) else { return false }
        guard flow === source, source.isCurrent, source.unread == summary else {
            storedStatus = .unavailable; return false
        }
        return true
    }
}
