import Foundation

/// Deterministic author-local inspection. No player roll, payment, outcome, or reward.
public struct TemplateCoinFlipRehearsal: Equatable {
    public enum Mode: Equatable { case currentConfiguration, sourceExample }
    public enum Face: String, CaseIterable, Identifiable {
        case heads = "HEADS", tails = "TAILS"
        public var id: String { rawValue }
        public var labelKey: String { self == .heads ? "templateCoin.heads" : "templateCoin.tails" }
    }
    public struct Side: Equatable {
        public let label: String
        public let action: String
    }
    public struct Result: Equatable {
        public let face: Face
        public let side: Side
    }
    public let draft: TemplateAdvancedDraft
    public let mode: Mode
    public let kicker: String
    public let heads: Side
    public let tails: Side
    public let filledFields: [String]
    public private(set) var selection: Face = .heads
    public private(set) var result: Result?

    public init?(_ original: TemplateAdvancedDraft, mode: Mode) {
        guard var fields = original.value["coinFlip"]?.object else { return nil }
        var filled: [String] = []
        if mode == .sourceExample {
            guard let defaults = TemplateAdvancedDraft.defaults["coinFlip"]?.object,
                  let demo = try? JSONDecoder().decode([String: TemplateAuthoringJSON].self, from: Data(Self.demoJSON.utf8)) else { return nil }
            for key in demo.keys.sorted() {
                guard let current = fields[key], let expected = defaults[key],
                      let bytes = Self.bytes(current), bytes == Self.bytes(expected), let example = demo[key] else { continue }
                fields[key] = example; filled.append(key)
            }
            fields["enabled"] = .bool(true)
        }
        func read(_ object: [String: TemplateAuthoringJSON], _ key: String, fallback: String = "") -> String? {
            guard let raw = object[key] else { return fallback }
            guard let text = raw.string else { return nil }
            let clean = TemplateAuthoringStory.sourceTrim(text)
            return clean.isEmpty ? fallback : clean
        }
        func side(_ key: String, fallback: String) -> Side? {
            guard fields[key] == nil || fields[key]?.object != nil else { return nil }
            let object = fields[key]?.object ?? [:]
            guard let label = read(object, "label", fallback: fallback), let action = read(object, "action") else { return nil }
            return .init(label: label, action: action)
        }
        guard let kicker = read(fields, "kicker", fallback: "抛一次,认结果"),
              let heads = side("heads", fallback: "正面"), let tails = side("tails", fallback: "反面") else { return nil }
        var copy = original; copy.value["coinFlip"] = .object(fields)
        self.draft = copy; self.mode = mode; self.kicker = kicker
        self.heads = heads; self.tails = tails; filledFields = filled
    }
    public func side(_ face: Face) -> Side { face == .heads ? heads : tails }
    public mutating func select(_ face: Face) { selection = face; result = nil }
    public mutating func showSelectedResult() { result = .init(face: selection, side: side(selection)) }
    public mutating func reset() { selection = .heads; result = nil }
    private static func bytes<T: Encodable>(_ value: T) -> Data? {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try? encoder.encode(value)
    }
    // Only the bounded DEMO data; the private source module is not part of this product.
    private static let demoJSON = #"""
{"kicker":"抛完照做","heads":{"label":"正面","action":"这杯店家请"},"tails":{"label":"反面","action":"你请下一杯"}}
"""#
}
