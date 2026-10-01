import Foundation

/// Only /merchant/info can establish absence or an application. Entry intent grants nothing.
public enum MerchantOnboardingSnapshot: Equatable {
    case none
    case application(MerchantOnboardingApplication)
}

public struct MerchantOnboardingApplication: Decodable, Equatable {
    public let id: Int
    public let status: Int
    public let accountStatus: Int
    public let name, preference, phone, address, businessTime, description, businessLicense: String
    public let derivatives, rejectReason, disableReason, createTime: String
    public var canReapply: Bool { status == 2 && accountStatus != 2 }
    public var statusKey: String {
        if accountStatus == 2 { return "merchant.onboarding.status.disabled" }
        if status == 1 && accountStatus == 1 { return "merchant.onboarding.status.effective" }
        if status == 2 { return "merchant.onboarding.status.rejected" }
        if status == 1 { return "merchant.onboarding.status.activation" }
        return "merchant.onboarding.status.pending"
    }
    public var explanationKey: String { statusKey + ".hint" }
    /// A historical rejection is never presented as the reason for disablement.
    public var displayedReason: String? {
        let reason = accountStatus == 2 ? disableReason : (status == 2 ? rejectReason : "")
        return reason.isEmpty ? nil : reason
    }
    enum CodingKeys: String, CodingKey {
        case id, status, accountStatus, name, preference, phone, address, businessTime, description, businessLicense
        case derivatives, reson, disableReason, createTime
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = c.merchantInteger(.id), id > 0,
              let status = c.merchantInteger(.status), (0...2).contains(status),
              let accountStatus = c.merchantInteger(.accountStatus), (0...2).contains(accountStatus) else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: c, debugDescription: "Unconfirmed merchant application")
        }
        self.id = id; self.status = status; self.accountStatus = accountStatus
        func text(_ key: CodingKeys) throws -> String {
            try c.decodeIfPresent(String.self, forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        name = try text(.name); preference = try text(.preference); phone = try text(.phone)
        address = try text(.address); businessTime = try text(.businessTime); description = try text(.description)
        businessLicense = try text(.businessLicense); derivatives = try text(.derivatives)
        rejectReason = try text(.reson); disableReason = try text(.disableReason); createTime = try text(.createTime)
    }
}

/// No public string initializer: a form cannot pretend a local image is an uploaded license.
public struct MerchantOnboardingLicense: Equatable {
    public let url: String
    init(serverURL: String) throws {
        let value = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URLComponents(string: value), url.scheme == "https", let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.fragment == nil else { throw APIError.malformedResponse }
        self.url = value
    }
}

public struct MerchantOnboardingDraft: Equatable {
    public private(set) var id: Int?
    public var name = "", preference = "", phone = "", address = "", businessTime = "", description = ""
    public var wechat = ""
    public var license: MerchantOnboardingLicense?
    public init() {}
    public init(reapplying application: MerchantOnboardingApplication) throws {
        guard application.canReapply else { throw APIError.invalidRequest }
        id = application.id; name = application.name; preference = application.preference
        phone = application.phone; address = application.address; businessTime = application.businessTime
        description = application.description
        license = try? MerchantOnboardingLicense(serverURL: application.businessLicense)
        // Source deliberately does not backfill wechat/coordinates/derivatives.
    }
    public func blocker(step: Int? = nil) -> String? {
        if step == nil || step == 1 {
            if name.merchantOnboardingTrimmed.isEmpty { return "merchant.onboarding.required.name" }
            if phone.merchantOnboardingTrimmed.isEmpty { return "merchant.onboarding.required.phone" }
        }
        if step == nil || step == 2 {
            if address.merchantOnboardingTrimmed.isEmpty { return "merchant.onboarding.required.address" }
            if businessTime.merchantOnboardingTrimmed.isEmpty { return "merchant.onboarding.required.hours" }
        }
        if step == nil || step == 3 {
            if license == nil { return "merchant.onboarding.required.license" }
        }
        return nil
    }
    public func jsonData() throws -> Data {
        guard blocker() == nil, let license else { throw APIError.invalidRequest }
        var fields: [String: Any] = [
            "name": name.merchantOnboardingTrimmed, "preference": preference.merchantOnboardingTrimmed,
            "phone": phone.merchantOnboardingTrimmed, "description": description.merchantOnboardingTrimmed,
            "address": address.merchantOnboardingTrimmed, "businessTime": businessTime.merchantOnboardingTrimmed,
            "businessLicense": license.url, "wechat": wechat.merchantOnboardingTrimmed
        ]
        if let id { fields["id"] = id }
        return try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
    }
}

/// Locale changes must not change the source-established persisted businessTime format.
public struct MerchantOnboardingHours: Equatable {
    public var days: Set<Int> = Set(0...6)
    public var startMinutes = 600
    public var endMinutes = 1320
    public init() {}
    public func wireValue() throws -> String {
        guard !days.isEmpty, days.isSubset(of: Set(0...6)),
              (0..<1440).contains(startMinutes), (0..<1440).contains(endMinutes) else { throw APIError.invalidRequest }
        let labels = ["一", "二", "三", "四", "五", "六", "日"]
        let dayText = days.count == 7 ? "周一至周日" : "周" + days.sorted().map { labels[$0] }.joined(separator: "、")
        func time(_ minute: Int) -> String { String(format: "%02d:%02d", minute / 60, minute % 60) }
        return "\(dayText) \(time(startMinutes))-\(time(endMinutes))"
    }
}

public struct MerchantOnboardingImage: Equatable {
    /// A local memory cap, not an invented backend upload limit.
    public static let maximumBytes = 10 * 1024 * 1024
    public let data: Data
    public init(jpegData: Data) throws {
        guard !jpegData.isEmpty, jpegData.count <= Self.maximumBytes,
              jpegData.starts(with: [0xff, 0xd8, 0xff]) else { throw APIError.invalidRequest }
        data = jpegData
    }
}

public struct MerchantOnboardingFailure: Error, Equatable {
    public let code: Int?
    public let message: String?
    public init(code: Int?, message: String? = nil) { self.code = code; self.message = message }
    public var isUnauthorized: Bool { code == 401 }
}
public enum MerchantOnboardingWriteError: Error, Equatable {
    case notSent, rejected(MerchantOnboardingFailure), outcomeUnknown
}
extension String {
    fileprivate var merchantOnboardingTrimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
