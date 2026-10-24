import Foundation

/// A removal-only proposal bound to exact source bytes. Duplicate references keep
/// separate original indices; no caller can supply replacement or reordered URLs.
public struct ProfileCasePictureSubset: Equatable {
    let source: String
    public let retainedIndices: [Int]
    public let originalCount: Int
    private let references: [String]
    public init(source: String, retainedIndices: [Int]) throws {
        guard source.utf8.count <= 64 * 1024 else { throw APIError.invalidRequest }
        let values = source.split(separator: ";", omittingEmptySubsequences: false)
            .map(String.init).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard values.count <= 100, retainedIndices.allSatisfy({ values.indices.contains($0) }),
              zip(retainedIndices, retainedIndices.dropFirst()).allSatisfy({ $0.0 < $0.1 }) else { throw APIError.invalidRequest }
        self.source = source; self.retainedIndices = retainedIndices
        references = values; originalCount = values.count
    }
    public var hasChanges: Bool { retainedIndices != Array(0..<originalCount) }
    public var retainedCount: Int { retainedIndices.count }
    public var wireValue: String {
        hasChanges ? retainedIndices.map { references[$0] }.joined(separator: ";") : source
    }
    public func matches(source: String) -> Bool { self.source.utf8.elementsEqual(source.utf8) }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.source.utf8.elementsEqual(rhs.source.utf8) && lhs.retainedIndices == rhs.retainedIndices
    }
}
