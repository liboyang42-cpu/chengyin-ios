import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore
@MainActor final class NativeChannelAppealDetailsTests:XCTestCase {
    func testOriginalTextJSONSupplementsAndServerTimesArePreserved() {
        let value=NativeChannelAppealDetails(source:["reason_text":" 原说明 ","submitted_at":"server time","decided_at":"decision time","evidence_count":2,
          "evidence_json":["text":"初次材料"],"supplements":[#"{"text":" 追加材料 "}"#],"timeline":[["event":"APPEAL_SUBMITTED","at":"original time","reason":"原文"]]])
        XCTAssertEqual(value.reason," 原说明 ");XCTAssertEqual(value.submittedAt,"server time");XCTAssertEqual(value.decidedAt,"decision time")
        XCTAssertEqual(value.evidence.map(\.text),["初次材料"," 追加材料 "]);XCTAssertEqual(value.timeline.first?.event,"APPEAL_SUBMITTED")
        XCTAssertEqual(value.evidenceCount,2);XCTAssertFalse(value.evidenceUnavailable)
    }
    func testNoRawSnapshotOrMediaURLsAreProjectedAsEvidenceText() {
        let value=NativeChannelAppealDetails(source:["evidence_json":["url":"https://private.invalid/file","context":["secret":"hidden"]],"supplements":[#"{"media":["private"]}"#],"timeline":[]])
        XCTAssertEqual(value.evidence.count,2);XCTAssertTrue(value.evidence.allSatisfy{$0.text==nil})
    }
    func testMessageReferencesAndAttachmentCountsDoNotBecomeNavigationOrURLs() {
        let value=NativeChannelAppealDetails(source:["evidence_json":["message_ids":[88101,"88102"],"screenshot_urls":["https://private.invalid/image"]],"supplements":[],"timeline":[]])
        XCTAssertEqual(value.evidence.first?.messageIDs,["88101","88102"]);XCTAssertEqual(value.evidence.first?.attachmentCount,1)
        XCTAssertNil(value.evidence.first?.text)
    }
    func testMissingAndMalformedRemainUnknownRatherThanEmptySuccess() {
        let value=NativeChannelAppealDetails(source:["evidence_count":true,"submitted_at":123,"supplements":"broken","timeline":"broken"])
        XCTAssertNil(value.evidenceCount);XCTAssertNil(value.submittedAt);XCTAssertTrue(value.evidenceUnavailable);XCTAssertTrue(value.timelineUnavailable)
        XCTAssertTrue(NativeChannelAppealDetails(source:[:]).evidenceUnavailable)
    }
    func testExplicitEmptyCollectionsAndNullInitialEvidenceAreRespected() {
        let value=NativeChannelAppealDetails(source:["evidence_json":NSNull(),"evidence_count":0,"supplements":[],"timeline":[]])
        XCTAssertTrue(value.evidence.isEmpty);XCTAssertFalse(value.evidenceUnavailable);XCTAssertTrue(value.timeline.isEmpty);XCTAssertFalse(value.timelineUnavailable)
    }
    func testUnknownTimelineEventAndOriginalOrderAreNotRewritten() {
        let value=NativeChannelAppealDetails(source:["timeline":[["event":"FUTURE_EVENT","at":"z"],["event":"APPEAL_SUBMITTED","at":"a"]]])
        XCTAssertEqual(value.timeline.map(\.event),["FUTURE_EVENT","APPEAL_SUBMITTED"]);XCTAssertEqual(value.timeline.map(\.at),["z","a"])
    }
    private func flow(_ wire:AppealDetailsWire,_ storage:AppealDetailsStore, current:@escaping ()->Bool={true}) throws -> NativeChannelAppealFlow {
        let context=RuntimeDependencyContext(market:.china,baseURL:URL(string:"https://example.test/")!,role:"player",session:try PlayExperienceSession(accountID:17,epoch:3,namespace:"fixture",token:"not-live"))
        let notice=NativeChannelGovernanceNotice(messageID:1,conversationID:2,recipientID:17,actionID:"51",guildKind:1,guildID:"42")
        return try NativeChannelAppealFlow(notice:notice,context:context,transport:wire,storage:storage,current:current,permits:{_,_ in true},unauthorized:{})
    }
    func testNormalCurrentShowsPreviouslySubmittedMaterialsAndReturnRefreshes() async throws {
        let wire=AppealDetailsWire(),store=AppealDetailsStore();let model=try flow(wire,store)
        await model.activate();XCTAssertEqual(model.appealDetails?.reason,"original reason");XCTAssertEqual(model.appealDetails?.evidence.first?.text,"original text")
        model.deactivate();XCTAssertNil(model.appealDetails);wire.reason="updated current";await model.activate()
        XCTAssertEqual(model.appealDetails?.reason,"updated current");XCTAssertEqual(wire.posts,0)
    }
    func testOriginalEvidenceWriterReceiptThenIndependentCurrentDisplaysNewMaterial() async throws {
        let wire=AppealDetailsWire(),store=AppealDetailsStore();let model=try flow(wire,store)
        await model.activate();XCTAssertTrue(model.prepare(.evidence,text:"new evidence"));await model.confirm()
        XCTAssertEqual(wire.posts,1);XCTAssertFalse(model.hasPending);XCTAssertTrue(store.values.isEmpty)
        XCTAssertEqual(model.appealDetails?.evidence.last?.text,"new evidence");XCTAssertEqual(model.appealDetails?.reason,"current after write")
        XCTAssertNotEqual(model.appealDetails?.reason,"historical receipt reason")
    }
    func testOriginalWithdrawalReturnsServerWithdrawalTimeAndCurrentState() async throws {
        let wire=AppealDetailsWire(),store=AppealDetailsStore();let model=try flow(wire,store)
        await model.activate();XCTAssertTrue(model.prepare(.withdraw,text:"withdraw reason"));await model.confirm()
        XCTAssertEqual(wire.posts,1);XCTAssertEqual(model.appealStatus,"WITHDRAWN");XCTAssertEqual(model.appealDetails?.withdrawnAt,"server-withdraw-time")
        XCTAssertFalse(model.canWithdraw);XCTAssertFalse(model.hasPending)
    }
    func testReceiptConfirmedButCurrentFailedDoesNotShowReceiptAsCurrentOrResend() async throws {
        let wire=AppealDetailsWire(),store=AppealDetailsStore();let model=try flow(wire,store)
        await model.activate();wire.failCurrentAfterWrite=true;XCTAssertTrue(model.prepare(.evidence,text:"new evidence"));await model.confirm()
        XCTAssertEqual(model.state,.applied);XCTAssertTrue(model.currentReadFailed);XCTAssertNil(model.appealDetails);XCTAssertEqual(wire.posts,1);XCTAssertFalse(model.hasPending)
    }
    func testUnknownRestartUsesOriginalReceiptWithoutAnotherPost() async throws {
        let wire=AppealDetailsWire(),store=AppealDetailsStore();let first=try flow(wire,store)
        await first.activate();wire.losePostResponse=true;XCTAssertTrue(first.prepare(.evidence,text:"new evidence"));await first.confirm()
        XCTAssertTrue(first.hasPending);XCTAssertNil(first.appealDetails);XCTAssertFalse(store.values.isEmpty);first.deactivate()
        let restarted=try flow(wire,store);await restarted.activate()
        XCTAssertEqual(wire.posts,1);XCTAssertFalse(restarted.hasPending);XCTAssertEqual(restarted.appealDetails?.evidence.last?.text,"new evidence")
    }
    func testWrongAppellantOrActionNeverPublishesMaterials() async throws {
        for field in ["appellant_member_id","action_id"] {
            let wire=AppealDetailsWire();wire.wrongField=field;let model=try flow(wire,AppealDetailsStore());await model.activate()
            XCTAssertNil(model.appealDetails);XCTAssertFalse(model.canSupplement)
        }
    }
    func testBackgroundAndChangedAccountHideDetailsWithoutDeletingOriginalLog() async throws {
        let wire=AppealDetailsWire(),store=AppealDetailsStore();var current=true;let model=try flow(wire,store,current:{current})
        await model.activate();XCTAssertNotNil(model.appealDetails);current=false;XCTAssertNil(model.appealDetails)
        model.deactivate();XCTAssertNil(model.appealDetails);XCTAssertEqual(wire.posts,0)
    }
}
@MainActor private final class AppealDetailsStore:ProjectEditDataStorage {
 var values:[String:Data]=[:]
 func read(_ key:String)throws->Data?{values[key]}
 func write(_ value:Data,key:String)throws{values[key]=value}
 func remove(_ key:String)throws{values[key]=nil}
}
@MainActor private final class AppealDetailsWire:HTTPTransport {
 var posts=0,reason="original reason",wrongField:String?,losePostResponse=false,failCurrentAfterWrite=false
 var supplementary:String?,receipt:[String:Any]?
 var withdrawn=false
 func detail()->[String:Any] {
  var row:[String:Any]=["appeal_id":"61","action_id":"51","appellant_member_id":"17","status":withdrawn ? "WITHDRAWN":"PENDING","can_add_evidence":supplementary==nil && !withdrawn ? 1:0,
    "reason_text":reason,"submitted_at":"server-submit-time","evidence_json":["text":"original text"],"evidence_count":supplementary==nil ? 1:2,
    "supplements":supplementary.map{[String(data:try! JSONSerialization.data(withJSONObject:["text":$0]),encoding:.utf8)!]} ?? [],
    "timeline":[["event":"APPEAL_SUBMITTED","at":"server-time","reason":"original reason"]]]
  if withdrawn {row["withdrawn_at"]="server-withdraw-time"};if let wrongField {row[wrongField]="999"};return row
 }
 func send(_ request:URLRequest) async throws -> (Data,Int) {
  let path=request.url!.path;var value:[String:Any]
  if request.httpMethod=="POST" {
   posts+=1;let body=try JSONSerialization.jsonObject(with:request.httpBody!) as! [String:Any]
   if path.hasSuffix("/withdraw"){withdrawn=true}else{supplementary=(body["evidence_json"] as? [String:Any])?["text"] as? String};reason="current after write"
   var original=detail();original["request_id"]=body["request_id"];original["state"]="APPLIED";original["reason_text"]="historical receipt reason";receipt=original
   if losePostResponse{throw APIError.malformedResponse};value=original
  } else if path.contains("/requests/") {value=["state":"APPLIED","result":receipt!]}
  else if path.hasSuffix("/moderation/me") {value=["list":[["action_id":"51","guild_kind":1,"guild_id":"42","target_member_id":"17","existing_appeal_id":"61","appealable":0]]]}
  else if path=="/api/im/appeals/61" {if failCurrentAfterWrite && posts>0{throw APIError.malformedResponse};value=detail()}
  else {XCTFail("Unexpected original route: \(path)");throw APIError.invalidRequest}
  return (try JSONSerialization.data(withJSONObject:["code":200,"data":value]),200)
 }
}
