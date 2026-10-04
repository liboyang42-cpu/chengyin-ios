import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Exact source-backed reads and dormant writes. Upload/provider generation remain separate.
public struct MerchantOperationsService {
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    public init(configuration: APIConfiguration, transport: any HTTPTransport) {
        self.configuration = configuration; self.transport = transport
    }
    private enum Body { case none, json, form([String: String]) }
    private struct Envelope<Value: Decodable>: Decodable {
        let data: Value
        enum CodingKeys: String, CodingKey { case code, msg, data }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let code = try c.decode(Int.self, forKey: .code)
            if code == 401 { throw APIError.unauthorized }
            if code == 403 { throw MerchantOperationsFailure.accessDenied }
            guard code == 200 else { throw MerchantOperationsFailure.rejected(code: code, message: try c.decodeIfPresent(String.self, forKey: .msg)) }
            data = try c.decode(Value.self, forKey: .data)
        }
    }
    private struct Rows<Value: Decodable>: Decodable {
        let values: [Value]
        private enum CodingKeys: String, CodingKey { case rows }
        init(from decoder: Decoder) throws {
            if let values = try? decoder.singleValueContainer().decode([Value].self) { self.values = values }
            else { values = try decoder.container(keyedBy: CodingKeys.self).decode([Value].self, forKey: .rows) }
        }
    }
    private struct NullableCharacter: Decodable {
        let character: MerchantStoreCharacter
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            character = c.decodeNil() ? MerchantStoreCharacter() : try c.decode(MerchantStoreCharacter.self)
        }
    }
    private func read<Value: Decodable>(_ path: String, body: Body, token: String) async throws -> Value {
        guard AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        try Task.checkCancellation()
        let form: [String: String]
        let multipart: Bool
        if case .form(let fields) = body { form = fields; multipart = true } else { form = [:]; multipart = false }
        var request = try AuthRequestBuilder.makeFormRequest(url: configuration.baseURL.appendingPathComponent(path), fields: form, token: token, includesBody: multipart)
        if case .json = body { request.httpBody = Data("{}".utf8); request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, status) = try await transport.send(request)
        try Task.checkCancellation()
        if status == 401 { throw APIError.unauthorized }
        if status == 403 { throw MerchantOperationsFailure.accessDenied }
        guard (200..<300).contains(status) else { throw APIError.httpStatus(status) }
        do { return try JSONDecoder().decode(Envelope<Value>.self, from: data).data }
        catch let error as APIError { throw error }
        catch let error as MerchantOperationsFailure { throw error }
        catch { throw APIError.malformedResponse }
    }
    public func access(token: String) async throws -> MerchantOperationsAccess {
        try await read("api/merchant/access/me", body: .none, token: token)
    }
    public func document(_ destination: MerchantOperationsDestination, access: MerchantOperationsAccess, token: String) async throws -> MerchantOperationsDocument {
        guard access.allows(destination) else { throw MerchantOperationsFailure.accessDenied }
        switch destination {
        case .businessStatus:
            let value: MerchantBusinessStatusDocument = try await read("api/merchant/business-status", body: .none, token: token)
            guard let owner = access.identity.merchantID, owner > 0 else { throw APIError.malformedResponse }
            return .draft(.businessStatus(try .init(merchantID: owner, status: value.businessStatus)))
        case .profile:
            let value: MerchantStoreProfile = try await read("api/merchant/info", body: .form([:]), token: token)
            guard value.id == access.identity.merchantID else { throw APIError.malformedResponse }
            return .draft(.profile(value))
        case .decor, .gallery, .story, .cooperation:
            let value: MerchantStorefront = try await read("api/merchant/coop-profile", body: .json, token: token)
            if let id = value.profile.id, id != access.identity.merchantID { throw APIError.malformedResponse }
            switch destination {
            case .decor: return .draft(.decor(value.decor)); case .gallery: return .draft(.gallery(value.decor))
            case .story: return .draft(.story(value)); default: return .draft(.cooperation(value.cooperation))
            }
        case .character:
            let value: NullableCharacter = try await read("api/merchant/npc/profile", body: .json, token: token)
            return .draft(.character(value.character))
        case .assets:
            async let voice: MerchantVoiceResource = read("api/merchant/npc/voice/status", body: .json, token: token)
            async let avatar: MerchantAvatarResource = read("api/merchant/npc/avatar/status", body: .json, token: token)
            return try await .assets(.init(voice: voice, avatar: avatar))
        case .cityNodes:
            return .cityNodes(try await read("api/merchant/city-node/list", body: .none, token: token))
        case .templates:
            let page: Rows<MerchantTemplateRecord> = try await read("api/template/my-list", body: .form(["is_quote": "", "keyword": "", "category_id": "", "pageNum": "1", "pageSize": "100"]), token: token)
            let rows = page.values
            guard rows.allSatisfy({ $0.id > 0 }), Set(rows.map(\.id)).count == rows.count else { throw APIError.malformedResponse }
            return .templates(rows)
        case .template(let id):
            guard let id else { return .draft(.template(.init())) }
            guard id > 0 else { throw APIError.invalidRequest }
            let value: MerchantNodeTemplate = try await read("api/template/myinfo", body: .form(["id": String(id)]), token: token)
            guard value.id == id else { throw APIError.malformedResponse }
            return .draft(.template(value))
        }
    }
    /// Exact source writes, disabled unless an independently scoped grant and durable journal
    /// are injected. A story is two non-atomic writes; never retry, roll back or send its second
    /// request after an ambiguous first response. Known partial completion also remains locked.
    @MainActor public func save(_ draft: MerchantOperationsDraft, token: String,
                              approval: OperationEndpointApproval? = nil, namespace: String = "", accountID: Int = 0,
                              baseline: MerchantOperationsDraft? = nil, journal: (any OperationPendingJournal)? = nil,
                              checkSession: (() throws -> Void)? = nil) async throws -> MerchantOperationsAcknowledgment {
        guard let approval, let baseline, let journal, let checkSession, draft.destination == baseline.destination else { throw MerchantOperationsFailure.liveWritesDisabled }
        if case .businessStatus(let proposed) = draft {
            guard case .businessStatus(let original) = baseline, proposed.merchantID == original.merchantID else { throw MerchantOperationsFailure.notSent }
        }
        let previews = try draft.previews()
        guard !previews.isEmpty, previews.allSatisfy({ approval.allows(configuration: configuration, namespace: namespace, accountID: accountID, path: $0.path) }) else { throw MerchantOperationsFailure.liveWritesDisabled }
        let ownerKey = "\(namespace.utf8.count):\(namespace):\(accountID)"
        var record = OperationPendingRecord(ownerKey: ownerKey, targetKey: draft.destination.pendingTarget)
        let requests: [URLRequest]
        do {
            try Task.checkCancellation(); try checkSession()
            guard try journal.pending(ownerKey: ownerKey, targetKey: record.targetKey) == nil else { throw MerchantOperationsFailure.outcomeUnknown }
            let access = try await access(token: token); try checkSession(); try Task.checkCancellation()
            guard access.allows(draft.destination) else { throw MerchantOperationsFailure.accessDenied }
            let fresh = try await document(draft.destination, access: access, token: token)
            try checkSession(); try Task.checkCancellation()
            guard fresh == .draft(baseline) else { throw MerchantOperationsFailure.notSent }
            requests = try previews.map { preview in
                if let fields = preview.form {
                    var request = try AuthRequestBuilder.makeFormRequest(url: configuration.baseURL.appendingPathComponent(preview.path), fields: [:], token: token, includesBody: false)
                    var components = URLComponents()
                    components.queryItems = fields.keys.sorted().map { URLQueryItem(name: $0, value: fields[$0]) }
                    request.httpBody = Data((components.percentEncodedQuery ?? "").utf8)
                    request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
                    return request
                }
                return try OperationAdapterHTTP.json(configuration: configuration, path: preview.path, body: preview.json, token: token)
            }
            guard try journal.pending(ownerKey: ownerKey, targetKey: record.targetKey) == nil else { throw MerchantOperationsFailure.outcomeUnknown }
            try journal.write(record)
        } catch let error as MerchantOperationsFailure { throw error }
        catch { throw MerchantOperationsFailure.notSent }
        var lastMessage: String?, templateID: Int?
        for (index, request) in requests.enumerated() {
            do { try checkSession(); try Task.checkCancellation() }
            catch {
                if record.acknowledgedSteps > 0 { throw MerchantOperationsFailure.partial(acknowledgedSteps: record.acknowledgedSteps) }
                do { try journal.clear(record) } catch { throw MerchantOperationsFailure.outcomeUnknown }
                throw MerchantOperationsFailure.notSent
            }
            do {
                let (data, status) = try await transport.send(request)
                try checkSession(); try Task.checkCancellation()
                let acknowledgment = try Self.decodeAcknowledgment(data, status: status, template: previews[index].path == "api/merchant/city-node/template/submit")
                lastMessage = acknowledgment.message; templateID = acknowledgment.templateID ?? templateID
                record.acknowledgedSteps += 1
                try journal.write(record)
            } catch {
                if record.acknowledgedSteps > 0 { throw MerchantOperationsFailure.partial(acknowledgedSteps: record.acknowledgedSteps) }
                if let failure = error as? MerchantOperationsFailure, case .rejected = failure {
                    do { try journal.clear(record) } catch { throw MerchantOperationsFailure.outcomeUnknown }
                    throw failure
                }
                throw MerchantOperationsFailure.outcomeUnknown
            }
        }
        do { try journal.clear(record) } catch { throw MerchantOperationsFailure.partial(acknowledgedSteps: record.acknowledgedSteps) }
        return .init(acknowledgedSteps: record.acknowledgedSteps, templateID: templateID, message: lastMessage)
    }
    static func decodeAcknowledgment(_ data: Data, status: Int, template: Bool) throws -> MerchantOperationsAcknowledgment {
        let envelope = try? OperationAdapterHTTP.envelope(data)
        if status == 401 || status == 403 { throw MerchantOperationsFailure.rejected(code: status, message: envelope?["msg"]?.text) }
        guard (200..<300).contains(status), let code = envelope?["code"]?.integer else { throw MerchantOperationsFailure.outcomeUnknown }
        guard code == 200 else { throw MerchantOperationsFailure.rejected(code: code, message: envelope?["msg"]?.text) }
        var templateID: Int?
        if template {
            // merchant_api.dart requires numeric data, unlike team create's teamId object.
            guard let id = envelope?["data"]?.integer, id > 0 else { throw MerchantOperationsFailure.outcomeUnknown }
            templateID = id
        }
        return .init(acknowledgedSteps: 1, templateID: templateID, message: envelope?["msg"]?.text)
    }
}
