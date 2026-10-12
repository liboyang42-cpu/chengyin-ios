import XCTest
@testable import QuestifyCore

final class ClubTopicMerchantListTests: XCTestCase {
    private let scope = ClubGovernanceScope(clubID: 81, topicID: 91)
    private func context(_ scope: ClubGovernanceScope = .init(clubID: 81, topicID: 91), operation: ClubGovernanceRead = .recruit, identity: ClubReadIdentity? = .init(accountID: 701, epoch: 1)) -> ClubGovernanceReadContext {
        .init(operation: operation, scope: scope, identity: identity, viewerRevision: 0, authorizationGeneration: nil)
    }
    private func node(_ id: Int, state: ClubGovernanceValue = .string("ASSIGNED"), fields: [String: ClubGovernanceValue] = [:]) -> ClubGovernanceValue {
        .object(["nodeId": .integer(id), "name": .string("Station \(id)"), "merchantName": .string("Merchant"), "state": state].merging(fields) { _, new in new })
    }
    private func snapshot(_ nodes: ClubGovernanceValue, allowed: Bool = true, fields: [String: ClubGovernanceValue] = [:]) throws -> ClubGovernanceSnapshot {
        let permissions = try ClubGovernancePermissions(value: .object(["active": .bool(true), "club": .object(["id": .integer(81)]), "roleCodes": .array([]),
            "permissions": .array(allowed ? [.string("club:content:manage")] : []), "canManageRoles": .bool(false)]), scope: scope)
        return .init(operation: .recruit, scope: scope, permissions: permissions, value: .object(["nodes": nodes].merging(fields) { _, new in new }))
    }
    private func project(_ nodes: [ClubGovernanceValue]) throws -> ClubTopicMerchantList { try .init(snapshot: snapshot(.array(nodes)), context: context()) }
    func testExcludeOpenSlotsAndKeepSourceOrder() throws {
        let value = try project([node(3), node(1, state: .string("OPEN")), node(2)])
        XCTAssertEqual(value.rows.map(\.id), [3, 2]); XCTAssertEqual(value.scope, scope)
    }
    func testSameMerchantAtTwoStationsRemainsTwoStationRecords() throws {
        let value = try project([node(1), node(2)])
        XCTAssertEqual(value.rows.count, 2); XCTAssertEqual(value.rows.map(\.merchantName), ["Merchant", "Merchant"])
        XCTAssertEqual(value.rows.map(\.stationName), ["Station 1", "Station 2"])
    }
    func testOnlyExactOpenIsExcludedAndUnknownStateIsNotConfirmed() throws {
        let value = try project([node(1, state: .null), node(2, state: .string("open")), node(3, state: .integer(9))])
        XCTAssertEqual(value.rows.count, 3); XCTAssertNil(value.rows[0].state); XCTAssertEqual(value.rows[1].state, "open"); XCTAssertNil(value.rows[2].state)
    }
    func testNamesUseSafeUnknownFallbackAndInitialSupportsUnicode() throws {
        let row = try XCTUnwrap(project([node(1, fields: ["merchantName": .string("  商家 "), "name": .string("  ")])]).rows.first)
        XCTAssertEqual(row.merchantName, "商家"); XCTAssertEqual(row.initial, "商"); XCTAssertNil(row.stationName)
        XCTAssertNil(try project([node(2, fields: ["merchantName": .null])]).rows.first?.initial)
    }
    func testRawContactAndMaskedContactDoNotEnterPresentation() throws {
        let value = try project([node(1, fields: ["phone": .string("PRIVATE_PHONE"), "phoneText": .string("MASKED_PHONE"), "mobile": .string("PRIVATE_MOBILE"), "contact": .object(["phone": .string("NESTED_PHONE")])])])
        let text = String(reflecting: value)
        for marker in ["PRIVATE_PHONE", "MASKED_PHONE", "PRIVATE_MOBILE", "NESTED_PHONE"] { XCTAssertFalse(text.contains(marker)) }
    }
    func testMissingOrMalformedNodesCannotBecomeEmptySuccess() throws {
        for nodes: ClubGovernanceValue in [.null, .string("bad"), .array([.null])] {
            XCTAssertThrowsError(try ClubTopicMerchantList(snapshot: snapshot(nodes), context: context()))
        }
        XCTAssertTrue(try project([]).rows.isEmpty); XCTAssertTrue(try project([node(1, state: .string("OPEN"))]).rows.isEmpty)
    }
    func testDuplicateOrInvalidIncludedNodeIDsFail() {
        XCTAssertThrowsError(try project([node(1), node(1)]))
        for id in [0, -1, 9_007_199_254_740_992] { XCTAssertThrowsError(try project([node(id)])) }
    }
    func testExplicitForeignRootOrNodeScopeFails() throws {
        let nodes = [node(1)]
        for fields: [String: ClubGovernanceValue] in [["clubId": .integer(82)], ["topicId": .integer(92)]] {
            XCTAssertThrowsError(try ClubTopicMerchantList(snapshot: snapshot(.array(nodes), fields: fields), context: context()))
            XCTAssertThrowsError(try project([node(1, fields: fields)]))
        }
    }
    func testWrongOperationScopeIdentityAndMissingPermissionFail() throws {
        let source = try snapshot(.array([node(1)]))
        for c in [context(.init(clubID: 81, topicID: 92)), context(operation: .topics), context(identity: nil)] {
            XCTAssertThrowsError(try ClubTopicMerchantList(snapshot: source, context: c))
        }
        XCTAssertThrowsError(try ClubTopicMerchantList(snapshot: snapshot(.array([node(1)]), allowed: false), context: context()))
    }
    func testExistingReadWireContractIsExactAndClosed() throws {
        XCTAssertEqual(ClubGovernanceRead.recruit.path, "api/club/recruit/overview")
        XCTAssertEqual(try ClubGovernanceRead.recruit.fields(scope: scope), ["clubId": .integer(81), "topicId": .integer(91)])
        XCTAssertThrowsError(try ClubGovernanceRead.recruit.fields(scope: .init(clubID: 81)))
        XCTAssertEqual(ClubGovernanceRead.recruit.permission, "club:content:manage")
    }
}
