import Foundation

/// Unsent QA/TYPE input only. A length limit rejects review; it must never
/// silently replace the player's answer with a shorter prefix.
/// No wire keys, answer matching, command identity or recovery state live here.
public struct PlayQATextInput: Equatable {
    public static let maximumUTF16Count = 4096
    public private(set) var revision: String?
    public private(set) var mountID = UUID()
    private var value = ""
    public init() {}

    public mutating func mount(revision: String?) {
        self.revision = revision; mountID = UUID(); value = ""
    }
    public mutating func clear() { mount(revision: nil) }
    private func isCurrent(_ current: String?, mountID: UUID) -> Bool {
        guard let revision, let current, !revision.isEmpty else { return false }
        return revision.utf8.elementsEqual(current.utf8) && self.mountID == mountID
    }
    public func text(current: String?, mountID: UUID) -> String {
        isCurrent(current, mountID: mountID) ? value : ""
    }
    @discardableResult public mutating func update(_ text: String, current: String?, mountID: UUID) -> Bool {
        guard isCurrent(current, mountID: mountID) else { return false }
        // Preserve marked-text composition and overlong paste exactly. The
        // existing server input boundary still applies when requesting review.
        value = text
        return true
    }
    public func isOverLimit(current: String?, mountID: UUID) -> Bool {
        isCurrent(current, mountID: mountID) && value.utf16.count > Self.maximumUTF16Count
    }
    /// A value snapshot for the existing frozen review; not an action ID.
    public func reviewInput(current: String?, mountID: UUID) -> String? {
        guard isCurrent(current, mountID: mountID), value.utf16.count <= Self.maximumUTF16Count,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }
}
