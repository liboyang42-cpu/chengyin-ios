import XCTest
@testable import QuestifyCore

/// Authored for XCTest. Linux execution of this file is NOT_RUN unless compiled.
final class ProfileOrderEventHostTests: XCTestCase {
    private struct PostFailed: Error {}

    func testFirstJourneyOwnedOrderReadsInfoThenOriginalEventAndRecoverOriginal() async throws {
        var host = ProfileOrderEventHost()
        let opened = await host.open(501) { path, id in
            if path == ProfileOrderEventHost.registrationInfoPath {
                return Self.envelope(#"{"id":501,"title":"周末沙发","payableAmount":200.00,"memberId":7}"#)
            }
            if path == ProfileOrderEventHost.originalEventPath {
                return Self.envelope(#"{"requestId":"c11-owned-order","targetType":"ORDER","targetId":501,"action":"CREATE","afterJson":"UNKNOWN","title":"周末沙发","payableAmount":200.00}"#)
            }
            XCTFail(path)
            return nil
        }

        XCTAssertEqual(opened, 501)
        XCTAssertEqual(host.calls, [
            .init(path: "api/registration/info", id: "501"),
            .init(path: "api/registration/original-event", id: "501"),
        ])
        XCTAssertFalse(host.calls.contains { $0.path.contains("audit-log") || $0.path.contains("business/audit") })
        let events = try XCTUnwrap(host.injection.events)
        XCTAssertEqual(events, [
            OriginalAuditEvent(
                requestId: "c11-owned-order", targetType: "ORDER", targetId: 501,
                action: "CREATE", afterJson: "UNKNOWN"),
        ])
        XCTAssertEqual(host.injection.lookups, 1)
        XCTAssertEqual(host.injection.sends, 0)
        let projection = SupportCurrentProjection(
            requestId: "c11-owned-order",
            appliedState: SupportEventLocator.projectionAppliedSuccess)
        let recovered = try XCTUnwrap(host.injection.recoverOriginal(
            requestID: "c11-owned-order", currentProjection: projection))
        XCTAssertEqual(recovered.originalOutcome, "UNKNOWN")
        XCTAssertEqual(recovered.orderId, 501)
        XCTAssertNotEqual(recovered.originalOutcome, SupportEventLocator.projectionAppliedSuccess)
        XCTAssertEqual(host.injection.sends, 0)
    }

    func testMismatchTransportFailureAndAbsentBodyDoNotInventEvents() async {
        var mismatch = ProfileOrderEventHost()
        let mismatched = await mismatch.open(501) { path, _ in
            XCTAssertEqual(path, ProfileOrderEventHost.registrationInfoPath)
            return Self.envelope(#"{"id":99,"title":"别的订单","payableAmount":1}"#)
        }
        XCTAssertNil(mismatched)
        XCTAssertEqual(mismatch.calls.map(\.path), ["api/registration/info"])
        XCTAssertNil(mismatch.injection.events)
        XCTAssertEqual(mismatch.injection.lookups, 0)

        var infoFailed = ProfileOrderEventHost()
        let infoFailure = await infoFailed.open(501) { _, _ in throw PostFailed() }
        XCTAssertNil(infoFailure)
        XCTAssertEqual(infoFailed.calls.map(\.path), ["api/registration/info"])
        XCTAssertNil(infoFailed.injection.events)

        var eventFailed = ProfileOrderEventHost()
        let eventFailure = await eventFailed.open(501) { path, _ in
            if path == ProfileOrderEventHost.registrationInfoPath {
                return Self.envelope(#"{"id":"501"}"#)
            }
            throw PostFailed()
        }
        XCTAssertNil(eventFailure)
        XCTAssertEqual(eventFailed.calls.map(\.path), ["api/registration/info", "api/registration/original-event"])
        XCTAssertNil(eventFailed.injection.events)

        var absent = ProfileOrderEventHost()
        let absentBody = await absent.open(501) { path, _ in
            if path == ProfileOrderEventHost.registrationInfoPath {
                return Self.envelope(#"{"id":501}"#)
            }
            return nil
        }
        XCTAssertNil(absentBody)
        XCTAssertEqual(absent.calls.count, 2)
        XCTAssertNil(absent.injection.events)

        var blank = ProfileOrderEventHost()
        let blankID = await blank.open(0) { _, _ in
            XCTFail("blank id must not post")
            return Data()
        }
        XCTAssertNil(blankID)
        XCTAssertEqual(blank.calls, [])
        XCTAssertNil(blank.injection.events)
    }

    func testProfileOrderFieldsAndADifferentFirstOrderDoNotBecomeThisOrder() async {
        var profile = ProfileOrderEventHost()
        let invented = await profile.open(501) { path, id in
            XCTAssertEqual(id, "501")
            if path == ProfileOrderEventHost.registrationInfoPath {
                return Self.envelope(#"{"id":501,"title":"周末沙发","payableAmount":200,"memberId":7,"registrationNo":"NO501"}"#)
            }
            return Self.envelope(#"{"id":501,"title":"周末沙发","payableAmount":200,"memberId":7}"#)
        }
        XCTAssertNil(invented)
        XCTAssertEqual(profile.calls.map(\.path), ["api/registration/info", "api/registration/original-event"])
        XCTAssertNil(profile.injection.events)
        XCTAssertEqual(profile.injection.sends, 0)

        var different = ProfileOrderEventHost()
        let otherFirst = await different.open(501) { path, _ in
            if path == ProfileOrderEventHost.registrationInfoPath {
                return Self.envelope(#"{"id":501}"#)
            }
            return Self.envelope(#"[{"requestId":"c11-other","targetType":"ORDER","targetId":9,"action":"CREATE","afterJson":"PENDING"},{"requestId":"c11-owned-order","targetType":"ORDER","targetId":501,"action":"CREATE","afterJson":"UNKNOWN"}]"#)
        }
        XCTAssertNil(otherFirst)
        XCTAssertNil(different.injection.events)

        var runOnly = ProfileOrderEventHost()
        let runRow = await runOnly.open(501) { path, _ in
            if path == ProfileOrderEventHost.registrationInfoPath {
                return Self.envelope(#"{"id":501}"#)
            }
            return Self.envelope(#"{"requestId":"c11-run","targetType":"RUN","targetId":77,"action":"START","afterJson":"UNKNOWN"}"#)
        }
        XCTAssertNil(runRow)
        XCTAssertEqual(runOnly.calls.map(\.path), ["api/registration/info", "api/registration/original-event"])
        XCTAssertNil(runOnly.injection.events)

        var refused = ProfileOrderEventHost()
        let denied = await refused.open(501) { path, _ in
            XCTAssertEqual(path, ProfileOrderEventHost.registrationInfoPath)
            return Data(#"{"code":500,"msg":"无权查看该报名信息","data":{"id":501}}"#.utf8)
        }
        XCTAssertNil(denied)
        XCTAssertEqual(refused.calls.map(\.path), ["api/registration/info"])
        XCTAssertNil(refused.injection.events)
    }

    private static func envelope(_ data: String, code: Int = 200) -> Data {
        Data("{\"code\":\(code),\"data\":\(data)}".utf8)
    }
}
