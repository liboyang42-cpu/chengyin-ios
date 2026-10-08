import Foundation

/// Existing professional-ticket fields. Coordinates use the mini editor's GCJ-02
/// datum; this value neither converts coordinates nor requests device location.
public struct ProjectTicketMeetingPoint: Equatable {
    public var name: String
    public var address: String
    public var longitude: String
    public var latitude: String

    public init(ticket: ProjectEditTicket) {
        name = ticket.meetingPoint
        address = ticket.localMetadata["meetingPointAddress"]?.text ?? ""
        longitude = Self.coordinateText(ticket.gatherLng, original: ticket.localMetadata["gatherLng"])
        latitude = Self.coordinateText(ticket.gatherLat, original: ticket.localMetadata["gatherLat"])
    }

    /// Missing/null and the documented source types are editable. In particular,
    /// numeric-looking strings are not silently reinterpreted as backend numbers.
    public static func supportsEditing(_ ticket: ProjectEditTicket) -> Bool {
        for key in ["meetingPoint", "meetingPointAddress", "gatherLng", "gatherLat"] {
            guard let raw = ticket.localMetadata[key], raw != .null else { continue }
            switch raw {
            case .string where key == "meetingPoint" || key == "meetingPointAddress": break
            case .number where key == "gatherLng" || key == "gatherLat": break
            default: return false
            }
        }
        return true
    }

    public var hasValidCoordinates: Bool {
        let x = longitude.trimmingCharacters(in: .whitespacesAndNewlines)
        let y = latitude.trimmingCharacters(in: .whitespacesAndNewlines)
        if x.isEmpty && y.isEmpty { return true }
        return Self.coordinate(x, limit: 180) != nil && Self.coordinate(y, limit: 90) != nil
    }
    public var canApply: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && hasValidCoordinates }

    /// Mutate only explicitly changed fields. Untouched absent/null/number shapes,
    /// unknown siblings, IDs and every other ticket field retain their original bytes.
    public func applying(to ticket: ProjectEditTicket) throws -> ProjectEditTicket {
        guard Self.supportsEditing(ticket), canApply else { throw ProjectEditError.invalidDraft }
        let original = Self(ticket: ticket)
        var result = ticket
        if !name.utf8.elementsEqual(original.name.utf8) { result.meetingPoint = name }
        if !address.utf8.elementsEqual(original.address.utf8) {
            result.localMetadata["meetingPointAddress"] = address.isEmpty ? .null : .string(address)
        }
        if !longitude.utf8.elementsEqual(original.longitude.utf8) {
            result.gatherLng = longitude.trimmingCharacters(in: .whitespacesAndNewlines)
            result.localMetadata["gatherLng"] = Self.coordinate(result.gatherLng, limit: 180).map(ProjectEditJSON.number) ?? .null
        }
        if !latitude.utf8.elementsEqual(original.latitude.utf8) {
            result.gatherLat = latitude.trimmingCharacters(in: .whitespacesAndNewlines)
            result.localMetadata["gatherLat"] = Self.coordinate(result.gatherLat, limit: 90).map(ProjectEditJSON.number) ?? .null
        }
        return result
    }

    public static func wireFields(_ ticket: ProjectEditTicket) throws -> [String: ProjectEditJSON] {
        let value = Self(ticket: ticket)
        guard supportsEditing(ticket), value.hasValidCoordinates else { throw ProjectEditError.invalidDraft }
        var result: [String: ProjectEditJSON] = [:]
        if !ticket.meetingPoint.isEmpty { result["meetingPoint"] = .string(ticket.meetingPoint) }
        else if ticket.localMetadata["meetingPoint"] == .null { result["meetingPoint"] = .null }
        else if ticket.localMetadata["meetingPoint"] != nil { result["meetingPoint"] = .string("") }
        if let address = ticket.localMetadata["meetingPointAddress"] { result["meetingPointAddress"] = address }
        for (key, text, limit) in [("gatherLng", value.longitude, 180), ("gatherLat", value.latitude, 90)] {
            if let coordinate = coordinate(text, limit: limit) { result[key] = .number(coordinate) }
            else if ticket.localMetadata[key] == .null { result[key] = .null }
            else if ticket.localMetadata[key] != nil { throw ProjectEditError.invalidDraft }
        }
        return result
    }

    /// Recovers numeric readback from older local envelopes whose string-only
    /// decoder left the display field empty. Explicit clearing stores null instead.
    public static func coordinateText(_ current: String, original: ProjectEditJSON?) -> String {
        if !current.isEmpty { return current }
        if case .number(let value) = original { return NSDecimalNumber(decimal: value).stringValue }
        return original?.text ?? ""
    }
    private static func coordinate(_ value: String, limit: Int) -> Decimal? {
        guard let number = ProjectEditValidation.decimal(value),
              NSDecimalNumber(decimal: number).doubleValue.isFinite,
              number >= Decimal(-limit), number <= Decimal(limit) else { return nil }
        return number
    }
}
