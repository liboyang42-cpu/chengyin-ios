import Foundation

/// A card's owner-member identity is distinct from the directory's positional ID.
/// Selections are issued only by the accepted, visible directory snapshot.
public struct ClubMerchantProfileSelection: Equatable, Identifiable {
    public let id: UUID
    public let owner: PublicMerchantOwnerID
    public let row: ClubMerchantDiscoveryRow
    let permit: ClubMerchantDiscoveryModel.Permit
    let generation: UUID
    init(row: ClubMerchantDiscoveryRow, owner: PublicMerchantOwnerID,
         permit: ClubMerchantDiscoveryModel.Permit, generation: UUID) {
        id = UUID(); self.row = row; self.owner = owner
        self.permit = permit; self.generation = generation
    }
}
