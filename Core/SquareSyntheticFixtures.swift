#if DEBUG
import Foundation

/// Offline synthetic examples only. These payloads are not evidence of deployed API support.
public enum SquareSyntheticFixtures {
    public static let legacyPostJSON = #"{"id":701,"memberId":81,"contents":"A synthetic city walk / 一次示例城市漫步","pics":"","memberNickname":"Example walker","rz":1,"memberLevelId":"2","authorBadge":"Example guide","noticeBadge":"Synthetic notice","clubId":"41","clubName":"Example walking club","address":"Example city","likeNum":12,"commentCount":3,"isLiked":1,"sportName":"Example river route","sportTopicId":"31","dataId":31,"dataType":2,"isTopicTemplate":true,"nodeTotal":6,"nodeDoneCount":6,"completed":true,"createTime":"2026-01-01 10:00","safetyLabelsJson":"[\"WEATHER_RISK\"]"}"#
    public static let wrappedPostJSON = #"{"post":{"id":702,"authorId":82,"body":"A second synthetic post","authorNickname":"Example explorer","viewerLiked":"1","likeCount":5,"commentCount":1,"publishedAt":"2026-01-02","poiName":"Example district","audience":"PUBLIC","commentPolicy":"EVERYONE"},"media":[{"media_type":"IMAGE","derived_object_key":"example/object-key"},{"mediaType":"MAP_SNAPSHOT","derivedObjectKey":"example/route-key"}],"references":[{"reference_type":"TOPIC","reference_id":"32","snapshot_json":"{\"title\":\"Example route snapshot\",\"cover_url\":\"example/cover-key\"}"}],"viewerCanComment":false}"#
    public static let commentsJSON = #"[{"id":801,"memberId":81,"contents":"Synthetic root / 示例评论","memberNickname":"Example walker","likeCount":2,"createTime":"2026-01-01"},{"id":802,"author_id":82,"body":"Synthetic reply","author_nickname":"Example explorer","root_id":801,"reply_id":801,"replied_to_member_id":81},{"id":803,"memberId":83,"contents":"Parent is not loaded","memberNickname":"Example guest","parentId":999,"repliedToMemberId":82}]"#
    public static func post(id: Int = 701) throws -> SquarePost {
        guard id > 0 else { throw APIError.invalidRequest }
        let json = legacyPostJSON.replacingOccurrences(of: "\"id\":701", with: "\"id\":\(id)")
        return try JSONDecoder().decode(SquarePost.self, from: Data(json.utf8)).qualified(as: .legacySquare)
    }
    public static func comments() throws -> [SquareComment] {
        try JSONDecoder().decode([SquareComment].self, from: Data(commentsJSON.utf8)).map { $0.qualified(as: .legacySquare) }
    }
}

#endif
