import Foundation

/// The authorized runtime chapter, not public topic/chapter marketing detail.
public struct ChapterStoryDocument: Equatable {
    public let chapterID: Int
    public let title: String?
    public let cover: String?
    public let description: String?
    public let blocks: [PlayWireValue]
    public init(raw: PlayWireValue) throws {
        guard let id = raw["chapterId"].tolerantInteger, id > 0 else { throw APIError.malformedResponse }
        chapterID = id
        title = ParticipationRecord.text(raw["title"]) ?? ParticipationRecord.text(raw["name"])
        cover = ParticipationRecord.text(raw["imgArr"]).flatMap { $0.components(separatedBy: ",").first }.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        description = ParticipationRecord.text(raw["description"])
        if raw["blocks"] == .null { blocks = [] }
        else {
            guard let blocks = raw["blocks"].array, blocks.allSatisfy({ $0.object != nil }) else { throw APIError.malformedResponse }
            self.blocks = blocks
        }
    }
}
public struct ChapterStorySegment: Equatable, Identifiable {
    public enum Content: Equatable {
        case text(String), image(String), audio(String), voice(speaker: String, text: String)
        case reveal(speaker: String, lines: [String]), dream(title: String?, images: [ChapterStoryDreamImage])
        case thought(name: String, description: String?), game(nodeID: Int)
        /// Text block marked `optional: true`: 「延伸阅读」, collapsed by default; `who` is its subtitle.
        case optionalReading(subtitle: String?, paragraphs: [String])
        /// Cast contract: a book-style paragraph whose speaker name sits in the leading margin.
        case line(ChapterStoryLine)
        /// E3: an unanswered story branch, numbered inside the reading column. Nothing after it shows.
        case choice(ChapterStoryChoice)
    }
    public let id: String
    public let content: Content
    public let mood: String?
    public let odd: Int
}
public struct ChapterStoryDreamImage: Equatable { public let url: String; public let line: String? }
/// One reading-column paragraph with an optional margin speaker. Never a bubble.
public struct ChapterStoryLine: Equatable {
    public enum Speaker: Equatable {
        /// A configured cast member (`castConfig.cast[].id`).
        case cast(String)
        /// The player; the margin shows the chosen name, or 「你」.
        case player
        /// Legacy `type:"text"` block `who`: a name with no card.
        case named(String)
    }
    /// Nil renders the line as plain text with no name (e.g. a removed cast id).
    public let speaker: Speaker?
    public let text: String
    /// Author recording (`media-asset:N` or https); empty means none.
    public let audioURL: String?
    /// Block key used for the lazy TTS request.
    public let blockKey: String?
    /// E3 「{name}会记住这件事」: cast ids whose trust the player's picked option changed.
    public let rememberedBy: [String]
    public init(speaker: Speaker?, text: String, audioURL: String? = nil, blockKey: String? = nil, rememberedBy: [String] = []) {
        self.speaker = speaker; self.text = text; self.audioURL = audioURL; self.blockKey = blockKey; self.rememberedBy = rememberedBy
    }
}

public enum ChapterStoryProjection {
    /// Scalar replacement only. Missing variables keep the authored token unless a fallback exists.
    public static func substitute(_ text: String, variables: [String: PlayWireValue]) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\{([a-zA-Z][a-zA-Z0-9_]{0,15})(?:\|([^}]{0,20}))?\}"#) else { return text }
        var output = text
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let full = Range(match.range, in: text), let key = Range(match.range(at: 1), in: text) else { continue }
            let name = String(text[key]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value: String?
            switch variables[name] {
            case .string(let s): value = s.isEmpty ? nil : s
            case .integer(let n): value = String(n)
            case .number(let n): value = n.isFinite ? String(n) : nil
            case .bool(let b): value = b ? "true" : "false"
            default: value = nil
            }
            let fallback = Range(match.range(at: 2), in: text).map { String(text[$0]) }
            if let replacement = value ?? fallback, !replacement.isEmpty { output.replaceSubrange(full, with: replacement) }
        }
        return output
    }
    /// Client rendering never reveals a block beyond the first incomplete OR unknown node.
    /// Backend projection is an independent security boundary; this is a spoiler guard.
    public static func segments(chapter: ChapterStoryDocument, snapshot: PlaySnapshot,
                                variables: [String: PlayWireValue], thoughts: [PlayWireValue] = [],
                                storyVoices: [String: PlayWireValue] = [:], activeInlineNodeID: Int? = nil,
                                cast: CastStoryContext? = nil) -> [ChapterStorySegment] {
        var result: [ChapterStorySegment] = []
        var mood: String?
        var odd = 0
        func append(_ content: ChapterStorySegment.Content, id: String) {
            result.append(.init(id: id, content: content, mood: mood, odd: odd))
        }
        func fill(_ text: String) -> String {
            let value = substitute(text, variables: variables)
            return cast.map { CastStoryVariables.fill(value, profile: $0.profile, config: $0.config) } ?? value
        }
        func paragraphs(_ raw: String?, prefix: String, who: String? = nil) {
            guard let raw else { return }
            var named = false
            for (index, value) in raw.components(separatedBy: .newlines).enumerated() {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                // `who` is drawn once, in the margin beside the first paragraph; never a 「某某：」 prefix.
                if let who, !named { named = true; append(.line(.init(speaker: .named(who), text: fill(trimmed))), id: "\(prefix).\(index)") }
                else { append(.text(fill(trimmed)), id: "\(prefix).\(index)") }
            }
        }
        func voices(_ nodeID: Int, prefix: String) {
            for (index, voice) in (storyVoices[String(nodeID)]?.array ?? []).enumerated() {
                if let text = ParticipationRecord.text(voice["text"]) {
                    append(.voice(speaker: voice["who"].text ?? "", text: fill(text)), id: "\(prefix).voice.\(index)")
                }
            }
        }
        if let cover = chapter.cover { append(.image(cover), id: "cover") }
        if chapter.blocks.isEmpty {
            paragraphs(chapter.description, prefix: "legacy")
            for node in snapshot.visibleNodes where node.chapterID == chapter.chapterID && snapshot.isDone(node) && !snapshot.isLocked(node) {
                if activeInlineNodeID == node.id { append(.game(nodeID: node.id), id: "game.\(node.id)") }
                voices(node.id, prefix: "legacy.\(node.id)")
                paragraphs(node.storyText, prefix: "note.\(node.id)")
            }
            if let node = snapshot.visibleNodes.first(where: { $0.chapterID == chapter.chapterID && !snapshot.isDone($0) && !snapshot.isLocked($0) }) {
                append(.game(nodeID: node.id), id: "game.\(node.id)")
            }
            return result
        }
        for (index, block) in chapter.blocks.enumerated() {
            let id = "block.\(index)"
            switch block["type"].text {
            case "node":
                guard let nodeID = block["nodeId"].tolerantInteger,
                      let node = snapshot.visibleNodes.first(where: { $0.id == nodeID && $0.chapterID == chapter.chapterID }),
                      !snapshot.isLocked(node) else { return result }
                if !snapshot.isDone(node) {
                    append(.game(nodeID: nodeID), id: id)
                    voices(nodeID, prefix: id)
                    return result
                }
                if activeInlineNodeID == nodeID { append(.game(nodeID: nodeID), id: id + ".game") }
                voices(nodeID, prefix: id)
                paragraphs(node.storyText, prefix: id + ".note")
            case "text":
                if block["optional"].bool == true {
                    let lines = (block["content"].text ?? "").components(separatedBy: .newlines).compactMap { value -> String? in
                        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
                        return value.isEmpty ? nil : fill(value)
                    }
                    let subtitle = block["who"].text?.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !lines.isEmpty { append(.optionalReading(subtitle: subtitle?.isEmpty == false ? subtitle : nil, paragraphs: lines), id: id) }
                } else {
                    let who = block["who"].text?.trimmingCharacters(in: .whitespacesAndNewlines)
                    paragraphs(block["content"].text, prefix: id, who: who?.isEmpty == false ? who : nil)
                }
            case "line":
                guard let content = block["content"].text?.trimmingCharacters(in: .whitespacesAndNewlines), !content.isEmpty else { break }
                let speakerID = block["speaker"].text
                let speaker: ChapterStoryLine.Speaker?
                if speakerID == "player" { speaker = .player }
                else if let member = cast?.config.member(speakerID) { speaker = .cast(member.id) }
                else { speaker = nil } // Unknown or cast off: plain paragraph, never a crash.
                let audio = ParticipationRecord.text(block["audioUrl"])
                append(.line(.init(speaker: speaker, text: fill(String(content.prefix(300))), audioURL: audio,
                                   blockKey: ParticipationRecord.text(block["key"]))), id: id)
            case "branch":
                // Without cast the story branch block stays hidden, exactly as before.
                guard let cast, let choice = ChapterStoryChoice(raw: block, chapterID: chapter.chapterID, fill: fill) else { break }
                let key = CastStoryContext.pickKey(chapterID: chapter.chapterID, blockKey: choice.blockKey)
                guard let picked = cast.picks[key], choice.options.indices.contains(picked) else {
                    append(.choice(choice), id: id)
                    return result
                }
                // The pick stays in the story as the player's own line; the other options disappear.
                let option = choice.options[picked]
                let remembered = CastTrustDelta.remembered(option.trust, config: cast.config).map(\.id)
                append(.line(.init(speaker: .player, text: option.text, rememberedBy: remembered)), id: id)
                if option.endsFlow { return result }
            case "image": if let url = ParticipationRecord.text(block["url"]) { append(.image(url), id: id) }
            case "audio": if let url = ParticipationRecord.text(block["url"]) { append(.audio(url), id: id) }
            case "voice":
                if let text = ParticipationRecord.text(block["content"]) {
                    append(.voice(speaker: block["who"].text ?? "", text: fill(text)), id: id)
                }
            case "reveal":
                let lines = (block["content"].text ?? "").components(separatedBy: .newlines).compactMap { value -> String? in
                    let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    return value.isEmpty ? nil : fill(value)
                }
                if !lines.isEmpty { append(.reveal(speaker: block["who"].text ?? "", lines: lines), id: id) }
            case "dream":
                let images = (block["images"].array ?? []).compactMap { raw -> ChapterStoryDreamImage? in
                    guard let url = ParticipationRecord.text(raw["url"]) else { return nil }
                    return .init(url: url, line: raw["line"].text.map { fill($0) })
                }
                if !images.isEmpty { append(.dream(title: block["title"].text, images: images), id: id) }
            case "thought":
                if let key = block["thoughtKey"].text, let thought = thoughts.first(where: { $0["key"].text == key }),
                   let name = ParticipationRecord.text(thought["name"]) {
                    append(.thought(name: name, description: thought["desc"].text), id: id)
                } // Unknown thoughts never expose an authored name or trigger an implicit claim.
            case "mood": mood = block["mood"].text
            case "odd": odd = max(0, min(3, block["level"].tolerantInteger ?? 0))
            default: break
            }
        }
        return result
    }
}
