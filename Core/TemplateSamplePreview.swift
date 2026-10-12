import Foundation

/// Source-backed examples exist only in this hypothetical author-local copy.
public struct TemplateSamplePreview {
    public enum Group: String, CaseIterable, Identifiable {
        case questions, interaction, challenge
        public var id: String { rawValue }
        public var labelKey: String { "templateSamples.group." + rawValue }
    }
    public enum Choice: String, CaseIterable, Identifiable {
        case qaText, qaPick, estimate, random, profile, note, typeIn
        public var id: String { rawValue }
        public var labelKey: String { "templateSamples.choice." + rawValue }
        public var family: TemplateCreatorFamily {
            switch self {
            case .qaText, .qaPick: return .qa
            case .estimate: return .estimate
            case .random: return .random
            case .profile: return .profile
            case .note: return .note
            case .typeIn: return .typeIn
            }
        }
        public var group: Group {
            switch self { case .qaText, .qaPick: return .questions; case .typeIn: return .challenge; default: return .interaction }
        }
    }
    public let choice: Choice
    public let draft: TemplateAdvancedDraft
    public let filledFields: [String]
    public init?(_ original: TemplateAdvancedDraft, choice: Choice) {
        guard var fields = original.value[choice.family.rawValue]?.object,
              let pristine = TemplateAdvancedDraft.defaults[choice.family.rawValue]?.object,
              let examples = try? JSONDecoder().decode([String: [String: TemplateAuthoringJSON]].self, from: Data(Self.demoJSON.utf8)),
              let demo = examples[choice.rawValue] else { return nil }
        var filled: [String] = []
        for key in demo.keys.sorted() {
            // An omitted or explicitly changed field is not pristine. Never overwrite it.
            guard let current = fields[key], let expected = pristine[key],
                  let bytes = Self.bytes(current), bytes == Self.bytes(expected), let example = demo[key] else { continue }
            fields[key] = example; filled.append(key)
        }
        fields["enabled"] = .bool(true)
        if choice == .qaText { fields["mode"] = .string("TYPE") }
        if choice == .qaPick { fields["mode"] = .string("PICK") }
        var copy = original; copy.value[choice.family.rawValue] = .object(fields)
        self.choice = choice; draft = copy; filledFields = filled
    }
    public static func snapshot(_ draft: TemplateAuthoringDraft) -> Data? { bytes(draft) }
    private static func bytes<T: Encodable>(_ value: T) -> Data? {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try? encoder.encode(value)
    }
    // Bounded demo fields derived from node-game-catalog DEMO; not the private source module.
    private static let demoJSON = #"""
{
  "qaText": {
    "title": "这座桥建于哪一年?",
    "answerText": "1937"
  },
  "qaPick": {
    "title": "石碑上的图案象征什么?",
    "options": [
      {
        "id": "opt_1",
        "label": "丰收",
        "fb": "对了,是麦穗。",
        "correct": true
      },
      {
        "id": "opt_2",
        "label": "远航",
        "fb": "再看看穗子。",
        "correct": false
      }
    ]
  },
  "estimate": {
    "title": "这罐豆子有多少颗?",
    "unit": "颗",
    "reveal": "一共 480 颗,老板数了两遍。",
    "answer": 480
  },
  "random": {
    "deckName": "今日线索卡",
    "items": [
      {
        "id": "item_1",
        "label": "线索卡",
        "weight": 1,
        "content": "去吧台问一句今天的手冲是什么。"
      },
      {
        "id": "item_2",
        "label": "任务卡",
        "weight": 1,
        "content": "找到店里最旧的那样东西,拍下来。"
      },
      {
        "id": "item_3",
        "label": "彩蛋卡",
        "weight": 1,
        "content": "跟店员说「今天的天气」,看他回你什么。"
      }
    ]
  },
  "profile": {
    "title": "旅人登记",
    "lead": "留下你的名字，准备出发",
    "questions": [
      {
        "key": "name",
        "label": "怎么称呼你",
        "kind": "text",
        "maxLength": 12,
        "required": true
      },
      {
        "key": "destination",
        "label": "想去哪里",
        "kind": "pick",
        "required": true,
        "options": [
          {
            "key": "sea",
            "label": "海边",
            "effects": []
          },
          {
            "key": "mountain",
            "label": "山间",
            "effects": []
          }
        ]
      }
    ]
  },
  "note": {
    "title": "留给下一位旅人",
    "prompt": "写下此刻想说的话",
    "presets": [
      "慢慢走",
      "前面有好风景"
    ]
  },
  "typeIn": {
    "title": "输入通行口令",
    "target": "今天也要出发",
    "seconds": 20
  }
}
"""#
}
