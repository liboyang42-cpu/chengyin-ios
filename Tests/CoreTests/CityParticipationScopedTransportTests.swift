import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor final class CityParticipationScopedTransportTests: XCTestCase {
    private static let invite = "00000000-0000-0000-0000-000000000001"
    @MainActor private final class Wire: HTTPTransport {
        var requests: [URLRequest] = []
        var status = 200
        var body = Data(#"{"code":200}"#.utf8)
        var beforeReply: (() -> Void)?
        func send(_ request: URLRequest) async throws -> (Data,Int) {
            requests.append(request); beforeReply?(); return (body,status)
        }
    }
    @MainActor private final class Harness {
        let context: RuntimeDependencyContext
        let api: APIConfiguration
        let scope: CityParticipationCommandScope
        let readScope: CityParticipationReadScope
        let command: CityParticipationCommand
        var current: RuntimeDependencyContext?
        var revision: UInt64 = 1
        var bundle: CityParticipationRuntimeGrants?
        var state: CityParticipationReadGrant?
        var invitation: CityParticipationInvitationGrant?
        var write: CityParticipationCommandGrant?
        var receipt: CityOriginalReceiptReadGrant?
        var unauthorizedCount = 0
        let wire = Wire()
        init() throws {
            api = try .init(baseURL:URL(string:"https://city.example.test/native/")!)
            let session = try PlayExperienceSession(accountID:7,epoch:2,namespace:"city-test",token:"fake-token",role:"player")
            context = .init(market:.china,baseURL:api.baseURL,role:"player",session:session); current = context
            scope = try .init(market:.china,baseURL:api.baseURL,namespace:"city-test",accountID:7,epoch:2,token:"fake-token")
            readScope = try .init(market:.china,baseURL:api.baseURL,namespace:"city-test",accountID:7,epoch:2,token:"fake-token",regionID:"region")
            command = try .init(kind:.create,requestID:"original",regionID:"region",releaseID:1,contentHash:String(repeating:"a",count:64),expectedVersion:0)
            bundle = try makeBundle()
        }
        func makeBundle() throws -> CityParticipationRuntimeGrants {
            try .init(context:context,revision:1,regionID:"region",expiresAt:Date().addingTimeInterval(600),
                state:{_ in self.state},invitation:{_,_,_ in self.invitation},command:{_ in self.write},receipt:{_ in self.receipt})
        }
        func approveAll() throws {
            state = .init(scope:readScope); invitation = .init(scope:scope,regionID:"region",code:CityParticipationScopedTransportTests.invite)
            write = try .init(scope:scope,command:command)
            receipt = .init(reference:try .init(session:scope.session,domain:.participation,requestID:"original"))
        }
        func transport() throws -> CityParticipationScopedTransport {
            .init(configuration:api,grants:try XCTUnwrap(bundle),underlying:wire,currentContext:{self.current},
                  currentRevision:{self.revision},currentGrants:{self.bundle},unauthorized:{self.unauthorizedCount += 1})
        }
        func request(_ suffix: String, query: String? = nil, method: String = "GET", body: Data? = nil) throws -> URLRequest {
            var parts = try XCTUnwrap(URLComponents(url:api.baseURL.appendingPathComponent("api/city-game/team-participation/"+suffix),resolvingAgainstBaseURL:false))
            parts.percentEncodedQuery = query
            var request = URLRequest(url:try XCTUnwrap(parts.url));request.httpMethod=method;request.httpBody=body;request.httpShouldHandleCookies=false
            request.setValue("fake-token",forHTTPHeaderField:"Authorization")
            if method == "POST" { request.setValue("application/json",forHTTPHeaderField:"Content-Type") }
            return request
        }
    }
    private func denied(_ transport: CityParticipationScopedTransport,_ request: URLRequest) async {
        do { _ = try await transport.send(request);XCTFail("Expected exact-scope denial") } catch {}
    }
    func testEmptyProviderBundleDoesNotGrantAnyRoute() async throws {
        let h = try Harness(), transport = try h.transport()
        await denied(transport,try h.request("state",query:"regionId=region"))
        await denied(transport,try h.request("command",method:"POST",body:h.command.wireBytes()))
        XCTAssertTrue(h.wire.requests.isEmpty)
    }
    func testAllFourExactRoutesPreserveOriginalRequestBytes() async throws {
        let h = try Harness();try h.approveAll();let transport = try h.transport()
        let requests = [try h.request("state",query:"regionId=region"),try h.request("invite",query:"regionId=region&code="+Self.invite),
                        try h.request("request/original"),try h.request("command",method:"POST",body:h.command.wireBytes())]
        for request in requests { _ = try await transport.send(request) }
        XCTAssertEqual(h.wire.requests.count,4);XCTAssertEqual(h.wire.requests.last?.httpBody,try h.command.wireBytes())
        XCTAssertEqual(h.wire.requests.map(\.url),requests.map(\.url))
    }
    func testDuplicateOrExtraQueryAndWrongMethodNeverDispatch() async throws {
        let h = try Harness();try h.approveAll();let transport = try h.transport()
        for request in [try h.request("state",query:"regionId=region&regionId=region"),try h.request("state",query:"regionId=region&x=1"),
                        try h.request("state",query:"regionId"),try h.request("request/original",query:"regionId=region"),
                        try h.request("command",query:"",method:"POST",body:h.command.wireBytes()),try h.request("state",method:"DELETE")] {
            await denied(transport,request)
        }
        XCTAssertTrue(h.wire.requests.isEmpty)
    }
    func testAlteredBodyOtherReferenceAndCrossOriginDoNotReuseGrant() async throws {
        let h = try Harness();try h.approveAll();let transport = try h.transport()
        var bytes = try h.command.wireBytes();bytes.append(32)
        await denied(transport,try h.request("command",method:"POST",body:bytes))
        await denied(transport,try h.request("request/another-original"))
        await denied(transport,try h.request("request/original%2Fother"))
        var foreign = try h.request("state",query:"regionId=region");foreign.url=URL(string:"https://other.example.test/native/api/city-game/team-participation/state?regionId=region")!
        await denied(transport,foreign)
        var token = try h.request("state",query:"regionId=region");token.setValue("other-token",forHTTPHeaderField:"Authorization")
        await denied(transport,token)
        XCTAssertTrue(h.wire.requests.isEmpty)
    }
    func testCookieAndGETBodyCannotReachUnderlyingTransport() async throws {
        let h = try Harness();try h.approveAll();let transport = try h.transport()
        var cookie = try h.request("state",query:"regionId=region");cookie.setValue("unapproved=1",forHTTPHeaderField:"Cookie")
        await denied(transport,cookie)
        var automatic = try h.request("state",query:"regionId=region");automatic.httpShouldHandleCookies=true
        await denied(transport,automatic)
        await denied(transport,try h.request("state",query:"regionId=region",body:Data()))
        XCTAssertTrue(h.wire.requests.isEmpty)
    }
    func testRevokedGrantDropsLateReplyWithoutRetry() async throws {
        let h = try Harness();try h.approveAll();let transport = try h.transport();h.wire.beforeReply={h.state?.revoke()}
        await denied(transport,try h.request("state",query:"regionId=region"));XCTAssertEqual(h.wire.requests.count,1)
        await denied(transport,try h.request("state",query:"regionId=region"));XCTAssertEqual(h.wire.requests.count,1)
    }
    func testBundleReplacementAndRevisionChangeCannotReuseOldTransport() async throws {
        let h = try Harness();try h.approveAll();let transport = try h.transport()
        h.bundle = try h.makeBundle();await denied(transport,try h.request("state",query:"regionId=region"))
        let fresh = try h.transport();h.revision=2;await denied(fresh,try h.request("state",query:"regionId=region"))
        XCTAssertTrue(h.wire.requests.isEmpty)
    }
    func testOnlyCurrent401MayNotifySessionOwner() async throws {
        let h = try Harness();try h.approveAll();let transport = try h.transport();h.wire.status=401
        _ = try await transport.send(h.request("state",query:"regionId=region"));XCTAssertEqual(h.unauthorizedCount,1)
        h.wire.beforeReply={h.current=nil}
        await denied(transport,try h.request("state",query:"regionId=region"));XCTAssertEqual(h.unauthorizedCount,1)
    }
    func testExpiryAndRevocationDoNotCreateAuthority() throws {
        let h = try Harness(), bundle = try XCTUnwrap(h.bundle)
        XCTAssertFalse(bundle.matches(h.context,revision:1,now:bundle.expiresAt))
        bundle.revoke();XCTAssertFalse(bundle.matches(h.context,revision:1));XCTAssertNil(bundle.state(h.readScope))
    }
}
