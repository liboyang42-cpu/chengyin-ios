import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@available(macOS 14.0, *) @MainActor final class CityPlayerValueRecoveryTests: XCTestCase {
 private let base=URL(string:"https://example.test/native")!
 private func capture() throws -> CityValueBoundedCapture {
  let board=CityReadBoard(gameId:"g",boardId:"b",regionId:"r",seasonId:"s",rulesReleaseId:"v",rulesHash:String(repeating:"a",count:64),lifecycle:"FROZEN",title:"Fixture",revision:1)
  let bounds=CityValueBoundedBounds(south:1,west:2,north:1.1,east:2.1)
  let descriptor=CityValueBoundedDescriptor(contract:"CITY_BOUNDED_MAP_V1",datum:"WGS84",initialViewport:bounds,initialZoom:10,minZoom:0,maxZoom:22,pageSize:50,maxPages:4,maxViewportSpanDegrees:0.5)
  let point:[String:Any]=["pointId":"p","title":"Point","latitude":1.05,"longitude":2.05,"mine":false,"datum":"WGS84","domain":"POI","collectedAt":"2026-01-01T00:00:00Z","coordinateAssurance":"PLATFORM_REVIEWED_METADATA","availability":"AVAILABLE","ownership":"NOT_EVALUATED","grantsNavigation":false,"grantsAction":false,"merchantVersion":1,"platformVersion":1]
  let decoded=try JSONDecoder().decode(CityValueBoundedPoint.self,from:JSONSerialization.data(withJSONObject:point))
  return .init(board:board,descriptor:descriptor,query:try .init(bounds:bounds,datum:"WGS84",zoom:10),points:[decoded],watermark:String(repeating:"a",count:64),page:1,nextCursor:nil,complete:true,pageLimitReached:false)
 }
 private func services() throws -> Data {
  try JSONSerialization.data(withJSONObject:["code":200,"data":["status":"AVAILABLE","regionId":"r","boardId":"b","seasonId":"s","rulesReleaseId":"v","services":[["pointId":"p","poiId":8,"serviceType":"CITY_NODE_COUPON_REDEMPTION","canBegin":true]],"mapPage":["watermark":String(repeating:"a",count:64),"page":1,"pointIds":["p"],"complete":true,"pageLimitReached":false]]])
 }
 private func setup(_ fake:Fake) throws -> (CityPlayerValueController,CityPlayerValueApproval,CityValueBoundedMapApproval) {
  let c=try capture();let context=RuntimeDependencyContext(market:.china,baseURL:base,role:"player",session:try .init(accountID:7,epoch:1,namespace:"value-fixture",token:"synthetic-token"))
  let read=try CityPlayerReadApproval(context:context,regionID:"r",expiresAt:Date().addingTimeInterval(600));let map=try CityValueBoundedMapApproval(readApproval:read)
  let approval=try CityPlayerValueApproval(mapApproval:map,capture:c,operations:Set(CityPlayerValueOperation.allCases))
  let service=try CityPlayerValueService(approval:approval,capture:c,transport:fake,currentApproval:{approval},currentMapApproval:{map},currentCapture:{c},currentContext:{context})
  return (CityPlayerValueController(read:c,service:service),approval,map)
 }
 func testUnknownBeginExplicitRetryPreservesExactBody() async throws {
  let fake=Fake();fake.serviceData=try services();let(model,_,_)=try setup(fake)
  await model.load();let selected=try XCTUnwrap(model.services.first);await model.select(selected)
  XCTAssertTrue(model.canBegin);await model.begin();XCTAssertEqual(model.issue,"BIND_UNKNOWN");await model.begin()
  let writes=fake.requests.filter{$0.httpMethod=="POST"};XCTAssertEqual(writes.count,2);XCTAssertEqual(writes.first?.httpBody,writes.last?.httpBody)
 }
 func testOpeningAndSelectingNeverWrites() async throws {
  let fake=Fake();fake.serviceData=try services();let(model,_,_)=try setup(fake);await model.load();await model.select(try XCTUnwrap(model.services.first));XCTAssertTrue(fake.requests.allSatisfy{$0.httpMethod=="GET"})
 }
 func testMapRevocationHidesLoadedReferences() async throws {
  let fake=Fake();fake.serviceData=try services();let(model,_,map)=try setup(fake);await model.load();XCTAssertEqual(model.services.count,1);map.revoke();XCTAssertTrue(model.services.isEmpty);XCTAssertFalse(model.canBegin)
 }
 func testLateVisitApprovalRevocationDropsResponse() async throws {
  let fake=Fake();fake.serviceData=try services();let(model,approval,_)=try setup(fake);fake.afterSend={approval.revoke()};await model.load();XCTAssertTrue(model.services.isEmpty)
 }
 func testNilVisitApprovalCannotSend() async throws {
  let fake=Fake();let c=try capture();let service=try CityPlayerValueService(capture:c,transport:fake,currentApproval:{nil},currentMapApproval:{nil},currentCapture:{c},currentContext:{nil})
  let model=CityPlayerValueController(read:c,service:service);await model.load();XCTAssertTrue(fake.requests.isEmpty)
 }
 func testUnknownFeedbackRetriesSameOriginalPayload() async throws {
  let fake=Fake();var envelope=try XCTUnwrap(JSONSerialization.jsonObject(with:services()) as? [String:Any]);var data=try XCTUnwrap(envelope["data"] as? [String:Any]);data["services"]=[["pointId":"p","poiId":8,"serviceType":"CITY_NODE_COUPON_REDEMPTION","canBegin":false,"visitId":"visit"]];envelope["data"]=data;fake.serviceData=try JSONSerialization.data(withJSONObject:envelope)
  fake.visitData=try JSONSerialization.data(withJSONObject:["code":200,"data":["status":"VISIT","visitId":"visit","rulesReleaseId":"v","regionId":"r","boardId":"b","seasonId":"s","pointId":"p","poiId":8,"enteredAt":"2026-01-01T00:00:00Z","closed":false,"meaningfulAction":"NOT_OBSERVED","serviceSuccess":"NOT_OBSERVED","publicGoal":"UNAVAILABLE","cooperativeGoal":"UNAVAILABLE","netPoints":"UNAVAILABLE","budget":"UNAVAILABLE"]])
  let(model,_,_)=try setup(fake);await model.load();await model.select(try XCTUnwrap(model.services.first));XCTAssertNotNil(model.visit)
  await model.feedback(.exit(.noTime));XCTAssertEqual(model.issue,"FEEDBACK_UNKNOWN");XCTAssertFalse(model.canFeedback);await model.retryFeedback()
  let writes=fake.requests.filter{$0.httpMethod=="POST"};XCTAssertEqual(writes.count,2);XCTAssertEqual(writes.first?.httpBody,writes.last?.httpBody)
 }
 func testFourRoutesCanonicalAndForeignOriginDenied() throws {
  let c=try capture(),scope=try CityPlayerValueScope(board:c.board),page=try CityPlayerValueMapPage(read:c,query:c.query,watermark:c.watermark,page:c.page)
  let routes:[CityPlayerValueRoute]=[.services(scope,page:page),.visit("visit"),.begin(requestID:"request",scope:scope,page:page,pointID:"p",poiID:8),.feedback(visitID:"visit",.exit(.noTime))]
  for route in routes { var request=try route.request(baseURL:base,token:"synthetic-token");XCTAssertEqual(CityPlayerValueRoute(request:request,baseURL:base,scope:scope,mapPage:page),route);var parts=URLComponents(url:request.url!,resolvingAgainstBaseURL:false)!;parts.host="other.test";request.url=parts.url;XCTAssertNil(CityPlayerValueRoute(request:request,baseURL:base,scope:scope,mapPage:page)) }
 }
 private final class Fake:HTTPTransport {
  var serviceData=Data();var visitData=Data();var requests:[URLRequest]=[];var afterSend:(()->Void)?
  func send(_ request:URLRequest) async throws -> (Data,Int) {requests.append(request);if request.httpMethod=="POST"{throw APIError.httpStatus(503)};afterSend?();return(request.url?.lastPathComponent == "services" ? serviceData : visitData,200)}
 }
}
