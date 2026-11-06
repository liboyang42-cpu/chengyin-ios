import Foundation
import XCTest
@testable import QuestifyCore

final class NativeChannelAppealPublicRestorationTests: XCTestCase {
    func testCanonicalLocalIntegerDoesNotNeedAdmissionDirectory() {
        for raw in [true, false, 1.5, "01", "-0", "+1", "1.0", " 1", "9223372036854775808"] as [Any] {
            XCTAssertNil(NativeChannelGovernanceNotice.integer(raw))
        }
        XCTAssertEqual(NativeChannelGovernanceNotice.integer("0"), 0)
        XCTAssertEqual(NativeChannelGovernanceNotice.integer(Int64.max), Int64.max)
        XCTAssertEqual(NativeChannelGovernanceNotice.integer("-1"), -1)
        XCTAssertNil(NativeChannelActionFacts(source: ["duration_sec": "-1"]).durationSeconds)
    }
    func testRuntimeCatalogSeparatesReadWriteAndReceipt() throws {
        let read = try BusinessRuntimeRoute(method: "GET", path: "api/im/appeals/61")
        XCTAssertTrue(BusinessRuntimeFeature.imChannelAppealRead.accepts(read))
        XCTAssertFalse(BusinessRuntimeFeature.imChannelAppealWrite.accepts(read))
        XCTAssertFalse(BusinessRuntimeFeature.imChannelAppealReceipt.accepts(read))
        for path in ["api/im/appeals/0", "api/im/appeals/01", "api/im/appeals/61/", "api/im/appeals/61/evidence"] {
            XCTAssertFalse(BusinessRuntimeFeature.imChannelAppealRead.accepts(try .init(method: "GET", path: path)))
        }
        XCTAssertTrue(BusinessRuntimeFeature.imChannelAppealWrite.accepts(try .post("api/im/appeals/61/evidence")))
        XCTAssertFalse(BusinessRuntimeFeature.imChannelAppealWrite.accepts(try .post("api/im/appeals/61/delete")))
        XCTAssertTrue(BusinessRuntimeFeature.imChannelAppealReceipt.accepts(try .init(method: "GET", path: "api/channel-platform/governance/moderation/requests/00000000-0000-0000-0000-000000000001")))
        XCTAssertFalse(BusinessRuntimeFeature.imChannelAppealReceipt.accepts(try .init(method: "GET", path: "api/channel-platform/governance/moderation/requests/not-a-uuid")))
    }
}
