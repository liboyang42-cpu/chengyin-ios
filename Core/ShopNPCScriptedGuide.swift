import Foundation

/// Only already-visible node instructions/materials. No answer, hint, story,
/// merchant-private guide or AI response is carried by this projection.
public struct ShopNPCScriptedGuide: Equatable {
    public let nodeID: ShopNPCNodeID
    public let rules: String?
    public let materials: String?
}
public enum ShopNPCScriptedGuideState: Equatable {
    case unavailable, tooLarge
    case available(ShopNPCScriptedGuide)
}

/// Retains a weak runtime and its unforgeable rendered-read context, not copied
/// script text. A refreshed snapshot cannot silently replace an open guide.
@available(macOS 14.0, *)
@MainActor public final class ShopNPCScriptedGuideSource {
    private weak var runtime: PlayExperienceCoordinator?
    private let context: PlayInteractionContext
    private let conversation: ShopNPCScope
    private let playScope: PlaySessionScope
    private let nodeID: ShopNPCNodeID
    private var retired = false
    public init?(runtime: PlayExperienceCoordinator, nodeID: Int, conversation: ShopNPCScope) {
        guard conversation.valid, conversation.nodeID.rawValue == nodeID,
              let id = ShopNPCNodeID(nodeID), let context = runtime.interactionContext,
              runtime.hasCurrentMediaSnapshot, let snapshot = runtime.snapshot, snapshot.availability == .active,
              let node = snapshot.visibleNodes.first(where: { $0.id == nodeID }), !snapshot.isLocked(node), node.npc != nil else { return nil }
        self.runtime = runtime; self.context = context; self.nodeID = id; self.conversation = conversation; playScope = runtime.scope
    }
    public func state(for conversation: ShopNPCScope) -> ShopNPCScriptedGuideState {
        guard !retired, conversation == self.conversation, let runtime,
              runtime.scope == playScope, runtime.interactionContext == context, runtime.hasCurrentMediaSnapshot,
              let snapshot = runtime.snapshot, snapshot.availability == .active,
              let node = snapshot.visibleNodes.first(where: { $0.id == nodeID.rawValue }),
              !snapshot.isLocked(node), node.npc != nil else { return .unavailable }
        guard (node.ruleInstructions?.utf8.count ?? 0) <= 65_536,
              (node.requiredMaterials?.utf8.count ?? 0) <= 16_384 else { return .tooLarge }
        func present(_ value: String?) -> String? {
            guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return value // Preserve source wording, whitespace and line breaks.
        }
        return .available(.init(nodeID: nodeID, rules: present(node.ruleInstructions), materials: present(node.requiredMaterials)))
    }
    public func retire() { retired = true; runtime = nil }
}
