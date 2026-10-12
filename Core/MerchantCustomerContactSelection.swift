import Foundation

/// A selection of an already-authorized CRM row, never a phone number or a grant.
public struct MerchantCustomerContactSelection: Equatable, Identifiable {
    public let id: UUID
    public let scope: MerchantBusinessScope
    public let authorizationGeneration: UUID?
    public let snapshot: MerchantBusinessSnapshot
    public let record: MerchantBusinessRecord
    public let customerID: MerchantCustomerID
    public let purpose: MerchantContactPurpose
    public var merchantID: Int { snapshot.access.merchantID }
    public var command: MerchantEngagementCommand { .contact(customerID, purpose) }
    public init?(scope: MerchantBusinessScope?, authorizationGeneration: UUID?, snapshot: MerchantBusinessSnapshot?, record: MerchantBusinessRecord, purpose: MerchantContactPurpose) {
        guard let scope, let snapshot, case .customers = snapshot.document.query,
              snapshot.document.rows.contains(record), record.kind == .customer,
              snapshot.access.allows("merchant:crm:read"), snapshot.access.allows("merchant:crm:sensitive:read"),
              let contact = MerchantCustomerContactPresentation(record: record, access: snapshot.access), case .maskedPhone = contact,
              let raw = Int(record.id), let customer = try? MerchantCustomerID(raw) else { return nil }
        id = UUID(); self.scope = scope; self.authorizationGeneration = authorizationGeneration
        self.snapshot = snapshot; self.record = record; customerID = customer; self.purpose = purpose
    }
    public func matches(scope: MerchantBusinessScope?, authorizationGeneration: UUID?, snapshot: MerchantBusinessSnapshot?) -> Bool {
        self.scope == scope && self.authorizationGeneration == authorizationGeneration && self.snapshot == snapshot
    }
}
