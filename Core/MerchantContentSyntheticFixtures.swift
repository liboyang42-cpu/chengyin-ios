#if DEBUG
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum MerchantContentFixtureData {
    public static let access = #"{"active":true,"merchant":{"id":31,"name":"Synthetic Atelier"},"roleCode":"MERCHANT_OWNER","permissions":["merchant:project:manage","merchant:marketing:read"]}"#
    public static let application = #"{"id":12,"topicId":70,"chapterId":7,"topicName":"Synthetic route","chapterName":"Market chapter","status":0,"source":0,"offerActive":false}"#
    public static let registration = #"{"id":22,"topicId":70,"topicName":"Synthetic route","status":2,"auditStatus":0,"reason":"Add a clear venue description","addressName":"Atelier","address":"Synthetic street","longitude":"","latitude":"","activityDesc":"A local activity","picUrl":"","limitNum":4,"startDate":"source civil time"}"#
    public static let projection = #"{"perspective":"MERCHANT","sessionId":90,"activityId":80,"revision":3,"status":"PREPARING","availableActions":["STATION_ACCEPT","STATION_DECLINE","STATION_READY"],"merchant":{"stations":[{"stationId":61,"nodeId":62,"nodeName":"Synthetic station","stationCode":"SHOP_A","status":"ACCEPTED","revision":3,"preparationChecklist":[{"code":"KIT","label":"Prepare the kit","checked":false}],"capacity":4,"serviceStartAt":"2026-10-02 10:00","serviceEndAt":"2026-10-02 12:00","pendingVerificationCount":0,"merchantInstruction":"Check materials","hiddenInfoReminder":"Keep the answer private","playerTask":{"prompt":"Find the pattern"},"playable":false}],"fallbackOptions":[]}}"#
    public static func value(_ json: String) throws -> MerchantContentValue { try JSONDecoder().decode(MerchantContentValue.self, from: Data(json.utf8)) }
}
/// Requests terminate here; no socket, URLSession, media capture or provider exists in the fixture.
public final class MerchantContentFixtureTransport: MerchantContentOfflineTransport {
    public var denied = false
    public var unknownWrite = false
    public var failReads = false
    public private(set) var requests: [URLRequest] = []
    private var npc = #"{"name":"Synthetic guide","avatar":"fixture-avatar","greeting":"Welcome","voiceStatus":0}"#
    private var lastCommand: MerchantContentValue = .null
    public init() {}
    public func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        let path = request.url?.path ?? ""
        if path == "/api/merchant/access/me" { return envelope(denied ? #"{"active":false,"permissions":[]}"# : MerchantContentFixtureData.access) }
        if failReads { throw URLError(.notConnectedToInternet) }
        switch path {
        case "/api/merchant/marketing-home": return envelope(#"{"recruiting":{"items":[{"id":70,"name":"Synthetic recruiting route","merchantSignUpEndDate":"2026-10-10"}]}}"#)
        case "/api/project/my": return envelope(#"{"rows":[{"id":70,"bizType":"topic","title":"Synthetic route","stateText":"Draft"}],"total":1}"#)
        case "/api/project/home": return envelope(#"{"topic":{"name":"Synthetic route","city":"Sample city"},"host":{"recruit":{"nodeFilled":1,"nodeTotal":2,"pendingCount":1},"players":{"paidCount":2}},"join":{"registration":{"addressName":"Atelier","status":0}}}"#)
        case "/api/project/players": return envelope(#"{"rows":[{"name":"Synthetic guest","ticketName":"Sample ticket","state":"pending"}],"summary":{"paidCount":1,"pendingCount":1},"contactVisible":false,"contactHint":"Contact sharing consent is unavailable"}"#)
        case "/api/topic/info-to-user", "/api/topic/info-to-merchant": return envelope(#"{"id":70,"name":"Synthetic route","chaptersList":[{"id":7,"nodes":[{"id":62,"name":"Synthetic station"}]}]}"#)
        case "/api/topic/merchant-recruitment-chapters": return envelope(#"[{"id":7,"name":"Market chapter","description":"A short local visit","category":"Cafe","required":1,"recruitStatus":{"termsMode":"TRAFFIC","remainingMerchantCount":3,"maxMerchant":4,"state":"OPEN"}}]"#)
        case "/api/merchant/chapter-application/mine", "/api/merchant/chapter-application/owner-list": return envelope("[" + MerchantContentFixtureData.application + "]")
        case "/api/merchant/chapter-application/invitable": return envelope(#"[{"memberId":42,"chapterId":7,"name":"Synthetic partner","chapterName":"Market chapter"}]"#)
        case "/api/merchant/chapter-node/mine", "/api/merchant/chapter-node/pending": return envelope(#"[{"id":62,"chapterId":7,"topicId":70,"name":"Synthetic station","nodeAuditStatus":1,"address":"Synthetic street"}]"#)
        case "/api/merchant/upcoming-runs": return envelope(#"[{"ticketId":11,"startTime":"2026-10-02 10:00:00","paidCount":3,"teamStatus":"FORMED"}]"#)
        case "/api/registration/merchant/list": return envelope("{\"rows\":[" + MerchantContentFixtureData.registration + "]}")
        case "/api/registration/merchant/info": return envelope(MerchantContentFixtureData.registration)
        case "/api/registration/merchant/select": return envelope(#""未报名""#)
        case "/api/merchant/city-node/list": return envelope(#"{"nodes":[{"poiId":17,"name":"Synthetic place","status":1,"address":"Synthetic street"}],"applications":[{"id":91,"poiName":"Claim awaiting review","applicationType":2,"auditStatus":0}],"used":1,"max":5}"#)
        case "/api/merchant/city-node/claimable": return envelope(#"[{"poiId":18,"name":"Synthetic square"}]"#)
        case "/api/merchant/info": return envelope(#"{"id":31,"name":"Synthetic Atelier","address":"Synthetic street","locationLat":12.3,"locationLng":45.6}"#)
        case "/api/template/my-list": return envelope(#"{"rows":[{"id":4,"title":"Synthetic question"}]}"#)
        case "/api/merchant/chapter-node/npc/detail": return envelope(npc)
        case "/api/merchant/chapter-node/npc/voice/status": return envelope(#"{"voiceStatus":1}"#)
        case "/api/game/session/merchant/entries": return envelope(#"[{"activityId":80,"topicId":70,"activityName":"Synthetic play session","stationCount":1}]"#)
        case "/api/game/session/view": return envelope(MerchantContentFixtureData.projection)
        case "/api/game/session/receipt":
            guard lastCommand.object != nil else { return envelope(#"{"outcome":"PENDING"}"#) }
            var f: [String: MerchantContentValue] = ["activityId": lastCommand["activityId"], "requestId": lastCommand["requestId"], "action": lastCommand["action"], "outcome": .string("APPLIED"), "receiptId": .integer(77), "revision": .integer(4)]
            if unknownWrite { f["outcome"] = .string("PENDING") }
            return (try JSONEncoder().encode(MerchantContentValue.object(["code": .integer(200), "data": .object(f)])), 200)
        case "/api/merchant/chapter-node/poster-code": return envelope(#"{"code":"SYNTHETIC-NOT-REDEEMABLE","nodeName":"Synthetic station"}"#)
        default:
            if path == "/api/game/session/command", let body = request.httpBody { lastCommand = try JSONDecoder().decode(MerchantContentValue.self, from: body) }
            if unknownWrite { throw URLError(.timedOut) }
            if path == "/api/merchant/city-node/save" { return envelope(#"{"id":92}"#) }
            return envelope(#"{}"#)
        }
    }
    private func envelope(_ data: String) -> (Data, Int) { (Data(("{\"code\":200,\"msg\":\"Synthetic acknowledgement\",\"data\":" + data + "}").utf8), 200) }
}
#endif
