#if DEBUG
import Foundation

public enum SocialAccountSyntheticFixtures {
    public static let profileJSON = #"{"id":82,"nickname":"Example city explorer","introduction":"Synthetic profile for offline native testing / 离线原生测试资料","levelId":3,"followNum":4,"fansNum":8,"likeNum":12,"topicNum":2,"activityNum":1,"isFollow":false,"casePics":"","sysCategoryList":[{"id":5,"categoryName":"Example walking interest"}]}"#
    public static let informationJSON = #"[{"id":91,"title":"Example city guide / 示例城市指南","subtitle":"Synthetic route basics","contents":"This is offline fixture content. No real route, purchase or location is represented."},{"id":92,"title":"2026","subtitle":"Example yearly city recap","contents":"Synthetic information body."},{"id":93,"title":"11","subtitle":"11","contents":"Filtered: no meaningful title."},{"id":94,"title":"Empty fixture","contents":""}]"#
    public static let membersJSON = #"[{"id":7,"nickname":"Example invited member","createTime":"2026-09-28 09:30:00"},{"id":8,"nickname":"","createTime":"2026-09-20 10:00:00"},{"id":9,"nickname":"Example earlier member","createTime":"2026-08-02 12:00:00"},{"id":10,"nickname":"Example undated member"}]"#
    public static let rewardsJSON = #"{"rows":[{"id":1,"eventType":5,"eventId":"007","changePoints":12.5,"createTime":"2026-09-29"},{"id":2,"eventType":5,"eventId":7,"changePoints":2.5},{"id":3,"eventType":5,"eventId":8,"changePoints":-8},{"id":4,"eventType":6,"eventId":9,"changePoints":99}],"total":4}"#
    public static func profile(id: Int = 82, relationshipKnown: Bool = true) throws -> SocialPublicProfile {
        var json = profileJSON.replacingOccurrences(of: "\"id\":82", with: "\"id\":\(id)")
        if !relationshipKnown { json = json.replacingOccurrences(of: "\"isFollow\":false,", with: "") }
        return try JSONDecoder().decode(SocialPublicProfile.self, from: Data(json.utf8))
    }
    public static func information() throws -> [SocialInformation] { try JSONDecoder().decode([SocialInformation].self, from: Data(informationJSON.utf8)) }
    public static func members() throws -> [SocialInvitedMember] { try JSONDecoder().decode([SocialInvitedMember].self, from: Data(membersJSON.utf8)) }
    public static func rewards(partial: Bool = false) throws -> SocialRewardScan {
        try JSONDecoder().decode(SocialRewardScan.self, from: Data((partial ? rewardsJSON.replacingOccurrences(of: "\"total\":4", with: "\"total\":240") : rewardsJSON).utf8))
    }
    public static func imageMessage() throws -> MessagingMessage {
        try JSONDecoder().decode(MessagingMessage.self, from: Data(#"{"id":90,"conversationId":901,"senderId":82,"msgType":2,"content":"https://media.example.test/synthetic.png"}"#.utf8))
    }
}
#endif
