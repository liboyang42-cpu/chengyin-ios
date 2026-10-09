import Foundation

public struct MerchantDecorTagDraft: Equatable, Sendable {
    public enum Failure: Error, Equatable { case empty, tooLong, limit }
    public struct Group: Sendable {
        public let key: String
        public let values: [String]
    }
    public static let groups: [Group] = [
        .init(key: "space", values: ["老街", "天台", "独立空间", "宠物友好", "夜间开放", "适合拍照"]),
        .init(key: "experience", values: ["适合单人", "适合情侣", "适合亲子", "适合组队", "雨天可去", "安静"]),
        .init(key: "audience", values: ["学生党", "上班族", "摄影爱好者", "美食探店", "亲子家庭", "潮流青年"])
    ]
    public private(set) var selected: [String]
    public init(selected: [String]) { self.selected = selected }
    public var canApply: Bool { selected.count <= 12 }
    public func contains(_ tag: String) -> Bool { selected.contains { Self.equal($0, tag) } }
    public mutating func toggle(_ tag: String) throws {
        if let index = selected.firstIndex(where: { Self.equal($0, tag) }) { selected.remove(at: index) }
        else { guard selected.count < 12 else { throw Failure.limit }; selected.append(tag) }
    }
    public mutating func remove(at index: Int) { if selected.indices.contains(index) { selected.remove(at: index) } }
    public mutating func addCustom(_ raw: String) throws {
        let tag = raw.trimmingCharacters(in: Self.sourceWhitespace)
        guard !tag.isEmpty else { throw Failure.empty }
        guard raw.utf16.count <= 16 else { throw Failure.tooLong }
        guard selected.count <= 12, contains(tag) || selected.count < 12 else { throw Failure.limit }
        if !contains(tag) { selected.append(tag) }
    }
    /// Source indexOf uses literal code units; do not fold case or normalize custom tags.
    public static func equal(_ lhs: String, _ rhs: String) -> Bool { lhs.utf16.elementsEqual(rhs.utf16) }
    public static func equal(_ lhs: [String], _ rhs: [String]) -> Bool {
        lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { equal($0.0, $0.1) }
    }
    private static let sourceWhitespace = CharacterSet(charactersIn:
        "\u{0009}\u{000B}\u{000C}\u{0020}\u{00A0}\u{1680}\u{2000}\u{2001}\u{2002}\u{2003}\u{2004}\u{2005}\u{2006}\u{2007}\u{2008}\u{2009}\u{200A}\u{202F}\u{205F}\u{3000}\u{FEFF}\u{000A}\u{000D}\u{2028}\u{2029}")
}
