import Foundation
import Observation

public enum NativeNotificationPermissionAuthorization: Equatable {
    case notDetermined, denied, authorized, provisional, ephemeral, unknown(Int)
    public var label: String {
        switch self {
        case .notDetermined: return "尚未选择"
        case .denied: return "系统通知已关闭"
        case .authorized: return "系统允许通知"
        case .provisional: return "允许安静送达"
        case .ephemeral: return "临时授权"
        case .unknown: return "系统权限状态未知"
        }
    }
}
public enum NativeNotificationPermissionSetting: Equatable { case enabled, disabled, unsupported, unknown(Int) }
public struct NativeNotificationPermissionSnapshot: Equatable {
    public let authorization: NativeNotificationPermissionAuthorization
    public let alerts: NativeNotificationPermissionSetting
    public let sounds: NativeNotificationPermissionSetting
    public let badges: NativeNotificationPermissionSetting
    public init(authorization: NativeNotificationPermissionAuthorization, alerts: NativeNotificationPermissionSetting,
                sounds: NativeNotificationPermissionSetting, badges: NativeNotificationPermissionSetting) {
        self.authorization = authorization; self.alerts = alerts; self.sounds = sounds; self.badges = badges
    }
}
@MainActor public protocol NativeNotificationPermissionProviding: AnyObject {
    func read() async throws -> NativeNotificationPermissionSnapshot
    func requestFromUserAction() async throws
    func openSettingsFromUserAction() async throws
}

/// OS authorization never writes service preferences or device bindings.
@MainActor @Observable public final class NativeNotificationPermissionState {
    private let provider: any NativeNotificationPermissionProviding
    private var generation: UInt64 = 0
    public private(set) var snapshot: NativeNotificationPermissionSnapshot?
    public private(set) var busy = false
    public private(set) var issue: String?
    public init(provider: any NativeNotificationPermissionProviding) { self.provider = provider }
    public func retire() { generation &+= 1; busy = false; snapshot = nil; issue = nil }
    public func refresh() async {
        guard !busy else { return }
        let ticket = generation; busy = true
        defer { if ticket == generation { busy = false } }
        do {
            let value = try await provider.read()
            guard ticket == generation, !Task.isCancelled else { return }
            snapshot = value; issue = nil
        } catch { if ticket == generation { snapshot = nil; issue = "无法读取系统通知权限，请重试。" } }
    }
    public func requestFromUserAction() async {
        guard !busy, snapshot?.authorization == .notDetermined else { return }
        let ticket = generation; busy = true
        defer { if ticket == generation { busy = false } }
        do {
            try await provider.requestFromUserAction()
            guard ticket == generation, !Task.isCancelled else { return }
            let value = try await provider.read()
            guard ticket == generation, !Task.isCancelled else { return }
            snapshot = value
            issue = nil
        } catch { if ticket == generation { snapshot = nil; issue = "系统授权操作未完成，请重新读取权限状态。" } }
    }
    public func openSettingsFromUserAction() async {
        guard !busy, let authorization = snapshot?.authorization, authorization != .notDetermined else { return }
        let ticket = generation; busy = true
        defer { if ticket == generation { busy = false } }
        do { try await provider.openSettingsFromUserAction(); if ticket == generation { issue = nil } }
        catch { if ticket == generation { issue = "无法打开系统设置，请稍后重试。" } }
    }
}
