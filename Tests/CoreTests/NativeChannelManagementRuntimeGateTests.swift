import Foundation
import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

/// Local synthetic transports only. These fixtures issue no production authority.
@MainActor final class NativeChannelManagementRuntimeGateTests: XCTestCase {
    private let requestID = "00000000-0000-4000-8000-000000000001"
    private var catalog: [(BusinessRuntimeFeature, String, String)] { [
        (.imChannelPersonalStateRead, "GET", "api/channels/9"),
        (.imChannelPersonalStateWrite, "POST", "api/channels/9/member-state"),
        (.imChannelPersonalStateReceipt, "GET", "api/channels/member-state-requests/" + requestID),
        (.imChannelRoleRead, "GET", "api/im/roles"),
        (.imChannelRoleWrite, "POST", "api/im/roles"),
        (.imChannelRoleReceipt, "GET", "api/channel-platform/governance/requests/" + requestID),
        (.imChannelRoleMemberRead, "GET", "api/channels/9/members"),
        (.imChannelModerationRead, "GET", "api/im/moderation/actions"),
        (.imChannelModerationWrite, "POST", "api/im/moderation/timeout"),
        (.imChannelModerationReceipt, "GET", "api/channel-platform/governance/moderation/requests/" + requestID),
        (.imChannelAuditRead, "GET", "api/im/audit-log"),
        (.imChannelLifecycleAuditRead, "GET", "api/channels/9/op-log")
    ] }
    private let mutations: [(String, String)] = [
        ("PATCH", "api/im/roles/17"), ("DELETE", "api/im/roles/17"),
        ("PUT", "api/im/members/23/roles"), ("PUT", "api/im/roles/17/members")
    ]

    func testDefaultEmptyConfigurationDoesNotGrantAnyManagementRoute() async throws {
        let h = try ManagementRuntimeGateHarness(routes: [:])
        let gate = try h.gate(features: Set(catalog.map { $0.0 }))
        XCTAssertTrue(h.issued.routes.isEmpty)
        for (feature, method, path) in catalog {
            XCTAssertNil(h.issued.routes[feature])
            await assertDenied(gate, h.request(method, path))
        }
        for (method, path) in mutations { await assertDenied(gate, h.request(method, path)) }
        await assertDenied(gate, h.request("POST", "api/im/send"))
        XCTAssertTrue(h.wire.requests.isEmpty)
    }

    func testEveryRestoredFeatureRetainsItsOwnExactCatalog() throws {
        for (feature, method, path) in catalog {
            let route = try BusinessRuntimeRoute(method: method, path: path)
            XCTAssertTrue(feature.accepts(route))
            _ = try ManagementRuntimeGateHarness(routes: [feature: [route]])
            let wrongMethod = try BusinessRuntimeRoute(method: method == "GET" ? "POST" : "GET", path: path)
            XCTAssertFalse(feature.accepts(wrongMethod))
            XCTAssertThrowsError(try ManagementRuntimeGateHarness(routes: [feature: [wrongMethod]]))
            for (otherFeature, otherMethod, otherPath) in catalog where otherFeature != feature {
                let other = try BusinessRuntimeRoute(method: otherMethod, path: otherPath)
                XCTAssertFalse(feature.accepts(other))
                XCTAssertThrowsError(try ManagementRuntimeGateHarness(routes: [feature: [other]]))
            }
            XCTAssertFalse(feature.accepts(try .post("api/im/send")))
            XCTAssertFalse(feature.accepts(try .init(method: method, path: path + "/extra")))
        }
    }

    func testRestoredNumericTargetsRejectNoncanonicalAndConfusedPaths() throws {
        let cases: [(BusinessRuntimeFeature, String, String, String)] = [
            (.imChannelPersonalStateRead, "GET", "api/channels/", ""),
            (.imChannelPersonalStateWrite, "POST", "api/channels/", "/member-state"),
            (.imChannelRoleMemberRead, "GET", "api/channels/", "/members"),
            (.imChannelModerationWrite, "POST", "api/im/moderation/", "/revoke"),
            (.imChannelLifecycleAuditRead, "GET", "api/channels/", "/op-log")
        ]
        for (feature, method, prefix, suffix) in cases {
            XCTAssertTrue(feature.accepts(try .init(method: method, path: prefix + "9" + suffix)))
            for target in ["", "0", "-1", "+9", "09", "9.0", " 9", "9 ", "9/extra", "９", "9223372036854775808"] {
                let route = try BusinessRuntimeRoute(method: method, path: prefix + target + suffix)
                XCTAssertFalse(feature.accepts(route), route.path)
            }
        }
        for action in ["timeout", "kick", "ban"] {
            XCTAssertTrue(BusinessRuntimeFeature.imChannelModerationWrite.accepts(try .post("api/im/moderation/" + action)))
        }
        for (feature, method, path) in catalog {
            XCTAssertFalse(feature.accepts(try .init(method: method, path: path.replacingOccurrences(of: "api/", with: "api//"))))
        }
    }

    func testReceiptsRequireOriginalNamespaceAndWholeUUID() throws {
        let receipts: [(BusinessRuntimeFeature, String)] = [
            (.imChannelPersonalStateReceipt, "api/channels/member-state-requests/"),
            (.imChannelRoleReceipt, "api/channel-platform/governance/requests/"),
            (.imChannelModerationReceipt, "api/channel-platform/governance/moderation/requests/")
        ]
        for (feature, prefix) in receipts {
            for suffix in ["", "9", "not-a-uuid", requestID + "/extra", "/" + requestID] {
                XCTAssertFalse(feature.accepts(try .init(method: "GET", path: prefix + suffix)))
            }
            for (other, otherPrefix) in receipts where other != feature {
                XCTAssertFalse(feature.accepts(try .init(method: "GET", path: otherPrefix + requestID)))
            }
        }
    }

    func testGenericConstructorStillRejectsAllNonGETPOSTMethods() throws {
        for (method, path) in mutations {
            XCTAssertThrowsError(try BusinessRuntimeRoute(method: method, path: path))
            XCTAssertNoThrow(try BusinessRuntimeRoute.channelRoleMutation(method: method, path: path))
        }
        for method in ["PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"] {
            XCTAssertThrowsError(try BusinessRuntimeRoute(method: method, path: "api/im/send"))
        }
        XCTAssertNoThrow(try BusinessRuntimeRoute.post("api/im/send"))
    }

    func testNamedRoleFactoryAcceptsOnlyFourCanonicalOriginalMethodPathShapes() throws {
        for (method, path) in mutations {
            let route = try BusinessRuntimeRoute.channelRoleMutation(method: method, path: path)
            XCTAssertEqual(route.method, method)
            XCTAssertEqual(route.path, path)
            XCTAssertTrue(BusinessRuntimeFeature.imChannelRoleWrite.accepts(route))
            for other in ["GET", "POST", "HEAD", "OPTIONS", method.lowercased(), " " + method] {
                XCTAssertThrowsError(try BusinessRuntimeRoute.channelRoleMutation(method: other, path: path))
            }
        }
        for (method, path) in [("PUT", "api/im/roles/17"), ("PATCH", "api/im/roles/17/members"),
                               ("DELETE", "api/im/members/23/roles"), ("PATCH", "api/im/members/23")] {
            XCTAssertThrowsError(try BusinessRuntimeRoute.channelRoleMutation(method: method, path: path))
        }
        for method in ["PATCH", "DELETE", "PUT"] {
            for path in ["api/im/send", "api/im/roles", "api/im/roles/17/extra", "api/im/roles/17/roles",
                         "api/im/members/23/members", "api/other/roles/17", "/api/im/roles/17",
                         "api//im/roles/17", "api/im/roles//17", "api/im/roles/17/",
                         "api/im/roles/../17", "api/im/roles/17?admin=1", "api/im/roles/17#fragment",
                         "api/im/roles/%31%37", "api/im/roles/*", "api/im/roles/17%2Fmembers"] {
                XCTAssertThrowsError(try BusinessRuntimeRoute.channelRoleMutation(method: method, path: path), path)
            }
        }
        for id in ["", "0", "-1", "+17", "017", "17.0", " 17", "17 ", "１７", "9223372036854775808"] {
            for (method, path) in [("PATCH", "api/im/roles/" + id), ("DELETE", "api/im/roles/" + id),
                                   ("PUT", "api/im/members/" + id + "/roles"), ("PUT", "api/im/roles/" + id + "/members")] {
                XCTAssertThrowsError(try BusinessRuntimeRoute.channelRoleMutation(method: method, path: path))
            }
        }
    }

    func testConstructedRoleMutationStillRequiresIndependentRoleWriteIssuance() throws {
        let forbidden = catalog.map { $0.0 }.filter { $0 != .imChannelRoleWrite } +
            [.imSend, .imRead, .imChannelMentionRoleRead, .imChannelMentionMemberRead, .imChannelAppealWrite]
        for (method, path) in mutations {
            let route = try BusinessRuntimeRoute.channelRoleMutation(method: method, path: path)
            _ = try ManagementRuntimeGateHarness(routes: [.imChannelRoleWrite: [route]])
            for feature in forbidden {
                XCTAssertFalse(feature.accepts(route))
                XCTAssertThrowsError(try ManagementRuntimeGateHarness(routes: [feature: [route]]))
            }
        }
    }

    func testEveryManagementFeatureDispatchesOnlyItsOwnIssuedRoute() async throws {
        var routes: [BusinessRuntimeFeature: Set<BusinessRuntimeRoute>] = [:]
        for (feature, method, path) in catalog { routes[feature] = [try .init(method: method, path: path)] }
        for (feature, method, path) in catalog {
            let h = try ManagementRuntimeGateHarness(routes: routes)
            let gate = try h.gate(features: [feature])
            _ = try await gate.send(h.request(method, path))
            for (other, otherMethod, otherPath) in catalog where other != feature {
                await assertDenied(gate, h.request(otherMethod, otherPath))
            }
            XCTAssertEqual(h.wire.requests.count, 1)
            XCTAssertEqual(h.wire.requests.first?.url, h.request(method, path).url)
        }
    }

    func testFourOriginalRoleMutationsPreserveTargetMethodBodyAndToken() async throws {
        for (method, path) in mutations {
            let route = try BusinessRuntimeRoute.channelRoleMutation(method: method, path: path)
            let h = try ManagementRuntimeGateHarness(routes: [.imChannelRoleWrite: [route]])
            let gate = try h.gate(features: [.imChannelRoleWrite])
            var request = h.request(method, path)
            // Opaque original request bytes are forwarded unchanged, never rebuilt by this gate.
            request.httpBody = Data(#"{"request_id":"00000000-0000-4000-8000-000000000001"}"#.utf8)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            _ = try await gate.send(request)
            let forwarded = try XCTUnwrap(h.wire.requests.first)
            XCTAssertEqual(forwarded.url, request.url)
            XCTAssertEqual(forwarded.httpMethod, method)
            XCTAssertEqual(forwarded.httpBody, request.httpBody)
            XCTAssertEqual(forwarded.value(forHTTPHeaderField: "Authorization"), h.context.session.token)
            XCTAssertEqual(forwarded.value(forHTTPHeaderField: "Content-Type"), "application/json")
            for otherMethod in ["GET", "POST", "PATCH", "DELETE", "PUT"] where otherMethod != method {
                await assertDenied(gate, h.request(otherMethod, path))
            }
            for (otherMethod, otherPath) in mutations where otherMethod != method || otherPath != path {
                await assertDenied(gate, h.request(otherMethod, otherPath))
            }
            await assertDenied(gate, h.request(method, path.replacingOccurrences(of: "17", with: "18").replacingOccurrences(of: "23", with: "24")))
            XCTAssertEqual(h.wire.requests.count, 1)
        }
    }

    func testGETAndSENDCannotLendAuthorityToManagementOrRoleMutations() async throws {
        let h = try ManagementRuntimeGateHarness(routes: [
            .imSend: [.post("api/im/send")],
            .imChannelRoleRead: [.init(method: "GET", path: "api/im/roles")],
            .imChannelMentionRoleRead: [.init(method: "GET", path: "api/im/roles")],
            .imChannelMentionMemberRead: [.init(method: "GET", path: "api/channels/9/members")]
        ])
        let unissued = Set(catalog.map { $0.0 }).subtracting([.imChannelRoleRead])
        let gate = try h.gate(features: unissued)
        for (method, path) in mutations { await assertDenied(gate, h.request(method, path)) }
        await assertDenied(gate, h.request("POST", "api/im/roles"))
        await assertDenied(gate, h.request("GET", "api/im/roles"))
        await assertDenied(gate, h.request("GET", "api/channels/9/members"))
        await assertDenied(gate, h.request("POST", "api/im/send"))
        let readGate = try h.gate(features: [.imChannelRoleRead])
        for (method, path) in mutations { await assertDenied(readGate, h.request(method, path)) }
        XCTAssertTrue(h.wire.requests.isEmpty)
    }

    func testMentionCatalogOverlapDoesNotIssueRoleReaders() async throws {
        for (issuedFeature, consumer, path) in [
            (BusinessRuntimeFeature.imChannelMentionRoleRead, BusinessRuntimeFeature.imChannelRoleRead, "api/im/roles"),
            (.imChannelMentionMemberRead, .imChannelRoleMemberRead, "api/channels/9/members"),
            (.imChannelRoleRead, .imChannelMentionRoleRead, "api/im/roles"),
            (.imChannelRoleMemberRead, .imChannelMentionMemberRead, "api/channels/9/members")
        ] {
            let h = try ManagementRuntimeGateHarness(routes: [issuedFeature: [.init(method: "GET", path: path)]])
            await assertDenied(try h.gate(features: [consumer]), h.request("GET", path))
            XCTAssertTrue(h.wire.requests.isEmpty)
        }
    }

    func testObservedWithdrawalAndIdenticalRegrantCannotReviveAnyManagementGate() async throws {
        for (feature, method, path) in catalog {
            let h = try ManagementRuntimeGateHarness(routes: [feature: [.init(method: method, path: path)]])
            let gate = try h.gate(features: [feature])
            h.live = try h.configuration(routes: [:])
            XCTAssertFalse(gate.isCurrent)
            h.live = h.issued
            XCTAssertFalse(gate.isCurrent)
            await assertDenied(gate, h.request(method, path))
            XCTAssertTrue(h.wire.requests.isEmpty)
            _ = try await h.gate(features: [feature]).send(h.request(method, path))
            XCTAssertEqual(h.wire.requests.count, 1)
        }
        for (method, path) in mutations {
            let h = try ManagementRuntimeGateHarness(routes: [.imChannelRoleWrite: [.channelRoleMutation(method: method, path: path)]])
            let gate = try h.gate(features: [.imChannelRoleWrite])
            h.live = nil
            await assertDenied(gate, h.request(method, path))
            h.live = h.issued
            await assertDenied(gate, h.request(method, path))
            XCTAssertFalse(gate.isCurrent)
            XCTAssertTrue(h.wire.requests.isEmpty)
        }
    }

    func testFourRoleMutationLateResponsesRetireBeforeIdenticalRegrant() async throws {
        for (method, path) in mutations {
            let h = try ManagementRuntimeGateHarness(routes: [.imChannelRoleWrite: [.channelRoleMutation(method: method, path: path)]])
            let gate = try h.gate(features: [.imChannelRoleWrite])
            h.wire.beforeReturn = { h.live = nil }
            do {
                _ = try await gate.send(h.request(method, path))
                XCTFail("Withdrawn role mutation result must not reach the consumer")
            } catch { XCTAssertTrue(error is CancellationError) }
            h.live = h.issued; h.wire.beforeReturn = nil
            XCTAssertFalse(gate.isCurrent)
            await assertDenied(gate, h.request(method, path))
            await assertDenied(try h.gate(features: [.imSend]), h.request(method, path))
            await assertDenied(try h.gate(features: [.imChannelRoleRead]), h.request(method, path))
            XCTAssertEqual(h.wire.requests.count, 1)
        }
    }

    func testLiveReplacementOfExactRoleWriteRouteRetiresPreviousGate() async throws {
        let original = try BusinessRuntimeRoute.channelRoleMutation(method: "PATCH", path: "api/im/roles/17")
        let replacement = try BusinessRuntimeRoute.channelRoleMutation(method: "PATCH", path: "api/im/roles/18")
        let h = try ManagementRuntimeGateHarness(routes: [.imChannelRoleWrite: [original]])
        let gate = try h.gate(features: [.imChannelRoleWrite])
        h.live = try h.configuration(routes: [.imChannelRoleWrite: [replacement]])
        await assertDenied(gate, h.request(original.method, original.path))
        h.live = h.issued
        await assertDenied(gate, h.request(original.method, original.path))
        XCTAssertTrue(h.wire.requests.isEmpty)
    }

    func testViewerAndRuntimeEpochRetirementRemainMonotonicForManagement() async throws {
        for (feature, method, path) in catalog {
            for retireViewer in [true, false] {
                let h = try ManagementRuntimeGateHarness(routes: [feature: [.init(method: method, path: path)]])
                let gate = try h.gate(features: [feature])
                if retireViewer { h.active = false }
                else { h.liveContext = try h.contextWith(epoch: 2) }
                await assertDenied(gate, h.request(method, path))
                h.active = true; h.liveContext = h.context
                XCTAssertFalse(gate.isCurrent)
                await assertDenied(gate, h.request(method, path))
                XCTAssertTrue(h.wire.requests.isEmpty)
            }
        }
    }

    func testPostDispatchConfigurationViewerAndEpochChecksDropLateResults() async throws {
        for (feature, method, path) in catalog {
            for reason in ["configuration", "viewer", "epoch"] {
                let h = try ManagementRuntimeGateHarness(routes: [feature: [.init(method: method, path: path)]])
                let gate = try h.gate(features: [feature])
                let replacement = try h.contextWith(epoch: 2)
                h.wire.status = 401
                h.wire.beforeReturn = {
                    if reason == "configuration" { h.live = nil }
                    else if reason == "viewer" { h.active = false }
                    else { h.liveContext = replacement }
                }
                do {
                    _ = try await gate.send(h.request(method, path))
                    XCTFail("Stale response must not reach a management consumer or logout handler")
                } catch { XCTAssertTrue(error is CancellationError) }
                h.live = h.issued; h.active = true; h.liveContext = h.context
                XCTAssertFalse(gate.isCurrent)
                await assertDenied(gate, h.request(method, path))
                XCTAssertEqual(h.wire.requests.count, 1)
            }
        }
    }

    func testRoleWritesRejectWrongCredentialCookiesOriginAndPathConfusion() async throws {
        for (method, path) in mutations {
            let h = try ManagementRuntimeGateHarness(routes: [.imChannelRoleWrite: [.channelRoleMutation(method: method, path: path)]])
            let gate = try h.gate(features: [.imChannelRoleWrite])
            var wrongToken = h.request(method, path); wrongToken.setValue("other-token", forHTTPHeaderField: "Authorization")
            var noToken = h.request(method, path); noToken.setValue(nil, forHTTPHeaderField: "Authorization")
            var cookie = h.request(method, path); cookie.setValue("session=other", forHTTPHeaderField: "Cookie")
            var handlesCookies = h.request(method, path); handlesCookies.httpShouldHandleCookies = true
            for request in [wrongToken, noToken, cookie, handlesCookies] { await assertDenied(gate, request) }
            for url in ["https://other.example.test/prod-api/" + path,
                        "https://api.example.test/other/" + path,
                        "https://api.example.test/prod-api/" + path + "/extra",
                        "https://api.example.test/prod-api/" + path + "#fragment",
                        "https://user@api.example.test/prod-api/" + path,
                        "https://api.example.test/prod-api/" + path.replacingOccurrences(of: "api/im/", with: "api//im/")] {
                var request = h.request(method, path); request.url = try XCTUnwrap(URL(string: url))
                await assertDenied(gate, request)
            }
            XCTAssertTrue(h.wire.requests.isEmpty)
        }
    }

    func testHostSupportedSetStillRejectsUnrelatedBusinessFeatures() throws {
        let h = try ManagementRuntimeGateHarness(routes: [.bankCreate: [.post("api/withdrawal/create")]])
        XCTAssertNil(NativeChannelHostRuntimeTransport(context: h.context, issued: h.issued,
            features: [.bankCreate], underlying: h.wire, runtime: { h.liveContext },
            configuration: { h.live }, presentation: { h.active }))
    }

    func testExistingPOSTFeaturesRemainAvailableOnlyUnderTheirOwnGrant() async throws {
        for (feature, path) in [(BusinessRuntimeFeature.imSend, "api/im/send"), (.imRead, "api/im/read"),
                               (.imMute, "api/im/mute"), (.imPollCreate, "api/im/poll/create")] {
            let h = try ManagementRuntimeGateHarness(routes: [feature: [.post(path)]])
            let gate = try h.gate(features: [feature])
            _ = try await gate.send(h.request("POST", path))
            await assertDenied(gate, h.request("GET", path))
            XCTAssertEqual(h.wire.requests.count, 1)
        }
    }

    private func assertDenied(_ gate: NativeChannelHostRuntimeTransport, _ request: URLRequest,
                              file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await gate.send(request)
            XCTFail("Unissued or retired management request reached the wire", file: file, line: line)
        } catch { XCTAssertEqual(error as? APIError, .notConfigured, file: file, line: line) }
    }
}

@MainActor private final class ManagementRuntimeGateHarness {
    let context: RuntimeDependencyContext
    var liveContext: RuntimeDependencyContext?
    let issued: BusinessRuntimeConfiguration
    var live: BusinessRuntimeConfiguration?
    var active = true
    let wire = ManagementRuntimeGateWire()

    init(routes: [BusinessRuntimeFeature: Set<BusinessRuntimeRoute>]) throws {
        let base = URL(string: "https://api.example.test/prod-api/")!
        context = .init(market: .china, baseURL: base, role: "member",
            session: try .init(accountID: 7, epoch: 1, namespace: "CN:management-gate-test", token: "fixture-token"))
        issued = try .init(market: .china, baseURL: base, namespace: "CN:management-gate-test", accountID: 7, routes: routes)
        live = issued; liveContext = context
    }
    func contextWith(epoch: UInt64) throws -> RuntimeDependencyContext {
        .init(market: context.market, baseURL: context.baseURL, role: context.role,
              session: try .init(accountID: context.session.accountID, epoch: epoch,
                                 namespace: context.session.namespace, token: context.session.token))
    }
    func configuration(routes: [BusinessRuntimeFeature: Set<BusinessRuntimeRoute>]) throws -> BusinessRuntimeConfiguration {
        try .init(market: context.market, baseURL: context.baseURL, namespace: context.session.namespace,
                  accountID: context.session.accountID, routes: routes)
    }
    func gate(features: Set<BusinessRuntimeFeature>) throws -> NativeChannelHostRuntimeTransport {
        try XCTUnwrap(NativeChannelHostRuntimeTransport(context: context, issued: issued, features: features,
            underlying: wire, runtime: { self.liveContext }, configuration: { self.live }, presentation: { self.active }))
    }
    func request(_ method: String, _ path: String) -> URLRequest {
        var request = URLRequest(url: context.baseURL.appendingPathComponent(path))
        request.httpMethod = method; request.httpShouldHandleCookies = false
        request.setValue(context.session.token, forHTTPHeaderField: "Authorization")
        return request
    }
}

@MainActor private final class ManagementRuntimeGateWire: HTTPTransport {
    var requests: [URLRequest] = []
    var beforeReturn: (() -> Void)?
    var status = 200
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); beforeReturn?()
        return (Data(), status)
    }
}
