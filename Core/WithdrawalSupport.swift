import Foundation

/// The current mini-app retired bank submission. This module has no payout command.
/// Missing balance in a successful user-info data object means a new account's zero balance;
/// a missing data object or a failed request remains an error at the service boundary.
public struct WithdrawalBalance: Decodable, Equatable {
    public let balance: WalletAmount
    public let currency: String?
    enum CodingKeys: String, CodingKey { case balance, currency }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if !c.contains(.balance) { balance = WalletAmount(0) }
        else if try c.decodeNil(forKey: .balance) { balance = WalletAmount(0) }
        else if let text = try? c.decode(String.self, forKey: .balance), text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { balance = WalletAmount(0) }
        else { balance = try c.decode(WalletAmount.self, forKey: .balance) }
        guard balance.value >= 0 else { throw APIError.malformedResponse }
        currency = try c.decodeIfPresent(String.self, forKey: .currency)
    }
}
/// Deployment-reviewed business contact only. No private source contact is embedded in the app.
public struct WithdrawalSupportContact: Equatable {
    public let weChatID: String
    public init(weChatID: String) throws {
        let value = weChatID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...64).contains(value.utf8.count), value.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil else { throw APIError.invalidConfiguration }
        self.weChatID = value
    }
}
