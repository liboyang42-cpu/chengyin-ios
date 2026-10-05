import Foundation

/// Inert CMS text projection, not a browser or a general HTML implementation.
/// Attributes/URLs are never retained. Unknown wrappers keep their text; active
/// subtrees and media are omitted. Escaped markup is decoded once, never parsed again.
public struct SocialArticleContent: Equatable {
    public enum Kind: Equatable { case paragraph, heading(Int), listItem(marker: String, depth: Int), quote }
    public struct Run: Equatable {
        public let text: String
        public let bold: Bool
        public let italic: Bool
    }
    public struct Block: Equatable {
        public let kind: Kind
        public let runs: [Run]
        public var text: String { runs.map(\.text).joined() }
    }
    public let blocks: [Block]
    /// Includes bounded/truncated input and deliberately omitted non-text content.
    public let isLimited: Bool
    public static let maximumSourceScalars = 65_536
    public static let maximumOutputScalars = 32_768
    public static let maximumBlocks = 256
    public static let maximumRuns = 512
    public static let maximumDepth = 32
    public static let maximumTokens = 4_096
    public static let maximumTagScalars = 1_024

    public init(_ source: String) {
        var parser = ArticleTextParser(source)
        self = parser.parse()
    }
    fileprivate init(blocks: [Block], isLimited: Bool) {
        self.blocks = blocks; self.isLimited = isLimited
    }
}

private struct ArticleTextParser {
    typealias Article = SocialArticleContent
    private struct Tag { let name: String; let closing: Bool; let selfClosing: Bool; let end: Int }
    private struct ListContext { let ordered: Bool; var next = 1 }
    private enum AttributeState { case between, name, afterName, beforeValue, unquoted, quoted(Unicode.Scalar), afterQuoted, selfClosing }
    private let input: [Unicode.Scalar]
    private let plain: Bool
    private var index = 0
    private var tokens = 0
    private var outputCount = 0
    private var runCount = 0
    private var limited = false
    private var stopped = false
    private var blocks: [Article.Block] = []
    private var runs: [Article.Run] = []
    private var buffer: [Unicode.Scalar] = []
    private var kind: Article.Kind = .paragraph
    private var styles: [String] = []
    private var lists: [ListContext] = []
    private var quoteDepth = 0
    private var suppressed: String?
    private var rawText: String?
    private var scriptEscaped = false
    private var suppressedDepth = 0
    private var lastWhitespace = true

    init(_ source: String) {
        let prefix = Array(source.unicodeScalars.prefix(Article.maximumSourceScalars + 1))
        limited = prefix.count > Article.maximumSourceScalars
        let bounded = Array(prefix.prefix(Article.maximumSourceScalars))
        input = bounded
        plain = !bounded.indices.contains { Self.isTagStart(in: bounded, at: $0) }
    }

    mutating func parse() -> Article {
        while index < input.count && !stopped {
            if rawText != nil { skipRawTextScalar(); continue }
            if input[index] == "<", isTagStart(at: index) {
                tokens += 1
                guard tokens <= Article.maximumTokens else { stop(); break }
                if matches("<!--", at: index) { skipComment(); continue }
                // CMS fragments do not need declarations/processing instructions.
                // Stop on unsupported modes instead of risking a false boundary.
                if matches("<!", at: index) || matches("<?", at: index) { stop(); break }
                guard let tag = readTag() else { stop(); break }
                index = tag.end
                consume(tag)
            } else if suppressed != nil {
                index += 1
            } else if input[index] == "&", let entity = readEntity() {
                for scalar in entity.text.unicodeScalars { append(scalar) }
                index = entity.end
            } else {
                append(input[index]); index += 1
            }
        }
        if suppressed != nil { limited = true }
        flushBlock()
        return Article(blocks: blocks, isLimited: limited)
    }

    private func matches(_ literal: String, at start: Int) -> Bool {
        let pattern = Array(literal.unicodeScalars)
        guard start + pattern.count <= input.count else { return false }
        return input[start..<(start + pattern.count)].elementsEqual(pattern)
    }
    private func isLetter(_ c: Unicode.Scalar) -> Bool { (65...90).contains(c.value) || (97...122).contains(c.value) }
    private func isSpace(_ c: Unicode.Scalar) -> Bool { [9, 10, 12, 13, 32].contains(c.value) }
    private func isTagStart(at start: Int) -> Bool { Self.isTagStart(in: input, at: start) }
    private static func isTagStart(in scalars: [Unicode.Scalar], at start: Int) -> Bool {
        func letter(_ c: Unicode.Scalar) -> Bool { (65...90).contains(c.value) || (97...122).contains(c.value) }
        guard scalars[start] == "<", start + 1 < scalars.count else { return false }
        let next = scalars[start + 1]
        if letter(next) || next == "!" || next == "?" { return true }
        return next == "/" && start + 2 < scalars.count && letter(scalars[start + 2])
    }
    private mutating func stop() { limited = true; stopped = true }

    /// Each tag is scanned once, bounded even for unterminated quoted attributes.
    private func readTag() -> Tag? {
        var cursor = index + 1
        let closing = cursor < input.count && input[cursor] == "/"
        if closing { cursor += 1 }
        let nameStart = cursor
        // Consume the whole name token, so script:bogus or script-bogus can
        // never be mistaken for the active-content name script.
        while cursor < input.count && !isSpace(input[cursor]) && input[cursor] != "/" && input[cursor] != ">" {
            cursor += 1
            if cursor - index >= Article.maximumTagScalars { return nil }
        }
        let name = String(String.UnicodeScalarView(input[nameStart..<cursor])).lowercased()
        var state = AttributeState.between
        while cursor < input.count && cursor - index < Article.maximumTagScalars {
            let c = input[cursor]
            if c == ">" {
                if case .quoted = state { } else {
                    let selfClosing: Bool
                    if case .selfClosing = state { selfClosing = true } else { selfClosing = false }
                    return Tag(name: name, closing: closing, selfClosing: selfClosing, end: cursor + 1)
                }
            }
            switch state {
            case .quoted(let quote):
                if c == quote { state = .afterQuoted }
            case .beforeValue:
                if isSpace(c) { break }
                if c == "\"" || c == "'" { state = .quoted(c) }
                else if c == "<" || c == "`" || c == "=" { return nil }
                else { state = .unquoted }
            case .unquoted:
                if isSpace(c) { state = .between }
                else if c == "\"" || c == "'" || c == "<" || c == "`" { return nil }
                // A slash here belongs to the value, not a self-closing mark.
            case .afterQuoted:
                if isSpace(c) { state = .between }
                else if c == "/" { state = .selfClosing }
                else { return nil }
            case .selfClosing:
                return nil
            case .between, .afterName:
                if isSpace(c) { break }
                if c == "/" { state = .selfClosing }
                else if c == "=" {
                    if case .afterName = state { state = .beforeValue } else { return nil }
                } else if c == "\"" || c == "'" || c == "<" { return nil }
                else { state = .name }
            case .name:
                if isSpace(c) { state = .afterName }
                else if c == "=" { state = .beforeValue }
                else if c == "/" { state = .selfClosing }
                else if c == "\"" || c == "'" || c == "<" { return nil }
            }
            cursor += 1
        }
        return nil
    }
    private mutating func skipComment() {
        index += 4
        // HTML also ends comments on abrupt initial > / -> and on --!>.
        if matches(">", at: index) { index += 1; return }
        if matches("->", at: index) { index += 2; return }
        while index < input.count {
            if matches("-->", at: index) { index += 3; return }
            if matches("--!>", at: index) { index += 4; return }
            index += 1
        }
        limited = true
    }

    /// Omitted raw-text/RCDATA modes never parse apparent tags/comments/quotes.
    /// Only their exact end
    /// tag can finish it, including when nested inside an omitted container.
    private mutating func skipRawTextScalar() {
        guard let name = rawText else { return }
        if name == "script" {
            if matches("<!--", at: index) { scriptEscaped = true; index += 4; return }
            if matches("-->", at: index) { scriptEscaped = false; index += 3; return }
            // Legacy double-escaped script parsing is outside this text subset.
            // Stop conservatively rather than expose a suffix of script source.
            if scriptEscaped && rawTagPrefix("<script") { stop(); return }
        }
        if rawTagPrefix("</" + name) {
            guard let tag = readTag() else { stop(); return }
            if tag.closing && tag.name == name {
                index = tag.end; rawText = nil; scriptEscaped = false
                if suppressed == name { suppressed = nil; suppressedDepth = 0 }
                return
            }
        }
        index += 1
    }
    private func rawTagPrefix(_ literal: String) -> Bool {
        let marker = Array(literal.unicodeScalars)
        guard index + marker.count < input.count,
              zip(input[index..<(index + marker.count)], marker).allSatisfy({ actual, expected in
                  let value = actual.value
                  return (value >= 65 && value <= 90 ? value + 32 : value) == expected.value
              }) else { return false }
        let boundary = input[index + marker.count]
        return isSpace(boundary) || boundary == "/" || boundary == ">"
    }

    private mutating func consume(_ tag: Tag) {
        if !tag.closing && tag.name == "plaintext" { stop(); return }
        if let suppressed {
            if !tag.closing && Self.rawTextNames.contains(tag.name) {
                rawText = tag.name; scriptEscaped = false
                return
            }
            if tag.name == suppressed {
                if tag.closing {
                    suppressedDepth -= 1
                    if suppressedDepth == 0 { self.suppressed = nil }
                } else if !(tag.selfClosing && ["svg", "math"].contains(tag.name)) {
                    suppressedDepth += 1
                    if suppressedDepth > Article.maximumDepth { stop() }
                }
            }
            return
        }
        if Self.rawTextNames.contains(tag.name) || ["object", "svg", "math", "template", "canvas", "video", "audio", "head"].contains(tag.name) {
            limited = true
            if !tag.closing && !(tag.selfClosing && ["svg", "math"].contains(tag.name)) {
                suppressed = tag.name; suppressedDepth = 1
                if Self.rawTextNames.contains(tag.name) { rawText = tag.name; scriptEscaped = false }
            }
            return
        }
        if ["img", "embed", "input", "source", "track", "link", "meta"].contains(tag.name) { limited = true; return }
        if ["b", "strong", "i", "em"].contains(tag.name) {
            flushRun()
            if tag.closing {
                if let position = styles.lastIndex(of: tag.name) { styles.removeSubrange(position...) }
            } else if !tag.selfClosing {
                guard styles.count < Article.maximumDepth else { stop(); return }
                styles.append(tag.name)
            }
            return
        }
        if tag.name == "br" { if !tag.closing { append("\n", preserve: true) }; return }
        if tag.name == "ul" || tag.name == "ol" {
            flushBlock()
            if tag.closing {
                if !lists.isEmpty { lists.removeLast() }
                kind = defaultKind
            }
            else if !tag.selfClosing {
                guard lists.count < Article.maximumDepth else { stop(); return }
                lists.append(ListContext(ordered: tag.name == "ol"))
            }
            return
        }
        if tag.name == "li" {
            flushBlock()
            if tag.closing { kind = defaultKind }
            else if !tag.selfClosing {
                let marker: String
                if let list = lists.last, list.ordered {
                    marker = "\(list.next)."; lists[lists.count - 1].next += 1
                } else { marker = "•" }
                kind = .listItem(marker: marker, depth: max(0, lists.count - 1))
            }
            return
        }
        if tag.name == "blockquote" {
            flushBlock()
            if tag.closing { quoteDepth = max(0, quoteDepth - 1) }
            else if !tag.selfClosing {
                guard quoteDepth < Article.maximumDepth else { stop(); return }
                quoteDepth += 1
            }
            kind = quoteDepth > 0 ? .quote : .paragraph
            return
        }
        if ["h1", "h2", "h3", "h4", "h5", "h6"].contains(tag.name) {
            flushBlock()
            kind = tag.closing ? defaultKind : .heading(Int(tag.name.suffix(1)) ?? 1)
            return
        }
        if ["p", "div", "section", "article", "header", "footer", "hr", "pre", "table", "tr", "dl", "dt", "dd"].contains(tag.name) {
            flushBlock()
            return
        }
        if tag.name == "td" || tag.name == "th" { append(" "); return }
        // Links and unsupported wrappers retain only inert visible child text.
        // All attributes, including href/src/style/on*, are discarded by readTag.
    }

    private static let rawTextNames = ["script", "style", "iframe", "xmp", "noembed", "noframes", "noscript", "textarea", "title"]
    private var defaultKind: Article.Kind { quoteDepth > 0 ? .quote : .paragraph }
    private var bold: Bool { styles.contains("b") || styles.contains("strong") }
    private var italic: Bool { styles.contains("i") || styles.contains("em") }
    private mutating func append(_ scalar: Unicode.Scalar, preserve: Bool = false) {
        guard !stopped else { return }
        let whitespace = isSpace(scalar)
        if whitespace && !plain && !preserve && lastWhitespace { return }
        guard outputCount < Article.maximumOutputScalars else { stop(); return }
        if scalar.value < 32 && !whitespace { return }
        buffer.append(whitespace && !plain && !preserve ? " " : scalar)
        outputCount += 1; lastWhitespace = whitespace
    }
    private mutating func flushRun() {
        guard !buffer.isEmpty else { return }
        guard runCount < Article.maximumRuns else { stop(); buffer.removeAll(keepingCapacity: true); return }
        runs.append(Article.Run(text: String(String.UnicodeScalarView(buffer)), bold: bold, italic: italic))
        runCount += 1; buffer.removeAll(keepingCapacity: true)
    }
    private mutating func flushBlock() {
        flushRun()
        while let last = runs.last {
            let trimmed = String(String.UnicodeScalarView(last.text.unicodeScalars.reversed().drop(while: { isSpace($0) }).reversed()))
            if trimmed.isEmpty { runs.removeLast() }
            else { runs[runs.count - 1] = Article.Run(text: trimmed, bold: last.bold, italic: last.italic); break }
        }
        guard !runs.isEmpty else { return }
        guard blocks.count < Article.maximumBlocks else { stop(); runs.removeAll(); return }
        blocks.append(Article.Block(kind: kind, runs: runs))
        runs.removeAll(keepingCapacity: true); kind = defaultKind; lastWhitespace = true
    }

    /// Semicolon-terminated named/numeric entities only; unknown names stay literal.
    /// Decoded scalars are emitted directly and cannot introduce another tag/entity.
    private func readEntity() -> (text: String, end: Int)? {
        var end = index + 1
        while end < input.count && end - index <= 32 && input[end] != ";" {
            if isSpace(input[end]) || input[end] == "<" || input[end] == "&" { return nil }
            end += 1
        }
        guard end < input.count, end - index <= 32, input[end] == ";" else { return nil }
        let name = String(String.UnicodeScalarView(input[(index + 1)..<end]))
        let named = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00a0}",
                     "ndash": "–", "mdash": "—", "bull": "•", "hellip": "…", "copy": "©", "reg": "®", "trade": "™", "laquo": "«", "raquo": "»"]
        if let value = named[name] { return (value, end + 1) }
        guard name.hasPrefix("#") else { return nil }
        let hex = name.hasPrefix("#x") || name.hasPrefix("#X")
        let digits = name.dropFirst(hex ? 2 : 1)
        guard !digits.isEmpty, digits.allSatisfy({ hex ? $0.isHexDigit && $0.isASCII : $0.isASCII && $0.isNumber }),
              let value = UInt32(digits, radix: hex ? 16 : 10), let scalar = Unicode.Scalar(value),
              value >= 32 || [9, 10, 13].contains(value), value != 127 else { return ("�", end + 1) }
        return (String(scalar), end + 1)
    }
}
