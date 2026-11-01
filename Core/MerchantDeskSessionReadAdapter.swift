import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Reads the existing merchant desk from the ordinary session's API configuration,
/// transport, token, and account. A nil approval is left nil. Save is not called.
@MainActor public struct MerchantDeskSessionReadAdapter {
    public struct Supply: Equatable {
        public let accountID: Int
        public let token: String
        public init(accountID: Int, token: String) {
            self.accountID = accountID
            self.token = token
        }
    }

    private let entry: MerchantDeskReadEntry
    private let captured: Supply
    private let current: () -> Supply?
    private let approval: MerchantBusinessProductionApproval?

    /// `configuration`, `transport`, `token`, and `accountID` come from the session.
    /// `approval` is the value session dependencies already hold. Nil is not replaced.
    /// `context` is the session context when the caller has one. It is not used to open save while approval is nil.
    public init?(configuration: APIConfiguration,
                 transport: any HTTPTransport,
                 token: String,
                 accountID: Int,
                 approval: MerchantBusinessProductionApproval? = nil,
                 context: @escaping () -> RuntimeDependencyContext? = { nil },
                 current: @escaping () -> Supply?) {
        guard accountID > 0, AuthRequestBuilder.isValidToken(token) else { return nil }
        let supply = Supply(accountID: accountID, token: token)
        guard current() == supply else { return nil }
        let service = MerchantBusinessService(configuration: configuration, readTransport: transport)
        let production = approval.map { existing in
            MerchantBusinessProductionFactory(api: configuration, approval: existing, transport: transport, current: context)
        }
        self.entry = MerchantDeskReadEntry(service: service, production: production)
        self.captured = supply
        self.current = current
        self.approval = approval
    }

    /// Lists, then opens detail only for a listed product id. The receipt is the entry's receipt.
    public func open(productID: Int, requestID: String) async throws -> MerchantDeskReadEntry.Opened? {
        guard current() == captured else { return nil }
        let opened = try await entry.open(productID: productID, requestID: requestID, token: captured.token)
        guard current() == captured else { return nil }
        return opened
    }

    /// Nil approval keeps the original writer closed. This does not call save.
    public func saveStaysClosed(_ mutation: MerchantBusinessMutation, merchantID: Int) -> Bool {
        guard approval != nil else { return true }
        return entry.saveStaysClosed(mutation, merchantID: merchantID)
    }
}
