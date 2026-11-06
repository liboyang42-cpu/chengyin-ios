import Foundation
import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private actor CurrentTrendWire: HTTPTransport {
    private(set) var count = 0
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        count += 1
        return (Data(#"{"code":200,"data":[]}"#.utf8), 200)
    }
}
@MainActor final class ClubParticipationTrendCurrentGateTests: XCTestCase {
    func testDefaultNilDedicatedApprovalNeverSends() async throws {
        let wire = CurrentTrendWire()
        let service = ClubGovernanceService(configuration: try .init(baseURL: URL(string: "https://example.test/")!), transport: wire)
        let session = try ClubGovernanceSession(accountID: 7, epoch: 1, token: "synthetic", storageNamespace: "unit")
        do {
            _ = try await service.readParticipationTrend(topicID: 9, session: session, check: {})
            XCTFail("Ordinary governance transport must not imply trend approval")
        } catch { XCTAssertEqual(error as? ClubGovernanceFailure, .notConfigured) }
        let sent = await wire.count
        XCTAssertEqual(sent, 0)
    }
    func testSparseOriginalRowsAndMalformedCounts() throws {
        func decode(_ text: String) throws -> ClubParticipationTrend {
            try .init(topicID: 9, value: JSONDecoder().decode(ClubGovernanceValue.self, from: Data(text.utf8)))
        }
        let result = try decode(#"[{"participateDate":"2026-11-03","totalCount":"3"},{"participateDate":"2026-11-01","totalCount":0}]"#)
        XCTAssertEqual(result.rows.map(\.date), ["2026-11-03", "2026-11-01"])
        XCTAssertEqual(result.rows.map(\.count), [3, 0])
        for count in ["null", "true", "-1", "1.5", "\"\""] {
            XCTAssertThrowsError(try decode("[{\"participateDate\":\"2026-11-01\",\"totalCount\":\(count)}]"))
        }
    }
}
