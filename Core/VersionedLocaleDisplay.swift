import Foundation

/// C11 versioned CN/US locale / timezone / payment display. PROFILE_VERSION=2:
/// market catalog timezone is not the event timezone.
/// Legal gates stay NOT_RUN. Changing display requires bumping PROFILE_VERSION.
public enum VersionedLocaleDisplay {
    public static let profileVersion = 2
    public static let notRun = "NOT_RUN"
    public static let eventTimezoneSource = "locale.eventTimezone"

    public enum Failure: Error, Equatable {
        case waitingSource(String)
    }

    public enum Market: String, Equatable, Sendable {
        case cn = "CN"
        case us = "US"
    }

    public enum LegalGate: String, CaseIterable, Equatable, Sendable {
        case icpFiling = "ICP_FILING"
        case privacyAgreement = "PRIVACY_AGREEMENT"
        case userAgreement = "USER_AGREEMENT"
        case wechatMiniprogramReview = "WECHAT_MINIPROGRAM_REVIEW"
        case appStoreReview = "APP_STORE_REVIEW"
        case playStoreReview = "PLAY_STORE_REVIEW"
        case productionCapacity = "PRODUCTION_CAPACITY"
        case productionDDL = "PRODUCTION_DDL"
    }

    public struct Profile: Equatable, Sendable {
        public var version: Int { VersionedLocaleDisplay.profileVersion }
        public var market: Market
        public var localeIdentifier: String
        public var timeZoneIdentifier: String
        public var datePattern: String
        public var languageTag: String
        public var paymentChannel: String
        public var readability: String

        public func asView() -> [String: String] {
            [
                "version": String(version),
                "market": market.rawValue,
                "languageTag": languageTag,
                "timezone": timeZoneIdentifier,
                "eventTimezone": "WAITING_SOURCE",
                "paymentChannel": paymentChannel,
                "readability": readability,
                "legalGates": VersionedLocaleDisplay.notRun,
            ]
        }
    }

    private static let cn = Profile(
        market: .cn,
        localeIdentifier: "zh_CN",
        timeZoneIdentifier: "Asia/Shanghai",
        datePattern: "yyyy-MM-dd HH:mm:ss",
        languageTag: "zh-CN",
        paymentChannel: "微信支付（线下消费/核销）",
        readability: "24h yyyy-MM-dd HH:mm:ss · 中文不加负字距"
    )

    private static let us = Profile(
        market: .us,
        localeIdentifier: "en_US",
        timeZoneIdentifier: "America/New_York",
        datePattern: "MMM d, yyyy h:mm a",
        languageTag: "en-US",
        paymentChannel: "Apple IAP（虚拟道具；线下核销仍不走 IAP）",
        readability: "12h MMM d, yyyy h:mm a · Dynamic Type 可读"
    )

    public static func profile(_ market: Market) -> Profile {
        switch market {
        case .cn: return cn
        case .us: return us
        }
    }

    public static func format(_ market: Market, instant: Date?) throws -> String {
        _ = profile(market)
        guard instant != nil else { return "UNKNOWN" }
        throw Failure.waitingSource(eventTimezoneSource)
    }

    public static func format(_ market: Market, instant: Date?, timeZone: TimeZone) throws -> String {
        let profile = profile(market)
        guard let instant else { return "UNKNOWN" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: profile.localeIdentifier)
        formatter.timeZone = timeZone
        formatter.dateFormat = profile.datePattern
        return formatter.string(from: instant)
    }

    public static func legalGateStatuses() -> [LegalGate: String] {
        var gates: [LegalGate: String] = [:]
        for gate in LegalGate.allCases {
            gates[gate] = notRun
        }
        return gates
    }

    public static func legalGateStatus(_ gate: LegalGate) -> String {
        notRun
    }
}
