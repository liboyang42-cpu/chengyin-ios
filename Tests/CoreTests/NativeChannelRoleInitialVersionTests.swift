import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@MainActor final class NativeChannelRoleInitialVersionTests:XCTestCase {
 func testOriginalZeroStringRoleAppearsInNormalList() async throws {
  let h=try await RoleZeroHarness();await h.flow.activate()
  XCTAssertEqual(h.flow.state,.ready);XCTAssertEqual(h.flow.roles.first?.version,"0")
  XCTAssertEqual(h.flow.roles.first?.id,"77");XCTAssertEqual(h.wire.writes,0)
 }
 func testIntegerZeroAndExistingPositiveVersionsRemainAccepted() async throws {
  for version in [0,"1",2,String(Int64.max)] as [Any] {
   let wire=RoleZeroWire();wire.version=version;let h=try await RoleZeroHarness(wire:wire);await h.flow.activate()
   XCTAssertEqual(h.flow.state,.ready);XCTAssertEqual(h.flow.roles.count,1)
  }
 }
 func testMalformedNegativeBooleanFractionalAndNoncanonicalVersionsFailClosed() async throws {
  for version in ["-1",-1,true,0.5,"00","+0","0.0"," 0","9223372036854775808",NSNull()] as [Any] {
   let wire=RoleZeroWire();wire.version=version;let h=try await RoleZeroHarness(wire:wire);await h.flow.activate()
   XCTAssertEqual(h.flow.state,.unavailable);XCTAssertTrue(h.flow.roles.isEmpty);XCTAssertEqual(wire.writes,0)
  }
 }
 func testZeroEntityIDIsStillRejected() async throws {
  let wire=RoleZeroWire();wire.roleID="0";let h=try await RoleZeroHarness(wire:wire);await h.flow.activate()
  XCTAssertEqual(h.flow.state,.unavailable);XCTAssertTrue(h.flow.roles.isEmpty)
 }
 func testForeignGuildStillRejectsWholeList() async throws {
  let wire=RoleZeroWire();wire.guild="43";let h=try await RoleZeroHarness(wire:wire);await h.flow.activate()
  XCTAssertEqual(h.flow.state,.unavailable);XCTAssertTrue(h.flow.roles.isEmpty)
 }
 func testNormalEditFreezesZeroCASAndReadsUpdatedCurrentAfterResult() async throws {
  let h=try await RoleZeroHarness();await h.flow.activate();var options=NativeChannelRoleFlow.Options();options.position=6
  XCTAssertTrue(h.flow.prepare(.edit,target:"77",name:"Updated",permissions:"0x0",ids:[],reason:"Fixture",options:options))
  await h.flow.confirm();XCTAssertEqual(h.flow.state,.applied);XCTAssertFalse(h.flow.hasPending)
  XCTAssertEqual(h.wire.lastBody?["version"] as? String,"0");XCTAssertEqual(h.wire.writes,1)
  await h.flow.refresh();XCTAssertEqual(h.flow.roles.first?.version,"1");XCTAssertEqual(h.flow.roles.first?.name,"Updated")
 }
 func testCreateOriginalAppliedZeroResultSettlesJournalThenReadsCurrent() async throws {
  let h=try await RoleZeroHarness();await h.flow.activate();XCTAssertTrue(h.prepareCreate())
  await h.flow.confirm();XCTAssertEqual(h.flow.state,.applied);XCTAssertFalse(h.flow.hasPending);XCTAssertTrue(h.store.values.isEmpty)
  XCTAssertTrue(h.flow.result.contains("版本 0"));await h.flow.refresh()
  XCTAssertEqual(h.flow.roles.first?.version,"0");XCTAssertEqual(h.wire.writes,1)
 }
 func testCreateTimeoutRestartRecoversSameOriginalZeroVersionReceiptWithoutResend() async throws {
  let wire=RoleZeroWire(),store=RoleZeroStore();wire.unknown=true
  let first=try await RoleZeroHarness(wire:wire,store:store);await first.flow.activate();XCTAssertTrue(first.prepareCreate());await first.flow.confirm()
  let original=try XCTUnwrap(first.flow.originalRequestID);XCTAssertTrue(first.flow.hasPending);first.flow.deactivate()
  let restored=try await RoleZeroHarness(wire:wire,store:store);await restored.flow.activate()
  XCTAssertEqual(restored.flow.originalRequestID,original);XCTAssertTrue(restored.flow.hasPending);XCTAssertEqual(wire.writes,1)
  wire.unknown=false;await restored.flow.refresh();XCTAssertFalse(restored.flow.hasPending);XCTAssertEqual(restored.flow.roles.first?.version,"0");XCTAssertEqual(wire.writes,1)
 }
 func testInvalidAppliedVersionNeverClearsPendingJournal() async throws {
  let wire=RoleZeroWire();wire.createdVersion="-1";let h=try await RoleZeroHarness(wire:wire);await h.flow.activate();XCTAssertTrue(h.prepareCreate())
  await h.flow.confirm();XCTAssertTrue(h.flow.hasPending);XCTAssertFalse(h.store.values.isEmpty);XCTAssertEqual(h.flow.state,.unknown)
 }
 func testCurrentFailureAfterAppliedDoesNotUndoOriginalResult() async throws {
  let h=try await RoleZeroHarness();await h.flow.activate();XCTAssertTrue(h.prepareCreate());await h.flow.confirm()
  h.wire.failRoleRead=true;await h.flow.refresh()
  XCTAssertFalse(h.flow.hasPending);XCTAssertTrue(h.store.values.isEmpty);XCTAssertFalse(h.flow.result.isEmpty);XCTAssertTrue(h.flow.roles.isEmpty);XCTAssertEqual(h.wire.writes,1)
 }
 func testRevocationBeforeConfirmDoesNotPersistOrWrite() async throws {
  let h=try await RoleZeroHarness();await h.flow.activate();XCTAssertTrue(h.prepareCreate());h.grant.revoke();await h.flow.confirm()
  XCTAssertEqual(h.wire.writes,0);XCTAssertTrue(h.store.values.isEmpty);XCTAssertTrue(h.flow.roles.isEmpty)
 }
 func testBackgroundAfterDispatchKeepsJournalAndDoesNotAcceptLateResult() async throws {
  let wire=RoleZeroWire(),store=RoleZeroStore();let h=try await RoleZeroHarness(wire:wire,store:store)
  await h.flow.activate();XCTAssertTrue(h.prepareCreate());wire.suspendWrite=true
  let task=Task {await h.flow.confirm()};await wire.waitForWrite();h.flow.deactivate();wire.finishWrite();await task.value
  XCTAssertTrue(h.flow.hasPending);XCTAssertFalse(store.values.isEmpty);XCTAssertTrue(h.flow.result.isEmpty)
  let restored=try await RoleZeroHarness(wire:wire,store:store);await restored.flow.activate()
  XCTAssertFalse(restored.flow.hasPending);XCTAssertEqual(restored.flow.roles.first?.version,"0");XCTAssertEqual(wire.writes,1)
 }
 func testDifferentAccountCannotRecoverOriginalJournal() async throws {
  let wire=RoleZeroWire(),store=RoleZeroStore();wire.unknown=true;let first=try await RoleZeroHarness(wire:wire,store:store)
  await first.flow.activate();XCTAssertTrue(first.prepareCreate());await first.flow.confirm();first.flow.deactivate()
  let other=try await RoleZeroHarness(actor:18,wire:wire,store:store);await other.flow.activate()
  XCTAssertFalse(other.flow.hasPending);XCTAssertFalse(store.values.isEmpty);XCTAssertEqual(wire.writes,1)
 }
}
@MainActor private final class RoleZeroHarness {
 let flow:NativeChannelRoleFlow,wire:RoleZeroWire,store:RoleZeroStore,grant:NativeChannelManagementApproval
 let service:NativeChannelManagementHTTPService
 init(actor:Int=17,wire:RoleZeroWire?=nil,store:RoleZeroStore?=nil)async throws {
  let wire=wire ?? RoleZeroWire(),store=store ?? RoleZeroStore()
  self.wire=wire;self.store=store
  let context=RuntimeDependencyContext(market:.china,baseURL:URL(string:"https://example.test/")!,role:"player",session:try PlayExperienceSession(accountID:actor,epoch:3,namespace:"role-zero-fixture",token:"not-live"))
  let scope=try NativeChannelManagementScope(guildKind:1,guildID:.init("42"))
  let grant=try NativeChannelManagementApproval(context:context,viewerRevision:1,scope:scope,operations:[.detail],expiresAt:Date().addingTimeInterval(600));self.grant=grant
  let service=try NativeChannelManagementHTTPService(context:context,viewerRevision:1,scope:scope,configuration:.init(baseURL:context.baseURL),transport:NativeChannelManagementDispatchTransport{request,fence in
   guard fence.isCurrent else{throw APIError.unauthorized};return try await wire.send(request)
  },current:{context},viewer:{1},selectedApproval:{grant});self.service=service
  let captured=try await service.currentChannelContext(channelID:.init("9012"))
  flow=try NativeChannelRoleFlow(captured:captured,channels:service,context:context,transport:wire,storage:store,current:{!grant.revoked},permits:{_,_ in !grant.revoked},unauthorized:{})
 }
 func prepareCreate()->Bool {flow.prepare(.create,target:"",name:"Created",permissions:"0x0",ids:[],reason:"Fixture")}
}
@MainActor private final class RoleZeroStore:ProjectEditDataStorage {
 var values:[String:Data]=[:]
 func read(_ key:String)throws->Data?{values[key]}
 func write(_ data:Data,key:String)throws{values[key]=data}
 func remove(_ key:String)throws{values[key]=nil}
}
@MainActor private final class RoleZeroWire:HTTPTransport {
 var version:Any="0",createdVersion:Any="0",roleID="77",guild="42",roleName="Initial"
 var writes=0,unknown=false,failRoleRead=false,suspendWrite=false
 var requestID="",lastBody:[String:Any]?,result:[String:Any]=[:]
 private var gate:CheckedContinuation<Void,Never>?,started:CheckedContinuation<Void,Never>?
 func waitForWrite()async {if gate != nil{return};await withCheckedContinuation{started=$0}}
 func finishWrite(){gate?.resume();gate=nil}
 func row()->[String:Any] {["id":roleID,"guild_kind":1,"guild_id":guild,"version":version,"name":roleName,"permissions":"0x0","position":5,"status":1,"is_system":0,"managed":0,"is_everyone":0,"hoist":0,"mentionable":0,"color":NSNull()]}
 func response(_ value:[String:Any])throws->(Data,Int){(try JSONSerialization.data(withJSONObject:["code":200,"data":value]),200)}
 func send(_ request:URLRequest)async throws->(Data,Int) {
  let path=request.url!.path
  if path=="/api/channels/9012" {return try response(["id":"9012","guild_kind":1,"guild_id":"42","parent_id":"0","kind":1,"name":"Original","position":0,"is_default":0,"status":0,"version":"1","perm_version":"1","visibility":1,"slowmode_sec":0,"my_permissions_list":["VIEW_CHANNEL","MANAGE_ROLE"]])}
  if path=="/api/im/roles",request.httpMethod=="GET" {
   if failRoleRead{throw APIError.malformedResponse};return try response(["list":[row()],"has_more":false,"my_highest_position":10])
  }
  if (path=="/api/im/roles" && request.httpMethod=="POST") || (path=="/api/im/roles/77" && request.httpMethod=="PATCH") {
   writes+=1;let body=try JSONSerialization.jsonObject(with:request.httpBody!) as! [String:Any];lastBody=body;requestID=body["request_id"] as! String
   version=request.httpMethod=="POST" ? createdVersion:"1";roleName=body["name"] as! String
   result=row();result["request_id"]=requestID;result["state"]="APPLIED";result["audit_id"]="55"
   if suspendWrite{await withCheckedContinuation{gate=$0;started?.resume();started=nil}}
   if unknown{throw URLError(.timedOut)};return try response(result)
  }
  if path=="/api/channel-platform/governance/requests/"+requestID {
   return try response(unknown ? ["request_id":requestID,"state":"UNKNOWN"]:["request_id":requestID,"state":"APPLIED","result":result])
  }
  XCTFail("Unexpected original role route");throw APIError.invalidRequest
 }
}
