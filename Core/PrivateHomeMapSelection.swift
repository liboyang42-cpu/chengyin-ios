import Foundation

public enum PrivateHomeMapIssue: String, Error, Equatable {
    case providerUnverified, datumUnsupported, coordinateInvalid, precisionUnsupported
}

/// A separately reviewed renderer/output contract, never inferred from language, device
/// locale, a coordinate's numeric range, or a CLLocationCoordinate2D type alone.
public struct PrivateHomeMapSource: Equatable {
    public let providerID: String
    public let region: String
    public let datum: WalkingCoordinateDatum?
    public let contractRevision: String
    public init(providerID: String, region: String, datum: WalkingCoordinateDatum?, contractRevision: String) {
        self.providerID = providerID; self.region = region; self.datum = datum; self.contractRevision = contractRevision
    }
    var isReviewedWGS84: Bool {
        !providerID.isEmpty && providerID.utf8.count <= 100 && !contractRevision.isEmpty &&
        contractRevision.utf8.count <= 100 && region.utf8.count == 2 &&
        region.utf8.allSatisfy { (65...90).contains($0) } && datum == .wgs84
    }
}

/// Decimal text is preserved until validation: adapters must not silently round, truncate,
/// convert datum, or copy this private selection to a public-map/search/NPC service.
public struct PrivateHomeMapCandidate: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    public let latitude: String
    public let longitude: String
    public let source: PrivateHomeMapSource?
    public init(latitude: String, longitude: String, source: PrivateHomeMapSource?) {
        self.latitude = latitude; self.longitude = longitude; self.source = source
    }
    public func reviewedPoint(approvedSource: PrivateHomeMapSource?) throws -> PrivateHomePoint {
        guard let approvedSource, approvedSource.isReviewedWGS84, let source else { throw PrivateHomeMapIssue.providerUnverified }
        guard source.datum == .wgs84 else { throw PrivateHomeMapIssue.datumUnsupported }
        guard source == approvedSource else { throw PrivateHomeMapIssue.providerUnverified }
        for value in [latitude, longitude] {
            guard value.utf8.count <= 64,
                  value.range(of: "\\A[+-]?[0-9]{1,3}(?:\\.[0-9]+)?\\z", options: .regularExpression) != nil else { throw PrivateHomeMapIssue.coordinateInvalid }
            if let separator = value.firstIndex(of: "."), value.distance(from: separator, to: value.endIndex) > 7 {
                throw PrivateHomeMapIssue.precisionUnsupported
            }
        }
        do { return try PrivateHomePoint.parse(latitude: latitude, longitude: longitude) }
        catch { throw PrivateHomeMapIssue.coordinateInvalid }
    }
    public var description: String { "PrivateHome[redacted]" }
    public var debugDescription: String { description }
}

/// Ephemeral selection only; never persists and never mints a request ID or mutation.
public struct PrivateHomeMapSelection: CustomStringConvertible, CustomDebugStringConvertible {
    public private(set) var generation: UUID?
    public private(set) var point: PrivateHomePoint?
    public private(set) var issue: PrivateHomeMapIssue?
    private var approvedSource: PrivateHomeMapSource?
    public init() {}
    @discardableResult public mutating func open(approvedSource: PrivateHomeMapSource?) -> UUID {
        close(); let ticket = UUID(); generation = ticket; self.approvedSource = approvedSource
        if approvedSource?.isReviewedWGS84 != true { issue = .providerUnverified }
        return ticket
    }
    @discardableResult public mutating func select(_ candidate: PrivateHomeMapCandidate, generation ticket: UUID) -> Bool {
        guard generation == ticket else { return false }
        point = nil; issue = nil
        do { point = try candidate.reviewedPoint(approvedSource: approvedSource); return true }
        catch { issue = (error as? PrivateHomeMapIssue) ?? .coordinateInvalid; return false }
    }
    public mutating func close() { generation = nil; point = nil; issue = nil; approvedSource = nil }
    public var description: String { "PrivateHome[redacted]" }
    public var debugDescription: String { description }
}
