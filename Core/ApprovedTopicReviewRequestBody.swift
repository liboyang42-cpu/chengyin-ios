import Foundation

/// Bounded review wire budget, shared by the client, outer route and durable-intent preflight.
/// Thirty-two exact sources with positive signed-64-bit IDs require at most 13,630
/// prepare bytes or 13,843 submit bytes (36-byte UUID); the backend's 128-byte request
/// ID ceiling yields 13,935. Only these two routes receive the 16 KiB allowance.
/// The coordinated backend uses at most 1,024 JSON tokens and depth 16 for these
/// exact allowlisted shapes (32-source prepare 841 tokens, submit 849).
public enum ApprovedTopicReviewRequestBody {
    public static let maximumSourceBodyBytes = 16 * 1024
    public static let maximumSelectorBodyBytes = 4096
    public static func maximumBytes(for path: String) -> Int {
        path == ApprovedTopicReviewPath.prepare || path == ApprovedTopicReviewPath.submit
            ? maximumSourceBodyBytes : maximumSelectorBodyBytes
    }
    /// Keep the original small envelope when no source selections are supplied.
    public static func maximumBytes(for path: String, fields: [String: ProjectEditJSON]) -> Int {
        fields["sourceSelections"] != nil ? maximumBytes(for: path) : maximumSelectorBodyBytes
    }
    public static func encode(_ fields: [String: ProjectEditJSON], path: String) throws -> Data {
        let encoded = try JSONEncoder().encode(fields)
        guard encoded.count <= maximumBytes(for: path, fields: fields) else { throw ApprovedTopicReleaseError.invalidResponse }
        return encoded
    }
    /// Check the complete submit command, never just its smaller prepare selector.
    /// This does not grant submit authority or mutate an existing historical intention.
    public static func preflight(_ command: ApprovedTopicReviewCommand, capture: ApprovedTopicReviewCapture) throws {
        _ = try ApprovedTopicReviewCommand.decode(.object(command.fields), capture: capture)
        _ = try encode(command.fields, path: ApprovedTopicReviewPath.submit)
    }
}
