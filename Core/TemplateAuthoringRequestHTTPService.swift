import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The original personal request producer and exact receipt reader, not a second writer.
/// Missing approvals remain unavailable. Reads never call submit or resume-media.
@MainActor public final class TemplateAuthoringRequestHTTPService {
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    private let readApproval: OperationEndpointApproval?
    private let submitApproval: OperationEndpointApproval?
    private let currentReadApproval: (() -> OperationEndpointApproval?)?
    private let currentSubmitApproval: (() -> OperationEndpointApproval?)?
    private let credentials: () -> (session: TemplateAuthoringSession, token: String)?
    public init(configuration: APIConfiguration, transport: any HTTPTransport,
                readApproval: OperationEndpointApproval? = nil, submitApproval: OperationEndpointApproval? = nil,
                currentReadApproval: (() -> OperationEndpointApproval?)? = nil,
                currentSubmitApproval: (() -> OperationEndpointApproval?)? = nil,
                credentials: @escaping () -> (session: TemplateAuthoringSession, token: String)?) {
        self.configuration = configuration; self.transport = transport
        self.readApproval = readApproval; self.submitApproval = submitApproval
        self.currentReadApproval = currentReadApproval; self.currentSubmitApproval = currentSubmitApproval
        self.credentials = credentials
    }
    private func allowed(_ path: String, write: Bool) -> Bool {
        guard let c = credentials(), AuthRequestBuilder.isValidToken(c.token) else { return false }
        let issued = write ? submitApproval : readApproval
        let current = write ? currentSubmitApproval : currentReadApproval
        guard let issued, current == nil || current?() == issued else { return false }
        return issued.allows(configuration: configuration, namespace: c.session.namespace, accountID: c.session.accountID, path: path)
    }
    public var canRead: Bool { allowed(TemplateAuthoringRequestReceipt.readPath, write: false) }
    public func canSubmit(path: String) -> Bool {
        ["/api/template/draft", "/api/template/publish"].contains(path) &&
        allowed(TemplateAuthoringRequestReceipt.submitPath, write: true) && allowed(String(path.dropFirst()), write: true)
    }
    private func send<T: Encodable>(_ value: T, path: String, write: Bool, session: TemplateAuthoringSession) async throws -> TemplateAuthoringRequestReceipt.Receipt {
        guard !Task.isCancelled, allowed(path, write: write), let c = credentials(),
              TemplateAuthoringSavedResult.exactSession(c.session, session), AuthRequestBuilder.isValidToken(c.token) else { throw TemplateAuthoringError.unavailable }
        let request = try OperationAdapterHTTP.json(configuration: configuration, path: path, body: JSONEncoder().encode(value), token: c.token)
        let (data, status) = try await transport.send(request)
        guard !Task.isCancelled, let current = credentials(), TemplateAuthoringSavedResult.exactSession(current.session, c.session),
              current.token.utf8.elementsEqual(c.token.utf8), allowed(path, write: write) else { throw TemplateAuthoringError.changedSession }
        guard data.count <= 2_097_152 else { throw TemplateAuthoringError.invalidContract }
        // Validate original response bytes before decoding/re-encoding can erase
        // duplicate receipt identities, including escaped aliases and nested keys.
        let envelope = try ApprovedTopicReleaseWire.envelope(data)
        guard (200..<300).contains(status), envelope["code"]?.integer == 200, let body = envelope["data"] else { throw TemplateAuthoringError.uncertain }
        return try JSONDecoder().decode(TemplateAuthoringRequestReceipt.Receipt.self, from: JSONEncoder().encode(body))
    }
    public func submit(_ value: TemplateAuthoringRequestReceipt.Submit, session: TemplateAuthoringSession) async throws -> TemplateAuthoringRequestReceipt.Receipt {
        guard let command = value.command, canSubmit(path: command.descriptor.path) else { throw TemplateAuthoringError.unavailable }
        let result = try await send(value, path: TemplateAuthoringRequestReceipt.submitPath, write: true, session: session)
        guard canSubmit(path: command.descriptor.path), result.matches(value) else { throw TemplateAuthoringError.invalidContract }
        return result
    }
    public func read(_ value: TemplateAuthoringRequestReceipt.Submit, session: TemplateAuthoringSession) async throws -> TemplateAuthoringRequestReceipt.Receipt {
        guard value.command != nil else { throw TemplateAuthoringError.invalidContract }
        let result = try await send(TemplateAuthoringRequestReceipt.Read(value), path: TemplateAuthoringRequestReceipt.readPath, write: false, session: session)
        guard result.matches(value) else { throw TemplateAuthoringError.invalidContract }
        return result
    }
}
