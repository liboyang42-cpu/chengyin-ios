#if DEBUG
import Foundation

public enum ProjectEditRichStoryFixtures {
    public static func draft() -> ProjectEditDraft {
        var draft = ProjectEditSyntheticFixtures.draft(), chapter = draft.chapters[0]
        let node = chapter.nodes[0].id
        var blocks = [ProjectEditBlock(kind: .text, content: chapter.description)]
        var question = ProjectEditBlock(kind: .text, content: "Which clue will you follow?", nodeID: node)
        question.selectBeat(.brief); question.setField("field", .string("question")); question.nodeID = node; blocks.append(question)
        blocks.append(.init(kind: .node, nodeID: node))
        var reward = ProjectEditBlock(kind: .text, content: "A fictional keepsake", nodeID: node)
        reward.selectBeat(.deliver); reward.nodeID = node; blocks.append(reward)
        var dream = ProjectEditRichStoryContract.defaultBlock(.dream); dream.id = "rich-dream"
        dream.setField("title", .string("Fixture album")); dream.setField("images", .array([.object(["url": .string("fixture://story-image"), "line": .string("A fictional harbor")])]))
        blocks.append(dream)
        var mood = ProjectEditRichStoryContract.defaultBlock(.mood); mood.id = "rich-mood"; blocks.append(mood)
        var thought = ProjectEditRichStoryContract.defaultBlock(.thought); thought.id = "rich-thought"; thought.setField("thoughtKey", .string("harbor")); blocks.append(thought)
        var voice = ProjectEditRichStoryContract.defaultBlock(.voice); voice.id = "rich-voice"; voice.content = "Remember this place."; blocks.append(voice)
        var odd = ProjectEditRichStoryContract.defaultBlock(.odd); odd.id = "rich-odd"; odd.setField("level", .number(2)); blocks.append(odd)
        var reveal = ProjectEditRichStoryContract.defaultBlock(.reveal); reveal.id = "rich-reveal"; reveal.content = "You have been here before."; reveal.setField("who", .string("Guide")); blocks.append(reveal)
        for index in blocks.indices where !blocks[index].id.hasPrefix("rich-") { blocks[index].id = "rich-base-\(index)" }
        chapter.blocks = blocks; draft.chapters = [chapter]; return draft
    }
}
#endif
