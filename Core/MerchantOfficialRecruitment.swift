import Foundation

/// Source P084 official channel; display selection is never participation authority.
public enum MerchantOfficialRecruitment {
    public static func includes(_ event: OfficialEvent) -> Bool {
        guard event.isCompleteRecord, event.status == 1 || event.status == 2 else { return false }
        return event.fulfillmentPolicy == "OPTIONAL_PARTNERS" || event.fulfillmentPolicy == "REQUIRED_FULFILLMENT"
    }
    public static func visible(_ events: [OfficialEvent]) -> [OfficialEvent] {
        events.filter(includes)
    }
}
