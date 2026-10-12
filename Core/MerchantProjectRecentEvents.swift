import Foundation

/// Mini project key: topic = 1, activity = 2. IDs are independent across kinds.
public struct MerchantProjectEventKey: Equatable {
    public let ownerType: String
    public let ownerID: String
    public init?(project: MerchantProject) {
        guard project.projectID > 0, project.projectID <= 9_007_199_254_740_991 else { return nil }
        switch project.bizType {
        case "topic": ownerType = "1"
        case "activity": ownerType = "2"
        default: return nil
        }
        ownerID = String(project.projectID)
    }
    public func matches(_ event: MerchantEvent) -> Bool {
        event.projectOwnerType == ownerType && event.projectOwnerID == ownerID
    }
    public func recentEvents(in events: [MerchantEvent]) -> [MerchantEvent] {
        events.filter(matches)
    }
}
