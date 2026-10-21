import Foundation
import XCTest
@testable import QuestifyCore

final class OpsServerReadoutsTests: XCTestCase {
    private func status(_ overall: String, updatedAt: String = "2026-10-19T10:00:00Z", component: String = "OPERATIONAL") -> Data {
        Data(#"{"code":200,"msg":"操作成功","data":{"overallStatus":"\#(overall)","updatedAt":"\#(updatedAt)","source":"LOCAL_STATIC_SNAPSHOT","components":[{"code":"CORE_API","name":"城瘾核心服务","status":"\#(component)","updatedAt":"\#(updatedAt)"}],"incidents":[]}}"#.utf8)
    }

    func testExistingStatusFeedDecodesAndUsesServerTimestamp() throws {
        let readout = try XCTUnwrap(OpsServiceStatusDecoder.decode(status("MAINTENANCE", updatedAt: "2026-10-19T10:00:00.123Z")))
        XCTAssertEqual(readout.overall, .maintenance)
        XCTAssertEqual(readout.components, [.init(code: "CORE_API", status: .operational)])
        XCTAssertEqual(readout.globalReadout().observedAt.timeIntervalSince1970, 1_792_404_000.123, accuracy: 0.001)
    }

    func testDefaultMappingInformsButNeverBlocksAndUnknownStaysUnknown() throws {
        let maintenance = try XCTUnwrap(OpsServiceStatusDecoder.decode(status("MAINTENANCE"))).globalReadout()
        XCTAssertEqual(maintenance.state, .active(.init(blocksNewOperations: false, affectsExisting: nil), incident: .serviceDegraded))
        let reviewed = try XCTUnwrap(OpsServiceStatusDecoder.decode(status("MAINTENANCE"))).globalReadout(blocking: [.maintenance])
        XCTAssertEqual(reviewed.state, .active(.init(blocksNewOperations: true, affectsExisting: nil), incident: .serviceDegraded))
        XCTAssertEqual(try XCTUnwrap(OpsServiceStatusDecoder.decode(status("UNKNOWN"))).globalReadout().state, .unknown)
        XCTAssertEqual(try XCTUnwrap(OpsServiceStatusDecoder.decode(status("OPERATIONAL"))).globalReadout().state, .inactive)
    }

    func testInvalidStatusFeedsAreRejectedLikeTheServer() {
        XCTAssertNil(OpsServiceStatusDecoder.decode(status("FINE")))
        XCTAssertNil(OpsServiceStatusDecoder.decode(status("OPERATIONAL", component: "GREEN")))
        XCTAssertNil(OpsServiceStatusDecoder.decode(status("OPERATIONAL", updatedAt: "yesterday")))
        XCTAssertNil(OpsServiceStatusDecoder.decode(Data(#"{"code":500,"data":null}"#.utf8)))
    }

    func testFeatureFlagsOnlyAllowExplicitBooleanTrue() {
        let flags = OpsServerFeatureFlags.decode(Data(#"{"code":200,"data":{"shopNpcChat":true,"merchantNpcChat":1,"drops":"true","communityPostRead":false,"invented":true}}"#.utf8))
        XCTAssertTrue(flags.allows("shopNpcChat"))
        XCTAssertFalse(flags.allows("merchantNpcChat"))
        XCTAssertFalse(flags.allows("drops"))
        XCTAssertFalse(flags.allows("communityPostRead"))
        XCTAssertFalse(flags.allows("invented"))
        XCTAssertFalse(flags.allows("roamNpcEvent"))
        XCTAssertEqual(OpsServerFeatureFlags.decode(Data("oops".utf8)), .unread)
        XCTAssertEqual(OpsServerFeatureFlags.decode(Data(#"{"code":500,"data":{"shopNpcChat":true}}"#.utf8)), .unread)
    }

    func testWriteOutcomeMatchesMiniProgramUnknownRule() {
        XCTAssertEqual(OpsWriteOutcomeClass(httpStatus: nil), .outcomeUnknown)
        XCTAssertEqual(OpsWriteOutcomeClass(httpStatus: 408), .outcomeUnknown)
        XCTAssertEqual(OpsWriteOutcomeClass(httpStatus: 502), .outcomeUnknown)
        XCTAssertEqual(OpsWriteOutcomeClass(httpStatus: 400), .rejected)
        XCTAssertEqual(OpsWriteOutcomeClass(httpStatus: 401), .rejected)
        XCTAssertEqual(OpsWriteOutcomeClass(httpStatus: 200), .httpDelivered)
    }
}
