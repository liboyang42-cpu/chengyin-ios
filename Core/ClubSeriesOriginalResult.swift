import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum ClubSeriesOriginalResultFailure: Error { case unavailable, stale, malformed, forbidden, unknown }
/// Deployment input only. It issues no writer grant and never enables the shipped factory.
public struct ClubSeriesOriginalResultApproval: Equatable {
    public static let path = "api/club/event-ops/series/original-result"
    public let endpoints: OperationEndpointApproval
    public let scopes: Set<ClubGovernanceScope>
    public let reads: Bool
    public let policyVersion: String
    public let approvalID: UUID
    public init(endpoints: OperationEndpointApproval, scopes: Set<ClubGovernanceScope>, reads: Bool = false,
                policyVersion: String = "club-series-original-result-v1", approvalID: UUID = UUID()) throws {
        guard !scopes.isEmpty, scopes.allSatisfy({ scope in
            guard let club = scope.clubID, club > 0, let topic = scope.topicID, topic > 0 else { return false }
            return scope == .init(clubID: club, topicID: topic)
        }), policyVersion == "club-series-original-result-v1" else { throw ClubSeriesOriginalResultFailure.unavailable }
        self.endpoints = endpoints; self.scopes = scopes; self.reads = reads; self.policyVersion = policyVersion; self.approvalID = approvalID
    }
    func permits(_ context: RuntimeDependencyContext, scope: ClubGovernanceScope) -> Bool {
        reads && context.market == .china && scopes.contains(scope) && context.baseURL == endpoints.baseURL
            && context.session.accountID == endpoints.accountID && context.session.namespace == endpoints.namespace
            && endpoints.paths.contains(Self.path)
    }
}
public enum ClubSeriesOriginalResult: Equatable {
    /// Historical generic pending has no original request; it is never queried with a replacement ID.
    case legacyUnknown
    case unknown(requestID: String)
    case applied(ClubSeriesOriginalReceipt)
}
public struct ClubSeriesOriginalReceipt: Equatable {
    public let original: ClubSeriesOriginalRequest
    /// Full immutable first-party initial result. This is not a current schedule or publication claim.
    public let value: ClubGovernanceValue
    public var series: ClubGovernanceValue { value["series"] }
    public var occurrences: [ClubGovernanceValue] { value["occurrences"].array ?? [] }
    public var seriesID: Int { series["id"].int! }
    public var requestID: String { value["requestId"].string! }
    static func decode(_ value: ClubGovernanceValue, original: ClubSeriesOriginalRequest) throws -> ClubSeriesOriginalResult {
        guard let object = value.object, value["version"] == .integer(1), value["actorMemberId"] == .integer(original.accountID),
              value["clubId"] == original.fields["clubId"], value["topicId"] == original.fields["topicId"],
              let rawID = original.fields["requestId"]?.string,
              let requestID = value["requestId"].string, Array(requestID.utf8) == Array(javaTrim(rawID).utf8) else {
            throw ClubSeriesOriginalResultFailure.malformed
        }
        let identity: Set<String> = ["version", "actorMemberId", "clubId", "topicId", "requestId", "state"]
        if value["state"] == .string("UNKNOWN") {
            guard Set(object.keys) == identity else { throw ClubSeriesOriginalResultFailure.malformed }
            return .unknown(requestID: rawID)
        }
        guard value["state"] == .string("APPLIED"),
              Set(object.keys) == identity.union(["wire", "series", "effectiveDates", "startTime", "occurrences", "receiptHash"]),
              let wire = value["wire"].object else { throw ClubSeriesOriginalResultFailure.malformed }
        var expected = original.fields
        expected["rrule"] = .null; expected["seriesId"] = .null; expected["expectedVersion"] = .null
        // JSON byte comparison preserves exact original Unicode and nulls; never normalize historical fields.
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        guard try encoder.encode(wire) == encoder.encode(expected) else { throw ClubSeriesOriginalResultFailure.malformed }
        let series = value["series"], rows = value["occurrences"].array, dates = value["effectiveDates"].array
        guard positive(series["id"]), series["clubId"] == original.fields["clubId"], series["topicId"] == original.fields["topicId"],
              series["createdByMemberId"] == .integer(original.accountID), series["requestId"] == value["requestId"],
              series["status"] == .string("ACTIVE"), series["version"] == .integer(0), series["timezone"] == .string("Asia/Shanghai"),
              positive(series["defaultLeadMemberId"]), series["waitlistEnabled"].bool != nil,
              series["defaultCapacity"] == .null || (1...10_000).contains(series["defaultCapacity"].int ?? 0),
              (5...1440).contains(series["offerMinutes"].int ?? 0), positive(series["createdAtEpochMs"]),
              series["createdAtEpochMs"] == series["updatedAtEpochMs"],
              hash(series["requestFingerprint"]), hash(value["receiptHash"]),
              let rows, let dates, (1...64).contains(dates.count), rows.count == dates.count,
              Set(dates.compactMap(\.string)).count == dates.count,
              value["startTime"] == original.fields["startTime"],
              ["ONCE", "WEEKLY", "CUSTOM_DATES"].contains(series["recurrenceType"].string ?? "") else {
            throw ClubSeriesOriginalResultFailure.malformed
        }
        var occurrenceIDs: Set<Int> = [], activityIDs: Set<Int> = []
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian); formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"; formatter.isLenient = false
        for (index, row) in rows.enumerated() {
            guard positive(row["id"]), positive(row["activityId"]), row["seriesId"] == series["id"],
                  occurrenceIDs.insert(row["id"].int!).inserted, activityIDs.insert(row["activityId"].int!).inserted,
                  row["defaultLeadMemberId"] == series["defaultLeadMemberId"], row["status"] == .string("ACTIVE"),
                  row["version"] == .integer(0), row["createdAtEpochMs"] == series["createdAtEpochMs"],
                  let date = dates[index].string, let time = value["startTime"].string,
                  let moment = formatter.date(from: "\(date) \(time)"), formatter.string(from: moment) == "\(date) \(time)",
                  row["occurrenceAtEpochMs"] == .integer(Int((moment.timeIntervalSince1970 * 1000).rounded())) else {
                throw ClubSeriesOriginalResultFailure.malformed
            }
        }
        return .applied(.init(original: original, value: value))
    }
    private static func positive(_ value: ClubGovernanceValue) -> Bool {
        guard case .integer(let number) = value else { return false }; return (1...9_007_199_254_740_991).contains(number)
    }
    private static func hash(_ value: ClubGovernanceValue) -> Bool {
        guard let string = value.string else { return false }
        return string.utf8.count == 64 && string.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    static func javaTrim(_ input: String) -> String {
        let values = input.utf16.drop(while: { $0 <= 0x20 }).reversed().drop(while: { $0 <= 0x20 }).reversed()
        return String(decoding: Array(values), as: UTF16.self)
    }
}
@MainActor public final class ClubSeriesOriginalResultReader {
    private let transport: any HTTPTransport
    private let current: () -> RuntimeDependencyContext?
    private let approval: (RuntimeDependencyContext) -> ClubSeriesOriginalResultApproval?
    private let unauthorized: (RuntimeDependencyContext) -> Void
    public init(transport: any HTTPTransport, current: @escaping () -> RuntimeDependencyContext?,
                approval: @escaping (RuntimeDependencyContext) -> ClubSeriesOriginalResultApproval?,
                unauthorized: @escaping (RuntimeDependencyContext) -> Void = { _ in }) {
        self.transport = transport; self.current = current; self.approval = approval; self.unauthorized = unauthorized
    }
    public func canRead(scope: ClubGovernanceScope, identity: ClubReadIdentity?, realm: String) -> Bool {
        guard let context = current(), identity?.accountID == context.session.accountID,
              identity?.epoch == context.session.epoch, realm == Self.realm(context) else { return false }
        return approval(context)?.permits(context, scope: scope) == true
    }
    func read(_ original: ClubSeriesOriginalRequest, identity: ClubReadIdentity, check: () throws -> Void) async throws -> ClubSeriesOriginalResult {
        let scope = ClubGovernanceScope(clubID: original.fields["clubId"]?.int, topicID: original.fields["topicId"]?.int)
        guard original.version == 1, original.accountID == identity.accountID,
              canRead(scope: scope, identity: identity, realm: original.realm), let context = current(), let issued = approval(context) else {
            throw ClubSeriesOriginalResultFailure.unavailable
        }
        var request = URLRequest(url: context.baseURL.appendingPathComponent(ClubSeriesOriginalResultApproval.path))
        request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(context.session.token, forHTTPHeaderField: "Authorization")
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; request.httpBody = try encoder.encode(original.fields)
        guard (request.httpBody?.count ?? Int.max) <= 65_536 else { throw ClubSeriesOriginalResultFailure.malformed }
        try check()
        guard current() == context, approval(context) == issued, !Task.isCancelled else { throw ClubSeriesOriginalResultFailure.stale }
        let (data, status) = try await transport.send(request)
        try check()
        guard current() == context, approval(context) == issued, !Task.isCancelled else { throw ClubSeriesOriginalResultFailure.stale }
        if status == 401 { unauthorized(context); throw ClubSeriesOriginalResultFailure.forbidden }
        if status == 403 { throw ClubSeriesOriginalResultFailure.forbidden }
        guard data.count <= 262_144, let text = String(data: data, encoding: .utf8),
              (try? ContentDraftJSON.parse(text)) != nil else { throw ClubSeriesOriginalResultFailure.malformed }
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        if envelope.code == 401 { unauthorized(context); throw ClubSeriesOriginalResultFailure.forbidden }
        if envelope.code == 403 { throw ClubSeriesOriginalResultFailure.forbidden }
        guard (200..<300).contains(status), envelope.code == 200, let value = envelope.data else { throw ClubSeriesOriginalResultFailure.unknown }
        return try ClubSeriesOriginalReceipt.decode(value, original: original)
    }
    private struct Envelope: Decodable { let code: Int; let data: ClubGovernanceValue? }
    private static func realm(_ context: RuntimeDependencyContext) -> String {
        "\(context.market)|\(context.baseURL.absoluteString)|\(context.session.namespace)"
    }
}
