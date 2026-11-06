import Foundation

/// Adapts explicitly supplied per-account endpoint approvals into the original consent client.
/// This is not an authority issuer. No environment, account, merchant or channel is inferred.
struct MerchantMarketingConsentRuntimeConfiguration: Equatable {
    static let readPaths: Set<String> = [MerchantMarketingConsentOriginalClient.path,
        MerchantMarketingConsentOriginalClient.resultPath]
    let read: OperationEndpointApproval
    let write: OperationEndpointApproval?
    let grants: Set<MerchantMarketingConsentOriginalGrant>
    let issuanceID: UUID

    init(read: OperationEndpointApproval, write: OperationEndpointApproval? = nil,
         grants: Set<MerchantMarketingConsentOriginalGrant> = [], issuanceID: UUID) throws {
        guard read.paths == Self.readPaths, write != nil || grants.isEmpty else {
            throw APIError.invalidConfiguration
        }
        if let write {
            guard write.baseURL.absoluteString.utf8.elementsEqual(read.baseURL.absoluteString.utf8), write.namespace.utf8.elementsEqual(read.namespace.utf8),
                  write.accountID == read.accountID,
                  write.paths == [MerchantMarketingConsentOriginalClient.path] else {
                throw APIError.invalidConfiguration
            }
        }
        self.read = read; self.write = write; self.grants = grants; self.issuanceID = issuanceID
    }

    func approval(for context: RuntimeDependencyContext) -> MerchantMarketingConsentOriginalApproval? {
        guard context.market == .china, context.baseURL.absoluteString.utf8.elementsEqual(read.baseURL.absoluteString.utf8),
              context.session.namespace.utf8.elementsEqual(read.namespace.utf8), context.session.accountID == read.accountID else { return nil }
        return try? MerchantMarketingConsentOriginalApproval(baseURL: read.baseURL,
            namespace: read.namespace, accountID: read.accountID, grants: write == nil ? [] : grants,
            revision: issuanceID)
    }
}
