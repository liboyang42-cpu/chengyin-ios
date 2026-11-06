import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Shape/privacy checks only. This does not grant access; the composition still checks the
/// exact reviewed owner/realm/role grant and live authenticated token before final forwarding.
@MainActor enum PrivateHomeRequestBoundary {
    static func accepts(_ request: URLRequest, baseURL: URL) -> Bool {
        guard request.url?.absoluteString.utf8.elementsEqual(baseURL.appendingPathComponent(PrivateHomeService.path).absoluteString.utf8) == true,
              request.httpBodyStream == nil,
              request.cachePolicy == .reloadIgnoringLocalCacheData,
              request.value(forHTTPHeaderField: "Cache-Control") == "no-store",
              request.value(forHTTPHeaderField: "Pragma") == "no-cache" else { return false }
        if request.httpMethod == "GET" { return request.httpBody == nil }
        guard request.httpMethod == "PUT" || request.httpMethod == "DELETE",
              request.value(forHTTPHeaderField: "Content-Type") == "application/json",
              let body = request.httpBody, body.count <= 16_384,
              let text = String(data: body, encoding: .utf8), text.utf16.count <= 4_096,
              let fields = FlatJSON.parse(body),
              case .string(let requestID)? = fields["requestId"],
              case .number(let versionToken)? = fields["expectedVersion"],
              !versionToken.contains("."), !versionToken.lowercased().contains("e"),
              let version = Int64(versionToken) else { return false }
        if request.httpMethod == "DELETE" {
            return Set(fields.keys) == ["requestId", "expectedVersion"] &&
                (try? PrivateHomeMutation(requestId: requestID, expectedVersion: version)) != nil
        }
        guard Set(fields.keys) == ["requestId", "expectedVersion", "label", "latitude", "longitude", "datum"],
              case .string(let label)? = fields["label"],
              case .string("WGS84")? = fields["datum"],
              case .number(let latitudeToken)? = fields["latitude"],
              case .number(let longitudeToken)? = fields["longitude"],
              let latitude = coordinate(latitudeToken, limit: 90), let longitude = coordinate(longitudeToken, limit: 180),
              let point = try? PrivateHomePoint(latitude: latitude, longitude: longitude) else { return false }
        return (try? PrivateHomeMutation(requestId: requestID, expectedVersion: version, label: label, point: point)) != nil
    }

    /// Match the original BigDecimal stripTrailingZeros().scale <= 6 and range contract.
    /// Reduce the original token BEFORE Decimal conversion, so very long tails cannot round
    /// into a valid point. Whitespace, field order, escapes, exponents and trailing zeros are legal.
    private static func coordinate(_ token: String, limit: Decimal) -> Decimal? {
        let parts = token.lowercased().split(separator: "e", omittingEmptySubsequences: false)
        guard parts.count <= 2 else { return nil }
        let exponent: Int
        if parts.count == 2 {
            guard let value = Int32(parts[1]) else { return nil }; exponent = Int(value)
        } else { exponent = 0 }
        let coefficient = String(parts[0]).replacingOccurrences(of: "-", with: "")
        let fraction = coefficient.split(separator: ".", omittingEmptySubsequences: false)
        let fractionalCount = fraction.count == 2 ? fraction[1].count : 0
        let wireScale = fractionalCount - exponent
        guard (Int(Int32.min)...Int(Int32.max)).contains(wireScale) else { return nil }
        let digits = coefficient.filter { $0 != "." }
        if digits.allSatisfy({ $0 == "0" }) { return 0 }
        let trailing = digits.reversed().prefix(while: { $0 == "0" }).count
        let significant = digits.drop(while: { $0 == "0" }).dropLast(trailing)
        let (scale, scaleOverflow) = (fractionalCount - trailing).subtractingReportingOverflow(exponent)
        guard !scaleOverflow, scale <= 6 else { return nil }
        let (integerDigits, countOverflow) = significant.count.subtractingReportingOverflow(scale)
        guard !countOverflow, integerDigits <= 3 else { return nil }
        // At most nine significant digits remain for an in-range six-place coordinate.
        let sign = token.hasPrefix("-") ? "-" : ""
        guard let value = Decimal(string: sign + String(significant) + "e" + String(-scale), locale: Locale(identifier: "en_US_POSIX")),
              !value.isNaN, value >= -limit, value <= limit else { return nil }
        return value
    }

    /// Flat request object grammar: no unknown containers, nulls/booleans, duplicate decoded
    /// keys or trailing JSON. String decoding validates UTF-8/escapes; numbers retain raw tokens.
    private enum FlatJSON {
        enum Value { case string(String), number(String) }
        static func parse(_ data: Data) -> [String: Value]? {
            let bytes = Array(data); var index = 0
            func whitespace() { while index < bytes.count && [UInt8(9), 10, 13, 32].contains(bytes[index]) { index += 1 } }
            func take(_ byte: UInt8) -> Bool {
                guard index < bytes.count, bytes[index] == byte else { return false }; index += 1; return true
            }
            func string() -> String? {
                let start = index
                guard take(34) else { return nil }
                while index < bytes.count {
                    let byte = bytes[index]; index += 1
                    if byte == 34 { return try? JSONDecoder().decode(String.self, from: Data(bytes[start..<index])) }
                    if byte == 92 { guard index < bytes.count else { return nil }; index += 1 }
                }
                return nil
            }
            func number() -> String? {
                let start = index
                _ = take(45)
                if !take(48) {
                    guard index < bytes.count, (49...57).contains(bytes[index]) else { return nil }
                    while index < bytes.count && (48...57).contains(bytes[index]) { index += 1 }
                }
                if take(46) {
                    let digits = index
                    while index < bytes.count && (48...57).contains(bytes[index]) { index += 1 }
                    guard index > digits else { return nil }
                }
                if take(101) || take(69) {
                    if !take(43) { _ = take(45) }
                    let digits = index
                    while index < bytes.count && (48...57).contains(bytes[index]) { index += 1 }
                    guard index > digits else { return nil }
                }
                return String(bytes: bytes[start..<index], encoding: .utf8)
            }
            whitespace(); guard take(123) else { return nil }; whitespace()
            var fields: [String: Value] = [:]
            if take(125) { whitespace(); return index == bytes.count ? fields : nil }
            while index < bytes.count {
                guard let key = string(), fields[key] == nil else { return nil }
                whitespace(); guard take(58) else { return nil }; whitespace()
                if index < bytes.count && bytes[index] == 34 {
                    guard let value = string() else { return nil }; fields[key] = .string(value)
                } else {
                    guard let value = number() else { return nil }; fields[key] = .number(value)
                }
                whitespace()
                if take(125) { whitespace(); return index == bytes.count ? fields : nil }
                guard take(44) else { return nil }; whitespace()
            }
            return nil
        }
    }
}
