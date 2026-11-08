/// A failed-attempt label belongs to the submitted text. Editing a new retry
/// hides that old label until a later server attempt or a terminal readback.
/// This controls presentation only: it never changes an attempt, verdict,
/// completion flag, submission gate, reward or recovery record.
public struct PlayQATextFeedbackState: Equatable {
    private var hasEdited = false
    private var editedAttempt = 0
    public init() {}

    public mutating func markEdited(attempts: Int?, finished: Bool) {
        guard !finished else { return }
        hasEdited = true
        editedAttempt = max(editedAttempt, max(0, attempts ?? 0))
    }
    public func showsResult(attempts: Int?, finished: Bool) -> Bool {
        if !hasEdited || finished { return true }
        guard let attempts else { return false }
        return attempts > editedAttempt
    }
}
