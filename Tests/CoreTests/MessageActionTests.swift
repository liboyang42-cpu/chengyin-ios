import Foundation
import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private let messageReceiptJSON = #"{"code":200,"data":{"id":42,"conversationId":9,"senderId":7,"msgType":1,"content":"hello"}}"#
private func messageReceipt() throws -> MessagingMessage {
    struct Wrapper:Decodable { let data:MessagingMessage }
    return try JSONDecoder().decode(Wrapper.self,from:Data(messageReceiptJSON.utf8)).data
}
private final class MessageTransport:HTTPTransport {
    var requests:[URLRequest]=[]
    var json=messageReceiptJSON
    var status=200
    var error:Error?
    func send(_ request:URLRequest) async throws -> (Data,Int) {
        requests.append(request);if let error { throw error };return (Data(json.utf8),status)
    }
}
final class MessageActionServiceTests:XCTestCase {
    private func service(_ transport:MessageTransport) throws -> MessageActionService {
        try MessageActionService(configuration:APIConfiguration(baseURL:URL(string:"https://example.com/prod-api")!),transport:transport)
    }
    func testTextIntentTrimsOnceAndKeepsClientKey() throws {
        let key=String(repeating:"a",count:32)
        let intent=try MessageTextIntent(conversationID:9,content:"  hello\n",clientMessageID:key)
        XCTAssertEqual(intent.content,"hello");XCTAssertEqual(intent.clientMessageID,key)
        XCTAssertThrowsError(try MessageTextIntent(conversationID:0,content:"hello"))
        XCTAssertThrowsError(try MessageTextIntent(conversationID:9,content:" \n"))
        XCTAssertThrowsError(try MessageTextIntent(conversationID:9,content:"hello",clientMessageID:"invalid"))
    }
    func testExactWireAndNoImplicitReadReceipt() async throws {
        let t=MessageTransport();let intent=try MessageTextIntent(conversationID:9,content:"hello")
        let receipt=try await service(t).send(intent,token:"fixture-token")
        XCTAssertEqual(receipt.id,42);XCTAssertEqual(t.requests.count,1)
        let request=try XCTUnwrap(t.requests.first)
        XCTAssertEqual(request.url?.absoluteString,"https://example.com/prod-api/api/im/send")
        XCTAssertEqual(request.httpMethod,"POST");XCTAssertEqual(request.value(forHTTPHeaderField:"Authorization"),"fixture-token")
        let body=String(data:try XCTUnwrap(request.httpBody),encoding:.utf8)!
        for pair in [("conversation_id","9"),("msg_type","1"),("content","hello"),("client_message_id",intent.clientMessageID)] {
            XCTAssertTrue(body.contains("name=\"\(pair.0)\"\r\n\r\n\(pair.1)\r\n"))
        }
        XCTAssertFalse(body.contains("extra_json"))
    }
    func testTimeoutDoesNotRetry() async throws {
        let t=MessageTransport();t.error=URLError(.timedOut)
        do { _=try await service(t).send(MessageTextIntent(conversationID:9,content:"hello"),token:"fixture-token");XCTFail() }
        catch { XCTAssertEqual((error as? URLError)?.code,.timedOut) }
        XCTAssertEqual(t.requests.count,1)
    }
    func testMalformedOrMismatchedReceiptFails() async throws {
        for body in ["{}",messageReceiptJSON.replacingOccurrences(of:"\"conversationId\":9",with:"\"conversationId\":10"),messageReceiptJSON.replacingOccurrences(of:"\"msgType\":1",with:"\"msgType\":2")] {
            let t=MessageTransport();t.json=body
            do { _=try await service(t).send(MessageTextIntent(conversationID:9,content:"hello"),token:"fixture-token");XCTFail() }
            catch { XCTAssertEqual(error as? APIError,.malformedResponse) }
        }
    }
    func testClosedFailureIsTyped() async throws {
        let t=MessageTransport();t.json = #"{"code":409,"errorCode":"HANGOUT_CLOSED"}"#
        do { _=try await service(t).send(MessageTextIntent(conversationID:9,content:"hello"),token:"fixture-token");XCTFail() }
        catch { XCTAssertTrue((error as? MessagingReadFailure)?.isClosed == true) }
    }
    func testInvalidTokenSendsNothing() async throws {
        let t=MessageTransport()
        do { _=try await service(t).send(MessageTextIntent(conversationID:9,content:"hello"),token:"bad\r\nheader");XCTFail() } catch {}
        XCTAssertTrue(t.requests.isEmpty)
    }
}

@MainActor private final class MessageWriter:MessageActionWriting {
    var isConfigured=true
    var identity:MessagingReadIdentity? = .init(accountID:7,epoch:1)
    var intents:[MessageTextIntent]=[]
    var error:Error?
    var suspended=false
    private var continuation:CheckedContinuation<MessagingMessage,Error>?
    private var started:CheckedContinuation<Void,Never>?
    func waitStarted() async { if intents.isEmpty { await withCheckedContinuation { started=$0 } } }
    func resolve() throws { continuation?.resume(returning:try messageReceipt());continuation=nil }
    func send(_ intent:MessageTextIntent,expectedIdentity:MessagingReadIdentity) async throws -> MessagingMessage {
        intents.append(intent);started?.resume();started=nil
        if suspended { return try await withCheckedThrowingContinuation { continuation=$0 } }
        if let error { throw error };return try messageReceipt()
    }
}
@MainActor final class MessageActionCoordinatorTests:XCTestCase {
    private let identity=MessagingReadIdentity(accountID:7,epoch:1)
    func testDuplicateTapWhileSuspendedSendsOnce() async throws {
        let writer=MessageWriter();writer.suspended=true
        let flow=MessageActionCoordinator(accountID:7,conversationID:9,writer:writer)
        let task=Task { await flow.sendNew("hello",conversationReady:true,expectedIdentity:identity) }
        await writer.waitStarted()
        let duplicate=await flow.sendNew("hello",conversationReady:true,expectedIdentity:identity)
        XCTAssertFalse(duplicate);XCTAssertEqual(writer.intents.count,1)
        try writer.resolve();let result=await task.value;XCTAssertTrue(result)
    }
    func testUnknownOutcomeBlocksReplacementAndExplicitRetryKeepsIntent() async throws {
        let writer=MessageWriter();writer.error=URLError(.timedOut)
        let flow=MessageActionCoordinator(accountID:7,conversationID:9,writer:writer)
        _=await flow.sendNew("hello",conversationReady:true,expectedIdentity:identity)
        XCTAssertEqual(flow.visibleState,.outcomeUnknown)
        let replacement=await flow.sendNew("different",conversationReady:true,expectedIdentity:identity)
        XCTAssertFalse(replacement);XCTAssertEqual(writer.intents.count,1)
        writer.error=nil;let retry=await flow.retry(conversationReady:true,expectedIdentity:identity)
        XCTAssertTrue(retry);XCTAssertEqual(writer.intents[0],writer.intents[1])
    }
    func testStaleReadyIdentityAndUnreadyHistoryCannotSend() async {
        let writer=MessageWriter();let flow=MessageActionCoordinator(accountID:7,conversationID:9,writer:writer)
        writer.identity = .init(accountID:7,epoch:2)
        let stale=await flow.sendNew("hello",conversationReady:true,expectedIdentity:identity)
        let unready=await flow.sendNew("hello",conversationReady:false,expectedIdentity:writer.identity!)
        XCTAssertFalse(stale);XCTAssertFalse(unready);XCTAssertTrue(writer.intents.isEmpty)
    }
    func testAccountChangeHidesPendingAndRejectsLateReceipt() async throws {
        let writer=MessageWriter();writer.suspended=true
        let flow=MessageActionCoordinator(accountID:7,conversationID:9,writer:writer)
        let task=Task { await flow.sendNew("hello",conversationReady:true,expectedIdentity:identity) }
        await writer.waitStarted();writer.identity = .init(accountID:8,epoch:2)
        XCTAssertNil(flow.pendingText);XCTAssertEqual(flow.visibleState,.idle)
        try writer.resolve();let result=await task.value;XCTAssertFalse(result)
        writer.identity = .init(accountID:7,epoch:3)
        XCTAssertEqual(flow.visibleState,.outcomeUnknown);XCTAssertEqual(flow.pendingText,"hello")
    }
    func testClosedConversationDoesNotRetry() async {
        let writer=MessageWriter();writer.error=MessagingReadFailure(code:409,errorCode:"HANGOUT_CLOSED")
        let flow=MessageActionCoordinator(accountID:7,conversationID:9,writer:writer)
        _=await flow.sendNew("hello",conversationReady:true,expectedIdentity:identity)
        XCTAssertEqual(flow.visibleState,.closed)
        let retry=await flow.retry(conversationReady:true,expectedIdentity:identity)
        XCTAssertFalse(retry);XCTAssertEqual(writer.intents.count,1)
    }
}
