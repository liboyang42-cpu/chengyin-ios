import Foundation

/// Display only: absence of an OS snapshot is not evidence of authorization or denial.
/// A failed attempt must not keep announcing an active read after busy has ended.
enum NativeNotificationPermissionStatusPresentation: Equatable {
    case waiting
    case loading
    case unavailable
    case known(NativeNotificationPermissionAuthorization)

    static func project(authorization: NativeNotificationPermissionAuthorization?,
                        busy: Bool, hasIssue: Bool) -> Self {
        // A settings-open failure can coexist with the last OS snapshot. Preserve
        // that exact fact; the original issue remains separately visible below it.
        if let authorization { return .known(authorization) }
        if busy { return .loading }
        if hasIssue { return .unavailable }
        return .waiting
    }

    var messageKey: String? {
        switch self {
        case .waiting: return "permission.status.waiting"
        case .loading: return "permission.status.loading"
        case .unavailable: return "permission.status.unavailable"
        case .known: return nil
        }
    }

    func title(locale: Locale) -> String {
        if case .known(let authorization) = self {
            return NativeChannelNotificationPresentation.authorization(authorization, locale: locale)
        }
        guard let key = messageKey else { return "" }
        return String(localized: LocalizedStringResource(String.LocalizationValue(stringLiteral: key),
            table: "NativeNotificationPermissionStatus", locale: locale))
    }
}
