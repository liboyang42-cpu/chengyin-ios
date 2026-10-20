import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class MemoryConsentStorage: UsageConsentStorage {
    var values: [String: Data] = [:]
    func data(forKey key: String) -> Data? { values[key] }
    func set(_ value: Data?, forKey key: String) { values[key] = value }
}

private final class FlagsTransport: HTTPTransport {
    var requests: [URLRequest] = []
    var body = #"{"code":200,"data":{}}"#
    var status = 200
    var onSend: (() -> Void)?
    var fails = false
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); onSend?()
        if fails { throw URLError(.timedOut) }
        return (Data(body.utf8), status)
    }
}

final class UsageConsentPolicyTests: XCTestCase {
    func testGateIsPendingUntilCheckedAgreementStoresCurrentVersions() throws {
        let storage = MemoryConsentStorage(); let policy = UsageConsentPolicy(storage: storage)
        XCTAssertFalse(policy.granted)
        XCTAssertThrowsError(try policy.agree(agreementChecked: false)) { XCTAssertEqual($0 as? UsageConsentFailure, .agreementNotChecked) }
        XCTAssertFalse(policy.granted)
        try policy.agree(agreementChecked: true)
        XCTAssertTrue(policy.granted)
        let stored = try JSONDecoder().decode([String: String].self, from: XCTUnwrap(storage.values[UsageConsentPolicy.choiceKey]))
        XCTAssertEqual(stored, ["privacy_policy": "v2.1", "user_service_agreement": "v2.2"])
    }

    func testVersionBumpOrDeclineMakesTheGateShowAgain() throws {
        let storage = MemoryConsentStorage(); let policy = UsageConsentPolicy(storage: storage)
        storage.values[UsageConsentPolicy.choiceKey] = try JSONEncoder().encode(["privacy_policy": "v2.0", "user_service_agreement": "v2.2"])
        XCTAssertFalse(policy.granted)
        try policy.agree(agreementChecked: true); policy.decline()
        XCTAssertFalse(policy.granted); XCTAssertNil(storage.values[UsageConsentPolicy.choiceKey])
    }

    func testLaunchGateNeverInterruptsRestoredSessionOrRepeatsAfterDecline() {
        XCTAssertTrue(UsageConsentGateDecision.showAtLaunch(granted: false, signedIn: false, declinedThisLaunch: false))
        XCTAssertFalse(UsageConsentGateDecision.showAtLaunch(granted: false, signedIn: true, declinedThisLaunch: false))
        XCTAssertFalse(UsageConsentGateDecision.showAtLaunch(granted: false, signedIn: false, declinedThisLaunch: true))
        XCTAssertFalse(UsageConsentGateDecision.showAtLaunch(granted: true, signedIn: false, declinedThisLaunch: false))
        XCTAssertTrue(UsageConsentGateDecision.signInRequiresGate(granted: false))
        XCTAssertFalse(UsageConsentGateDecision.signInRequiresGate(granted: true))
    }

    func testPendingRecordsKeepStableRequestIDsAcrossRelaunchUntilExactEcho() throws {
        let storage = MemoryConsentStorage(); var counter = 0
        let make = { () -> String in counter += 1; return "consent-fixture-\(counter)" }
        XCTAssertTrue(UsageConsentPolicy(storage: storage, makeRequestID: make).pendingRecords(accountID: 7).isEmpty)
        try UsageConsentPolicy(storage: storage, makeRequestID: make).agree(agreementChecked: true)
        let first = UsageConsentPolicy(storage: storage, makeRequestID: make).pendingRecords(accountID: 7)
        XCTAssertEqual(first.map(\.requestID), ["consent-fixture-1", "consent-fixture-2"])
        XCTAssertEqual(first.map(\.document), [.privacyPolicy, .userServiceAgreement])
        XCTAssertTrue(first.allSatisfy { $0.scene == "app_launch" && $0.eventType == "AGREE" })
        let relaunched = UsageConsentPolicy(storage: storage, makeRequestID: make)
        XCTAssertEqual(relaunched.pendingRecords(accountID: 7), first)
        XCTAssertFalse(relaunched.confirm(first[0], echoedRequestID: "other", echoedDocType: "privacy_policy", echoedScene: "app_launch", echoedVersion: "v2.1"))
        XCTAssertFalse(relaunched.confirm(first[0], echoedRequestID: first[0].requestID, echoedDocType: "privacy_policy", echoedScene: "app_launch", echoedVersion: "v2.0"))
        XCTAssertTrue(relaunched.confirm(first[0], echoedRequestID: first[0].requestID, echoedDocType: "privacy_policy", echoedScene: "app_launch", echoedVersion: "v2.1"))
        XCTAssertEqual(relaunched.pendingRecords(accountID: 7).map(\.document), [.userServiceAgreement])
        XCTAssertEqual(relaunched.pendingRecords(accountID: 8).map(\.requestID), ["consent-fixture-3", "consent-fixture-4"])
        XCTAssertTrue(relaunched.pendingRecords(accountID: 0).isEmpty)
    }

    func testLiveConsentRecordingStaysUnapproved() {
        XCTAssertFalse(UsageConsentPolicy.liveRecordingApproved)
    }
}

final class SessionExpiryNoticeTests: XCTestCase {
    func testOnlyExpiryTransitionFromSignedInPresents() {
        XCTAssertTrue(SessionExpiryNotice.shouldPresent(previousAccountID: 7, currentAccountID: nil, errorKey: "auth.expired"))
        XCTAssertFalse(SessionExpiryNotice.shouldPresent(previousAccountID: 7, currentAccountID: nil, errorKey: nil))
        XCTAssertFalse(SessionExpiryNotice.shouldPresent(previousAccountID: nil, currentAccountID: nil, errorKey: "auth.expired"))
        XCTAssertFalse(SessionExpiryNotice.shouldPresent(previousAccountID: 7, currentAccountID: 8, errorKey: "auth.expired"))
        XCTAssertFalse(SessionExpiryNotice.shouldPresent(previousAccountID: 7, currentAccountID: nil, errorKey: "auth.networkError"))
    }

    func testMiniProgramExpiryCodesAndMessages() {
        XCTAssertTrue(SessionExpiryNotice.isExpiryCode(httpStatus: 401, bodyCode: nil))
        XCTAssertTrue(SessionExpiryNotice.isExpiryCode(httpStatus: 200, bodyCode: 401))
        XCTAssertTrue(SessionExpiryNotice.isExpiryCode(httpStatus: 200, bodyCode: 2))
        XCTAssertFalse(SessionExpiryNotice.isExpiryCode(httpStatus: 200, bodyCode: 500))
        XCTAssertFalse(SessionExpiryNotice.isExpiryCode(httpStatus: 403, bodyCode: nil))
        for message in ["认证失败，无法访问系统资源", "请先登录", "登录状态已失效，请重新登录"] { XCTAssertTrue(SessionExpiryNotice.isExpiryMessage(message)) }
        for message in [nil, "", "请先登录后记录同意", "账号正在注销冷静期，仅可撤销注销或退出登录"] { XCTAssertFalse(SessionExpiryNotice.isExpiryMessage(message)) }
    }
}

final class LaunchFeatureFlagsTests: XCTestCase {
    private let base = URL(string: "https://fixture.example/base")!

    func testOnlyExactJSONTrueForKnownKeysEnables() throws {
        let flags = try LaunchFeatureFlags.decode(Data(#"{"code":200,"data":{"drops":true,"roamNpcChat":1,"clubMembership":"true","communityPostRead":true,"communityPostWrite":false,"invented":true}}"#.utf8))
        XCTAssertEqual(flags.enabled, ["drops", "communityPostRead"])
        XCTAssertFalse(flags.isOn("invented"))
        XCTAssertEqual(try LaunchFeatureFlags.decode(Data(#"{"code":200}"#.utf8)), .allOff)
        XCTAssertThrowsError(try LaunchFeatureFlags.decode(Data(#"{"code":500,"data":{"drops":true}}"#.utf8)))
        XCTAssertThrowsError(try LaunchFeatureFlags.decode(Data(#"{"code":true,"data":{"drops":true}}"#.utf8)))
    }

    func testRequestShapeMatchesMiniProgram() {
        let request = LaunchFeatureFlagsReader.request(baseURL: base, token: "synthetic-token")
        XCTAssertEqual(request.httpMethod, "POST"); XCTAssertEqual(request.url?.path, "/base/api/config/features")
        XCTAssertEqual(request.timeoutInterval, 6); XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "synthetic-token")
        XCTAssertNil(LaunchFeatureFlagsReader.request(baseURL: base, token: nil).value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(LaunchFeatureFlagsReader.request(baseURL: base, token: "bad\ntoken").value(forHTTPHeaderField: "Authorization"))
    }

    func testUnapprovedEndpointNeverDispatches() async throws {
        let transport = FlagsTransport()
        let reader = LaunchFeatureFlagsReader(configuration: try APIConfiguration(baseURL: base), transport: transport, approved: false, currentIdentity: { "guest" })
        let outcome = await reader.load(token: nil)
        XCTAssertEqual(outcome, .unavailable); XCTAssertTrue(transport.requests.isEmpty)
    }

    func testApprovedReadLoadsAndLateOrFailedReadsStayOff() async throws {
        let transport = FlagsTransport(); transport.body = #"{"code":200,"data":{"drops":true}}"#
        var identity = "account-7"
        let reader = LaunchFeatureFlagsReader(configuration: try APIConfiguration(baseURL: base), transport: transport, approved: true, currentIdentity: { identity })
        let loaded = await reader.load(token: "synthetic-token")
        XCTAssertEqual(loaded, .loaded(LaunchFeatureFlags(enabled: ["drops"])))
        transport.onSend = { identity = "account-8" }
        let late = await reader.load(token: "synthetic-token")
        XCTAssertEqual(late, .unavailable)
        transport.onSend = nil; transport.fails = true
        let failed = await reader.load(token: nil)
        XCTAssertEqual(failed, .unavailable)
        transport.fails = false; transport.status = 503
        let rejected = await reader.load(token: nil)
        XCTAssertEqual(rejected, .unavailable)
        XCTAssertEqual(transport.requests.count, 4)
    }

    func testLaunchFeatureFlagsMountStateAndPrivacySummaryItems() {
        let unmounted = LaunchFeatureFlagsMountState.unmountedAllowlistPending
        XCTAssertFalse(unmounted.isEnabled("drops"))
        XCTAssertEqual(unmounted.statusNotice, "功能开关待接入白名单")
        XCTAssertEqual(LaunchFeatureFlagsMountState.fromOutcome(.unavailable, approved: false), .unmountedAllowlistPending)

        let loaded = LaunchFeatureFlagsMountState.loaded(["drops": true, "roamNpcChat": false, "unknownFlag": true])
        XCTAssertTrue(loaded.isEnabled("drops"))
        XCTAssertFalse(loaded.isEnabled("roamNpcChat"))
        XCTAssertFalse(loaded.isEnabled("unknownFlag"))

        let failed = LaunchFeatureFlagsMountState.fromOutcome(.unavailable, approved: true)
        XCTAssertEqual(failed, .failed)
        XCTAssertFalse(failed.isEnabled("drops"))

        let summary = PrivacyGuideSummaryPresentation()
        XCTAssertEqual(summary.items.map(\.title), ["信息收集范围", "权限使用说明", "撤回同意与注销入口"])
        XCTAssertTrue(summary.items.allSatisfy { !$0.detail.isEmpty })
    }
}
