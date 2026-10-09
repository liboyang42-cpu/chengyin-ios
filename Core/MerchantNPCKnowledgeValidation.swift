import Foundation

extension MerchantNPCKnowledgeDraft {
    var fieldIssues: [MerchantNPCKnowledgeIssue] {
        var issues: [MerchantNPCKnowledgeIssue] = []
        func issue(_ section: MerchantNPCKnowledgeIssue.Section, _ row: Int? = nil, _ field: String? = nil, _ kind: MerchantNPCKnowledgeIssue.Kind) {
            issues.append(.init(section: section, row: row, field: field, kind: kind))
        }
        func text(_ value: String, _ max: Int, _ section: MerchantNPCKnowledgeIssue.Section, _ row: Int, _ field: String) {
            if !Self.validText(value, max: max) { issue(section, row, field, .text) }
        }
        for (section, count, limit) in [(MerchantNPCKnowledgeIssue.Section.products, products.count, 40),
                                      (.hours, hours.count, 7), (.promotions, promotions.count, 20),
                                      (.faq, faq.count, 30), (.neverSay, neverSay.count, 30)] {
            if count > limit { issue(section, nil, nil, .count) }
        }
        for (index, value) in products.enumerated() {
            text(value.name, 120, .products, index, "name")
            // ASCII integral minor units only; no floats, exponents, signs or locale separators.
            if value.priceMinor.isEmpty || !value.priceMinor.utf8.allSatisfy({ (48...57).contains($0) }) ||
                Int64(value.priceMinor).map({ !(0...100_000_000).contains($0) }) != false {
                issue(.products, index, "priceMinor", .price)
            }
            if value.currency.utf8.count != 3 || !value.currency.utf8.allSatisfy({ (65...90).contains($0) }) {
                issue(.products, index, "currency", .currency)
            }
        }
        var days = Set<Int>()
        for (index, value) in hours.enumerated() {
            if !(1...7).contains(value.day) { issue(.hours, index, "day", .day) }
            if !days.insert(value.day).inserted { issue(.hours, index, "day", .duplicateDay) }
            let opens = Self.clockMinute(value.opens), closes = Self.clockMinute(value.closes)
            if opens == nil { issue(.hours, index, "opens", .clock) }
            if closes == nil { issue(.hours, index, "closes", .clock) }
            if let opens, let closes, opens >= closes { issue(.hours, index, "closes", .order) }
            if !Self.validText(value.timeZone, max: 64) || !Self.validZone(value.timeZone) {
                issue(.hours, index, "timeZone", .timeZone)
            }
        }
        for (index, value) in promotions.enumerated() {
            text(value.title, 300, .promotions, index, "title")
            let start = Self.instant(value.startsAt), end = Self.instant(value.endsAt)
            if start == nil { issue(.promotions, index, "startsAt", .instant) }
            if end == nil { issue(.promotions, index, "endsAt", .instant) }
            if let start, let end, !(start < end) { issue(.promotions, index, "endsAt", .order) }
        }
        for (index, value) in faq.enumerated() {
            text(value.question, 200, .faq, index, "question"); text(value.answer, 600, .faq, index, "answer")
        }
        for (index, value) in neverSay.enumerated() { text(value.text, 200, .neverSay, index, "text") }
        return issues
    }

    /// Matches the source's Java UTF-16 limits, trim() boundary and ISO-control rejection.
    static func validText(_ value: String, max: Int) -> Bool {
        value.utf16.count <= max && value.unicodeScalars.contains(where: { $0.value > 32 }) &&
            !value.unicodeScalars.contains(where: { $0.value < 32 || (127...159).contains($0.value) })
    }
    static func clockMinute(_ value: String) -> Int? {
        let bytes = Array(value.utf8)
        guard bytes.count == 5, bytes[2] == 58,
              [0, 1, 3, 4].allSatisfy({ (48...57).contains(bytes[$0]) }) else { return nil }
        let hour = Int(bytes[0] - 48) * 10 + Int(bytes[1] - 48)
        let minute = Int(bytes[3] - 48) * 10 + Int(bytes[4] - 48)
        return hour < 24 && minute < 60 ? hour * 60 + minute : nil
    }
    static func validZone(_ value: String) -> Bool {
        if ["Z", "UTC", "GMT", "UT"].contains(value) { return true }
        var offset = value
        for prefix in ["UTC", "GMT", "UT"] where offset.hasPrefix(prefix) { offset = String(offset.dropFirst(prefix.count)); break }
        if offset.hasPrefix("+") || offset.hasPrefix("-") {
            let number = String(offset.dropFirst())
            guard !number.isEmpty, number.utf8.allSatisfy({ (48...57).contains($0) || $0 == 58 }) else { return false }
            let parts: [String]
            if number.contains(":") {
                parts = number.components(separatedBy: ":")
                guard (2...3).contains(parts.count), parts.allSatisfy({ $0.utf8.count == 2 }) else { return false }
            } else {
                guard [1, 2, 4, 6].contains(number.utf8.count) else { return false }
                if number.count <= 2 { parts = [number] }
                else { let chars = Array(number); parts = stride(from: 0, to: chars.count, by: 2).map { String(chars[$0..<($0 + 2)]) } }
            }
            guard parts.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } }) else { return false }
            let values = parts.compactMap(Int.init)
            guard values.count == parts.count, let hours = values.first, hours <= 18 else { return false }
            let minutes = values.count > 1 ? values[1] : 0, seconds = values.count > 2 ? values[2] : 0
            return minutes < 60 && seconds < 60 && (hours < 18 || (minutes == 0 && seconds == 0))
        }
        // Use installed IANA identifiers, not localized abbreviations (CST, PST, etc.).
        return TimeZone.knownTimeZoneIdentifiers.contains(value)
    }

    struct InstantValue: Comparable {
        let seconds: Int64
        let nanos: Int
        static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.seconds == rhs.seconds ? lhs.nanos < rhs.nanos : lhs.seconds < rhs.seconds
        }
    }
    /// Strict UTC/offset ISO instant with a separate nanosecond comparison. Date alone
    /// would collapse two distinct 9-digit fractions and could admit/reject the wrong order.
    /// The editor supports four-digit calendar years; wider Java Instant years are not imported.
    static func instant(_ value: String) -> InstantValue? {
        guard validText(value, max: 30) else { return nil }
        let pattern = #"^([0-9]{4})-([0-9]{2})-([0-9]{2})[Tt]([0-9]{2}):([0-9]{2}):([0-9]{2})(?:\.([0-9]{1,9}))?([Zz]|[+-][0-9]{2}:[0-9]{2})$"#
        guard let match = value.range(of: pattern, options: .regularExpression), match == value.startIndex..<value.endIndex else { return nil }
        let bytes = Array(value.utf8)
        func number(_ range: Range<Int>) -> Int { Int(String(decoding: bytes[range], as: UTF8.self))! }
        let year = number(0..<4), month = number(5..<7), day = number(8..<10)
        var hour = number(11..<13), minute = number(14..<16), second = number(17..<19)
        guard year >= 1, (1...12).contains(month), (1...31).contains(day), hour <= 24, minute < 60, second <= 60 else { return nil }
        let suffix = String(value.dropFirst(19))
        let zoneStart = suffix.firstIndex(where: { $0 == "Z" || $0 == "z" || $0 == "+" || $0 == "-" })!
        let fraction = String(suffix[..<zoneStart]).dropFirst()
        let nanos = fraction.isEmpty ? 0 : Int(String(fraction) + String(repeating: "0", count: 9 - fraction.count))!
        var nextDay = false
        if hour == 24 { guard minute == 0, second == 0, nanos == 0 else { return nil }; hour = 0; nextDay = true }
        if second == 60 { guard hour == 23, minute == 59 else { return nil }; second = 59 }
        let zone = String(suffix[zoneStart...])
        var offset = 0
        if zone != "Z" && zone != "z" {
            let zoneBytes = Array(zone.utf8), hours = Int(zoneBytes[1] - 48) * 10 + Int(zoneBytes[2] - 48)
            let minutes = Int(zoneBytes[4] - 48) * 10 + Int(zoneBytes[5] - 48)
            guard hours <= 18, minutes < 60, hours < 18 || minutes == 0 else { return nil }
            offset = (hours * 3600 + minutes * 60) * (zoneBytes[0] == 45 ? -1 : 1)
        }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
        guard let date = calendar.date(from: components) else { return nil }
        let readback = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        guard readback.year == year, readback.month == month, readback.day == day,
              readback.hour == hour, readback.minute == minute, readback.second == second else { return nil }
        return .init(seconds: Int64(date.timeIntervalSince1970.rounded()) + (nextDay ? 86_400 : 0) - Int64(offset), nanos: nanos)
    }
}
