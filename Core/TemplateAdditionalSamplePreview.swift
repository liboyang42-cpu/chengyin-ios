import Foundation

/// Additional source examples. Never writes an authoring model or emits gameplay evidence.
public struct TemplateAdditionalSamplePreview {
    public enum Choice: String, CaseIterable, Identifiable {
        case predict, pricePair, dice, d20
        public var id: String { rawValue }
        public var labelKey: String { "templateSampleCoverage.choice." + rawValue }
        public var family: TemplateCreatorFamily? {
            switch self { case .predict: return .predict; case .pricePair: return .pricePair; default: return nil }
        }
        public var section: String { family?.rawValue ?? "diceRoll" }
    }
    public let choice: Choice
    public let draft: TemplateAdvancedDraft
    public let filledFields: [String]
    public init?(_ original: TemplateAdvancedDraft, choice: Choice) {
        guard original.value[choice.section]?.object != nil else { return nil }
        var copy = original, pristine = TemplateAdvancedDraft()
        if choice == .dice { copy.setDiceMode("d6") }
        if choice == .d20 {
            pristine.setDiceMode("d20")
            // Only changing mode initializes the existing native mode defaults in the copy.
            // Missing fields in an already-D20 draft are not silently repaired.
            if copy.diceMode != "d20" { copy.setDiceMode("d20") }
        }
        guard var fields = copy.value[choice.section]?.object,
              let defaults = pristine.value[choice.section]?.object,
              let demos = try? JSONDecoder().decode([String: [String: TemplateAuthoringJSON]].self, from: Data(Self.demoJSON.utf8)),
              let demo = demos[choice.rawValue] else { return nil }
        var filled: [String] = []
        for key in demo.keys.sorted() {
            guard let current = fields[key], let expected = defaults[key],
                  let bytes = Self.bytes(current), bytes == Self.bytes(expected), let value = demo[key] else { continue }
            fields[key] = value; filled.append(key)
        }
        fields["enabled"] = .bool(true); copy.value[choice.section] = .object(fields)
        if choice == .dice, (try? TemplateD6Rehearsal(draft: copy)) == nil { return nil }
        if choice == .d20, (try? TemplateD20Rehearsal(draft: copy)) == nil { return nil }
        self.choice = choice; draft = copy; filledFields = filled
    }
    private static func bytes<T: Encodable>(_ value: T) -> Data? {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try? encoder.encode(value)
    }
    private static let demoJSON = #"""
{
  "predict": {
    "question": "明天中午哪种豆子卖得更多?",
    "options": [
      {
        "key": "A",
        "label": "耶加雪菲"
      },
      {
        "key": "B",
        "label": "曼特宁"
      }
    ]
  },
  "pricePair": {
    "title": "哪一张是这家店的老招牌?",
    "items": [
      {
        "id": "pic_1",
        "name": "木牌",
        "imageUrl": "",
        "correct": true
      },
      {
        "id": "pic_2",
        "name": "霓虹灯",
        "imageUrl": "",
        "correct": false
      },
      {
        "id": "pic_3",
        "name": "手写纸板",
        "imageUrl": "",
        "correct": false
      }
    ]
  },
  "dice": {
    "kicker": "掷到几就做第几件事",
    "faces": [
      "和店员说句今天的天气",
      "换个位置坐",
      "点一杯没喝过的",
      "拍一张门口",
      "把杯子摆正",
      "写一句留言"
    ]
  },
  "d20": {
    "kicker": "观察暗门",
    "successText": "你发现了门后的线索",
    "failText": "暂时没有发现，沿街继续寻找"
  }
}
"""#
}
