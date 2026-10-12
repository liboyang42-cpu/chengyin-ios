import Foundation

/// Mini P036 optional-module add/remove intent, applied only to an exact local draft snapshot.
public struct TemplateOptionalModules {
    public enum Module: String, CaseIterable, Identifiable { case reward, story, voice
        public var id: String { rawValue }
        public var labelKey: String { "templateAuthor." + rawValue }
    }
    public enum Change { case add(Module), remove(Module) }
    public struct Field: Identifiable {
        public let id: String
        public let value: String
        public var labelKey: String { id == "storyJson" ? "templateModules.timeline" : "templateAuthor.field." + id }
    }
    private let source: TemplateAuthoringDraft
    private let fingerprint: Data?
    public init(_ draft: TemplateAuthoringDraft) { source = draft; fingerprint = Self.snapshot(draft) }
    public func isCurrent(_ draft: TemplateAuthoringDraft) -> Bool { fingerprint != nil && fingerprint == Self.snapshot(draft) }
    public func enabled(_ module: Module) -> Bool {
        switch module { case .reward: return source.rewardEnabled; case .story: return source.storyEnabled; case .voice: return source.voiceEnabled }
    }
    public func fields(_ module: Module) -> [Field] {
        switch module {
        case .reward: return [.init(id: "couponId", value: source.couponId.map(String.init) ?? ""), .init(id: "feedbackText", value: source.feedbackText ?? ""), .init(id: "medalImg", value: source.medalImg ?? ""), .init(id: "medalName", value: source.medalName ?? ""), .init(id: "medalStyle", value: source.medalStyle ?? "")]
        case .story: return [.init(id: "storyText", value: source.storyText ?? ""), .init(id: "storyJson", value: source.storyJson ?? "")]
        case .voice: return [.init(id: "audioUrl", value: source.audioUrl ?? ""), .init(id: "audioDuration", value: source.audioDuration.map(String.init) ?? "")]
        }
    }
    public func canRemove(_ module: Module) -> Bool {
        guard fingerprint != nil else { return false }
        if enabled(module) { return true }
        switch module {
        case .reward:
            let nondefaultStyle = source.medalStyle.map { !$0.isEmpty && $0 != "glow" } ?? false
            return (source.couponId ?? 0) != 0 || [source.feedbackText, source.medalImg, source.medalName].contains { !($0 ?? "").isEmpty } || nondefaultStyle
        case .story: return !(source.storyText ?? "").isEmpty || !(source.storyJson ?? "").isEmpty
        case .voice: return !(source.audioUrl ?? "").isEmpty || source.audioDuration != nil
        }
    }
    public func applying(_ change: Change, to draft: TemplateAuthoringDraft) -> TemplateAuthoringDraft? {
        guard isCurrent(draft) else { return nil }
        var next = draft
        switch change {
        case .add(let module):
            guard !enabled(module) else { return nil }
            // A native enable switch can retain fields. Adding must never destroy them.
            switch module { case .reward: next.rewardEnabled = true; case .story: next.storyEnabled = true; case .voice: next.voiceEnabled = true }
        case .remove(let module):
            guard canRemove(module) else { return nil }
            switch module {
            case .reward:
                next.rewardEnabled = false; next.couponId = 0; next.feedbackText = ""; next.medalImg = ""; next.medalName = ""; next.medalStyle = "glow"
            case .story:
                next.storyEnabled = false; next.storyText = ""; next.storyJson = ""; next.storyTimelineEdited = true
                // Mini clears storyBeats, not the legacy storyImg. Existing timeline creates an empty editable beat.
            case .voice:
                next.voiceEnabled = false; next.audioUrl = ""; next.audioDuration = nil
                // Native Int? represents Mini's cleared duration input as nil, without changing the wire contract.
            }
        }
        return next
    }
    private static func snapshot(_ draft: TemplateAuthoringDraft) -> Data? {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]; return try? encoder.encode(draft)
    }
}
