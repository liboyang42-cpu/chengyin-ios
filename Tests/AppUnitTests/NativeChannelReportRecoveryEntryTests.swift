import XCTest
import CryptoKit
import Security
import SwiftUI
import UIKit
@testable import Questify

/// Entirely synthetic storage, attributes and HTTP transport. Never queries Keychain.
@MainActor final class NativeChannelReportRecoveryEntryTests: XCTestCase {
    func testKeyEnumerationRequestsOnlyExistingServiceAttributesAndFiltersExactOwner() async throws {
        let h = try CRRecoveryAppHarness(); try await h.seed()
        let key = try XCTUnwrap(h.store.rows.keys.first), context = try XCTUnwrap(h.context)
        let foreign = h.key(account: 99), wrongBase = h.key(base: "https://other.example.test/"), wrongFamily = "session-token"
        var calls = 0
        let keys = try NativeChannelReportJournalKeys.read(scope: h.scope, context: context) { query in
            calls += 1
            XCTAssertEqual(Set(query.keys), Set([kSecClass, kSecAttrService, kSecAttrSynchronizable, kSecReturnAttributes, kSecMatchLimit].map { $0 as String }))
            XCTAssertEqual(query[kSecClass as String] as? String, kSecClassGenericPassword as String)
            XCTAssertEqual(query[kSecAttrService as String] as? String, h.scope.service + ".project-editor")
            XCTAssertEqual(query[kSecAttrSynchronizable as String] as? Bool, false)
            XCTAssertEqual(query[kSecReturnAttributes as String] as? Bool, true)
            XCTAssertEqual(query[kSecMatchLimit as String] as? String, kSecMatchLimitAll as String)
            XCTAssertNil(query[kSecReturnData as String]); XCTAssertNil(query[kSecAttrAccessGroup as String])
            XCTAssertNil(query[kSecValueData as String]); XCTAssertNil(query[kSecAttrAccessible as String])
            let values = [key, foreign, wrongBase, wrongFamily].map { [kSecAttrAccount as String: $0] }
            return (errSecSuccess, values as NSArray)
        }
        XCTAssertEqual(keys, [key]); XCTAssertEqual(calls, 1)
        XCTAssertEqual(h.store.writes, 1); XCTAssertEqual(h.store.removes, 0)
    }

    func testKeychainDenialAndMalformedResultAreNotSuccessfulEmpty() throws {
        let h = try CRRecoveryAppHarness(), context = try XCTUnwrap(h.context)
        for status in [errSecInteractionNotAllowed, errSecAuthFailed, errSecParam] {
            XCTAssertThrowsError(try NativeChannelReportJournalKeys.read(scope: h.scope, context: context) { _ in (status, nil) })
        }
        let malformed: [CFTypeRef?] = [nil, Data("not-attributes".utf8) as NSData, [["unexpected": "value"]] as NSArray]
        for value in malformed {
            XCTAssertThrowsError(try NativeChannelReportJournalKeys.read(scope: h.scope, context: context) { _ in (errSecSuccess, value) })
        }
        XCTAssertEqual(try NativeChannelReportJournalKeys.read(scope: h.scope, context: context) { _ in (errSecItemNotFound, nil) }, [])
        XCTAssertEqual(try NativeChannelReportJournalKeys.read(scope: h.scope, context: context) { _ in (errSecSuccess, [] as NSArray) }, [])
    }

    func testMismatchedDeploymentNamespaceFailsBeforeKeychainBoundary() throws {
        let h = try CRRecoveryAppHarness()
        let wrong = try h.makeContext(namespace: "other-deployment")
        var called = false
        XCTAssertThrowsError(try NativeChannelReportJournalKeys.read(scope: h.scope, context: wrong) { _ in
            called = true; return (errSecItemNotFound, nil)
        })
        XCTAssertFalse(called)
    }

    func testDefaultOffAndWriteOnlyNeverCreateRecoveryAssemblyOrReadStorage() throws {
        let h = try CRRecoveryAppHarness()
        let configurations: [[BusinessRuntimeFeature: Set<BusinessRuntimeRoute>]] = [[:], [.imReport: [try .post("api/im/report")]]]
        for routes in configurations {
            h.configuration = try h.makeConfiguration(routes: routes)
            XCTAssertNil(h.makeDirectory()); XCTAssertEqual(h.keyReads, 0); XCTAssertTrue(h.wire.requests.isEmpty)
        }
    }

    func testNormalReporterAssemblyRequiresNoMembershipOrMessageHistoryAndNeverPosts() async throws {
        let h = try CRRecoveryAppHarness(); try await h.seed(); let bytes = h.store.rows
        let directory = try XCTUnwrap(h.makeDirectory()); directory.reload()
        let owner = try XCTUnwrap(directory.visibleEntries.first?.owner)
        XCTAssertEqual(h.keyReads, 1); XCTAssertEqual(h.store.rows, bytes)
        XCTAssertTrue(owner.canRecover); XCTAssertFalse(owner.canSubmit)
        XCTAssertEqual(h.wire.requests.map(\.httpMethod), ["POST"])
        await owner.recover(); await owner.submit()
        XCTAssertEqual(h.wire.requests.map(\.httpMethod), ["POST", "GET"])
        XCTAssertEqual(owner.state, .acknowledged(reportID: "61", status: "PENDING"))
        XCTAssertEqual(h.store.removes, 1)
    }

    func testOtherUUIDGrantCannotAuthorizeOriginalRequest() async throws {
        let h = try CRRecoveryAppHarness(); try await h.seed(); let bytes = h.store.rows
        h.configuration = try h.makeConfiguration(routes: [.imChannelReportReceipt: [try .init(method: "GET", path:
            "api/channel-platform/governance/reports/requests/22222222-2222-4222-8222-222222222222")]])
        let directory = try XCTUnwrap(h.makeDirectory()); directory.reload()
        let owner = try XCTUnwrap(directory.visibleEntries.first?.owner)
        XCTAssertFalse(owner.canRecover); await owner.recover(); await owner.submit()
        XCTAssertEqual(h.wire.requests.count, 1); XCTAssertEqual(h.store.rows, bytes)
    }

    func testReceiptIssuanceWithdrawalHidesRetainedDirectoryAndStopsRead() async throws {
        let h = try CRRecoveryAppHarness(); try await h.seed(); let bytes = h.store.rows
        let directory = try XCTUnwrap(h.makeDirectory()); directory.reload()
        let owner = try XCTUnwrap(directory.visibleEntries.first?.owner)
        h.configuration = try h.makeConfiguration(routes: [:])
        XCTAssertFalse(directory.isCurrent); XCTAssertTrue(directory.visibleEntries.isEmpty)
        await owner.recover(); XCTAssertEqual(h.wire.requests.count, 1); XCTAssertEqual(h.store.rows, bytes)
    }

    func testContextOrViewerChangesDuringReadCannotPublishOrExpireReplacementSession() async throws {
        for change in ["account", "epoch", "token", "namespace", "role", "viewer"] {
            let h = try CRRecoveryAppHarness(); try await h.seed(); let bytes = h.store.rows
            let directory = try XCTUnwrap(h.makeDirectory()); directory.reload()
            let owner = try XCTUnwrap(directory.visibleEntries.first?.owner)
            h.wire.status = 401
            h.wire.beforeGET = {
                switch change {
                case "account": h.context = try h.makeContext(account: 99)
                case "epoch": h.context = try h.makeContext(epoch: 9)
                case "token": h.context = try h.makeContext(token: "replacement-token")
                case "namespace": h.context = try h.makeContext(namespace: "other")
                case "role": h.context = try h.makeContext(role: "merchant")
                default: h.viewerCurrent = false
                }
            }
            await owner.recover()
            XCTAssertFalse(directory.isCurrent); XCTAssertTrue(directory.visibleEntries.isEmpty)
            XCTAssertEqual(owner.state, .unknown); XCTAssertEqual(h.expired, 0)
            XCTAssertEqual(h.store.rows, bytes); XCTAssertEqual(h.store.removes, 0)
        }
    }

    func testLateGrantWithdrawalAfterGETPreservesOriginalWithoutSuccess() async throws {
        let h = try CRRecoveryAppHarness(); try await h.seed(); let bytes = h.store.rows
        let directory = try XCTUnwrap(h.makeDirectory()); directory.reload()
        let owner = try XCTUnwrap(directory.visibleEntries.first?.owner)
        h.wire.beforeGET = { h.configuration = try h.makeConfiguration(routes: [:]) }
        await owner.recover()
        XCTAssertFalse(owner.isCurrent); XCTAssertEqual(owner.state, .unknown)
        XCTAssertEqual(h.store.rows, bytes); XCTAssertEqual(h.store.removes, 0)
    }

    func testNavigationRejectsRepeatedTapStaleDismissAndRetiredOrReloadedEntry() async throws {
        let h = try CRRecoveryAppHarness(); try await h.seed()
        let directory = try XCTUnwrap(h.makeDirectory()); directory.reload()
        let entry = try XCTUnwrap(directory.visibleEntries.first)
        var navigation = NativeChannelReportRecoveryNavigation()
        navigation.open(entry, directory: directory)
        let first = try XCTUnwrap(navigation.selection?.id)
        navigation.open(entry, directory: directory); XCTAssertEqual(navigation.selection?.id, first)
        navigation.close(first); navigation.open(entry, directory: directory)
        let second = try XCTUnwrap(navigation.selection?.id); XCTAssertNotEqual(first, second)
        navigation.close(first); XCTAssertEqual(navigation.selection?.id, second)
        navigation.close(second); directory.reload(); navigation.open(entry, directory: directory)
        XCTAssertNil(navigation.selection)
        let fresh = try XCTUnwrap(directory.visibleEntries.first); navigation.open(fresh, directory: directory)
        XCTAssertNotNil(navigation.selection); navigation.close(navigation.selection?.id)
        directory.retire(); navigation.open(fresh, directory: directory); XCTAssertNil(navigation.selection)
    }

    func testNativeViewsConstructInBothLanguagesAtLargestDynamicTypeWithoutAddingWriter() async throws {
        let h = try CRRecoveryAppHarness(); try await h.seed()
        let directory = try XCTUnwrap(h.makeDirectory()); directory.reload()
        let owner = try XCTUnwrap(directory.visibleEntries.first?.owner)
        for language in ["en", "zh-Hans"] {
            let view = NavigationStack { NativeChannelReportRecoveryView(directory: directory) }
                .environment(\.locale, Locale(identifier: language))
                .environment(\.dynamicTypeSize, .accessibility5)
            let controller = UIHostingController(rootView: view)
            controller.loadViewIfNeeded(); controller.view.frame = CGRect(x: 0, y: 0, width: 320, height: 640)
            controller.view.setNeedsLayout(); controller.view.layoutIfNeeded()
            let detail = UIHostingController(rootView: NavigationStack { NativeChannelReportRecoveryDetail(owner: owner) }
                .environment(\.locale, Locale(identifier: language)).environment(\.dynamicTypeSize, .accessibility5))
            detail.loadViewIfNeeded(); detail.view.frame = controller.view.frame; detail.view.layoutIfNeeded()
        }
        XCTAssertFalse(owner.canSubmit); XCTAssertEqual(h.wire.requests.count, 1)
        // This is a construction smoke test, not screenshot/VoiceOver/clipping acceptance.
    }
}

@MainActor private final class CRRecoveryAppStore: ProjectEditDataStorage {
    var rows: [String: Data] = [:]; var writes = 0, removes = 0
    func read(_ key: String) throws -> Data? { rows[key] }
    func write(_ data: Data, key: String) throws { writes += 1; rows[key] = data }
    func remove(_ key: String) throws { removes += 1; rows[key] = nil }
}
@MainActor private final class CRRecoveryAppWire: HTTPTransport {
    var requests: [URLRequest] = [], receipt: [String: Any] = [:]
    var status = 200; var beforeGET: (() throws -> Void)?
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        if request.httpMethod == "POST" {
            let bytes = try XCTUnwrap(request.httpBody)
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: String])
            receipt = ["state": "APPLIED", "request_id": body["submit_request_id"]!, "reporter_member_id": "17",
                       "target_type": "MESSAGE", "target_id": body["target_id"]!, "channel_id": "2",
                       "body_digest": SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(),
                       "report_id": "61", "audit_task_id": "71", "status": "PENDING"]
            throw URLError(.timedOut)
        }
        try beforeGET?()
        return (try JSONSerialization.data(withJSONObject: ["code": status, "data": receipt]), status)
    }
}
@MainActor private final class CRRecoveryAppHarness {
    let scope: RegionalSessionStorageScope
    let base = URL(string: "https://api.example.test/report-recovery")!
    let requestID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    let store = CRRecoveryAppStore(), wire = CRRecoveryAppWire()
    var context: RuntimeDependencyContext?, configuration: BusinessRuntimeConfiguration?
    var viewerCurrent = true, keyReads = 0, expired = 0
    var path: String { "api/channel-platform/governance/reports/requests/" + requestID.uuidString }
    init() throws {
        let baseText = "https://api.example.test/report-recovery"
        let regional = try RegionalConfiguration(market: .china, baseURL: baseText, approvedBaseURLs: [.china: [baseText]])
        scope = try RegionalSessionStorageScope(configuration: regional, bundleIdentifier: "example.report-recovery-tests", realm: "mock-only")
        context = try makeContext()
        configuration = try makeConfiguration(routes: [.imChannelReportReceipt: [try .init(method: "GET", path: path)]])
    }
    func makeContext(account: Int = 17, epoch: UInt64 = 3, token: String = "synthetic-token", namespace: String? = nil,
                     role: String = "player") throws -> RuntimeDependencyContext {
        .init(market: .china, baseURL: base, role: role,
              session: try .init(accountID: account, epoch: epoch, namespace: namespace ?? scope.service, token: token))
    }
    func makeConfiguration(routes: [BusinessRuntimeFeature: Set<BusinessRuntimeRoute>]) throws -> BusinessRuntimeConfiguration {
        try .init(market: .china, baseURL: base, namespace: scope.service, accountID: 17, routes: routes)
    }
    func factory() -> BusinessRuntimeFactory? {
        BusinessRuntimeFactory(configuration: configuration, api: try! APIConfiguration(baseURL: base), transport: wire, current: { self.context })
    }
    func makeDirectory() -> NativeChannelReportRecoveryDirectory? {
        guard let factory = factory() else { return nil }
        return NativeChannelReportRecoveryAssembly.make(factory: factory, currentFactory: { self.factory() }, storage: store,
            journalKeys: { self.keyReads += 1; return Array(self.store.rows.keys) }, current: { self.viewerCurrent },
            unauthorized: { self.expired += 1 })
    }
    func seed() async throws {
        let flow = try NativeChannelReportFlow(context: XCTUnwrap(context), conversationID: 2, transport: wire, storage: store,
            current: { true }, permitsWrite: { true }, permitsRead: { $0 == self.path }, unauthorized: {}, makeRequestID: { self.requestID })
        XCTAssertTrue(flow.prepare(messageID: 81)); flow.select(reason: .privacy, note: "PRIVATE original note")
        await flow.submit(); XCTAssertEqual(flow.state, .unknown)
    }
    func key(account: Int = 17, base: String? = nil) -> String {
        let values = [scope.service, base ?? self.base.absoluteString, String(account), "2"]
        return "native-channel-report.v1." + Data(values.map { "\($0.utf8.count):\($0)" }.joined().utf8).base64EncodedString()
    }
}
