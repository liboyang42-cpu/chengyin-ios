#if DEBUG
import SwiftUI

/// Parent may install only behind an explicit DEBUG UI-test launch argument.
@MainActor struct PublicMerchantHomeFixtureView: View {
    let scenario: String
    @State private var featuredScope = UUID()
    private let transport: PublicMerchantHomeFixtureTransport
    private let configuration: APIConfiguration
    private let session: PublicMerchantReviewSession
    private let journal = MerchantBusinessMemoryIntentStore()
    init(scenario: String) {
        self.scenario = scenario
        transport = PublicMerchantHomeFixtureTransport(scenario: scenario)
        configuration = try! APIConfiguration(baseURL: URL(string: "https://example.com/")!)
        session = try! PublicMerchantReviewSession(accountID: 8, scope: UUID(), realm: "https://example.com/", token: "fixture-token")
    }
    var body: some View {
        let reader = PublicMerchantHomeHTTPReader(configuration: configuration, transport: transport, scope: featuredScope, isOfflineExample: true)
        let reviewReader = PublicMerchantReviewHTTPReader(configuration: configuration, transport: transport, scope: session.scope, isOfflineExample: true, session: session)
        let writer = PublicMerchantReviewHTTPWriter(configuration: configuration, transport: transport, currentSession: { session })
        var context = PublicMerchantHomeContext(reader: reader, publicReviews: { target in
            AnyView(PublicMerchantReviewsView(target: target, reader: reviewReader, writes: .init(writer: writer, journal: journal)))
        })
        let captured = featuredScope
        if scenario.hasPrefix("featured-"), scenario != "featured-static" {
            context.featured = .init(scope: captured, isCurrent: { captured == featuredScope }, activity: { id in
                AnyView(VStack {
                    if scenario == "featured-unavailable" { Text("merchant.publicHome.unavailable") }
                    else { Text(verbatim: "Synthetic activity \(id)").accessibilityIdentifier("merchant.featured.fixture.activity") }
                    if scenario == "featured-switch" {
                        Button("Change fixture session") { featuredScope = UUID() }
                            .accessibilityIdentifier("merchant.featured.fixture.changeScope")
                    }
                }.navigationTitle("merchant.publicHome.featured.activity"))
            }, couponWallet: {
                AnyView(Text("Synthetic owned coupon wallet").accessibilityIdentifier("merchant.featured.fixture.wallet"))
            })
        }
        return NavigationStack {
            if scenario.hasPrefix("reviews-") {
                PublicMerchantReviewFilterFixtureView(scenario: scenario)
            } else {
                PublicMerchantHomeView(target: scenario == "invalid" ? nil : .ownerMemberID(PublicMerchantOwnerID(41)!), context: context)
            }
        }.dynamicTypeSize(ProcessInfo.processInfo.arguments.contains("--uitesting-large-text") ? .accessibility5 : .large)
    }
}
private final class PublicMerchantHomeFixtureTransport: HTTPTransport {
    let scenario: String
    private var requests = 0
    init(scenario: String) { self.scenario = scenario }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        let path = request.url?.path ?? ""
        let value: String
        if path.hasSuffix("/public-home") {
            requests += 1
            if scenario == "unavailable" { value = #"{"code":500,"msg":"商家不存在或未开放"}"# }
            else if scenario == "retry", requests == 1 { value = #"{"code":500,"msg":"Fixture failure"}"# }
            else if scenario == "missing-ids" { value = #"{"code":200,"data":{"name":"Fixture shop","id":73}}"# }
            else if scenario.hasPrefix("featured-") {
                let featured: String
                switch scenario {
                case "featured-coupon": featured = #"{"id":901,"featuredType":2,"featuredId":901,"name":"Synthetic featured coupon","description":"Public coupon description","imgUrl":"https://example.com/not-a-coupon-image.jpg"}"#
                case "featured-unknown": featured = #"{"id":601,"featuredType":99,"featuredId":601,"name":"Should not appear"}"#
                case "featured-malformed": featured = #"{"id":601,"featuredType":1,"featuredId":"601","name":"Should not appear"}"#
                case "featured-null": featured = "null"
                default:
                    let id = scenario == "featured-switch" && requests > 1 ? 602 : 601
                    featured = "{\"id\":\(id),\"featuredType\":1,\"featuredId\":\(id),\"name\":\"Synthetic featured walk\",\"description\":\"Public activity description\",\"imgUrl\":\"https://example.com/featured.jpg\"}"
                }
                let identity = scenario == "featured-missing-identity" ? "\"id\":73" :
                    (scenario == "featured-mismatched-owner" ? "\"id\":73,\"memberId\":42" : "\"id\":73,\"memberId\":41")
                value = "{\"code\":200,\"data\":{\"name\":\"Fixture shop\",\(identity),\"featured\":\(featured)}}"
            }
            else { value = #"{"code":200,"data":{"name":"Fixture shop","id":73,"memberId":41,"businessStatus":1,"gallery":"https://example.com/one.jpg;https://example.com/two.jpg","capacity":8,"availableTime":"Fixture hours","npc":{"name":"Fixture guide","greeting":"Welcome"}}}"# }
        } else if path.hasSuffix("/reviews/public") {
            value = #"{"code":200,"data":{"mode":"public","pageNum":1,"pageSize":20,"total":1,"hasMore":false,"averageRating":5,"eligibility":{"canCreate":true,"reasonCode":"ELIGIBLE","registrationId":19},"items":[{"id":9,"rating":5,"content":"Fixture review","imageUrls":[],"authorNickname":"Fixture player","verifiedRedemption":true,"status":"VISIBLE","version":2,"canReply":false,"canReport":true}]}}"#
        } else if scenario == "unknown" { throw URLError(.timedOut) }
        else if path.hasSuffix("/reviews/create") { value = #"{"code":200,"data":{"reviewId":10,"status":"PENDING_REVIEW","version":0,"replayed":false,"auditTaskId":44}}"# }
        else if path.hasSuffix("/reviews/report") { value = #"{"code":200,"data":{"reviewId":9,"status":"PENDING_PLATFORM_REVIEW","replayed":false,"auditTaskId":45}}"# }
        else { throw URLError(.unsupportedURL) }
        return (Data(value.utf8), 200)
    }
}
#endif
