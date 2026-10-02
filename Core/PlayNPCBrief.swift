import Foundation

/// Source /api/play/nodes row.npc only. No merchant-row bridge, persona, avatar or voice URL.
public struct PlayNPCBrief: Decodable, Equatable {
    public let name: String
    public let greeting: String?
    private enum CodingKeys: String, CodingKey { case name, greeting }
    public init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        name = try fields.decode(String.self, forKey: .name)
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw APIError.malformedResponse }
        greeting = try fields.decodeIfPresent(String.self, forKey: .greeting)
    }
}
