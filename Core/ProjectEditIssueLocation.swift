import Foundation

/// Routes known validation identities into existing editor fields. Localized error
/// text never selects a destination; unknown or ambiguous identities stay inert.
public enum ProjectEditIssueLocation: Equatable {
    case root(anchor: String)
    case chapter(id: String, anchor: String)
    case node(chapterID: String, nodeID: String, anchor: String)
    case ticket(id: String, anchor: String)

    public struct Row {
        public let issue: ProjectEditIssue
        public let location: ProjectEditIssueLocation?
    }
    public var anchor: String {
        switch self {
        case .root(let anchor), .chapter(_, let anchor), .node(_, _, let anchor), .ticket(_, let anchor): return anchor
        }
    }
    public static func rows(in draft: ProjectEditDraft, scope: ProjectEditScope) -> [Row] {
        ProjectEditValidation.issues(draft, scope: scope).map { .init(issue: $0, location: resolve($0.id, in: draft)) }
    }
    public static func location(for issue: ProjectEditIssue, in draft: ProjectEditDraft, scope: ProjectEditScope) -> ProjectEditIssueLocation? {
        let matching = rows(in: draft, scope: scope).filter { $0.issue == issue }
        return matching.count == 1 ? matching[0].location : nil
    }
    public func exists(in draft: ProjectEditDraft) -> Bool {
        switch self {
        case .root: return true
        case .chapter(let id, _): return draft.chapters.filter { $0.id == id }.count == 1
        case .node(let chapterID, let nodeID, _):
            let chapters = draft.chapters.filter { $0.id == chapterID }
            return chapters.count == 1 && chapters[0].nodes.filter { $0.id == nodeID }.count == 1
        case .ticket(let id, _): return draft.tickets.filter { $0.id == id }.count == 1
        }
    }
    private static func resolve(_ id: String, in draft: ProjectEditDraft) -> ProjectEditIssueLocation? {
        let roots = ["name": "name", "description": "description", "cover": "cover", "categories": "categories",
                     "start": "start", "end": "end", "dateOrder": "end", "deadline": "deadline",
                     "chapters": "chapters", "completionRules": "completionRules", "topicRewards": "topicRewards", "clubLead": "clubLead"]
        if let field = roots[id] { return .root(anchor: "project-issue-anchor-" + field) }
        var candidates: [ProjectEditIssueLocation] = []
        for (index, chapter) in draft.chapters.enumerated() {
            for prefix in ["story", "nodes", "blocks", "nodeIDs", "merchantCategory", "terms", "merchantQuota", "perk"] where id == prefix + String(index) {
                let field: String
                switch prefix {
                case "story": field = chapter.blocks == nil ? "story" : "storyFlow"
                case "nodes", "nodeIDs": field = "nodes"
                case "blocks": field = "storyFlow"
                default: field = "chapterSettings"
                }
                candidates.append(.chapter(id: chapter.id, anchor: "project-issue-anchor-" + field))
            }
            for block in chapter.blocks ?? [] where id == "reference" + block.id || id == "media" + block.id {
                candidates.append(.chapter(id: chapter.id, anchor: "project-issue-anchor-storyFlow"))
            }
            for node in chapter.nodes {
                for (prefix, field) in [("coordinate", "coordinates"), ("nodeName", "nodeName"), ("nodeTime", "nodeTime")] where id == prefix + node.id {
                    let storyGame = chapter.blocks?.contains { $0.kind == .node && $0.nodeID == node.id && $0.sourceFields?["locationRequired"] == .bool(false) } == true
                    let targetField = prefix == "coordinate" && storyGame && node.longitude.isEmpty && node.latitude.isEmpty && (node.templateID ?? 0) <= 0 ? "gameplay" : field
                    candidates.append(.node(chapterID: chapter.id, nodeID: node.id, anchor: "project-issue-anchor-" + targetField))
                }
            }
        }
        for ticket in draft.tickets {
            for (prefix, field) in [("ticketMeetingPoint", "ticketSchedule"), ("ticketSaleDates", "ticketSale"),
                ("ticketName", "ticketName"), ("price", "price"), ("stock", "stock"), ("team", "team"),
                ("ticketDates", "ticketSchedule"), ("ticketOrder", "ticketSchedule"), ("meeting", "ticketSchedule")] where id == prefix + ticket.id {
                candidates.append(.ticket(id: ticket.id, anchor: "project-issue-anchor-" + field))
            }
        }
        guard candidates.count == 1, candidates[0].exists(in: draft) else { return nil }
        return candidates[0]
    }
}
