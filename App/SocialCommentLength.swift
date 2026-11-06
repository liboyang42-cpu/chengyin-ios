/// Mirrors only the existing community V1 comment contract. Counts the raw
/// UTF-16 input without normalizing or truncating the user's draft.
enum SocialCommentLength {
    static func limit(purpose: SocialEditorPurpose, generation: SquareContentGeneration) -> Int? {
        purpose == .comment && generation == .communityV1 ? 2000 : nil
    }
    static func isTooLong(_ text: String, purpose: SocialEditorPurpose, generation: SquareContentGeneration) -> Bool {
        guard let limit = limit(purpose: purpose, generation: generation) else { return false }
        return text.utf16.count > limit
    }
}
