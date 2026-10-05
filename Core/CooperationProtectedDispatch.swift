import Foundation

/// Offline contract-test boundary only. Real networking transports must not adopt this protocol.
/// This marker is an injection contract, not a sandbox or production authorization mechanism.
public protocol CoopFlowOfflineHTTPTransport: HTTPTransport {}

public enum CoopFlowProtectedOperation: String, Hashable, CaseIterable {
    case invite, handle, contact, complaint, enrollOffer
    public init?(_ operation: CoopFlowMutation) {
        switch operation {
        case .invite: self = .invite
        case .handle: self = .handle
        case .contact: self = .contact
        case .complaint: self = .complaint
        case .enrollOffer: self = .enrollOffer
        default: return nil
        }
    }
}

/// Explicit, endpoint-bound per-operation opt-in for synthetic offline execution.
/// A grant never substitutes for the coordinator's exact review and fresh authoritative evidence.
public struct CoopFlowProtectedDispatch {
    public let operations: Set<CoopFlowProtectedOperation>
    public let endpoint: URL
    public init(operations: Set<CoopFlowProtectedOperation> = [], endpoint: URL) {
        self.operations = operations; self.endpoint = endpoint
    }
    func permits(_ operation: CoopFlowMutation, endpoint: URL) -> Bool {
        guard self.endpoint == endpoint, let kind = CoopFlowProtectedOperation(operation) else { return false }
        return operations.contains(kind)
    }
}
