import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Exact source paths, multipart fields and receipt envelopes from im_api.dart.
/// Injectable only. Production composition must supply a bounded no-redirect transport.
public struct IMExpandedService {
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    public let approvedMediaOrigins: Set<String>
    public let staticLocationEnabled: Bool
    public let staticLocationReceiptEnabled: Bool
    public let routeShareReadEnabled: Bool
    public let routeSendEnabled: Bool
    public let routeReceiptEnabled: Bool
    public let videoSendEnabled: Bool
    public let videoReceiptEnabled: Bool
    public let fileSendEnabled: Bool
    public let fileReceiptEnabled: Bool
    public let voiceSendEnabled: Bool
    public let voiceReceiptEnabled: Bool
    public let imageUploadReceiptEnabled: Bool
    public let ordinaryReadRequestEnabled: Bool
    public let ordinaryReadReceiptEnabled: Bool
    public let ordinaryReadStateEnabled: Bool
    public var canWriteOrdinaryRead: Bool { writesEnabled && ordinaryReadRequestEnabled && (enabledPaths?.contains("api/im/read") ?? false) }
    public let ordinaryMuteRequestEnabled: Bool
    public let ordinaryMuteReceiptEnabled: Bool
    public let ordinaryMuteStateEnabled: Bool
    public var canWriteOrdinaryMute: Bool { writesEnabled && ordinaryMuteRequestEnabled && (enabledPaths?.contains("api/im/mute") ?? false) }
    public let ordinaryReceiptEnabled: Bool
    private let ordinarySendEnabled: Bool
    private let writesEnabled: Bool
    private let enabledPaths: Set<String>?
    public var isConfigured: Bool { writesEnabled }
    public var canSendOrdinaryImage: Bool { writesEnabled && ordinarySendEnabled && (enabledPaths?.contains("api/im/send") ?? true) }
    public init(configuration: APIConfiguration, transport: any HTTPTransport, approvedMediaOrigins: Set<String>, writesEnabled: Bool = false, enabledPaths: Set<String>? = nil, staticLocationEnabled: Bool = false, staticLocationReceiptEnabled: Bool = false, ordinarySendEnabled: Bool = true, ordinaryReceiptEnabled: Bool = false, imageUploadReceiptEnabled: Bool = false, routeShareReadEnabled: Bool = false, routeSendEnabled: Bool? = nil, routeReceiptEnabled: Bool = false, voiceSendEnabled: Bool = false, voiceReceiptEnabled: Bool = false, fileSendEnabled: Bool = false, fileReceiptEnabled: Bool = false, videoSendEnabled: Bool = false, videoReceiptEnabled: Bool = false, ordinaryMuteRequestEnabled: Bool = false, ordinaryMuteReceiptEnabled: Bool = false, ordinaryMuteStateEnabled: Bool = false, ordinaryReadRequestEnabled: Bool = false, ordinaryReadReceiptEnabled: Bool = false, ordinaryReadStateEnabled: Bool = false) {
        self.ordinaryReadRequestEnabled = ordinaryReadRequestEnabled; self.ordinaryReadReceiptEnabled = ordinaryReadReceiptEnabled; self.ordinaryReadStateEnabled = ordinaryReadStateEnabled
        self.ordinaryMuteRequestEnabled = ordinaryMuteRequestEnabled; self.ordinaryMuteReceiptEnabled = ordinaryMuteReceiptEnabled; self.ordinaryMuteStateEnabled = ordinaryMuteStateEnabled
        self.configuration = configuration; self.transport = transport; self.approvedMediaOrigins = approvedMediaOrigins; self.writesEnabled = writesEnabled; self.enabledPaths = enabledPaths; self.staticLocationEnabled=staticLocationEnabled; self.staticLocationReceiptEnabled=staticLocationReceiptEnabled; self.ordinarySendEnabled=ordinarySendEnabled;self.ordinaryReceiptEnabled=ordinaryReceiptEnabled;self.imageUploadReceiptEnabled=imageUploadReceiptEnabled;self.routeShareReadEnabled=routeShareReadEnabled;self.routeSendEnabled=routeSendEnabled ?? writesEnabled;self.routeReceiptEnabled=routeReceiptEnabled; self.videoSendEnabled=videoSendEnabled;self.videoReceiptEnabled=videoReceiptEnabled;self.fileSendEnabled=fileSendEnabled;self.fileReceiptEnabled=fileReceiptEnabled;self.voiceSendEnabled=voiceSendEnabled; self.voiceReceiptEnabled=voiceReceiptEnabled
    }
    public func perform(_ mutation: IMMutation, token: String) async throws -> IMMutationReceipt {
        guard writesEnabled else { throw APIError.notConfigured }
        let path: String
        var fields: [String: String]
        switch mutation {
        case .start(let id):
            guard id > 0 else { throw APIError.invalidRequest }; path = "start"; fields = ["target_member_id": String(id)]
        case .read(let id):
            guard id > 0 else { throw APIError.invalidRequest }; path = "read"; fields = ["conversation_id": String(id)]
        case .readCursor(let id, let last, let requestID):
            guard id > 0, last >= 0, MessageContainerOriginalAck.isRequestID(requestID) else { throw APIError.invalidRequest }
            path = "read"
            fields = ["conversation_id": String(id), "last_message_id": String(last), "request_id": requestID]
        case .mute(let id, let muted):
            guard id > 0 else { throw APIError.invalidRequest }; path = "mute"; fields = ["conversation_id": String(id), "muted": muted ? "1" : "0"]
        case .send(let intent):
            if case .voice = intent.payload {
                guard voiceSendEnabled else { throw APIError.notConfigured }
            } else if case .file = intent.payload {
                guard fileSendEnabled else { throw APIError.notConfigured }
            } else if case .video = intent.payload {
                guard videoSendEnabled else { throw APIError.notConfigured }
            } else if case .staticLocation = intent.payload {
                guard staticLocationEnabled else { throw APIError.notConfigured }
            } else if case .route = intent.payload {
                guard routeSendEnabled else { throw APIError.notConfigured }
            } else { guard ordinarySendEnabled else { throw APIError.notConfigured } }
            path = "send"; fields = try intent.payload.wireFields(approvedOrigins: approvedMediaOrigins)
            fields["conversation_id"] = String(intent.scope.conversationID); fields["client_message_id"] = intent.clientMessageID
        }
        guard enabledPaths?.contains("api/im/\(path)") ?? true else { throw APIError.notConfigured }
        let request = try AuthRequestBuilder.makeFormRequest(url: configuration.baseURL.appendingPathComponent("api/im/\(path)"), fields: fields, token: token)
        let data = try await response(request)
        switch mutation {
        case .start:
            struct Receipt: Decodable { struct Body: Decodable { let conversationId: Int }; let data: Body }
            guard let receipt = try? JSONDecoder().decode(Receipt.self, from: data), receipt.data.conversationId > 0 else { throw APIError.malformedResponse }
            return .started(conversationID: receipt.data.conversationId)
        case .read: return .read
        case .readCursor(let id, let last, let requestID):
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let payload = object?["data"] as? [String: Any] else { throw APIError.malformedResponse }
            let receipt = try MessageContainerOriginalAck().receiptFromOriginalBody(payload, channelID: Int64(id), requestID: requestID)
            guard receipt.status == "APPLIED", !receipt.resumeSameRequest, last >= 0 else { throw IMCapabilityGap.unknownOutcome }
            return .read
        case .mute(_, let muted): return .muted(muted)
        case .send(let intent):
            struct Receipt: Decodable { let data: MessagingMessage }
            struct IdentityReceipt: Decodable { struct Body: Decodable { let clientMessageId: String }; let data: Body }
            guard let message = try? JSONDecoder().decode(Receipt.self, from: data).data,
                  let identity = try? JSONDecoder().decode(IdentityReceipt.self, from: data).data,
                  identity.clientMessageId.utf8.elementsEqual(intent.clientMessageID.utf8),
                  message.conversationID == intent.scope.conversationID, message.senderID == intent.scope.identity.accountID,
                  String(message.type ?? 0) == fields["msg_type"] else { throw APIError.malformedResponse }
            if case .voice(let reference)=intent.payload {
                guard IMVoiceReference.read(message) == reference else { throw APIError.malformedResponse }
            } else if case .file(let reference)=intent.payload {
                guard IMFileReference.read(message) == reference else { throw APIError.malformedResponse }
            } else if case .video(let reference)=intent.payload {
                guard IMVideoReference.read(message) == reference else { throw APIError.malformedResponse }
            } else if case .staticLocation(let place)=intent.payload {
                guard IMStaticLocation.read(message) == place else { throw APIError.malformedResponse }
            } else if case .route = intent.payload {
                guard matchesSent(message, intent: intent, fields: fields) else { throw APIError.malformedResponse }
            } else {
                guard message.content == fields["content"], message.extraJSON == fields["extra_json"] else { throw APIError.malformedResponse }
            }
            return .sent(message)
        }
    }
    public func readSent(_ intent: IMOutgoingIntent, token: String) async throws -> MessagingMessage? {
        // These new media paths use their independently granted original readers.
        switch intent.payload {
        case .voice, .file, .video, .staticLocation: throw APIError.notConfigured
        default: break
        }
        guard writesEnabled, AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        if let enabledPaths, !enabledPaths.contains("api/im/send-receipt") { return nil }
        let request = try AuthRequestBuilder.makeFormRequest(
            url: configuration.baseURL.appendingPathComponent("api/im/send-receipt"),
            fields: ["conversation_id": String(intent.scope.conversationID), "client_message_id": intent.clientMessageID],
            token: token)
        let data = try await response(request)
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (object["code"] as? Int) == 200,
              let payload = object["data"] as? [String: Any],
              let found = payload["found"] as? Bool else { throw APIError.malformedResponse }
        guard found else { return nil }
        let fields = try intent.payload.wireFields(approvedOrigins: approvedMediaOrigins)
        guard let raw = payload["message"] as? [String: Any],
              raw["clientMessageId"] as? String == intent.clientMessageID,
              let messageData = try? JSONSerialization.data(withJSONObject: raw),
              let message = try? JSONDecoder().decode(MessagingMessage.self, from: messageData),
              matchesSent(message, intent: intent, fields: fields) else { throw APIError.malformedResponse }
        return message
    }
    private func matchesSent(_ message: MessagingMessage, intent: IMOutgoingIntent, fields: [String: String]) -> Bool {
        guard message.conversationID == intent.scope.conversationID,
              message.senderID == intent.scope.identity.accountID else { return false }
        if case .route(let topicID) = intent.payload {
            guard message.type == 3,
                  let extra = message.extraJSON?.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: extra) as? [String: Any],
                  object["cardType"] as? String == "route" else { return false }
            let returned = object["topicId"] as? Int ?? (object["topicId"] as? NSNumber)?.intValue
            guard returned == topicID else { return false }
            return message.content == "路线已不可用" || message.content?.hasPrefix("[路线] ") == true
        }
        return String(message.type ?? 0) == fields["msg_type"]
            && message.content == fields["content"]
            && message.extraJSON == fields["extra_json"]
    }
    public func recoverOrdinaryImage(_ intent: IMOutgoingIntent, token: String) async throws -> OrdinaryIMSendReceiptResult {
        guard ordinaryReceiptEnabled, enabledPaths?.contains("api/im/send-receipt") ?? true,
              case .image = intent.payload else { throw APIError.notConfigured }
        return try await OrdinaryIMSendReceipt(configuration: configuration, transport: transport).readImage(intent, token: token)
    }
    public func routeShareSource(topicID:Int,token:String) async throws -> IMRouteShareSource {
        guard routeShareReadEnabled,topicID>0 else { throw APIError.notConfigured }
        let request=try AuthRequestBuilder.makeFormRequest(url:configuration.baseURL.appendingPathComponent("api/im/route-share-source"),
            fields:["topic_id":String(topicID)],token:token)
        struct Envelope:Decodable { let data:IMRouteShareSource }
        let data=try await response(request)
        let source=try JSONDecoder().decode(Envelope.self,from:data).data
        guard source.topicID==topicID else { throw APIError.malformedResponse };return source
    }
    public func recoverRoute(_ intent:IMOutgoingIntent,token:String) async throws -> MessagingMessage? {
        guard routeReceiptEnabled,case .route=intent.payload else { throw APIError.notConfigured }
        let request=try AuthRequestBuilder.makeFormRequest(url:configuration.baseURL.appendingPathComponent("api/im/send-receipt"),
            fields:["conversation_id":String(intent.scope.conversationID),"client_message_id":intent.clientMessageID],token:token)
        let data=try await response(request)
        struct Envelope:Decodable { struct Body:Decodable { let found:Bool;let message:MessagingMessage? };let data:Body }
        let body=try JSONDecoder().decode(Envelope.self,from:data).data
        guard body.found else { return nil }
        struct Identity:Decodable { struct Body:Decodable { struct Message:Decodable { let clientMessageId:String };let message:Message? };let data:Body }
        guard let message=body.message,let key=try JSONDecoder().decode(Identity.self,from:data).data.message?.clientMessageId,
              key==intent.clientMessageID,intent.matchesOriginalRouteMessage(message) else { throw APIError.malformedResponse }
        return message
    }
    /// Same original request lookup, never a new sender or a fabricated text/facade proof.
    public func recoverStaticLocation(_ intent: IMOutgoingIntent, token: String) async throws -> MessagingMessage? {
        guard staticLocationReceiptEnabled, case .staticLocation(let place)=intent.payload else { throw APIError.notConfigured }
        let request=try AuthRequestBuilder.makeFormRequest(url:configuration.baseURL.appendingPathComponent("api/im/send-receipt"),
            fields:["conversation_id":String(intent.scope.conversationID),"client_message_id":intent.clientMessageID],token:token)
        let data=try await response(request)
        struct Envelope: Decodable { struct Body: Decodable { let found: Bool; let message: MessagingMessage? }; let data: Body }
        let body=try JSONDecoder().decode(Envelope.self,from:data).data
        guard body.found else { return nil } // NOT_FOUND never rotates the key or authorizes resending.
        struct Identity: Decodable { struct Body: Decodable { struct Message: Decodable { let clientMessageId: String };let message: Message? };let data: Body }
        guard let message=body.message,let key=try JSONDecoder().decode(Identity.self,from:data).data.message?.clientMessageId,
              key == intent.clientMessageID,message.senderID == intent.scope.identity.accountID,
              message.conversationID == intent.scope.conversationID,IMStaticLocation.read(message) == place else { throw APIError.malformedResponse }
        return message
    }
    public func recoverVoice(_ intent: IMOutgoingIntent, token: String) async throws -> MessagingMessage? {
        guard voiceReceiptEnabled, case .voice(let reference)=intent.payload else { throw APIError.notConfigured }
        let request=try AuthRequestBuilder.makeFormRequest(url:configuration.baseURL.appendingPathComponent("api/im/send-receipt"),
            fields:["conversation_id":String(intent.scope.conversationID),"client_message_id":intent.clientMessageID],token:token)
        let data=try await response(request)
        struct Envelope: Decodable { struct Body: Decodable { let found: Bool; let message: MessagingMessage? }; let data: Body }
        let body=try JSONDecoder().decode(Envelope.self,from:data).data
        guard body.found else { return nil } // NOT_FOUND never rotates the key or authorizes resending.
        struct Identity: Decodable { struct Body: Decodable { struct Message: Decodable { let clientMessageId: String };let message: Message? };let data: Body }
        guard let message=body.message,let key=try JSONDecoder().decode(Identity.self,from:data).data.message?.clientMessageId,
              key == intent.clientMessageID,message.senderID == intent.scope.identity.accountID,
              message.conversationID == intent.scope.conversationID,IMVoiceReference.read(message) == reference else { throw APIError.malformedResponse }
        return message
    }
    public func recoverFile(_ intent: IMOutgoingIntent, token: String) async throws -> MessagingMessage? {
        guard fileReceiptEnabled, case .file(let reference)=intent.payload else { throw APIError.notConfigured }
        let request=try AuthRequestBuilder.makeFormRequest(url:configuration.baseURL.appendingPathComponent("api/im/send-receipt"),
            fields:["conversation_id":String(intent.scope.conversationID),"client_message_id":intent.clientMessageID],token:token)
        let data=try await response(request)
        struct Envelope: Decodable { struct Body: Decodable { let found: Bool; let message: MessagingMessage? }; let data: Body }
        let body=try JSONDecoder().decode(Envelope.self,from:data).data
        guard body.found else { return nil } // NOT_FOUND never rotates the key or authorizes resending.
        struct Identity: Decodable { struct Body: Decodable { struct Message: Decodable { let clientMessageId: String };let message: Message? };let data: Body }
        guard let message=body.message,let key=try JSONDecoder().decode(Identity.self,from:data).data.message?.clientMessageId,
              key == intent.clientMessageID,message.senderID == intent.scope.identity.accountID,
              message.conversationID == intent.scope.conversationID,IMFileReference.read(message) == reference else { throw APIError.malformedResponse }
        return message
    }
    public func recoverVideo(_ intent: IMOutgoingIntent, token: String) async throws -> MessagingMessage? {
        guard videoReceiptEnabled, case .video(let reference)=intent.payload else { throw APIError.notConfigured }
        let request=try AuthRequestBuilder.makeFormRequest(url:configuration.baseURL.appendingPathComponent("api/im/send-receipt"),
            fields:["conversation_id":String(intent.scope.conversationID),"client_message_id":intent.clientMessageID],token:token)
        let data=try await response(request)
        struct Envelope: Decodable { struct Body: Decodable { let found: Bool; let message: MessagingMessage? }; let data: Body }
        let body=try JSONDecoder().decode(Envelope.self,from:data).data
        guard body.found else { return nil } // NOT_FOUND never rotates the key or authorizes resending.
        struct Identity: Decodable { struct Body: Decodable { struct Message: Decodable { let clientMessageId: String };let message: Message? };let data: Body }
        guard let message=body.message,let key=try JSONDecoder().decode(Identity.self,from:data).data.message?.clientMessageId,
              key == intent.clientMessageID,message.senderID == intent.scope.identity.accountID,
              message.conversationID == intent.scope.conversationID,IMVideoReference.read(message) == reference else { throw APIError.malformedResponse }
        return message
    }
    public var canUploadOrdinaryImage: Bool { writesEnabled && (enabledPaths?.contains("api/common/uploadOSS") ?? true) }
    public func recoverImageUpload(requestID: UUID, sourceSHA256: String, token: String) async throws -> OrdinaryIMImageUploadResult {
        guard imageUploadReceiptEnabled, enabledPaths?.contains("api/common/uploadOSS/receipt") ?? true,
              sourceSHA256.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil,
              var parts = URLComponents(url: configuration.baseURL.appendingPathComponent("api/common/uploadOSS/receipt"), resolvingAgainstBaseURL: false) else { throw APIError.notConfigured }
        parts.queryItems = [.init(name: "request_id", value: requestID.uuidString), .init(name: "source_sha256", value: sourceSHA256)]
        guard let url = parts.url, AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        var request = URLRequest(url: url); request.httpMethod = "GET"; request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20; request.setValue(token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try imageUploadResult(try await response(request), requestID: requestID, sourceSHA256: sourceSHA256)
    }
    private func imageUploadResult(_ data: Data, requestID: UUID, sourceSHA256: String) throws -> OrdinaryIMImageUploadResult {
        struct Receipt: Decodable {
            let uploadProtocol: String; let uploadRequestId: String; let sourceSHA256: String; let uploadState: String
            let url: String?; let fileName: String?; let reviewState: String?
        }
        let row = try JSONDecoder().decode(Receipt.self, from: data)
        guard row.uploadProtocol == "original-upload-request-v1", row.uploadRequestId == requestID.uuidString,
              row.sourceSHA256 == sourceSHA256 else { throw APIError.malformedResponse }
        switch row.uploadState {
        case "NOT_FOUND": guard row.url == nil else { throw APIError.malformedResponse }; return .notFound
        case "PENDING": guard row.url == nil else { throw APIError.malformedResponse }; return .pending
        case "UPLOADED":
            guard row.reviewState == "APPROVED", let raw = row.url, let url = URL(string: raw), let key = row.fileName,
                  key.range(of: "^upload/[0-9a-f]{32}\\.(jpg|jpeg|png|gif)$", options: .regularExpression) != nil,
                  let parts = URLComponents(url: url, resolvingAgainstBaseURL: false), parts.percentEncodedPath == "/" + key,
                  parts.fragment == nil, let origin = SocialMessageMediaService.origin(url), approvedMediaOrigins.contains(origin) else { throw APIError.malformedResponse }
            return .uploaded(url)
        default: throw APIError.malformedResponse
        }
    }
    public func upload(_ selection: IMMediaSelection, consent: IMMediaConsent, token: String) async throws -> URL {
        guard writesEnabled, enabledPaths?.contains("api/common/uploadOSS") ?? true else { throw APIError.notConfigured }
        guard consent.selectionID == selection.id, consent.scope == selection.scope, consent.purpose == .upload else { throw IMCapabilityGap.consentRequired }
        try selection.validateImage()
        if imageUploadReceiptEnabled {
            // Verify support and the exact original key BEFORE PUT; a legacy backend cannot silently ignore recovery.
            switch try await recoverImageUpload(requestID: selection.id, sourceSHA256: OrdinaryIMImageJournal.digest(selection.bytes), token: token) {
            case .uploaded(let url): return url
            case .notFound: break
            case .pending: throw ImageUploadJournalFailure.locked
            }
        }
        let boundary = "im-" + UUID().uuidString
        var request = try AuthRequestBuilder.makeFormRequest(url: configuration.baseURL.appendingPathComponent("api/common/uploadOSS"), fields: [:], token: token)
        var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"image.\(selection.fileExtension)\"\r\nContent-Type: \(selection.mimeType)\r\n\r\n".utf8)
        body.append(selection.bytes); body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        request.httpBody = body; request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if imageUploadReceiptEnabled { request.setValue(selection.id.uuidString, forHTTPHeaderField: "X-Upload-Request-ID") }
        let data = try await response(request)
        if imageUploadReceiptEnabled {
            guard case .uploaded(let url) = try imageUploadResult(data, requestID: selection.id, sourceSHA256: OrdinaryIMImageJournal.digest(selection.bytes)) else { throw APIError.malformedResponse }
            return url
        }
        struct Receipt: Decodable { let url: String }
        guard let raw = try? JSONDecoder().decode(Receipt.self, from: data).url, let url = URL(string: raw),
              let origin = SocialMessageMediaService.origin(url), approvedMediaOrigins.contains(origin),
              URLComponents(url: url, resolvingAgainstBaseURL: false)?.fragment == nil else { throw APIError.malformedResponse }
        return url
    }
    public func performOrdinaryRead(_ intent: OrdinaryIMReadIntent, token: String) async throws -> OrdinaryIMReadReceipt {
        guard canWriteOrdinaryRead else { throw APIError.notConfigured }
        let request = try AuthRequestBuilder.makeFormRequest(url: configuration.baseURL.appendingPathComponent("api/im/read"),
            fields: ["conversation_id": String(intent.scope.conversationID), "read_to": String(intent.original.readTo), "request_id": intent.original.requestID], token: token)
        let data = try await response(request)
        struct Envelope: Decodable { let data: OrdinaryIMReadReceiptWire }
        return try JSONDecoder().decode(Envelope.self, from: data).data.validate(intent)
    }
    public func recoverOrdinaryRead(_ intent: OrdinaryIMReadIntent, token: String) async throws -> OrdinaryIMReadReceipt {
        guard ordinaryReadReceiptEnabled, enabledPaths?.contains("api/im/read-receipt") ?? false else { throw APIError.notConfigured }
        let data = try await ordinaryMuteRead(path: "api/im/read-receipt", fields: ["conversation_id": String(intent.scope.conversationID),
            "read_to": String(intent.original.readTo), "request_id": intent.original.requestID], token: token)
        struct Envelope: Decodable { let data: OrdinaryIMReadReceiptWire }
        return try JSONDecoder().decode(Envelope.self, from: data).data.validate(intent)
    }
    public func readOrdinaryRead(scope: IMScope, token: String) async throws -> OrdinaryIMReadCurrent {
        guard ordinaryReadStateEnabled, enabledPaths?.contains("api/im/read-state") ?? false else { throw APIError.notConfigured }
        let data = try await ordinaryMuteRead(path: "api/im/read-state", fields: ["conversation_id": String(scope.conversationID)], token: token)
        struct Envelope: Decodable { let data: OrdinaryIMReadCurrent }
        let value = try JSONDecoder().decode(Envelope.self, from: data).data
        try value.validate(scope: scope); return value
    }
    public func performOrdinaryMute(_ intent: OrdinaryIMMuteIntent, token: String) async throws -> OrdinaryIMMuteReceipt {
        guard canWriteOrdinaryMute else { throw APIError.notConfigured }
        let request = try AuthRequestBuilder.makeFormRequest(url: configuration.baseURL.appendingPathComponent("api/im/mute"),
            fields: ["conversation_id": String(intent.scope.conversationID), "muted": intent.muted ? "1" : "0", "request_id": intent.requestID], token: token)
        let data = try await response(request)
        struct Envelope: Decodable { let data: OrdinaryIMMuteReceiptWire }
        return try JSONDecoder().decode(Envelope.self, from: data).data.validate(intent)
    }
    public func recoverOrdinaryMute(_ intent: OrdinaryIMMuteIntent, token: String) async throws -> OrdinaryIMMuteReceipt {
        guard ordinaryMuteReceiptEnabled else { throw APIError.notConfigured }
        let data = try await ordinaryMuteRead(path: "api/im/mute-receipt", fields: ["conversation_id": String(intent.scope.conversationID),
            "muted": intent.muted ? "1" : "0", "request_id": intent.requestID], token: token)
        struct Envelope: Decodable { let data: OrdinaryIMMuteReceiptWire }
        return try JSONDecoder().decode(Envelope.self, from: data).data.validate(intent)
    }
    public func readOrdinaryMute(scope: IMScope, token: String) async throws -> OrdinaryIMMuteCurrent {
        guard ordinaryMuteStateEnabled else { throw APIError.notConfigured }
        let data = try await ordinaryMuteRead(path: "api/im/mute-state", fields: ["conversation_id": String(scope.conversationID)], token: token)
        struct Envelope: Decodable { let data: OrdinaryIMMuteCurrent }
        let value = try JSONDecoder().decode(Envelope.self, from: data).data
        try value.validate(scope: scope); return value
    }
    private func ordinaryMuteRead(path: String, fields: [String:String], token: String) async throws -> Data {
        var parts = URLComponents(url: configuration.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        parts?.queryItems = fields.sorted { $0.key < $1.key }.map { .init(name: $0.key, value: $0.value) }
        guard let url = parts?.url else { throw APIError.invalidConfiguration }
        var request = try AuthRequestBuilder.makeFormRequest(url: url, fields: [:], token: token, includesBody: false)
        request.httpMethod = "GET"; request.cachePolicy = .reloadIgnoringLocalCacheData
        let data = try await response(request)
        guard data.count <= 16384 else { throw APIError.malformedResponse }; return data
    }
    private func response(_ input: URLRequest) async throws -> Data {
        var request = input
        request.httpShouldHandleCookies = false
        try Task.checkCancellation()
        let (data, status) = try await transport.send(request)
        try Task.checkCancellation()
        struct Header: Decodable { let code: Int; let msg: String?; let errorCode: String? }
        guard data.count <= 2 * 1024 * 1024 else { throw APIError.malformedResponse }
        let header = try? JSONDecoder().decode(Header.self, from: data)
        guard (200..<300).contains(status) else { throw MessagingReadFailure(httpStatus: status, code: header?.code, errorCode: header?.errorCode, message: header?.msg) }
        guard let header else { throw APIError.malformedResponse }
        guard header.code == 200 else { throw MessagingReadFailure(code: header.code, errorCode: header.errorCode, message: header.msg) }
        return data
    }
}
