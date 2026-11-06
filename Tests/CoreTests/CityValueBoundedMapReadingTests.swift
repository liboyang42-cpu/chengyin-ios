import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@available(macOS 14.0, *) @MainActor final class CityValueBoundedMapReadingTests: XCTestCase {
 private let base = URL(string:"https://example.test/native")!
 private var board: [String:Any] { ["gameId":"g","boardId":"b","regionId":"r","seasonId":"s","rulesReleaseId":"v","rulesHash":String(repeating:"a",count:64),"lifecycle":"FROZEN","title":"Fixture","revision":1] }
 private var viewport: [String:Any] { ["south":1,"west":2,"north":1.1,"east":2.1] }
 private var descriptor: [String:Any] { ["contract":"CITY_BOUNDED_MAP_V1","datum":"WGS84","initialViewport":viewport,"initialZoom":10,"minZoom":0,"maxZoom":22,"pageSize":50,"maxPages":4,"maxViewportSpanDegrees":0.5] }
 private func current() -> [String:Any] { ["contract":"CITY_PLAYER_READ_V1","scope":"CITY","status":"AVAILABLE","board":board,"participationStatus":"NOT_JOINED","pointsStatus":"AVAILABLE","mapRead":descriptor] }
 private func points(watermark:String = String(repeating:"a",count:64)) -> [String:Any] { ["contract":"CITY_PLAYER_READ_V1","scope":"CITY","status":"AVAILABLE","board":board,"points":[],"mapContract":"CITY_BOUNDED_MAP_V1","watermark":watermark,"viewport":viewport,"datum":"WGS84","page":1,"complete":true,"pageLimitReached":false,"grantsNavigation":false,"grantsAction":false] }
 private func reply(_ payload: [String:Any]) throws -> (Data,Int) { (try JSONSerialization.data(withJSONObject:["code":200,"data":payload]),200) }
 private func setup(_ fake: Fake) throws -> (CityValueBoundedMapReader,CityValueBoundedMapApproval) {
  let context = RuntimeDependencyContext(market:.china,baseURL:base,role:"player",session:try .init(accountID:7,epoch:1,namespace:"bounded-fixture",token:"synthetic-token"))
  let read = try CityPlayerReadApproval(context:context,regionID:"r",expiresAt:Date().addingTimeInterval(600))
  let approval = try CityValueBoundedMapApproval(readApproval:read)
  let transport = CityValueBoundedMapScopedTransport(approval:approval,underlying:fake,context:{context},currentApproval:{approval})
  return (CityValueBoundedMapReader(regionID:"r",transport:transport),approval)
 }
 func testCurrentDescriptorThenExactBoundedGET() async throws {
  let fake = Fake(); fake.responses = [try reply(current()),try reply(points())]
  let (reader,_) = try setup(fake); await reader.load()
  XCTAssertNotNil(reader.capture); XCTAssertEqual(reader.capture?.points.count,0); XCTAssertEqual(fake.requests.count,2)
  XCTAssertEqual(fake.requests.map { $0.url!.lastPathComponent },["current","points"])
  XCTAssertTrue(fake.requests.allSatisfy { $0.httpMethod == "GET" && $0.httpBody == nil && !$0.httpShouldHandleCookies })
  XCTAssertTrue(fake.requests[1].url!.absoluteString.contains("limit=50"))
 }
 func testMissingDescriptorCannotGuessViewport() async throws {
  var value=current();value.removeValue(forKey:"mapRead");let fake=Fake();fake.responses=[try reply(value)]
  let(reader,_)=try setup(fake);await reader.load();XCTAssertNil(reader.capture);XCTAssertEqual(fake.requests.count,1)
 }
 func testMalformedWatermarkDropsPage() async throws {
  let fake=Fake();fake.responses=[try reply(current()),try reply(points(watermark:"invalid"))]
  let(reader,_)=try setup(fake);await reader.load();XCTAssertNil(reader.capture)
 }
 func testRevocationDuringReplyDropsLatePayload() async throws {
  let fake=Fake();fake.responses=[try reply(current())];let(reader,approval)=try setup(fake)
  fake.afterSend={approval.revoke()};await reader.load();XCTAssertNil(reader.capture);XCTAssertEqual(fake.requests.count,1)
 }
 func testNilApprovalNeverSends() async {
  let fake=Fake();let transport=CityValueBoundedMapScopedTransport(underlying:fake,context:{nil},currentApproval:{nil})
  let reader=CityValueBoundedMapReader(regionID:"r",transport:transport);await reader.load();XCTAssertNil(reader.capture);XCTAssertTrue(fake.requests.isEmpty)
 }
 func testSuspendDropsCapturedPage() async throws {
  let fake=Fake();fake.responses=[try reply(current()),try reply(points())];let(reader,_)=try setup(fake)
  await reader.load();XCTAssertNotNil(reader.capture);reader.suspend();XCTAssertNil(reader.capture)
 }
 private final class Fake: HTTPTransport {
  var requests:[URLRequest]=[];var responses:[(Data,Int)]=[];var afterSend:(()->Void)?
  func send(_ request:URLRequest) async throws -> (Data,Int) { requests.append(request);guard !responses.isEmpty else { throw APIError.invalidRequest };let value=responses.removeFirst();afterSend?();return value }
 }
}
