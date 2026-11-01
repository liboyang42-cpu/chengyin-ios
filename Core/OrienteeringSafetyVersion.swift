import Foundation

/// Safety version shown for a selected ordinary city course. Civil date uses the
/// course city timezone, never the device zone, GPS, or a fabricated coordinate.
public struct OrienteeringSafetyVersion: Equatable, Sendable {
    public let versionID: String
    public let courseID: Int
    public let cityTimeZoneIdentifier: String
    public let cityCivilDate: String
    public static func display(selection: OrdinaryCityCourseSelection, now: Date) -> OrienteeringSafetyVersion? {
        guard selection.courseID > 0, OrdinaryCityCourseSelector.versionOK(selection.safetyVersionID),
              let zone = TimeZone(identifier: selection.cityTimeZoneIdentifier),
              let civil = cityCivilDate(now: now, timeZone: zone) else { return nil }
        return OrienteeringSafetyVersion(
            versionID: selection.safetyVersionID, courseID: selection.courseID,
            cityTimeZoneIdentifier: selection.cityTimeZoneIdentifier, cityCivilDate: civil)
    }
    /// YYYY-MM-DD in the course city timezone. The device zone is not consulted.
    public static func cityCivilDate(now: Date, timeZone: TimeZone) -> String? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = Locale(identifier: "en_US_POSIX")
        let parts = calendar.dateComponents([.year, .month, .day], from: now)
        guard let year = parts.year, let month = parts.month, let day = parts.day,
              (1...9999).contains(year), (1...12).contains(month), (1...31).contains(day) else { return nil }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
    public func matches(_ selection: OrdinaryCityCourseSelection) -> Bool {
        versionID == selection.safetyVersionID && courseID == selection.courseID
            && cityTimeZoneIdentifier == selection.cityTimeZoneIdentifier
    }
}

extension OrdinaryCityCourseSelector {
    static func versionOK(_ value: String) -> Bool {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !text.isEmpty && text.utf8.count <= 64 && text == value
    }
}
