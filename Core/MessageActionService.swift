import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct MessageTextIntent: Equatable {
    public let conversationID: Int
    public let content: String
    public let clientMessageID: String
    public init(conversationID:Int,content:String,clientMessageID:String=UUID().uuidString.replacingOccurrences(of:"-",with:"").lowercased()) throws {
        let text=content.trimmingCharacters(in:.whitespacesAndNewlines)
        guard conversationID>0,!text.isEmpty,clientMessageID.count==32,
              clientMessageID.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { throw APIError.invalidRequest }
        self.conversationID=conversationID;self.content=text;self.clientMessageID=clientMessageID
    }
}

/// One explicit request. Preserves the caller's immutable message ID; no automatic retry.
public struct MessageActionService {
    private let configuration:APIConfiguration
    private let transport:any HTTPTransport
    public init(configuration:APIConfiguration,transport:any HTTPTransport) { self.configuration=configuration;self.transport=transport }
    public func send(_ intent:MessageTextIntent,token:String) async throws -> MessagingMessage {
        guard AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        try Task.checkCancellation()
        let request=try AuthRequestBuilder.makeFormRequest(url:configuration.baseURL.appendingPathComponent("api/im/send"),fields:[
            "conversation_id":String(intent.conversationID),"msg_type":"1","content":intent.content,"client_message_id":intent.clientMessageID
        ],token:token)
        let (data,status)=try await transport.send(request)
        try Task.checkCancellation()
        let header=try? JSONDecoder().decode(Header.self,from:data)
        guard (200..<300).contains(status) else {
            throw MessagingReadFailure(httpStatus:status,code:header?.code,errorCode:header?.errorCode,message:header?.msg)
        }
        guard let header else { throw APIError.malformedResponse }
        guard header.code==200 else { throw MessagingReadFailure(code:header.code,errorCode:header.errorCode,message:header.msg) }
        let receipt:Receipt
        do { receipt=try JSONDecoder().decode(Receipt.self,from:data) } catch { throw APIError.malformedResponse }
        guard receipt.data.conversationID==intent.conversationID,receipt.data.type==1,
              receipt.data.content==intent.content else { throw APIError.malformedResponse }
        return receipt.data
    }
    private struct Header:Decodable { let code:Int;let errorCode:String?;let msg:String? }
    private struct Receipt:Decodable { let data:MessagingMessage }
}

public struct MessageActionSession: Equatable {
    public let identity:MessagingReadIdentity
    fileprivate let token:String
    public init(accountID:Int,epoch:UInt64,token:String) throws {
        guard accountID>0,AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        identity=MessagingReadIdentity(accountID:accountID,epoch:epoch);self.token=token
    }
}

@MainActor public protocol MessageActionWriting:AnyObject {
    var isConfigured:Bool { get }
    var identity:MessagingReadIdentity? { get }
    func send(_ intent:MessageTextIntent,expectedIdentity:MessagingReadIdentity) async throws -> MessagingMessage
}

@MainActor public final class MessageSessionWriter:MessageActionWriting {
    private let service:MessageActionService?
    private let currentSession:()->MessageActionSession?
    private let onUnauthorized:(MessageActionSession)->Void
    public var isConfigured:Bool { service != nil }
    public var identity:MessagingReadIdentity? { currentSession()?.identity }
    public init(service:MessageActionService?,currentSession:@escaping ()->MessageActionSession?,onUnauthorized:@escaping (MessageActionSession)->Void={_ in}) {
        self.service=service;self.currentSession=currentSession;self.onUnauthorized=onUnauthorized
    }
    public func send(_ intent:MessageTextIntent,expectedIdentity:MessagingReadIdentity) async throws -> MessagingMessage {
        guard let service else { throw APIError.notConfigured }
        guard let snapshot=currentSession(),snapshot.identity==expectedIdentity else { throw APIError.unauthorized }
        do {
            let receipt=try await service.send(intent,token:snapshot.token)
            guard !Task.isCancelled,currentSession()==snapshot else { throw CancellationError() }
            guard receipt.senderID==snapshot.identity.accountID else { throw APIError.malformedResponse }
            return receipt
        } catch {
            guard !Task.isCancelled,currentSession()==snapshot else { throw CancellationError() }
            if (error as? MessagingReadFailure)?.isUnauthorized==true { onUnauthorized(snapshot) }
            throw error
        }
    }
}
