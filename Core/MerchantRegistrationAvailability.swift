import Foundation

/// Explicit replacement of a registration's availability, matching Mini civil strings.
/// These are calendar days and wall-clock minutes, never inferred UTC instants.
public struct MerchantRegistrationAvailability: Codable, Equatable {
    public var startDay: String
    public var endDay: String
    public var startMinutes: Int
    public var endMinutes: Int
    public init(startDay: String, endDay: String, startMinutes: Int = 540, endMinutes: Int = 1080) {
        self.startDay = startDay; self.endDay = endDay; self.startMinutes = startMinutes; self.endMinutes = endMinutes
    }
    public var isValid: Bool {
        Self.validDay(startDay) && Self.validDay(endDay) && startDay <= endDay
            && (0..<1440).contains(startMinutes) && (0..<1440).contains(endMinutes) && startMinutes < endMinutes
    }
    public static func validDay(_ day: String) -> Bool { MerchantStationCommand.validTime(day + " 00:00") }
    public var dailyTime: String { MerchantStoreHours.clock(startMinutes) + "-" + MerchantStoreHours.clock(endMinutes) }
    public func fields() throws -> [String: MerchantContentValue] {
        guard isValid else { throw MerchantContentFailure.invalid }
        return ["startDate": .string(startDay + " 00:00:00"), "endDate": .string(endDay + " 23:59:59"), "cooperateDate": .string(dailyTime)]
    }
    public func pickerDate(start: Bool) -> Date? {
        MerchantStationServiceWindow(day: start ? startDay : endDay).pickerDate
    }
    public mutating func selectDay(_ date: Date, start: Bool) {
        var carrier = MerchantStationServiceWindow(day: ""); carrier.selectPickerDate(date)
        if start { startDay = carrier.day } else { endDay = carrier.day }
    }
    public init?(source: MerchantRegistrationAvailabilitySource) {
        func day(_ value: MerchantContentValue, suffix: String) -> String? {
            guard let raw = value.text else { return nil }
            let result: String
            if raw.count == 10 { result = raw }
            else if raw.count == 19, raw.hasSuffix(suffix) { result = String(raw.prefix(10)) }
            else { return nil }
            return Self.validDay(result) ? result : nil
        }
        guard let start = day(source.start, suffix: " 00:00:00"), let end = day(source.end, suffix: " 23:59:59"),
              let raw = source.daily.text, raw.range(of: #"^(?:[01][0-9]|2[0-3]):[0-5][0-9]-(?:[01][0-9]|2[0-3]):[0-5][0-9]$"#, options: .regularExpression) != nil else { return nil }
        let parts = raw.split(whereSeparator: { $0 == ":" || $0 == "-" }).compactMap { Int($0) }
        guard parts.count == 4 else { return nil }
        self.init(startDay: start, endDay: end, startMinutes: parts[0] * 60 + parts[1], endMinutes: parts[2] * 60 + parts[3])
        guard isValid else { return nil }
    }
}
public struct MerchantRegistrationAvailabilitySource: Equatable {
    public let start: MerchantContentValue
    public let end: MerchantContentValue
    public let daily: MerchantContentValue
    public init(_ detail: MerchantContentValue) { start = detail["startDate"]; end = detail["endDate"]; daily = detail["cooperateDate"] }
    public var isEmpty: Bool { [start, end, daily].allSatisfy { $0 == .null || $0.text == "" } }
}
public extension MerchantRegistrationContentDraft {
    /// Only update uses this path. A nil replacement leaves all original date bytes on the server.
    func fieldsIncludingAvailability() throws -> [String: MerchantContentValue] {
        var result = try fields()
        if let availabilityReplacement { result.merge(try availabilityReplacement.fields()) { _, replacement in replacement } }
        return result
    }
}
public extension MerchantContentCommand {
    var registrationAvailability: MerchantRegistrationAvailability? {
        if case .updateRegistration(_, _, let draft) = self { return draft.availabilityReplacement }
        return nil
    }
}
