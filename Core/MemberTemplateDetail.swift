import Foundation

/// cms_member_template identity. Never substitute a public-library ID with the same number.
public struct MemberPlayTemplateID: RawRepresentable, Hashable {
    public let rawValue: Int
    public init?(rawValue: Int) { guard rawValue > 0 else { return nil }; self.rawValue = rawValue }
}
/// Presentation-only whitelist from /api/template/myinfo. Answers, verification secrets and
/// authoring mechanics are deliberately not retained in this read-only detail projection.
public struct MemberTemplateDetail: Decodable, Equatable {
    public let id: MemberPlayTemplateID
    public let overview: DiscoveryPlayTemplate
    public let memberID: Int?
    public let draftStatus: Int?
    public let gallery: [String]
    public let story: [MemberTemplateStoryPart]
    public init(from decoder: Decoder) throws {
        overview = try DiscoveryPlayTemplate(from: decoder)
        guard let id = MemberPlayTemplateID(rawValue: overview.id) else { throw APIError.malformedResponse }
        self.id = id
        let raw = try PlayWireValue(from: decoder)
        memberID = raw["memberId"].tolerantInteger.flatMap { $0 > 0 ? $0 : nil }
        draftStatus = raw["draftStatus"].tolerantInteger
        gallery = Self.images(overview.imgUrl)
        if let storyJSON = raw["storyJson"].text, !storyJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Corrupt optional authored rich content is not an empty successful story.
            guard let bytes = storyJSON.data(using: .utf8), let rows = try? JSONDecoder().decode([PlayWireValue].self, from: bytes),
                  rows.allSatisfy({ $0.object != nil }) else { throw APIError.malformedResponse }
            story = rows.enumerated().map { index, row in
                MemberTemplateStoryPart(id: index, text: ParticipationRecord.text(row["text"]),
                    tag: ParticipationRecord.text(row["tag"]), images: Self.storyImages(row))
            }
        } else { story = [] }
    }
    private static func storyImages(_ row: PlayWireValue) -> [String] {
        // Current arrays are authoritative, including an explicit empty array.
        if let images = row["imgs"].array { return images.compactMap(\.text) }
        // Legacy DTO storyJson used one `img` string. Missing/null imgs can use it;
        // malformed non-array imgs must not silently select a different source.
        guard case .null = row["imgs"], case .string(let legacy) = row["img"], !legacy.isEmpty else { return [] }
        // Projection is not URL approval. Existing media readers still enforce origins/schemes.
        return [legacy]
    }
    private static func images(_ raw: String?) -> [String] {
        guard let raw else { return [] }
        if let data = raw.data(using: .utf8), let rows = try? JSONDecoder().decode([String].self, from: data) {
            return rows.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }
        return raw.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
}
public struct MemberTemplateStoryPart: Equatable, Identifiable {
    public let id: Int
    public let text: String?
    public let tag: String?
    public let images: [String]
}
@MainActor public protocol MemberTemplateReading: AnyObject {
    var scope: UUID { get }
    var isAuthenticated: Bool { get }
    var isConfigured: Bool { get }
    func memberTemplate(id: MemberPlayTemplateID) async throws -> MemberTemplateDetail
}
