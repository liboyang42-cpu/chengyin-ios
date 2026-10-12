import Foundation

/// Optional, ordered registration derivatives. Only returned safe server URLs
/// enter the draft; local image bytes and picker identifiers never serialize.
public struct MerchantOnboardingBrandImages: Equatable {
    public static let limit = 6
    public private(set) var urls: [String]
    public init(urls: [String] = []) throws {
        guard urls.count <= Self.limit else { throw APIError.invalidRequest }
        self.urls = try urls.map(Self.checkedURL)
    }
    public init(source: String) throws {
        try self.init(urls: source.split(separator: ",").map(String.init).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    }
    public var wireValue: String { urls.joined(separator: ",") }
    public var canAdd: Bool { urls.count < Self.limit }
    public mutating func append(serverURL: String) throws {
        guard canAdd else { throw APIError.invalidRequest }
        urls.append(try Self.checkedURL(serverURL))
    }
    public mutating func remove(at index: Int) throws {
        guard urls.indices.contains(index) else { throw APIError.invalidRequest }
        urls.remove(at: index)
    }
    private static func checkedURL(_ raw: String) throws -> String {
        let value = try MerchantOnboardingLicense(serverURL: raw).url
        guard !value.contains(","), !value.contains("\n"), !value.contains("\r") else { throw APIError.invalidRequest }
        return value
    }
}
