import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@MainActor final class NativeChannelNotificationConfiguredSourceTests: XCTestCase {
    func testAckKeyRequiresChannelScopeAndDoesNotGrantSaveOrMute() throws {
        let h = try NotificationConfigurationHarness()
        XCTAssertThrowsError(try NativeChannelNotificationConfigurationKey(operation: .ack, scope: nil))
        XCTAssertThrowsError(try NativeChannelNotificationConfigurationKey(operation: .ack, scope: .init(type: 4, value: "11")))
        let key = try NativeChannelNotificationConfigurationKey(operation: .ack, scope: h.scope)
        h.live = try h.snapshot(operations: [key: h.operationRevision])
        let source = try h.source()
        XCTAssertEqual(source.authorizationRevision(for: .ack, scope: h.scope), h.operationRevision)
        XCTAssertNil(source.authorizationRevision(for: .save, scope: h.scope))
        XCTAssertNil(source.authorizationRevision(for: .mute, scope: h.scope))
    }
    func testExplicitReadScopeDoesNotImplySaveMuteOrAnotherScope() throws {
        let h = try NotificationConfigurationHarness()
        let key = try NativeChannelNotificationConfigurationKey(operation: .preference, scope: h.scope)
        h.live = try h.snapshot(operations: [key: h.operationRevision])
        let source = try h.source()
        XCTAssertEqual(source.authorizationRevision(for: .preference, scope: h.scope), h.operationRevision)
        XCTAssertNil(source.authorizationRevision(for: .save, scope: h.scope))
        XCTAssertNil(source.authorizationRevision(for: .mute, scope: h.scope))
        XCTAssertNil(source.authorizationRevision(for: .preference, scope: try .init(type: 1, value: "9013")))
        XCTAssertNil(source.authorizationRevision(for: .directory, scope: nil))
    }
    func testReceiptOnlyConfigurationNeedsNoCurrentReadOrWrite() throws {
        let h = try NotificationConfigurationHarness()
        let key = try NativeChannelNotificationConfigurationKey(operation: .receipt, scope: h.scope)
        h.live = try h.snapshot(operations: [key: h.operationRevision])
        let source = try h.source()
        XCTAssertEqual(source.authorizationRevision(for: .receipt, scope: h.scope), h.operationRevision)
        XCTAssertNil(source.authorizationRevision(for: .preference, scope: h.scope))
        XCTAssertNil(source.authorizationRevision(for: .save, scope: h.scope))
        XCTAssertNil(source.authorizationRevision(for: .receipt, scope: nil))
    }
    func testInvalidShapesAndForeignAccountDefaultCannotBeConfigured() throws {
        let h = try NotificationConfigurationHarness()
        XCTAssertThrowsError(try NativeChannelNotificationConfigurationKey(operation: .directory, scope: h.scope))
        XCTAssertThrowsError(try NativeChannelNotificationConfigurationKey(operation: .save, scope: nil))
        XCTAssertThrowsError(try NativeChannelNotificationConfigurationKey(operation: .mute, scope: .init(type: 4, value: "11")))
        let foreign = try NativeChannelNotificationConfigurationKey(operation: .preference, scope: .init(type: 4, value: "12"))
        XCTAssertThrowsError(try h.snapshot(operations: [foreign: h.operationRevision]))
        XCTAssertThrowsError(try h.snapshot(operations: [:]))
    }
    func testSourceIdentityStableAndWrongViewerCannotSelectIt() throws {
        let h = try NotificationConfigurationHarness(); let source = try h.source()
        let one = try XCTUnwrap(source.source(for: h.context, viewerRevision: 2))
        let two = try XCTUnwrap(source.source(for: h.context, viewerRevision: 2))
        XCTAssertEqual(ObjectIdentifier(one), ObjectIdentifier(two))
        XCTAssertNil(source.source(for: h.context, viewerRevision: 3))
        XCTAssertNotNil(source.source(for: h.context, viewerRevision: 2)) // Wrong caller does not revoke the real source.
    }
    func testObservedMissingConfigurationCannotReviveAndFreshSourceCanReadOldJournalOwner() throws {
        let h = try NotificationConfigurationHarness(); let original = try XCTUnwrap(h.live); let source = try h.source()
        h.live = nil; XCTAssertNil(source.authorizationVersion)
        h.live = original; XCTAssertNil(source.authorizationVersion)
        let fresh = try h.source(); XCTAssertEqual(fresh.authorizationVersion, original.authorizationVersion)
        XCTAssertEqual(NativeChannelNotificationJournalOwner(context: try XCTUnwrap(fresh.currentContext)),
                       NativeChannelNotificationJournalOwner(context: original.context))
    }
    func testChangedOperationMapWithSameGlobalVersionStillRetires() throws {
        let h = try NotificationConfigurationHarness(); let original = try XCTUnwrap(h.live); let source = try h.source()
        let other = try NativeChannelNotificationConfigurationKey(operation: .unread, scope: nil)
        h.live = try h.snapshot(operations: [other: h.operationRevision])
        XCTAssertNil(source.authorizationVersion)
        h.live = original; XCTAssertNil(source.authorizationVersion)
    }
    func testExpirationLatchesEvenIfClockReturnsAndCannotConstructAlreadyExpired() throws {
        let h = try NotificationConfigurationHarness(); let source = try h.source()
        h.time = h.time.addingTimeInterval(121); XCTAssertNil(source.currentContext)
        h.time = h.time.addingTimeInterval(-121); XCTAssertNil(source.currentContext)
        h.time = h.time.addingTimeInterval(121); XCTAssertThrowsError(try h.source())
    }
    func testConcreteProviderFeedsOriginalServiceFinalForwardAndRevocationFence() async throws {
        let h = try NotificationConfigurationHarness()
        let key = try NativeChannelNotificationConfigurationKey(operation: .unread, scope: nil)
        h.live = try h.snapshot(operations: [key: h.operationRevision])
        let source = try h.source(); let storage = NotificationConfigurationStorage()
        let journal = NativeChannelNotificationJournal(storage: storage, owner: .init(context: h.context))
        let wire = NotificationConfigurationWire()
        let forward = try NativeChannelNotificationFinalForward(context: h.context, viewerRevision: 2,
            source: source, journal: journal, underlying: wire, current: { h.context }, viewer: { 2 },
            selected: { source.source(for: h.context, viewerRevision: 2) })
        let service = NativeChannelNotificationService(authority: forward.authority, transport: forward)
        let first = try await service.unreadSummary()
        XCTAssertEqual(first.total, 0); XCTAssertEqual(wire.requests.count, 1)
        XCTAssertTrue(storage.rows.isEmpty)
        wire.beforeResponse = { h.live = nil }
        do { _ = try await service.unreadSummary(); XCTFail("revoked result must be hidden") } catch {}
        XCTAssertEqual(wire.requests.count, 2); XCTAssertFalse(service.isCurrent)
        XCTAssertTrue(storage.rows.isEmpty)
    }
    func testExistingCapturedAuthorityObservesProviderRevocationWithoutNetwork() throws {
        let h = try NotificationConfigurationHarness(); let source = try h.source()
        let authority = try NativeChannelNotificationAuthority(context: h.context, source: source)
        XCTAssertTrue(authority.allows(.directory, scope: nil))
        let original = h.live; h.live = nil; XCTAssertFalse(authority.isCurrent)
        h.live = original; XCTAssertFalse(authority.isCurrent)
    }
}
@MainActor private final class NotificationConfigurationHarness {
    let context: RuntimeDependencyContext; let scope: NativeChannelNotificationScope
    let version = UUID(); let operationRevision = UUID()
    var time = Date(timeIntervalSince1970: 2_000_000_000)
    let expiration = Date(timeIntervalSince1970: 2_000_000_120)
    var live: NativeChannelNotificationConfigurationSnapshot?
    init() throws {
        context = .init(market: .china, baseURL: URL(string: "https://example.com")!, role: "player",
            session: try .init(accountID: 11, epoch: 1, namespace: "CN:notification-config", token: "fixture-token"))
        scope = try .init(type: 1, value: "9012")
        live = try snapshot(operations: [.init(operation: .directory, scope: nil): operationRevision])
    }
    func snapshot(operations: [NativeChannelNotificationConfigurationKey: UUID]) throws -> NativeChannelNotificationConfigurationSnapshot {
        try .init(context: context, viewerRevision: 2, authorizationVersion: version, expiresAt: expiration, operations: operations)
    }
    func source() throws -> NativeChannelNotificationConfiguredSource {
        try .init(snapshot: XCTUnwrap(live), current: { self.live }, now: { self.time })
    }
}

@MainActor private final class NotificationConfigurationStorage: NativeChannelNotificationStorage {
    var rows: [String: Data] = [:]
    func read(_ key: String) throws -> Data? { rows[key] }
    func write(_ data: Data, key: String) throws { rows[key] = data }
    func remove(_ key: String) throws { rows.removeValue(forKey: key) }
}
@MainActor private final class NotificationConfigurationWire: HTTPTransport {
    var requests: [URLRequest] = []; var beforeResponse: (() -> Void)?
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); beforeResponse?()
        return (Data(#"{"code":200,"data":{"total":0,"mention_count":0,"has_mention":0,"by_tab":{"dm":0,"sys":0,"channel":0}}}"#.utf8), 200)
    }
}

extension NativeChannelNotificationConfiguredSourceTests {
    func test401RetirementChecksOriginalContextAndVersionWithoutAffectingNewIssuance() throws {
        let h = try NotificationConfigurationHarness(); let oldSnapshot = try XCTUnwrap(h.live); let old = try h.source()
        old.retireAuthorization(context: h.context, authorizationVersion: UUID())
        XCTAssertEqual(old.authorizationVersion, oldSnapshot.authorizationVersion)
        let foreign = RuntimeDependencyContext(market: .china, baseURL: h.context.baseURL, role: "player",
            session: try .init(accountID: 12, epoch: 1, namespace: "CN:notification-config", token: "other-token"))
        old.retireAuthorization(context: foreign, authorizationVersion: oldSnapshot.authorizationVersion)
        XCTAssertEqual(old.authorizationVersion, oldSnapshot.authorizationVersion)
        let replacement = try NativeChannelNotificationConfigurationSnapshot(context: h.context, viewerRevision: 2,
            authorizationVersion: UUID(), expiresAt: h.expiration, operations: oldSnapshot.operations)
        h.live = replacement; let fresh = try h.source()
        old.retireAuthorization(context: h.context, authorizationVersion: oldSnapshot.authorizationVersion)
        XCTAssertNil(old.authorizationVersion); XCTAssertEqual(fresh.authorizationVersion, replacement.authorizationVersion)
        fresh.retireAuthorization(context: h.context, authorizationVersion: oldSnapshot.authorizationVersion)
        XCTAssertEqual(fresh.authorizationVersion, replacement.authorizationVersion)
        fresh.retireAuthorization(context: h.context, authorizationVersion: replacement.authorizationVersion)
        XCTAssertNil(fresh.authorizationVersion)
    }
}
