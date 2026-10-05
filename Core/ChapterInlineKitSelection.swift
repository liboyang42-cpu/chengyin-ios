import Foundation

/// Selection never marks a task complete, resets its coordinator or discards a draft.
/// A completed selection stays visible until an explicit switch; reentry starts at
/// an unfinished interactive task before ambient/progress-only sections.
public struct ChapterInlineKitSelection: Equatable {
    public private(set) var selected: PlayKitScreenKind?
    public private(set) var sessionID: Int?
    public init() {}
    public static func segment(_ kind: PlayKitScreenKind, in state: PlayAdvancedState) -> PlayWireValue {
        if state.playKit[kind.rawValue].object != nil { return state.playKit[kind.rawValue] }
        if kind == .branch { return state.branch }
        if kind == .random {
            return .object(["drawn": .array(state.draws), "drawCount": state.config["random"]["drawCount"], "deckName": state.config["random"]["deckName"]])
        }
        return .null
    }
    public static func complete(_ kind: PlayKitScreenKind, in state: PlayAdvancedState) -> Bool {
        PlayKitScreenProjection(kind: kind, segment: segment(kind, in: state)).complete
    }
    public static func preferred(in state: PlayAdvancedState, excluding: PlayKitScreenKind? = nil) -> PlayKitScreenKind? {
        let available = PlayKitScreenKind.present(in: state).filter { $0 != excluding }
        let unfinished = available.filter { !complete($0, in: state) }
        return unfinished.first(where: { !$0.isProgress && !(PlayKitActionCatalog.actions[$0.rawValue] ?? []).isEmpty })
            ?? unfinished.first ?? (excluding == nil ? available.first : nil)
    }
    public mutating func reconcile(_ state: PlayAdvancedState, preservingDraft: Bool) {
        if sessionID != state.sessionID {
            sessionID = state.sessionID; selected = Self.preferred(in: state); return
        }
        if let selected, PlayKitScreenKind.present(in: state).contains(selected) { return }
        if !preservingDraft { selected = Self.preferred(in: state) }
    }
    @discardableResult public mutating func select(_ kind: PlayKitScreenKind, in state: PlayAdvancedState) -> Bool {
        guard sessionID == state.sessionID, PlayKitScreenKind.present(in: state).contains(kind) else { return false }
        selected = kind; return true
    }
}
