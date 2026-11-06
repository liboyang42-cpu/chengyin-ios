import Foundation

/// Only the five existing normal PLAYER actions. Photo/scan evidence and the
/// independent circle journey keep their existing, separately reviewed routes.
public enum PlayPlayerReviewIntent {
    case role
    case text(nodeID: Int, answer: String)
    case choice(nodeID: Int, choiceID: String)
    case hint(nodeID: Int)
    case reveal(nodeID: Int)
}
public struct PlayPlayerActionReviewContext {
    fileprivate let projection: PlayPlayerGameProjection
    fileprivate let owner: PlayExperienceSession
}
public struct PlayPlayerActionReviewValue: Identifiable {
    public let id = UUID()
    public let command: PlayPlayerCommand
    public let title: String?
    public let question: String?
    public let detail: String?
    public let consequence: String?
    public let hintLevel: Int?
    fileprivate let intent: PlayPlayerReviewIntent
    fileprivate let context: PlayPlayerActionReviewContext
}
extension PlayPlayerGameCoordinator {
    public func capturePlayerActionReview() throws -> PlayPlayerActionReviewContext {
        guard hasCurrentProjection, phase == "ready", pending == nil, let projection, let owner = currentSession() else { throw PlayExperienceError.staleSession }
        return .init(projection: projection, owner: owner)
    }
    public func acceptsPlayerActionReview(_ context: PlayPlayerActionReviewContext) -> Bool {
        hasCurrentProjection && phase == "ready" && pending == nil && currentSession() == context.owner && projection == context.projection
    }
    public func preparePlayerActionReview(_ context: PlayPlayerActionReviewContext, intent: PlayPlayerReviewIntent) throws -> PlayPlayerActionReviewValue {
        guard acceptsPlayerActionReview(context) else { throw PlayExperienceError.staleSession }
        let snapshot = context.projection
        let nodeID: Int?, action: PlayPlayerCommand.Action, payload: [String: PlayWireValue]
        var title: String?, question: String?, detail: String?, consequence: String?, hintLevel: Int?
        switch intent {
        case .role:
            nodeID = nil; action = .confirmRole; payload = [:]
            title = snapshot.role["name"].text ?? snapshot.role["code"].text; question = snapshot.role["publicBrief"].text
        case .text(let id, let answer):
            guard let node = snapshot.nodes.first(where: { $0.id == id }), node.task["inputType"].text == "TEXT",
                  let task = node.task["taskCode"].text else { throw PlayExperienceError.invalidAction }
            nodeID = id; action = .submit; payload = ["taskCode": .string(task), "evidenceUrls": .array([.string(try PlayPlayerCommand.textEvidence(answer))])]
            title = node.name; question = node.task["prompt"].text; detail = answer
        case .choice(let id, let choiceID):
            guard let node = snapshot.nodes.first(where: { $0.id == id }),
                  let choice = node.choices.first(where: { $0["id"].text?.utf8.elementsEqual(choiceID.utf8) == true }),
                  let label = choice["label"].text else { throw PlayExperienceError.invalidAction }
            nodeID = id; action = .choice; payload = ["choiceId": .string(choiceID)]
            title = node.name; question = node.task["prompt"].text; detail = label
        case .hint(let id):
            guard let node = snapshot.nodes.first(where: { $0.id == id }), let level = node.hint["nextLevel"].integer,
                  let impact = node.hint["nextImpactLabel"].text, !impact.isEmpty else { throw PlayExperienceError.invalidAction }
            nodeID = id; action = .hint; payload = ["level": .int(level)]
            title = node.name; hintLevel = level; consequence = impact
        case .reveal(let id):
            guard let node = snapshot.nodes.first(where: { $0.id == id }), node.hint["revealAvailable"].bool == true,
                  let impact = node.hint["revealImpactLabel"].text, !impact.isEmpty else { throw PlayExperienceError.invalidAction }
            nodeID = id; action = .reveal; payload = [:]; title = node.name; consequence = impact
        }
        let command = try PlayPlayerCommand(activityID: activityID, nodeID: nodeID, expectedRevision: snapshot.revision, action: action, payload: payload)
        guard snapshot.allows(command) else { throw PlayExperienceError.invalidAction }
        return .init(command: command, title: title, question: question, detail: detail, consequence: consequence, hintLevel: hintLevel, intent: intent, context: context)
    }
    public func acceptsPlayerActionReview(_ value: PlayPlayerActionReviewValue) -> Bool {
        guard acceptsPlayerActionReview(value.context), let projection,
              let current = try? preparePlayerActionReview(.init(projection: projection, owner: value.context.owner), intent: value.intent) else { return false }
        func same(_ a: String?, _ b: String?) -> Bool {
            switch (a, b) { case (nil, nil): return true; case (.some(let a), .some(let b)): return a.utf8.elementsEqual(b.utf8); default: return false }
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        guard let before = try? encoder.encode(PlayWireValue.object(value.command.payload)),
              let now = try? encoder.encode(PlayWireValue.object(current.command.payload)) else { return false }
        return before == now && same(current.title, value.title) && same(current.question, value.question) &&
            same(current.detail, value.detail) && same(current.consequence, value.consequence) && current.hintLevel == value.hintLevel
    }
    public func submitPlayerActionReview(_ value: PlayPlayerActionReviewValue) async {
        guard !Task.isCancelled, acceptsPlayerActionReview(value) else { return }
        await submit(value.command)
    }
}
