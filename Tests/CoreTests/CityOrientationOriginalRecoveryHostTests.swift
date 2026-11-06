import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@available(macOS 14.0, *) @MainActor final class CityOrientationOriginalRecoveryHostTests: XCTestCase {
    let base=URL(string:"https://example.test/city")!
    final class Store {var bytes:[String:Data]=[:];var failWrite=false
        lazy var journal=CityOrientationTaskJournal(read:{self.bytes[$0]},write:{data,key in
            if self.failWrite {throw PlayExperienceError.persistenceUnavailable};self.bytes[key]=data
        })
    }
    final class Wire: HTTPTransport {
        var requests:[URLRequest]=[]
        var reply: (URLRequest) throws -> (Data,Int) = {_ in throw PlayExperienceError.unknownResult}
        func send(_ request:URLRequest) async throws -> (Data,Int) {requests.append(request);return try reply(request)}
    }
    func owner(_ id:Int=7) throws -> PlayExperienceSession {
        try .init(accountID:id,epoch:1,namespace:"synthetic-city",token:"synthetic-token",role:"player")
    }
    func seeded(_ store:Store,session:PlayExperienceSession) throws -> CityOrientationTaskCommand {
        let command=try CityOrientationTaskCommand(sessionID:91,nodeID:701,expectedVersion:4,answer:"A")
        try store.journal.replace(.init(owner:.init(session:session),command:command,receipt:nil,settled:false),expected:nil,
            binding:base.absoluteString+":"+PlayRunStorageKey.make(session:session,scope:.activity(41)))
        return command
    }
    func reply(_ command:CityOrientationTaskCommand,pending:Bool=false) throws -> (Data,Int) {
        let value:[String:Any] = pending ? ["outcome":"PENDING","sessionId":91,"nodeId":701,"requestId":command.requestId] :
            ["contract":"CITY_ORIENTATION_ANSWER_V1","sessionId":91,"nodeId":701,"requestId":command.requestId,
             "payloadHash":command.payloadHash,"configVersion":12,"revision":5,"outcome":"APPLIED",
             "response":["code":200,"data":["nodeId":701]]]
        return (try JSONSerialization.data(withJSONObject:["code":200,"data":value]),200)
    }
    func host(_ store:Store,_ wire:Wire,approved:Bool=true,current:@escaping ()->PlayExperienceSession?) throws -> CityOrientationOriginalRecoveryHost {
        .init(scope:.activity(41),service:.init(configuration:try APIConfiguration(baseURL:base),transport:wire,
            receiptTransport:approved ? wire : nil,answerTransport:nil,receiptSessionID:91,answerSessionID:nil),journal:store.journal,currentSession:current)
    }
    func testMissingReadGrantNeverDispatchesOrClearsPending() async throws {
        let store=Store(),wire=Wire(),session=try owner();_ = try seeded(store,session:session)
        let model=try host(store,wire,approved:false,current:{session});await model.load()
        XCTAssertEqual(model.phase,.approvalRequired);XCTAssertNil(model.visibleReceipt);XCTAssertTrue(wire.requests.isEmpty)
        XCTAssertEqual(try store.journal.pendingSessionID(realm:base,scope:.activity(41),session:session),91)
    }
    func testUnknownOnlyRequeriesExactOriginalAndNeverPosts() async throws {
        let store=Store(),wire=Wire(),session=try owner(),command=try seeded(store,session:session)
        wire.reply={_ in try self.reply(command,pending:true)}
        let model=try host(store,wire,current:{session});await model.load();await model.load()
        XCTAssertEqual(model.phase,.unknown);XCTAssertFalse(model.canAcknowledge)
        XCTAssertEqual(wire.requests.count,2);XCTAssertTrue(wire.requests.allSatisfy{$0.httpMethod=="GET" && $0.url!.query!.contains(command.requestId)})
        XCTAssertEqual(try store.journal.pendingSessionID(realm:base,scope:.activity(41),session:session),91)
    }
    func testRealReceiptIsPersistedThenExplicitlyAcknowledged() async throws {
        let store=Store(),wire=Wire(),session=try owner(),command=try seeded(store,session:session)
        wire.reply={_ in try self.reply(command)}
        let model=try host(store,wire,current:{session});await model.load()
        XCTAssertEqual(model.visibleReceipt?.requestId,command.requestId);XCTAssertTrue(model.canAcknowledge)
        XCTAssertEqual(try store.journal.pendingSessionID(realm:base,scope:.activity(41),session:session),91)
        try model.acknowledge();XCTAssertEqual(model.phase,.settled)
        XCTAssertNil(try store.journal.pendingSessionID(realm:base,scope:.activity(41),session:session));XCTAssertEqual(wire.requests.count,1)
    }
    func testAccountChangeDuringReadCannotProjectOrSettle() async throws {
        let store=Store(),wire=Wire(),session=try owner(),command=try seeded(store,session:session);var current:PlayExperienceSession?=session
        wire.reply={_ in current=nil;return try self.reply(command)}
        let model=try host(store,wire,current:{current});await model.load()
        XCTAssertNil(model.visibleReceipt);XCTAssertFalse(model.canAcknowledge)
        XCTAssertEqual(try store.journal.pendingSessionID(realm:base,scope:.activity(41),session:session),91)
    }
    func testStorageFailurePreservesOriginalWithoutNetwork() async throws {
        let store=Store(),wire=Wire(),session=try owner();_ = try seeded(store,session:session)
        store.bytes=store.bytes.mapValues{_ in Data("corrupt".utf8)}
        let model=try host(store,wire,current:{session});await model.load()
        XCTAssertEqual(model.phase,.unavailable);XCTAssertTrue(wire.requests.isEmpty)
    }
    func testAcknowledgeFailureIsVisibleAndDoesNotSettle() async throws {
        let store=Store(),wire=Wire(),session=try owner(),command=try seeded(store,session:session)
        wire.reply={_ in try self.reply(command)};let model=try host(store,wire,current:{session});await model.load();store.failWrite=true
        XCTAssertThrowsError(try model.acknowledge());XCTAssertEqual(model.issue,.persistenceUnavailable)
        XCTAssertEqual(try store.journal.pendingSessionID(realm:base,scope:.activity(41),session:session),91)
    }
    func testCachedReceiptDoesNotBypassRevokedReadPermission() async throws {
        let store=Store(),wire=Wire(),session=try owner(),command=try seeded(store,session:session)
        wire.reply={_ in try self.reply(command)};let first=try host(store,wire,current:{session});await first.load()
        let next=try host(store,wire,approved:false,current:{session});await next.load()
        XCTAssertNil(next.visibleReceipt);XCTAssertEqual(next.phase,.approvalRequired);XCTAssertEqual(wire.requests.count,1)
    }
}
