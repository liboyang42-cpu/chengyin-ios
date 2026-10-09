import Foundation

/// Local extraction only. An identifier is not a receipt, ownership proof or approval.
/// The existing reviewed VERIFY_SUBMISSION command remains the only validation path.
public struct MerchantStationSubmissionCode: Equatable {
    public enum Format: Equatable { case decimal, json, query }
    public enum Failure: Error, Equatable { case oversized, unsupportedLink, invalid }
    public static let maximumInputBytes = 4_096
    public let submissionID: String
    public let format: Format

    public init(_ raw: String) throws {
        guard raw.utf8.count <= Self.maximumInputBytes else { throw Failure.oversized }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // The source accepts a query fragment but specifies no trusted QR URL host.
        // Reject all links rather than infer an origin or open/fetch pasted content.
        guard !value.contains("://"), !value.hasPrefix("//") else { throw Failure.unsupportedLink }
        let candidate: String
        if value.hasPrefix("{") {
            // A single exact field, with a decimal string or integer token. Parsing
            // lexical digits avoids Double precision loss and duplicate-key collapse.
            let pattern = #"\A\{[ \t\r\n]*"submissionId"[ \t\r\n]*:[ \t\r\n]*(?:"([1-9][0-9]{0,18})"|([1-9][0-9]{0,18}))[ \t\r\n]*\}\z"#
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
                  let range = Range(match.range(at: match.range(at: 1).location == NSNotFound ? 2 : 1), in: value) else { throw Failure.invalid }
            candidate = String(value[range]); format = .json
        } else if value.hasPrefix("?submissionId=") {
            candidate = String(value.dropFirst("?submissionId=".count)); format = .query
        } else { candidate = value; format = .decimal }
        // Java's positiveLong ultimately consumes a signed 64-bit value. Retain
        // exact decimal bytes, including IDs beyond JavaScript's safe integer range.
        guard !candidate.isEmpty, candidate.utf8.count <= 19,
              candidate.utf8.first != 48, candidate.utf8.allSatisfy({ (48...57).contains($0) }),
              let identifier = Int64(candidate), identifier > 0 else { throw Failure.invalid }
        submissionID = candidate
    }
}
