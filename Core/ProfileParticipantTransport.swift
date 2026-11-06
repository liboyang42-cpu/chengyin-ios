import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Recognizes only the canonical bytes produced by the existing services/builder.
/// There is no setDefault, order, badge, merchant, receipt-query or generic POST grant.
public struct ProfileParticipantRoute: Equatable {
    public enum Operation: Equatable { case list, info(Int), create(UUID), edit(Int), delete(Int) }
    public let operation: Operation
    public let path: String
    public var isWrite: Bool {
        switch operation { case .list, .info: return false; default: return true }
    }
    public static func parse(_ request: URLRequest, baseURL: URL) -> Self? {
        let allowedHeaders: Set<String> = ["accept", "authorization", "content-type"]
        guard (request.allHTTPHeaderFields ?? [:]).keys.allSatisfy({ allowedHeaders.contains($0.lowercased()) }),
              request.httpMethod == "POST", request.httpBodyStream == nil,
              request.value(forHTTPHeaderField: "Accept") == "application/json",
              let url = request.url, url.query == nil, url.fragment == nil,
              url.user == nil, url.password == nil else { return nil }
        let paths = ["list", "info", "action", "delete"]
        guard let leaf = paths.first(where: {
            url.absoluteString.utf8.elementsEqual(baseURL.appendingPathComponent("api/user/address/" + $0).absoluteString.utf8)
        }) else { return nil }
        let path = "api/user/address/" + leaf
        if leaf == "list" {
            guard request.httpBody == nil, request.value(forHTTPHeaderField: "Content-Type") == nil else { return nil }
            return Self(operation: .list, path: path)
        }
        guard let fields = fields(request) else { return nil }
        func positiveID(_ text: String?) -> Int? {
            guard let text, let id = Int(text), id > 0, String(id) == text else { return nil }; return id
        }
        if leaf == "info" || leaf == "delete" {
            guard Set(fields.keys) == ["id"], let id = positiveID(fields["id"]) else { return nil }
            return Self(operation: leaf == "info" ? .info(id) : .delete(id), path: path)
        }
        guard let name = fields["fullName"], !name.isEmpty,
              name == name.trimmingCharacters(in: .whitespacesAndNewlines),
              let phone = fields["mobilePhone"], let defaultValue = fields["isDefault"],
              defaultValue == "0" || defaultValue == "1" else { return nil }
        var draft = ParticipantFormDraft(); draft.fullName = name; draft.mobilePhone = phone
        guard draft.validation == nil, phone == phone.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        if let id = positiveID(fields["id"]) {
            let required: Set<String> = ["id", "fullName", "mobilePhone", "isDefault"]
            guard required.isSubset(of: Set(fields.keys)),
                  Set(fields.keys).isSubset(of: required.union(["province", "detailAddress"])) else { return nil }
            for key in ["province", "detailAddress"] {
                if let value = fields[key], value.isEmpty || value != value.trimmingCharacters(in: .whitespacesAndNewlines) { return nil }
            }
            return Self(operation: .edit(id), path: path)
        }
        guard Set(fields.keys) == ["fullName", "mobilePhone", "isDefault", "requestId"], defaultValue == "0",
              let key = fields["requestId"], let id = UUID(uuidString: key), id.uuidString.lowercased() == key else { return nil }
        return Self(operation: .create(id), path: path)
    }
    private static func fields(_ request: URLRequest) -> [String: String]? {
        let prefix = "multipart/form-data; boundary="
        guard let type = request.value(forHTTPHeaderField: "Content-Type"), type.hasPrefix(prefix),
              let data = request.httpBody, let body = String(data: data, encoding: .utf8) else { return nil }
        let boundary = String(type.dropFirst(prefix.count))
        guard !boundary.isEmpty, boundary.count <= 70,
              boundary.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) else { return nil }
        let closing = "--\(boundary)--\r\n", separator = "--\(boundary)\r\n"
        guard body.hasSuffix(closing) else { return nil }
        let pieces = String(body.dropLast(closing.count)).components(separatedBy: separator)
        guard pieces.first == "", pieces.count > 1 else { return nil }
        var values: [String: String] = [:]
        for piece in pieces.dropFirst() {
            let header = "Content-Disposition: form-data; name=\""
            guard piece.hasPrefix(header), piece.hasSuffix("\r\n"),
                  let split = piece.range(of: "\"\r\n\r\n") else { return nil }
            let name = String(piece[piece.index(piece.startIndex, offsetBy: header.count)..<split.lowerBound])
            // Swift String counts CRLF as one extended grapheme cluster, not
            // two Characters. Remove only the verified delimiter so the final
            // Character of the field remains in the canonical byte comparison.
            let value = String(piece[split.upperBound...].dropLast("\r\n".count))
            guard values[name] == nil else { return nil }
            values[name] = value
        }
        guard let url = request.url,
              let canonical = try? AuthRequestBuilder.makeFormRequest(url: url, fields: values,
                token: nil, boundary: boundary), canonical.httpBody == data else { return nil }
        return values
    }
}

/// A single original network attempt. Created afresh by the retained host for each read/write.
/// The dispatch marker is per attempt, never shared by concurrent reads and mutations.
@MainActor public final class ProfileParticipantTransport: HTTPTransport {
    public private(set) var hasForwardedRequest = false
    private var attempted = false
    private let context: RuntimeDependencyContext
    private let access: ProfileParticipantAccess
    private let underlying: any HTTPTransport
    private let current: () -> RuntimeDependencyContext?
    private let stillCurrent: () -> Bool
    public init(context: RuntimeDependencyContext, access: ProfileParticipantAccess, underlying: any HTTPTransport,
                current: @escaping () -> RuntimeDependencyContext?, stillCurrent: @escaping () -> Bool) {
        self.context = context; self.access = access; self.underlying = underlying
        self.current = current; self.stillCurrent = stillCurrent
    }
    public func send(_ request: URLRequest) async throws -> (Data, Int) {
        guard !attempted else { throw APIError.invalidRequest }; attempted = true
        try Task.checkCancellation()
        guard valid(), let route = ProfileParticipantRoute.parse(request, baseURL: context.baseURL),
              access.endpoints.paths.contains(route.path), !route.isWrite || access.permitsWrites,
              request.value(forHTTPHeaderField: "Authorization").map({ Data($0.utf8) }) == Data(context.session.token.utf8) else {
            throw APIError.notConfigured
        }
        // No suspension between this final fence and entering the original injected wire.
        guard valid(), !Task.isCancelled else { throw CancellationError() }
        hasForwardedRequest = true
        let result = try await underlying.send(request)
        guard valid(), !Task.isCancelled else { throw CancellationError() }
        return result
    }
    private func valid() -> Bool {
        ContentDraftContextFence.matches(current(), context) && access.matches(context) && stillCurrent()
    }
}
