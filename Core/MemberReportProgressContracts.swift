import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum MemberReportProgressFailure: Error, Equatable { case disabled, denied, malformed, unavailable, stale, oversized }
public enum MemberReportProgressCapability: String, Hashable { case history, detail, taxonomy }
public enum MemberReportProgressFilter: String, CaseIterable, Identifiable {
    case all, active, decided
    public var id: String { rawValue }
}
/// Preserve source time bytes. A timezone-free timestamp is not silently assigned a timezone.
public enum MemberReportProgressTime: Decodable, Equatable {
    case text(String), milliseconds(Int64)
    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if let text = try? value.decode(String.self) { self = .text(text) }
        else { self = .milliseconds(try value.decode(Int64.self)) }
    }
    public func display(locale: Locale = .current, timeZone: TimeZone = .current) -> String? {
        let date: Date
        switch self {
        case .milliseconds(let raw):
            // No Date or formatter receives unbounded/negative wire values.
            guard (1...253_402_300_799_999).contains(raw) else { return nil }
            date = Date(timeIntervalSince1970: Double(raw) / 1000)
        case .text(let raw):
            guard raw.utf8.count <= 128 else { return nil }
            if raw.range(of: #"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$"#, options: .regularExpression) != nil {
                let parser = DateFormatter(); parser.locale = Locale(identifier: "en_US_POSIX")
                parser.calendar = Calendar(identifier: .gregorian); parser.timeZone = TimeZone(secondsFromGMT: 0)
                parser.dateFormat = "yyyy-MM-dd HH:mm:ss"; parser.isLenient = false
                guard let parsed = parser.date(from: raw), parser.string(from: parsed) == raw,
                      raw.prefix(4) != "0000" else { return nil }
                return raw // Source supplied no offset; do not invent one.
            }
            guard raw.range(of: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:?\d{2})$"#, options: .regularExpression) != nil else { return nil }
            let wallText = String(raw.prefix(19)).replacingOccurrences(of: "T", with: " ")
            let wall = DateFormatter(); wall.locale = Locale(identifier: "en_US_POSIX")
            wall.calendar = Calendar(identifier: .gregorian); wall.timeZone = TimeZone(secondsFromGMT: 0)
            wall.dateFormat = "yyyy-MM-dd HH:mm:ss"; wall.isLenient = false
            guard let wallDate = wall.date(from: wallText), wall.string(from: wallDate) == wallText,
                  raw.prefix(4) != "0000" else { return nil }
            var isoText = raw
            if raw.range(of: #"[+-]\d{4}$"#, options: .regularExpression) != nil {
                isoText.insert(":", at: isoText.index(isoText.endIndex, offsetBy: -2))
            }
            let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var parsed = iso.date(from: isoText)
            if parsed == nil { iso.formatOptions = [.withInternetDateTime]; parsed = iso.date(from: isoText) }
            guard let parsed else { return nil }; date = parsed
        }
        let seconds = date.timeIntervalSince1970
        guard seconds.isFinite, seconds > 0, seconds <= 253_402_300_799.999 else { return nil }
        let formatter = DateFormatter(); formatter.locale = locale; formatter.timeZone = timeZone
        formatter.calendar = Calendar(identifier: .gregorian); formatter.dateStyle = .medium; formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
public struct MemberReportProgressEvent: Decodable, Equatable {
    public let eventType: String
    public let fromStage: String?
    public let toStage: String?
    public let publicNote: String?
    public let createTime: MemberReportProgressTime?
    public var stageKey: String? {
        guard let toStage else { return nil }
        switch toStage {
        case "SUBMITTED", "TRIAGED", "INVESTIGATING", "RESOLVED", "CLOSED", "APPEALED": return toStage
        default: return "UNKNOWN"
        }
    }
    public var titleKey: String {
        switch eventType { case "SUBMITTED", "APPEALED": return "report.timeline.\(eventType)"; default: return "report.timeline.event" }
    }
    // Deliberately no actor, internal note, event key or raw JSON retention.
}
public struct MemberReportProgressRecord: Decodable, Equatable, Identifiable {
    public let id: Int64
    public let targetType: String
    public let targetId: Int64
    public let reasonCode: String?
    public let policyVersion: String?
    public let description: String?
    public let evidenceAssetIds: [Int64]?
    public let anonymityPolicy: String?
    public let stage: String
    public let publicStage: String?
    public let estimatedResolveAt: MemberReportProgressTime?
    public let decisionSummary: String?
    public let version: Int
    public let createTime: MemberReportProgressTime?
    public let timeline: [MemberReportProgressEvent]?
    public var isDecided: Bool { stage == "RESOLVED" || stage == "CLOSED" }
    public var stageKey: String {
        switch stage {
        case "SUBMITTED", "TRIAGED", "INVESTIGATING", "RESOLVED", "CLOSED", "APPEALED": return stage
        default: return "UNKNOWN"
        }
    }
    public var targetKey: String {
        switch targetType {
        case "MEMBER", "MERCHANT", "CLUB", "ACTIVITY", "CONTENT", "COMMENT", "SAFETY_RATING": return targetType
        default: return "UNKNOWN"
        }
    }
    func validate() throws {
        guard id > 0, targetId > 0, version >= 0, !targetType.isEmpty, !stage.isEmpty,
              targetType.utf8.count <= 128, stage.utf8.count <= 128,
              evidenceAssetIds?.allSatisfy({ $0 > 0 }) ?? true,
              (timeline?.count ?? 0) <= 10_000 else { throw MemberReportProgressFailure.malformed }
    }
    func validateDetail(for original: Self) throws {
        try validate()
        guard id == original.id, targetType == original.targetType, targetId == original.targetId,
              reasonCode == original.reasonCode, policyVersion == original.policyVersion,
              description == original.description, evidenceAssetIds == original.evidenceAssetIds,
              anonymityPolicy == original.anonymityPolicy, createTime == original.createTime,
              version >= original.version else { throw MemberReportProgressFailure.malformed }
    }
}
public struct MemberReportProgressTaxonomy: Decodable, Equatable {
    public struct Reason: Decodable, Equatable { public let code: String; public let label: String }
    public let policyVersion: String
    public let reasons: [Reason]
    func validate() throws {
        guard !policyVersion.isEmpty, reasons.count <= 512,
              reasons.allSatisfy({ !$0.code.isEmpty && !$0.label.isEmpty }),
              Set(reasons.map(\.code)).count == reasons.count else { throw MemberReportProgressFailure.malformed }
    }
    public func label(for record: MemberReportProgressRecord) -> String? {
        // Current taxonomy is not an immutable label snapshot for an older policy.
        guard record.policyVersion == policyVersion else { return nil }
        return reasons.first { $0.code == record.reasonCode }?.label
    }
}
public enum MemberReportProgressScope {
    public static func matches(_ current: RuntimeDependencyContext?, _ captured: RuntimeDependencyContext) -> Bool {
        ContentDraftContextFence.matches(current, captured) &&
            current?.session.role.utf8.elementsEqual(captured.session.role.utf8) == true &&
            captured.role.utf8.elementsEqual(captured.session.role.utf8)
    }
}
public enum MemberReportProgressRoute: Equatable {
    case history, detail(Int64), taxonomy
    public var path: String {
        switch self {
        case .history: return "api/community-trust/reports/mine"
        case .detail(let id): return "api/community-trust/reports/\(id)"
        case .taxonomy: return "api/community-trust/reports/taxonomy"
        }
    }
    public var capability: MemberReportProgressCapability {
        switch self { case .history: return .history; case .detail: return .detail; case .taxonomy: return .taxonomy }
    }
    public var isValid: Bool { if case .detail(let id) = self { return id > 0 }; return true }
    public init?(request: URLRequest, baseURL: URL) {
        guard request.httpMethod == "GET", request.httpBody == nil, request.httpBodyStream == nil,
              !request.httpShouldHandleCookies, request.value(forHTTPHeaderField: "Cookie") == nil,
              request.value(forHTTPHeaderField: "Proxy-Authorization") == nil,
              let url = request.url, let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.user == nil, parts.password == nil, parts.fragment == nil, parts.query == nil else { return nil }
        if url.absoluteString.utf8.elementsEqual(baseURL.appendingPathComponent(Self.history.path).absoluteString.utf8) { self = .history }
        else if url.absoluteString.utf8.elementsEqual(baseURL.appendingPathComponent(Self.taxonomy.path).absoluteString.utf8) { self = .taxonomy }
        else {
            let raw = url.lastPathComponent
            guard let id = Int64(raw), String(id).utf8.elementsEqual(raw.utf8), id > 0,
                  url.absoluteString.utf8.elementsEqual(baseURL.appendingPathComponent(Self.detail(id).path).absoluteString.utf8) else { return nil }
            self = .detail(id)
        }
    }
}
