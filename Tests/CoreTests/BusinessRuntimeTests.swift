import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor final class BusinessRuntimeTests: XCTestCase {
    private let base = URL(string: "https://example.com/business/")!
    private func context(account: Int = 7, epoch: UInt64 = 1, token: String = "synthetic", role: String = "merchant", namespace: String = "fixture", market: RegionalMarket = .china) throws -> RuntimeDependencyContext {
        .init(market: market, baseURL: base, role: role, session: try .init(accountID: account, epoch: epoch, namespace: namespace, token: token))
    }
    private func config(_ routes: [BusinessRuntimeFeature: Set<BusinessRuntimeRoute>] = [:]) throws -> BusinessRuntimeConfiguration {
        try .init(market: .china, baseURL: base, namespace: "fixture", accountID: 7, routes: routes)
    }
    private func request(_ path: String, method: String = "POST", token: String = "synthetic") -> URLRequest {
        var value = URLRequest(url: base.appendingPathComponent(path)); value.httpMethod = method
        value.setValue(token, forHTTPHeaderField: "Authorization"); return value
    }
    func testMissingConfigurationAndEmptyFeatureSetsCannotDispatch() async throws {
        let context = try context(), transport = BusinessRuntimeRecorder()
        XCTAssertNil(BusinessRuntimeFactory(configuration: nil, api: try .init(baseURL: base), transport: transport, current: { context }))
        let factory = try XCTUnwrap(BusinessRuntimeFactory(configuration: config(), api: .init(baseURL: base), transport: transport, current: { context }))
        XCTAssertFalse(factory.permits(.bankPrepare)); XCTAssertNil(factory.approval([.projectWrite]))
        do { _ = try await factory.client([.imRead]).send(request("api/im/read")); XCTFail() } catch {}
        XCTAssertTrue(transport.requests.isEmpty)
    }
    func testFeatureLabelsCannotAuthorizeAnotherFeatureOrMethod() throws {
        XCTAssertThrowsError(try config([.imRead: [.post("api/im/send")]]))
        XCTAssertThrowsError(try config([.stampUpload: [.post("api/withdrawal/create")]]))
        XCTAssertThrowsError(try config([.projectRead: [.post("api/topic/create")]]))
        XCTAssertThrowsError(try config([.directVerification: [.post("api/merchant/update")]]))
        XCTAssertThrowsError(try config([.imRead: [.init(method: "GET", path: "api/im/read")]]))
        XCTAssertThrowsError(try BusinessRuntimeRoute.post("api/registration/*"))
    }
    func testReadOnlyIMClientUsesRealContractWithoutGrantingSendOrMute() async throws {
        let context = try context(), transport = BusinessRuntimeRecorder()
        let accepted = try config([.imRead: [.post("api/im/read")]])
        let factory = try XCTUnwrap(BusinessRuntimeFactory(configuration: accepted, api: .init(baseURL: base), transport: transport, current: { context }))
        let service = IMExpandedService(configuration: try .init(baseURL: base), transport: factory.client([.imRead]), approvedMediaOrigins: [], writesEnabled: true, enabledPaths: ["api/im/read"])
        _ = try await service.perform(.read(conversationID: 9), token: "synthetic")
        do { _ = try await service.perform(.mute(conversationID: 9, muted: true), token: "synthetic"); XCTFail() } catch {}
        XCTAssertEqual(transport.requests.count, 1); XCTAssertEqual(transport.requests[0].url?.path, "/business/api/im/read")
        XCTAssertTrue(String(decoding: transport.requests[0].httpBody!, as: UTF8.self).contains("conversation_id"))
    }
    func testMethodPathTokenAndBasePathAreCheckedImmediatelyBeforeSend() async throws {
        let context = try context(), transport = BusinessRuntimeRecorder()
        let factory = try XCTUnwrap(BusinessRuntimeFactory(configuration: config([.imRead: [.post("api/im/read")]]), api: .init(baseURL: base), transport: transport, current: { context }))
        let client = factory.client([.imRead])
        for input in [request("api/im/read", method: "GET"), request("api/im/read", token: "wrong"), request("api/im/send")] {
            do { _ = try await client.send(input); XCTFail() } catch {}
        }
        var wrongBase = request("api/im/read"); wrongBase.url = URL(string: "https://example.com/other/api/im/read")!
        XCTAssertFalse(client.permits(wrongBase)); XCTAssertTrue(transport.requests.isEmpty)
    }
    func testWrongMarketAccountNamespaceAndOriginCannotMount() throws {
        let accepted = try config(), transport = BusinessRuntimeRecorder()
        for context in [try context(account: 8), try context(namespace: "other"), try context(market: .unitedStates)] {
            XCTAssertNil(BusinessRuntimeFactory(configuration: accepted, api: try .init(baseURL: base), transport: transport, current: { context }))
        }
        let context = try context()
        XCTAssertNil(BusinessRuntimeFactory(configuration: accepted, api: try .init(baseURL: URL(string: "https://example.org")!), transport: transport, current: { context }))
    }
    func testRoleEpochTokenAndLogoutInvalidateCapturedClient() async throws {
        let initial = try context(), transport = BusinessRuntimeRecorder()
        for replacement in [try context(epoch: 2), try context(role: "member"), try context(token: "new"), nil] {
            var current: RuntimeDependencyContext? = initial
            let factory = try XCTUnwrap(BusinessRuntimeFactory(configuration: config([.imRead: [.post("api/im/read")]]), api: .init(baseURL: base), transport: transport, current: { current }))
            current = replacement
            do { _ = try await factory.client([.imRead]).send(request("api/im/read")); XCTFail() } catch {}
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }
    func testLateResponseAfterLogoutDoesNotReachCaller() async throws {
        var current: RuntimeDependencyContext? = try context(); let transport = BusinessRuntimeRecorder()
        transport.reply = { _ in current = nil; return Data(#"{"code":200,"data":{}}"#.utf8) }
        let factory = try XCTUnwrap(BusinessRuntimeFactory(configuration: config([.imRead: [.post("api/im/read")]]), api: .init(baseURL: base), transport: transport, current: { current }))
        do { _ = try await factory.client([.imRead]).send(request("api/im/read")); XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(transport.requests.count, 1)
    }
    func testPublishingAndProfessionalReadAdaptersAreActuallyExecutable() async throws {
        let context = try context(), transport = BusinessRuntimeRecorder()
        transport.reply = { _ in Data(#"{"code":200,"data":{"permission":{"canProPublish":true},"quota":{"themesRemaining":3}}}"#.utf8) }
        let accepted = try config([.publishingRead: [.post("api/publish/home")], .projectRead: [.post("api/publish/home")]])
        let factory = try XCTUnwrap(BusinessRuntimeFactory(configuration: accepted, api: .init(baseURL: base), transport: transport, current: { context }))
        let projectSession = try ProjectEditSession(accountID: 7, epoch: 1, storageNamespace: "fixture")
        let project = ProjectEditHTTPService(configuration: try .init(baseURL: base), transport: factory.client([.projectRead]), owner: .personal, currentCredentials: { try? .init(session: projectSession, token: "synthetic") })
        let preflight = try await project.preflight(topicID: nil, session: projectSession)
        XCTAssertTrue(preflight.capability.allowsCreate); XCTAssertEqual(project.authority, .readOnly)
        let publishingSession = PublishingSession(namespace: "fixture", accountID: 7, epoch: UUID(), role: "merchant", region: .china)
        let publishing = PublishingService(configuration: try .init(baseURL: base), transport: factory.client([.publishingRead]), credentials: { try? .init(session: publishingSession, token: "synthetic") })
        _ = try await publishing.read(.capability, session: publishingSession)
        XCTAssertFalse(publishing.mutationsConfigured); XCTAssertEqual(transport.requests.count, 2)
    }
    func testVerificationTransportIsProductionButNeverSyntheticOrGeneralMutation() async throws {
        let context = try context(), transport = BusinessRuntimeRecorder()
        let accepted = try config([.directVerification: [.post("api/coupon/verification")]])
        let factory = try XCTUnwrap(BusinessRuntimeFactory(configuration: accepted, api: .init(baseURL: base), transport: transport, current: { context }))
        let client = MerchantVerificationHTTPTransport(baseURL: base, transport: factory.client([.directVerification]))
        let service = MerchantBusinessService(configuration: try .init(baseURL: base), readTransport: transport, verificationTransport: client)
        XCTAssertFalse(service.canExecuteSyntheticMutation); XCTAssertTrue(service.canExecuteVerificationMutation)
        _ = try await service.verificationEnvelope(.form("api/coupon/verification", ["code": "synthetic"]), token: "synthetic")
        for path in ["api/registration/scan_dynamic_code", "api/merchant/update"] {
            do { _ = try await client.send(request(path)); XCTFail() } catch { XCTAssertEqual(error as? MerchantBusinessFailure, .disabled) }
        }
        XCTAssertEqual(transport.requests.count, 1)
    }
    func testAdditionalRouteCallbackCannotEscalateToAnotherFeature() async throws {
        let context = try context(), transport = BusinessRuntimeRecorder()
        let factory = try XCTUnwrap(BusinessRuntimeFactory(configuration: config(), api: .init(baseURL: base), transport: transport, current: { context }))
        let injected: Set<BusinessRuntimeRoute> = try [.post("api/im/send"), .post("api/fund/preflight/51/confirm")]
        let selections: [Set<BusinessRuntimeFeature>] = [[.imRead], [.bankPrepare, .bankCreate]]
        for features in selections {
            let client = factory.client(features, additionalRoutes: { injected })
            do { _ = try await client.send(request("api/im/send")); XCTFail() } catch {}
            do { _ = try await client.send(request("api/fund/preflight/51/confirm")); XCTFail() } catch {}
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }
    func testStampCreationRetainsExactOriginAndCreatePathGates() async throws {
        let context = try context(), transport = BusinessRuntimeRecorder()
        let accepted = try config([.stampCreate: [.post("api/roam/stamp/create")]])
        let factory = try XCTUnwrap(BusinessRuntimeFactory(configuration: accepted, api: .init(baseURL: base), transport: transport, current: { context }))
        let scope = try RetainedImageScope(accountID: 7, epoch: UUID(), realm: base.absoluteString, destination: .stamp, namespace: "fixture")
        let client = RoamMediaMutationService(configuration: try .init(baseURL: base), transport: factory.client([.stampCreate]), enabled: true,
            approval: factory.approval([.stampCreate]), approvedImageOrigins: ["https://images.example.com"], currentScope: { scope }, token: { "synthetic" })
        do { _ = try await client.execute(.createStamp(pictureURL: "https://other.example.com/a.jpg", caption: "", idempotencyKey: UUID().uuidString)); XCTFail() } catch {}
        XCTAssertTrue(transport.requests.isEmpty)
        _ = try await client.execute(.createStamp(pictureURL: "https://images.example.com/a.jpg", caption: "", idempotencyKey: UUID().uuidString))
        XCTAssertEqual(transport.requests.count, 1); XCTAssertEqual(transport.requests[0].url?.path, "/business/api/roam/stamp/create")
    }
}
@MainActor private final class BusinessRuntimeRecorder: HTTPTransport {
    var requests: [URLRequest] = []
    var reply: (URLRequest) throws -> Data = { _ in Data(#"{"code":200,"data":{}}"#.utf8) }
    func send(_ request: URLRequest) async throws -> (Data, Int) { requests.append(request); return (try reply(request), 200) }
}
