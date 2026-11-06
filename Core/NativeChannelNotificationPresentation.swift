import Foundation

/// Presentation only. The normal App callers pass their existing Environment.locale.
/// Pure keys preserve exact states; language never grants access or changes a request.
public enum NativeChannelNotificationPresentation {
    public static func localized(_ key: String, locale: Locale = .current) -> String {
        String(localized: LocalizedStringResource(String.LocalizationValue(stringLiteral: key),
                                                 table: "NativeChannelNotification", locale: locale))
    }
    public static func format(_ key: String, locale: Locale, _ values: String...) -> String {
        String(format: localized(key, locale: locale), locale: locale, arguments: values.map { $0 as CVarArg })
    }
    public static func levelKey(_ value: NativeChannelNotificationLevel) -> String {
        switch value { case .all: return "notification.level.all"; case .mentions: return "notification.level.mentions"
        case .nothing: return "notification.level.nothing"; case .inherit: return "notification.level.inherit" }
    }
    public static func level(_ value: NativeChannelNotificationLevel, locale: Locale = .current) -> String {
        localized(levelKey(value), locale: locale)
    }
    public static func effective(_ preference: NativeChannelNotificationPreference, locale: Locale = .current) -> String {
        format(preference.level == .inherit ? "notification.effective.inherited" : "notification.effective.current",
               locale: locale, level(preference.effective.level, locale: locale))
    }
    public static func mute(_ preference: NativeChannelNotificationPreference, locale: Locale = .current) -> String {
        if preference.permanentMuted { return localized("notification.mute.permanent", locale: locale) }
        if let until = preference.mutedUntil, let date = NativeChannelNotificationCommand.instant(until) {
            let displayed = date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(locale))
            return format("notification.mute.until", locale: locale, displayed)
        }
        if preference.effective.muted { return localized("notification.mute.inherited", locale: locale) }
        return localized("notification.mute.none", locale: locale)
    }
    public static func state(_ state: NativeChannelNotificationState, locale: Locale = .current) -> String? {
        stateKey(state).map { localized($0, locale: locale) }
    }
    public static func stateKey(_ state: NativeChannelNotificationState) -> String? {
        switch state {
        case .idle, .ready: return nil
        case .loading: return "notification.state.loading"
        case .saving: return "notification.state.saving"
        case .checkingReceipt: return "notification.state.checkingReceipt"
        case .outcomeUnknown: return "notification.state.outcomeUnknown"
        case .pending: return "notification.state.pending"
        case .applied: return "notification.state.applied"
        case .appliedRedacted: return "notification.state.appliedRedacted"
        case .refreshFailed: return "notification.state.refreshFailed"
        case .persistenceFailed: return "notification.state.persistenceFailed"
        case .accessClosed: return "notification.state.accessClosed"
        case .failed(.invalidInput): return "notification.error.invalidInput"
        case .failed(let failure): return knownFailureKey(failure) ?? "notification.error.read"
        }
    }
    /// UNKNOWN remains primary. Known conflict copy does not turn it into a terminal result.
    public static func failureDetail(_ failure: NativeChannelNotificationError?,
                                     state: NativeChannelNotificationState, locale: Locale = .current) -> String? {
        failureDetailKey(failure, state: state).map { localized($0, locale: locale) }
    }
    public static func failureDetailKey(_ failure: NativeChannelNotificationError?,
                                        state: NativeChannelNotificationState) -> String? {
        guard state == .outcomeUnknown, let failure else { return nil }
        return knownFailureKey(failure)
    }
    private static func knownFailureKey(_ failure: NativeChannelNotificationError) -> String? {
        // Only the exact existing code is recognized; arbitrary server prose is never echoed.
        switch failure.serverDetails?.errorCode {
        case "PREFERENCE_VERSION_CONFLICT": return "notification.error.versionConflict"
        default: return nil
        }
    }
    public static func authorization(_ value: NativeNotificationPermissionAuthorization, locale: Locale = .current) -> String {
        let key: String
        switch value {
        case .notDetermined: key = "notDetermined"
        case .denied: key = "denied"
        case .authorized: key = "authorized"
        case .provisional: key = "provisional"
        case .ephemeral: key = "ephemeral"
        case .unknown: key = "unknown"
        }
        return localized("notification.permission." + key, locale: locale)
    }
    public static func setting(_ value: NativeNotificationPermissionSetting, locale: Locale = .current) -> String {
        let key: String
        switch value { case .enabled: key = "enabled"; case .disabled: key = "disabled"
        case .unsupported: key = "unsupported"; case .unknown: key = "settingUnknown" }
        return localized("notification.permission." + key, locale: locale)
    }
    public static func permissionIssue(_ original: String, locale: Locale = .current) -> String {
        // The permission state owns these three existing local messages. Do not mutate it
        // or echo unknown text; only their exact known meanings are translated here.
        let key: String
        switch original {
        case "无法读取系统通知权限，请重试。": key = "readFailed"
        case "系统授权操作未完成，请重新读取权限状态。": key = "requestFailed"
        case "无法打开系统设置，请稍后重试。": key = "settingsFailed"
        default: key = "actionUnknown"
        }
        return localized("notification.permission." + key, locale: locale)
    }
}
