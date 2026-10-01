#if DEBUG
import Foundation

/// Offline-only fixture data. Same integer ID intentionally denotes two different entities.
public enum HomeFeedSyntheticFixtures {
    public static let activityJSON = #"{"id":7,"name":"Sample riverside walk","description":"Synthetic activity","minAmout":0,"startDate":"2026-09-01T10:00:00Z","addressName":"Sample meeting point"}"#
    public static let topicJSON = #"{"id":7,"name":"Sample neighborhood route","description":"Synthetic route","minAmout":12.5,"startDate":"2026-10-10 09:00:00","addressName":"Sample district","betaFlag":1}"#
    public static func activity() throws -> HomeFeedItem { .activity(try JSONDecoder().decode(ActivitySummary.self, from: Data(activityJSON.utf8))) }
    public static func topic() throws -> HomeFeedItem { .topic(try JSONDecoder().decode(TopicSummary.self, from: Data(topicJSON.utf8))) }
}

#endif
