import XCTest
@testable import Questify

/// New real-factory/AppSession regressions over synthetic HTTP, token and Keychain primitives only.
/// These tests do not call a location provider, URLSession, OS Keychain or a real backend.
@MainActor final class NativeHomeReturnCompositionTests: XCTestCase {
    private final class Token: AppTokenStorage {
        var value: String?
        func read() throws -> String? { value }
        func write(_ token: String) throws { value = token }
        func clear() throws { value = nil }
    }
    private actor Vault: PrivateHomeKeychainPrimitive {
        var items: [String: PrivateHomeKeychainItem] = [:]
        func read(key: String) throws -> PrivateHomeKeychainItem? { items[key] }
        func insert(key: String, item: PrivateHomeKeychainItem) throws -> Bool {
            guard items[key] == nil else { return false }; items[key] = item; return true
        }
        func remove(key: String, matchingTag: Data) throws -> Bool {
            guard items[key]?.tag == matchingTag else { return false }; items[key] = nil; return true
        }
    }
    private final class Wire: HTTPTransport {
        var requests: [URLRequest] = []
        var role = "player"
        var response: ((URLRequest) throws -> (Data, Int))?
        var pauseRuns = false
        var onPaused: (() -> Void)?
        private var pendingRuns: CheckedContinuation<(Data, Int), Error>?
        func resumeRuns() {
            pendingRuns?.resume(returning: (Data("{\"code\":200,\"data\":{\"runs\":[],\"truncated\":false}}".utf8), 200))
            pendingRuns = nil
        }
        var returnRequests: [URLRequest] { requests.filter { $0.url?.path.contains("/api/native/home/return/") == true } }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            if pauseRuns && request.url?.lastPathComponent == "runs" {
                pauseRuns = false
                return try await withCheckedThrowingContinuation { pendingRuns = $0; onPaused?() }
            }
            if let response { return try response(request) }
            switch request.url?.lastPathComponent {
            case "phone": return (Data("{\"code\":200,\"token\":\"synthetic-7\",\"data\":{\"id\":7,\"role\":\"\(role)\"}}".utf8), 200)
            case "userInfo": return (Data("{\"code\":200,\"appUser\":{\"id\":7,\"role\":\"\(role)\"}}".utf8), 200)
            case "runs": return (Data("{\"code\":200,\"data\":{\"runs\":[],\"truncated\":false}}".utf8), 200)
            default: return (Data("{\"code\":200,\"data\":null}".utf8), 200)
            }
        }
    }
    private func root(_ wire: Wire, granted: Bool = true, withVault: Bool = true) throws -> (AppCompositionRoot, RuntimeDependencyContext) {
        func make(_ grant: PrivateHomeTransportGrant?) throws -> ReviewedAppDeployment {
            try .init(market: .china, baseURL: "https://native-home.example.test/native",
                approvedBaseURLs: [.china: ["https://native-home.example.test/native"]], verifiedCapabilities: [.domesticChinaPhone],
                bundleIdentifier: "test.questify.nativeHome", realm: "synthetic", privateHome: grant)
        }
        let base = try make(nil)
        let deployment = try make(granted ? PrivateHomeTransportGrant(storageScope: base.storageScope, accountID: 7, role: "player") : nil)
        let suite = "native-home-composition-" + UUID().uuidString, token = Token()
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let vault: (any PrivateHomeKeychainPrimitive)? = withVault ? Vault() : nil
        let root = AppCompositionRoot(deployment: .reviewed(deployment),
            storage: .init(defaults: defaults, tokenStore: { _ in token }, privateHomeKeychain: vault), makeTransport: { wire })
        let context = RuntimeDependencyContext(market: .china, baseURL: URL(string: "https://native-home.example.test/native")!, role: "player",
            session: try .init(accountID: 7, epoch: 1, namespace: deployment.storageScope.service, token: "synthetic-7", role: "player"))
        return (root, context)
    }
    private func envelope(_ data: Any) throws -> (Data, Int) {
        (try JSONSerialization.data(withJSONObject: ["code": 200, "data": data]), 200)
    }
    func testRealFactoryForwardsAllSixExactRoutesWithIndependentGrant() async throws {
        let wire = Wire(), (root, context) = try self.root(wire)
        let grant = try NativeHomeReturnApproval(context: context, expiresAt: Date().addingTimeInterval(600))
        let transport = try XCTUnwrap(root.makeNativeHomeReturnTransport(approval: grant, current: { context }, selected: { _ in grant }))
        let service = NativeHomeReturnService(approval: grant, transport: transport, current: { context }, selected: { _ in grant })
        wire.response = { request in
            switch request.url!.lastPathComponent {
            case "policy": return try self.envelope(["policyVersion":"test-policy", "maxAccuracyMeters":50, "maxFixAgeSeconds":30, "dwellSeconds":0, "serverTimeMillis":1_000_000_000])
            case "runs": return try self.envelope(["runs":[], "truncated":false])
            case "account": return try self.envelope(["scopeType":"RUN", "scopeId":"42", "resourceType":"sys.hp", "current":2, "maximum":5, "version":4])
            case "verify":
                let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String:Any])
                return try self.envelope(["requestId":body["requestId"]!, "decision":"VERIFIED", "proofId":"proof-1", "homeVersion":3, "accountVersion":4, "expiresAtMillis":1_000_060_000])
            case "restore":
                let body = try JSONDecoder().decode(NativeHomeRestoreRequest.self, from: XCTUnwrap(request.httpBody))
                return try self.envelope(["requestId":body.requestId, "proofId":body.proofId, "decision":"RESTORED", "current":5, "maximum":5, "accountVersion":5])
            case "receipt": return (Data("{\"code\":200}".utf8), 200)
            default: XCTFail("Unexpected final-forward route"); return (Data(), 500)
            }
        }
        let publishedPolicy = try await service.policy()
        let policy = try XCTUnwrap(publishedPolicy)
        _ = try await service.runs(); _ = try await service.account(for: .run(runId: "42", resourceType: "sys.hp"))
        let home = try JSONDecoder().decode(PrivateHomeSnapshot.self, from: Data("{\"version\":3,\"status\":\"ACTIVE\",\"label\":\"Synthetic\",\"latitude\":12,\"longitude\":45,\"datum\":\"WGS84\",\"changedAt\":1,\"effectiveAt\":1}".utf8))
        let now = Date(timeIntervalSince1970: 1_000_000)
        let check = try NativeHomeReturnCheck.preflight(home: home,
            status: .measured(.init(latitude:12, longitude:45, accuracyMeters:5, capturedAt:now)),
            policy:policy, scope:.run(runId:"42",resourceType:"sys.hp"), now:now, expectedAccountVersion:4)
        let verification = try await service.verify(check), proof = try verification.proof(for: check)
        let request = try NativeHomeRestoreRequest(proof:proof, currentHomeVersion:3, expectedAccountVersion:4, deviceNow:now, serverOffset:0)
        _ = try await service.restore(request); let absent = try await service.restoreReceipt(for:request); XCTAssertNil(absent)
        XCTAssertEqual(wire.returnRequests.map { $0.url!.lastPathComponent }, ["policy","runs","account","verify","restore","receipt"])
        XCTAssertEqual(wire.returnRequests.map(\.httpMethod), ["GET","GET","GET","POST","POST","GET"])
        XCTAssertTrue(wire.returnRequests.allSatisfy { $0.value(forHTTPHeaderField:"Authorization") == "synthetic-7" })
    }
    func testFinalForwardRejectsForeignPathsMethodsQueriesBodiesAndToken() async throws {
        let wire = Wire(), (root, context) = try self.root(wire)
        let grant = try NativeHomeReturnApproval(context:context, expiresAt:Date().addingTimeInterval(600))
        let transport = try XCTUnwrap(root.makeNativeHomeReturnTransport(approval:grant, current:{context}, selected:{_ in grant}))
        func request(_ suffix:String, method:String = "GET") -> URLRequest {
            var request = URLRequest(url:URL(string:context.baseURL.absoluteString + "/" + suffix)!)
            request.httpMethod=method; request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("synthetic-7",forHTTPHeaderField:"Authorization"); request.setValue("no-store",forHTTPHeaderField:"Cache-Control")
            request.setValue("no-cache",forHTTPHeaderField:"Pragma"); return request
        }
        for suffix in ["api/native/home", "api/wallet/stages", "api/native/home/return/unknown", "api/native/home/return/policy?ownerId=7",
                       "api/native/home/return/account?runId=42&runId=43", "api/native/home/return/runs?beforeRunId=0042"] {
            do { _ = try await transport.send(request(suffix)); XCTFail("Unexpected route: \(suffix)") } catch {}
        }
        do { _ = try await transport.send(request("api/native/home/return/restore")); XCTFail() } catch {}
        do { _ = try await transport.send(request("api/native/home/return/policy",method:"POST")); XCTFail() } catch {}
        var wrongToken=request("api/native/home/return/policy"); wrongToken.setValue("other",forHTTPHeaderField:"Authorization")
        do { _ = try await transport.send(wrongToken); XCTFail() } catch {}
        var injected=request("api/native/home/return/restore",method:"POST"); injected.setValue("application/json",forHTTPHeaderField:"Content-Type")
        injected.httpBody=Data("{\"requestId\":\"request-1\",\"proofId\":\"proof-1\",\"homeVersion\":3,\"expectedAccountVersion\":4,\"scopeType\":\"RUN\",\"scopeId\":\"42\",\"resourceType\":\"sys.hp\",\"ownerId\":7}".utf8)
        do { _ = try await transport.send(injected); XCTFail() } catch {}
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testDefaultNilGrantMissingHomeGrantAndMissingVaultDoNotConstructJourney() async throws {
        for (homeGranted,withVault) in [(true,true),(false,true),(true,false)] {
            let wire=Wire(), (root,context)=try self.root(wire,granted:homeGranted,withVault:withVault)
            XCTAssertNil(root.nativeHomeReturnApproval(context))
            let grant=try NativeHomeReturnApproval(context:context,expiresAt:Date().addingTimeInterval(600))
            XCTAssertNil(root.makeNativeHomeReturnSelection(context:context,approval:grant,current:{context},selected:{_ in nil}))
            if !homeGranted || !withVault {
                XCTAssertNil(root.makeNativeHomeReturnSelection(context:context,approval:grant,current:{context},selected:{_ in grant}))
            }
            if !homeGranted { XCTAssertNil(root.makeNativeHomeReturnTransport(approval:grant,current:{context},selected:{_ in grant})) }
            XCTAssertTrue(wire.requests.isEmpty)
        }
    }
    func testFinalForwardRevocationDuringHTTPRejectsLateResult() async throws {
        let wire=Wire(), (root,context)=try self.root(wire)
        let grant=try NativeHomeReturnApproval(context:context,expiresAt:Date().addingTimeInterval(600))
        let transport=try XCTUnwrap(root.makeNativeHomeReturnTransport(approval:grant,current:{context},selected:{_ in grant}))
        let service=NativeHomeReturnService(approval:grant,transport:transport,current:{context},selected:{_ in grant})
        wire.response={ _ in grant.revoke(); return try self.envelope(["runs":[],"truncated":false]) }
        do { _ = try await service.runs(); XCTFail() } catch {}
        XCTAssertEqual(wire.returnRequests.count,1)
        do { _ = try await service.runs(); XCTFail() } catch {}
        XCTAssertEqual(wire.returnRequests.count,1)
    }
    func testRealAppSessionRetainsOwnerAndViewerRevisionBlocksRoleABA() async throws {
        let wire=Wire(), (root,_)=try self.root(wire), session=root.makeSession()
        await session.bootstrap(); await session.authChannels.loginWithPhone(phone:"10000000000",code:"123456")
        XCTAssertEqual(session.account?.id,7); XCTAssertNil(session.nativeHomeReturnSelection)
        var issued:NativeHomeReturnApproval?
        session.nativeHomeReturnApprovalSelector={ context in
            if issued == nil { issued=try? NativeHomeReturnApproval(context:context,expiresAt:Date().addingTimeInterval(600)) }
            return issued
        }
        let old=try XCTUnwrap(session.nativeHomeReturnSelection)
        XCTAssertTrue(session.nativeHomeReturnSelection === old)
        await old.load(); XCTAssertEqual(old.phase,.ready); XCTAssertEqual(wire.returnRequests.count,1)
        wire.role="merchant"; await session.refreshOwnAccount()
        wire.role="player"; await session.refreshOwnAccount()
        let count=wire.returnRequests.count
        await old.load(); XCTAssertEqual(old.phase,.invalidated); XCTAssertEqual(wire.returnRequests.count,count)
        let fresh=try XCTUnwrap(session.nativeHomeReturnSelection); XCTAssertFalse(fresh === old)
        session.setPrivateHomePresentationActive(false)
        await fresh.load(); XCTAssertEqual(fresh.phase,.invalidated); XCTAssertEqual(wire.returnRequests.count,count)
    }
    func testRealSessionLateRunsResponseCannotReviveOwnerAfterRoleABA() async throws {
        let wire = Wire(), (root, _) = try self.root(wire), session = root.makeSession()
        await session.bootstrap()
        await session.authChannels.loginWithPhone(phone: "10000000000", code: "123456")
        XCTAssertEqual(session.account?.id, 7)
        var issued: NativeHomeReturnApproval?
        session.nativeHomeReturnApprovalSelector = { context in
            if issued == nil { issued = try? NativeHomeReturnApproval(context: context, expiresAt: Date().addingTimeInterval(600)) }
            return issued
        }
        let old = try XCTUnwrap(session.nativeHomeReturnSelection)
        let paused = expectation(description: "Synthetic return request reached the final HTTP boundary")
        wire.pauseRuns = true; wire.onPaused = { paused.fulfill() }
        let load = Task { await old.load() }
        await fulfillment(of: [paused], timeout: 1)
        wire.role = "merchant"; await session.refreshOwnAccount()
        wire.role = "player"; await session.refreshOwnAccount()
        let replacement = try XCTUnwrap(session.nativeHomeReturnSelection)
        XCTAssertFalse(replacement === old)
        wire.resumeRuns(); await load.value
        XCTAssertEqual(old.phase, .invalidated); XCTAssertTrue(old.runs.isEmpty)
        XCTAssertEqual(replacement.phase, .idle); XCTAssertEqual(wire.returnRequests.count, 1)
    }

    func testFinalForwardUsesOriginalDecimalScaleAndRejectsDuplicateDecodedKeys() async throws {
        let wire = Wire(), (root, context) = try self.root(wire)
        let grant = try NativeHomeReturnApproval(context: context, expiresAt: Date().addingTimeInterval(600))
        let transport = try XCTUnwrap(root.makeNativeHomeReturnTransport(approval: grant, current: { context }, selected: { _ in grant }))
        let body = #"{"requestId":"request-1","homeVersion":3,"expectedAccountVersion":4,"scopeType":"RUN","scopeId":"42","resourceType":"sys.hp","policyVersion":"test-policy","latitude":12.123456,"longitude":45.123456,"datum":"WGS84","accuracyMeters":5.123456,"capturedAtMillis":1000000}"#
        func request(_ body: String) -> URLRequest {
            var request = URLRequest(url: context.baseURL.appendingPathComponent("api/native/home/return/verify"))
            request.httpMethod = "POST"; request.httpBody = Data(body.utf8); request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("synthetic-7", forHTTPHeaderField: "Authorization")
            request.setValue("no-store", forHTTPHeaderField: "Cache-Control"); request.setValue("no-cache", forHTTPHeaderField: "Pragma")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type"); return request
        }
        let invalid = [
            body.replacingOccurrences(of: "12.123456", with: "12.1234567"),
            body.replacingOccurrences(of: "45.123456", with: "45.00000000000000000001"),
            body.replacingOccurrences(of: "5.123456", with: "5.00000000000000000001"),
            body.replacingOccurrences(of: "12.123456", with: "1e-7"),
            body.replacingOccurrences(of: #""homeVersion":3"#, with: #""homeVersion":3.0"#),
            body.replacingOccurrences(of: #""expectedAccountVersion":4"#, with: #""expectedAccountVersion":4e0"#),
            body.replacingOccurrences(of: #""requestId":"request-1""#, with: #""requestId":"request-1","requestId":"request-1""#),
            body.replacingOccurrences(of: #""requestId":"request-1""#, with: #""requestId":"request-1","reque\u0073tId":"request-1""#)
        ]
        for value in invalid { do { _ = try await transport.send(request(value)); XCTFail("Invalid raw body crossed the boundary") } catch {} }
        XCTAssertTrue(wire.requests.isEmpty)
        _ = try await transport.send(request(body))
        _ = try await transport.send(request(body.replacingOccurrences(of: "5.123456", with: "0.0000000")))
        _ = try await transport.send(request(body.replacingOccurrences(of: "12.123456", with: "1000e-9")))
        XCTAssertEqual(wire.returnRequests.count, 3)
    }

}
