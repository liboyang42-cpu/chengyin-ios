import Foundation

/// A build/deployment boundary, never inferred from language, IP, currency or storefront.
public enum RegionalMarket: String, CaseIterable, Hashable {
    case china = "CN"
    case unitedStates = "US"

    public var defaultLanguage: AppLanguage {
        self == .china ? .simplifiedChinese : .english
    }
    /// Preserve every existing preference, including explicit System and its legacy fallback.
    public func language(storedValue: String?) -> AppLanguage {
        storedValue.map(AppLanguage.init(storedValue:)) ?? defaultLanguage
    }
}

public enum RegionalConfigurationError: Error, Equatable {
    case missingMarket, unsupportedMarket, unapprovedBackend
}

public enum RegionalCapability: String, CaseIterable, Hashable {
    case usernamePassword, domesticChinaPhone, internationalPhone, emailLogin
    case signInWithApple, signInWithGoogle
    case physicalEventPayment, digitalContentPayment, merchantPayout
}

public enum RegionalCapabilityAvailability: Equatable {
    case notRequested, implementationPending, backendNotConfigured, verificationPending, available
}

/// An input-format contract only. It does not imply a working login endpoint/provider.
public enum RegionalPhoneContract: Equatable {
    case chinaDomestic11Digits, internationalE164
}

public struct RegionalConfiguration {
    public let market: RegionalMarket
    public let apiConfiguration: APIConfiguration?
    private let verifiedCapabilities: Set<RegionalCapability>

    /// Exact, market-scoped endpoint approvals must come from reviewed deployment configuration.
    /// Do not populate the allowlist from the endpoint itself or a user-editable language setting.
    /// Empty endpoint is an intentional offline/unconfigured state, even if approvals exist.
    public init(market: RegionalMarket, baseURL: String? = nil,
                approvedBaseURLs: [RegionalMarket: Set<String>] = [:],
                verifiedCapabilities: Set<RegionalCapability> = []) throws {
        self.market = market
        self.verifiedCapabilities = verifiedCapabilities
        let value = baseURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if value.isEmpty {
            apiConfiguration = nil
        } else {
            guard let url = URL(string: value) else { throw APIError.invalidConfiguration }
            let configuration = try APIConfiguration(baseURL: url)
            // Exact origin + port + path comparison: no suffix/subdomain or cross-market fallback.
            guard approvedBaseURLs[market]?.contains(value) == true else {
                throw RegionalConfigurationError.unapprovedBackend
            }
            apiConfiguration = configuration
        }
    }

    /// Missing/unknown build metadata fails closed; do not default a live backend to CN or US.
    public static func market(buildValue: String?) throws -> RegionalMarket {
        guard let value = buildValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { throw RegionalConfigurationError.missingMarket }
        guard let market = RegionalMarket(rawValue: value) else {
            throw RegionalConfigurationError.unsupportedMarket
        }
        return market
    }

    public var phoneContract: RegionalPhoneContract {
        market == .china ? .chinaDomestic11Digits : .internationalE164
    }
    /// Product planning only. This list must never directly drive enabled controls or requests.
    public var desiredCapabilities: Set<RegionalCapability> {
        switch market {
        case .china:
            return [.usernamePassword, .domesticChinaPhone, .signInWithApple,
                    .physicalEventPayment, .digitalContentPayment, .merchantPayout]
        case .unitedStates:
            return [.internationalPhone, .emailLogin, .signInWithApple, .signInWithGoogle,
                    .physicalEventPayment, .digitalContentPayment, .merchantPayout]
        }
    }
    /// CN SMS is the only mounted native bootstrap contract. The retained password
    /// route requires a mini-program WeChat code; a capability flag cannot supply it.
    /// Provider/deployment verification is still required before enabling SMS.
    public var implementedCapabilities: Set<RegionalCapability> {
        market == .china ? [.domesticChinaPhone] : []
    }
    public func availability(of capability: RegionalCapability) -> RegionalCapabilityAvailability {
        guard desiredCapabilities.contains(capability) else { return .notRequested }
        guard implementedCapabilities.contains(capability) else { return .implementationPending }
        guard apiConfiguration != nil else { return .backendNotConfigured }
        guard verifiedCapabilities.contains(capability) else { return .verificationPending }
        return .available
    }
    public var availableCapabilities: Set<RegionalCapability> {
        Set(RegionalCapability.allCases.filter { availability(of: $0) == .available })
    }
    /// Use before constructing/injecting the legacy CN-only AuthChannelService/coordinator.
    public var canUseDomesticChinaPhone: Bool {
        availability(of: .domesticChinaPhone) == .available
    }
}
