#if DEBUG
import Foundation

/// Offline synthetic examples only. No real account, contact, agreement, money or server activity.
public enum CooperationSyntheticFixtures {
    public static let invitationsJSON = #"""
    {"code":200,"data":{"sent":[{"id":71,"inviteType":0,"topicId":301,"status":1,"shareMode":0,"termsFrozen":true,"partner":{"name":"Sample sent merchant"}}],"received":[{"id":71,"inviteType":1,"fromId":20,"toType":"club","toId":30,"topicId":301,"gameId":401,"status":0,"message":"Sample invitation notes","handleReason":"Sample recorded reply","shareMode":1,"shareRate":12.5,"depositOwed":true,"depositRefundPending":false,"partner":{"name":"Sample receiving partner"},"createTime":"2026-09-20 10:30:00","expireTime":"2026-10-20 10:30:00"},{"id":72,"inviteType":2,"topicId":302,"status":5,"shareMode":2,"fixedFee":8.25,"depositOwed":true,"partner":{"name":"Sample historical invitation"}},{"id":73,"inviteType":99,"topicId":303,"status":99,"partner":{"name":"Sample unknown state"}}],"slots":{"byGame":{"401":{"pending":2,"cap":4}},"byTopic":{"301":{"accepted":1,"cap":3}}}}}
    """#
    public static let receivedApplicationsJSON = #"""
    {"code":200,"data":[{"applyId":81,"topicId":301,"status":0,"clubId":30,"clubName":"Sample applying club","topicName":"Sample owned route","scope":"MERCHANT","startDate":"2026-10-12"}]}
    """#
    public static let sentApplicationsJSON = #"""
    {"code":200,"data":[{"applyId":82,"topicId":302,"status":2,"clubName":"Sample own club","merchantNick":"Sample merchant","topicName":"Sample withdrawn application","message":"Sample intention only"}]}
    """#
    public static let registrationsJSON = #"""
    {"code":200,"data":{"rows":[{"id":91,"topicId":301,"topicName":"Sample owned route","memberId":50,"merchantName":"Sample registered merchant","merchantMeta":"Synthetic candidate","addressName":"Sample meeting point","auditStatus":0}],"hasMore":true}}
    """#
    public static let poolJSON = #"""
    {"code":200,"data":{"hasClub":true,"rows":[{"topicId":301,"name":"Sample available collaboration","subtitle":"Synthetic source state","merchantNick":"Sample publisher","state":"open","startDate":"2026-10-12","recruitDeadline":"2026-10-10"},{"topicId":302,"name":"Sample converted collaboration","state":"converted","applyId":81},{"topicId":303,"name":"Sample future pool state","state":"future"}]}}
    """#
    public static let candidatesJSON = #"""
    {"code":200,"data":{"clubApplies":[{"id":81,"clubName":"Sample candidate club","status":3,"inviteStatus":"accepted","message":"Sample club application"}],"registrations":[{"id":91,"merchantName":"Sample candidate merchant","status":0}]}}
    """#
}

#endif
