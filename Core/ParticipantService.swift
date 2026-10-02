import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct ParticipantResponseFailure: Error, Equatable {
    public let httpStatus: Int?
    public let code: Int?
    public let message: String?
    public var isUnauthorized: Bool { httpStatus == 401 || code == 401 }
    public init(httpStatus: Int? = nil, code: Int? = nil, message: String? = nil) {
        self.httpStatus = httpStatus; self.code = code; self.message = message
    }
}

/// No arbitrary Error.localizedDescription is retained: it may contain a request or PII.
public enum ParticipantIssue: Equatable {
    case cancelled, malformedResponse, transport, accountChanged
    case response(ParticipantResponseFailure)
}

public enum ParticipantWriteError: Error, Equatable {
    case notSent(APIError)
    case cancelledBeforeDispatch
    case rejected(ParticipantResponseFailure)
    case outcomeUnknown(ParticipantIssue)
}

/// One source-aligned multipart request per call. No live host default, hidden retry,
/// credential refresh, redirect, or logging. Inject the existing no-redirect transport.
public struct ParticipantService {
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    public init(configuration: APIConfiguration, transport: any HTTPTransport) {
        self.configuration = configuration; self.transport = transport
    }

    public func perform(_ mutation: ParticipantMutation, token: String) async throws {
        _ = try await performReturningParticipant(mutation, requestID: nil, token: token)
    }

    /// Current create response carries the authoritative address row. Older acknowledgments
    /// remain successful but cannot identify a newly created participant for auto-selection.
    public func performReturningParticipant(_ mutation: ParticipantMutation, requestID: UUID?, token: String) async throws -> ProfileParticipant? {
        let request: URLRequest
        do {
            guard AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
            var fields = try mutation.fields()
            if case .save(let draft) = mutation, draft.id == nil, let requestID { fields["requestId"] = requestID.uuidString.lowercased() }
            request = try AuthRequestBuilder.makeFormRequest(
                url: configuration.baseURL.appendingPathComponent(mutation.path),
                fields: fields, token: token)
        } catch {
            throw ParticipantWriteError.notSent(.invalidRequest)
        }
        guard !Task.isCancelled else { throw ParticipantWriteError.cancelledBeforeDispatch }
        let data: Data
        let status: Int
        do { (data, status) = try await transport.send(request) }
        catch is CancellationError { throw ParticipantWriteError.outcomeUnknown(.cancelled) }
        catch let error as URLError where error.code == .cancelled {
            throw ParticipantWriteError.outcomeUnknown(.cancelled)
        } catch { throw ParticipantWriteError.outcomeUnknown(.transport) }
        guard !Task.isCancelled else { throw ParticipantWriteError.outcomeUnknown(.cancelled) }
        let envelope = try? JSONDecoder().decode(Response.self, from: data)
        let failure = ParticipantResponseFailure(httpStatus: (200..<300).contains(status) ? nil : status,
                                                 code: envelope?.code, message: envelope?.msg)
        // A response that explicitly rejects authentication is not an automatic retry.
        if status == 401 { throw ParticipantWriteError.rejected(failure) }
        guard (200..<300).contains(status) else {
            throw ParticipantWriteError.outcomeUnknown(.response(failure))
        }
        guard let envelope, let code = envelope.code else {
            throw ParticipantWriteError.outcomeUnknown(.malformedResponse)
        }
        guard code == 200 else { throw ParticipantWriteError.rejected(failure) }
        if requestID != nil, case .save(let draft) = mutation, draft.id == nil {
            struct Created: Decodable { let data: ProfileParticipant? }
            if let row = (try? JSONDecoder().decode(Created.self, from: data))?.data {
                guard row.id > 0, row.fullName == draft.fullName.trimmingCharacters(in: .whitespacesAndNewlines),
                      row.mobilePhone == draft.mobilePhone.trimmingCharacters(in: .whitespacesAndNewlines) else {
                    throw ParticipantWriteError.outcomeUnknown(.malformedResponse)
                }
                return row
            }
        }
        return nil
    }

    private struct Response: Decodable {
        let code: Int?
        let msg: String?
        private enum CodingKeys: String, CodingKey { case code, msg }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            code = try? c.decode(Int.self, forKey: .code)
            msg = try? c.decode(String.self, forKey: .msg)
        }
    }
}
