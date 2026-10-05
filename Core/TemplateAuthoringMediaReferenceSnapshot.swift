import Foundation

/// Read-only, local inventory. Raw reference text is never normalized, fetched or rewritten.
/// Keep one snapshot per loaded editor lifetime; reconstructing it mints fresh image-slot IDs.
public struct TemplateAuthoringMediaReferenceSnapshot {
    public struct Reference: Equatable {
        public let slot: TemplateAuthoringMediaSlot
        public let raw: String?
    }
    public let originalDraft: TemplateAuthoringDraft
    public let references: [Reference]
    public let supportsChoiceOptions: Bool
    public let supportsStory: Bool

    /// Use the existing editor's loaded beat UUIDs. Never derive identity from a row index,
    /// reference text, or another parse of storyJson. The IDs are not durable wire identity.
    /// Omit loadedStoryBeats to inventory only fixed fields; this does not infer story identity.
    public init(draft: TemplateAuthoringDraft, loadedStoryBeats: [TemplateStoryBeat]? = nil) throws {
        originalDraft = draft
        var values: [Reference] = [
            .init(slot: .init(field: .questionImage), raw: draft.questionImg),
            .init(slot: .init(field: .questionAudio), raw: draft.questionAudio),
            .init(slot: .init(field: .narration), raw: draft.audioUrl)
        ]
        let options = draft.choiceOptionMedia
        supportsChoiceOptions = options.isSupported
        if options.isSupported {
            for letter in TemplateChoiceOptionMedia.Letter.allCases {
                values.append(.init(slot: .init(field: .optionImage(letter)), raw: options.text(letter, .image)))
                values.append(.init(slot: .init(field: .optionAudio(letter)), raw: options.text(letter, .audio)))
            }
        }
        let parsed = try? TemplateAuthoringStory.editableBeats(raw: draft.storyJson)
        supportsStory = parsed != nil
        if let loadedStoryBeats {
            guard let parsed, Set(loadedStoryBeats.map(\.id)).count == loadedStoryBeats.count,
                  Self.matches(loadedStoryBeats, stored: parsed) else {
                throw TemplateAuthoringMediaIdentityScope.Failure.invalidSlots
            }
            for beat in loadedStoryBeats {
                for reference in beat.imgs {
                    values.append(.init(slot: .init(field: .storyBeatImage(beatID: beat.id)), raw: reference))
                }
            }
        }
        references = values
    }

    private static func matches(_ loaded: [TemplateStoryBeat], stored: [TemplateStoryBeat]) -> Bool {
        if exactRows(loaded, stored) { return true }
        // The existing editor adds an empty row on load and retains empty rows after edits;
        // setStory omits those rows on the wire. Use the supplied UUIDs without reparsing them.
        let serializedRows = loaded.filter {
            !TemplateAuthoringStory.sourceTrim($0.text).isEmpty || !$0.imgs.isEmpty
        }
        return exactRows(serializedRows, stored)
    }

    /// Swift String equality accepts canonically equivalent Unicode. Reference inventory
    /// requires the actual UTF-8 bytes, including composition and whitespace, to agree.
    private static func exactRows(_ left: [TemplateStoryBeat], _ right: [TemplateStoryBeat]) -> Bool {
        guard left.count == right.count else { return false }
        return zip(left, right).allSatisfy { lhs, rhs in
            lhs.text.utf8.elementsEqual(rhs.text.utf8) && lhs.tag.utf8.elementsEqual(rhs.tag.utf8) &&
                lhs.imgs.count == rhs.imgs.count && zip(lhs.imgs, rhs.imgs).allSatisfy { image, stored in
                    image.utf8.elementsEqual(stored.utf8)
                }
        }
    }
}
