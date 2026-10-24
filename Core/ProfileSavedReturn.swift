import Foundation

/// A one-use navigation receipt. Issued only by a completed save with matching
/// authoritative readback, never by a status string or a later refresh.
public struct ProfileSavedReturn: Equatable, Identifiable {
    public let id: UUID
    public let reviewID: UUID
    let session: ProfileEditSession
    let snapshot: ProfileEditSnapshot
    let generation: Int

    init(reviewID: UUID, session: ProfileEditSession, snapshot: ProfileEditSnapshot, generation: Int) {
        id = UUID()
        self.reviewID = reviewID
        self.session = session
        self.snapshot = snapshot
        self.generation = generation
    }
}
