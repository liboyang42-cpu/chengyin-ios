import Foundation

@MainActor public enum NearbyTeamSyntheticFixtures {
    public static let session = NearbyTeamSession(accountID: 7001, epoch: 1, region: "US", namespace: "nearby.synthetic", role: "player")
    public static let context = NearbyQueryContext(latitude: 37.78, longitude: -122.42)
    public static let teams = """
    {"code":200,"data":[
      {"teamId":501,"activityId":901,"topicId":801,"title":"Saturday explorers","activityName":"City clues","leaderName":"River","addressName":"Demo meeting point","coordSource":"GATHER","productType":1,"distance":1500,"latitude":37.78,"longitude":-122.42,"joinedCount":2,"maxMembers":4,"viewerStatus":"NONE","viewerHasTicket":true},
      {"teamId":502,"activityId":902,"title":"Pending team","leaderName":"Jun","joinedCount":2,"maxMembers":4,"viewerStatus":"PENDING","applyExpireTime":"2099-10-02T02:00:00Z"},
      {"teamId":503,"activityId":903,"title":"Your demo team","joinedCount":2,"maxMembers":4,"pendingCount":1,"viewerStatus":"LEADER"},
      {"teamId":504,"activityId":904,"title":"Ticket needed","joinedCount":1,"maxMembers":4,"viewerStatus":"NONE","viewerHasTicket":false},
      {"teamId":505,"activityId":905,"title":"Joined team","joinedCount":3,"maxMembers":4,"viewerStatus":"JOINED"},
      {"teamId":506,"activityId":906,"title":"Rejected application","joinedCount":1,"maxMembers":4,"viewerStatus":"REJECTED"}
    ]}
    """
    public static let applicants = """
    {"code":200,"data":[{"memberId":6001,"memberName":"Alex","applyMessage":"Happy to explore together","appliedAt":"2026-10-01 12:00:00","applyExpireTime":"2099-10-02T02:00:00Z"}]}
    """
    public static let applications = """
    {"code":200,"data":[{"teamId":502,"title":"Pending team","leaderName":"Jun","applyStatus":"PENDING","applyExpireTime":"2099-10-02T02:00:00Z"},{"teamId":506,"title":"Rejected application","applyStatus":"REJECTED"}]}
    """
    public static func response(_ json: String) -> NearbyTeamResponse { .init(data: Data(json.utf8)) }
    public static func coordinator() -> NearbyTeamCoordinator {
        let fake = NearbyTeamFakeTransport()
        fake.fallbackResponses = ["/api/team/nearby": response(teams), "/api/team/my-applications": response(applications), "/api/team/applications": response(applicants), "/api/team/apply": response("{\"code\":200}"), "/api/team/withdraw": response("{\"code\":200}"), "/api/team/handle": response("{\"code\":200}")]
        return .init(service: .init(fake: fake), session: session, locks: .init())
    }
}
