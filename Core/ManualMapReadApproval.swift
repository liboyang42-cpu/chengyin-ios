import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// An independently reviewed, time-bounded signed-in read grant. Never derive this from
/// login, device permission, a remote flag or a merchant role. This grants no device work.
/// Retain the reviewed instance while approved; replace it when issuing a new approval.
public struct ManualMapReadApproval {
    public let context: RuntimeDependencyContext
    public let expiresAt: Date
    public let revision = UUID()
    public init(context: RuntimeDependencyContext, expiresAt: Date) throws {
        guard context.market == .china, !context.role.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              expiresAt > Date() else { throw APIError.invalidConfiguration }
        self.context = context; self.expiresAt = expiresAt
    }
    public func matches(_ current: RuntimeDependencyContext, now: Date = Date()) -> Bool {
        ContentDraftContextFence.matches(context, current) && now < expiresAt
    }
}

/// Each browser owns one explicit manual center. Revision fences A → B → A, including
/// a re-selection of A while a request is in flight. There is no location-provider input.
@MainActor public final class ManualMapAreaSelection {
    public struct Snapshot: Equatable {
        public let area: RoamSearchArea
        public let revision: UInt64
    }
    public private(set) var revision: UInt64 = 0
    public private(set) var snapshot: Snapshot?
    public init() {}
    public func select(_ area: RoamSearchArea?) {
        revision &+= 1
        snapshot = area.map { Snapshot(area: $0, revision: revision) }
    }
    public func ensureSelected(_ area: RoamSearchArea) {
        if snapshot?.area != area { select(area) }
    }
}

/// Exact private-controller subset emitted by the existing manual-area readers.
/// Nearby's status/auditStatus and all presence, reveal, reward, merchant and provider
/// routes are deliberately absent. Local bounds may be narrower than the server's.
public enum ManualMapReadRoute: Equatable {
    case places, nearby, cityNodes, cityNode(Int)
    public init?(request: URLRequest, baseURL: URL, area: RoamSearchArea) {
        guard let url = request.url, request.httpBodyStream == nil,
              var parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.user == nil, parts.password == nil, parts.fragment == nil else { return nil }
        parts.query = nil
        guard let pathURL = parts.url else { return nil }
        func exact(_ path: String) -> Bool {
            pathURL.absoluteString == baseURL.appendingPathComponent(path).absoluteString
        }
        if exact("api/map/nearby") {
            guard request.httpMethod == "POST", url.query == nil,
                  let fields = Self.formFields(request), Set(fields.keys) == ["longitude", "latitude", "radius", "limit"],
                  fields["latitude"] == String(area.coordinate.latitude),
                  fields["longitude"] == String(area.coordinate.longitude),
                  let radiusText = fields["radius"], let radius = Double(radiusText), radius.isFinite,
                  (1...20000).contains(radius), radius.rounded() == radius,
                  radiusText == String(Int(radius)) || radiusText == String(radius),
                  Self.positiveInteger(fields["limit"], maximum: 100) != nil else { return nil }
            self = .nearby; return
        }
        guard request.httpMethod == "GET", request.httpBody == nil,
              request.value(forHTTPHeaderField: "Content-Type") == nil else { return nil }
        if exact("api/roam/pois") || exact("api/city/nodes") {
            guard let fields = Self.queryFields(url),
                  fields["lat"] == String(area.coordinate.latitude), fields["lng"] == String(area.coordinate.longitude),
                  Self.positiveInteger(fields["radius"], maximum: 20000) != nil else { return nil }
            if exact("api/roam/pois") {
                guard Set(fields.keys) == ["lat", "lng", "radius"] else { return nil }
                self = .places
            } else {
                guard Set(fields.keys).isSubset(of: ["lat", "lng", "radius", "keyword", "categoryId", "tag", "cityRole"]) else { return nil }
                if let id = fields["categoryId"], Self.positiveInteger(id, maximum: Int(Int32.max)) == nil { return nil }
                for key in ["keyword", "tag", "cityRole"] {
                    if let value = fields[key] {
                        // Bounded local input policy, not an assertion of a server string limit.
                        guard !value.isEmpty, value.utf8.count <= 256,
                              value == value.trimmingCharacters(in: .whitespacesAndNewlines),
                              !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
                    }
                }
                self = .cityNodes
            }
            return
        }
        let prefix = baseURL.appendingPathComponent("api/city/nodes").absoluteString + "/"
        guard url.query == nil, url.absoluteString.hasPrefix(prefix),
              let id = Self.positiveInteger(String(url.absoluteString.dropFirst(prefix.count)), maximum: Int.max),
              exact("api/city/nodes/\(id)") else { return nil }
        self = .cityNode(id)
    }
    private static func positiveInteger(_ value: String?, maximum: Int) -> Int? {
        guard let value, let number = Int(value), number > 0, number <= maximum, String(number) == value else { return nil }
        return number
    }
    private static func queryFields(_ url: URL) -> [String: String]? {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = parts.queryItems, !items.isEmpty, items.count <= 7,
              (url.query?.utf8.count ?? 0) <= 4096 else { return nil }
        var fields: [String: String] = [:]
        for item in items {
            guard fields[item.name] == nil, let value = item.value else { return nil }
            fields[item.name] = value
        }
        var canonical = parts
        canonical.queryItems = fields.keys.sorted().map { URLQueryItem(name: $0, value: fields[$0]) }
        // Servlet query decoding treats raw + as a space. Preserve literal plus filters.
        canonical.percentEncodedQuery = canonical.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        guard canonical.url?.absoluteString == url.absoluteString else { return nil }
        return fields
    }
    private static func formFields(_ request: URLRequest) -> [String: String]? {
        let prefix = "multipart/form-data; boundary="
        guard let type = request.value(forHTTPHeaderField: "Content-Type"), type.hasPrefix(prefix),
              let body = request.httpBody, body.count <= 2048, let text = String(data: body, encoding: .utf8),
              let url = request.url else { return nil }
        let boundary = String(type.dropFirst(prefix.count))
        guard !boundary.isEmpty, boundary.count <= 70,
              boundary.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) else { return nil }
        let end = "--\(boundary)--\r\n"
        guard text.hasSuffix(end) else { return nil }
        let chunks = String(text.dropLast(end.count)).components(separatedBy: "--\(boundary)\r\n")
        guard chunks.first == "", chunks.count == 5 else { return nil }
        var fields: [String: String] = [:]
        for chunk in chunks.dropFirst() {
            let header = "Content-Disposition: form-data; name=\""
            guard chunk.hasPrefix(header), chunk.hasSuffix("\r\n") else { return nil }
            // CRLF is one Swift Character; trim the delimiter, not two value characters.
            let pieces = String(chunk.dropFirst(header.count).dropLast("\r\n".count)).components(separatedBy: "\"\r\n\r\n")
            guard pieces.count == 2, fields[pieces[0]] == nil else { return nil }
            fields[pieces[0]] = pieces[1]
        }
        guard let canonical = try? AuthRequestBuilder.makeFormRequest(url: url, fields: fields, token: nil, boundary: boundary),
              canonical.httpBody == body else { return nil }
        return fields
    }
}

/// Owns button retries as well as SwiftUI task reads. Retiring a view or starting a
/// replacement read cancels the actual reader task, not only its painting token.
@MainActor public final class ManualMapReadTaskOwner {
    private var task: Task<Void, Never>?
    private var generation: UInt64 = 0
    private var active = true
    public init() {}
    public func activate() { active = true }
    public func deactivate() { active = false; cancel() }
    public func cancel() {
        generation &+= 1
        task?.cancel(); task = nil
    }
    /// Button handlers acquire ownership synchronously, before their task can be queued.
    public func start(_ operation: @escaping @MainActor () async -> Void) {
        _ = begin(operation)
    }
    private func begin(_ operation: @escaping @MainActor () async -> Void) -> Task<Void, Never>? {
        guard active, !Task.isCancelled else { return nil }
        cancel()
        let capturedGeneration = generation
        let currentTask = Task {
            defer { if self.generation == capturedGeneration { self.task = nil } }
            guard !Task.isCancelled else { return }
            await operation()
        }
        task = currentTask
        return currentTask
    }
    public func run(_ operation: @escaping @MainActor () async -> Void) async {
        guard let currentTask = begin(operation) else { return }
        await withTaskCancellationHandler {
            await currentTask.value
        } onCancel: {
            currentTask.cancel()
        }
    }
}
