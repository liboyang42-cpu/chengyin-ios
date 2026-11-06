import Foundation
import CoreFoundation

/// Signed-in order, then the sibling original-event read, then the existing support lookup.
/// ProfileOrder fields are not OriginalAuditEvent. A failed or mismatched read does not invent one.
public struct ProfileOrderEventHost {
    public static let registrationInfoPath = "api/registration/info"
    public static let originalEventPath = "api/registration/original-event"

    public struct FormPost: Equatable {
        public var path: String
        public var id: String
    }

    public private(set) var calls: [FormPost] = []
    public private(set) var injection = ProfileOrderEventSourceInjection(events: nil)

    public init() {}

    /// Posts the existing registration info form first. The sibling original-event form
    /// is sent only when that info id equals the opened order. Both reads go through
    /// `ProfileService.postOwnedOrderForm`. The returned row is mapped into the existing
    /// injection only when its first ORDER id equals that order. A mismatch, a thrown
    /// transport failure, or an empty body leaves the injection empty.
    public mutating func open(
        _ openedOrderID: Int,
        service: ProfileService,
        token: String
    ) async -> Int64? {
        calls = []
        injection = ProfileOrderEventSourceInjection(events: nil)
        guard openedOrderID > 0 else { return nil }

        let info = FormPost(path: Self.registrationInfoPath, id: String(openedOrderID))
        calls.append(info)
        let infoBody: Data?
        do {
            infoBody = try await service.postOwnedOrderForm(path: info.path, id: info.id, token: token)
        } catch {
            return nil
        }
        guard let infoBody, let infoID = Self.registrationID(in: infoBody), infoID == openedOrderID else {
            return nil
        }

        let event = FormPost(path: Self.originalEventPath, id: String(openedOrderID))
        calls.append(event)
        let eventBody: Data?
        do {
            eventBody = try await service.postOwnedOrderForm(path: event.path, id: event.id, token: token)
        } catch {
            return nil
        }
        guard let eventBody, let rows = Self.auditRows(in: eventBody) else { return nil }
        guard Self.firstOrderID(rows) == Int64(openedOrderID) else { return nil }
        let orderRows = rows.filter { $0.targetType == "ORDER" }
        guard Self.firstOrderID(orderRows) == Int64(openedOrderID) else { return nil }

        var loaded = ProfileOrderEventSourceInjection(events: orderRows)
        do {
            let lookedUp = try loaded.lookupOpenedOrder(openedOrderID)
            guard lookedUp == Int64(openedOrderID) else { return nil }
            injection = loaded
            return lookedUp
        } catch {
            return nil
        }
    }

    /// Info identity only. Title, amount, and other profile fields are not an event.
    private static func registrationID(in body: Data) -> Int? {
        guard let data = successData(in: body) as? [String: Any] else { return nil }
        return positiveInt(data["id"])
    }

    private static func auditRows(in body: Data) -> [OriginalAuditEvent]? {
        guard let data = successData(in: body) else { return nil }
        let rawRows: [[String: Any]]
        if let one = data as? [String: Any] {
            rawRows = [one]
        } else if let many = data as? [[String: Any]] {
            rawRows = many
        } else {
            return nil
        }
        var rows: [OriginalAuditEvent] = []
        for raw in rawRows {
            if let event = auditRow(raw) {
                rows.append(event)
            }
        }
        return rows.isEmpty ? nil : rows
    }

    /// Audit columns only. A profile id or title does not become targetId or requestId.
    private static func auditRow(_ raw: [String: Any]) -> OriginalAuditEvent? {
        guard let targetType = raw["targetType"] as? String else { return nil }
        guard targetType == "ORDER" || targetType == "RUN" else { return nil }
        guard let targetId = positiveInt64(raw["targetId"]) else { return nil }
        return OriginalAuditEvent(
            requestId: raw["requestId"] as? String,
            targetType: targetType,
            targetId: targetId,
            action: raw["action"] as? String,
            afterJson: raw["afterJson"] as? String)
    }

    private static func successData(in body: Data) -> Any? {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return nil }
        guard isSuccess(object["code"]) else { return nil }
        guard let data = object["data"], !isJSONBool(data), !(data is NSNull) else { return nil }
        return data
    }

    private static func isSuccess(_ code: Any?) -> Bool {
        if isJSONBool(code) { return false }
        if let number = code as? NSNumber, number.intValue == 200 { return true }
        if let text = code as? String, text == "200" { return true }
        return false
    }

    private static func firstOrderID(_ rows: [OriginalAuditEvent]) -> Int64? {
        for event in rows {
            guard event.targetType == "ORDER" else { continue }
            return event.targetId
        }
        return nil
    }

    private static func positiveInt(_ value: Any?) -> Int? {
        guard let wide = positiveInt64(value), wide <= Int64(Int.max) else { return nil }
        return Int(wide)
    }

    private static func positiveInt64(_ value: Any?) -> Int64? {
        if isJSONBool(value) { return nil }
        if let number = value as? NSNumber {
            let intValue = number.int64Value
            guard intValue > 0, Double(intValue) == number.doubleValue else { return nil }
            return intValue
        }
        if let text = value as? String {
            guard let intValue = Int64(text), intValue > 0, String(intValue) == text else { return nil }
            return intValue
        }
        return nil
    }

    private static func isJSONBool(_ value: Any?) -> Bool {
        guard let number = value as? NSNumber else { return false }
        return CFGetTypeID(number as CFTypeRef) == CFBooleanGetTypeID()
    }
}
