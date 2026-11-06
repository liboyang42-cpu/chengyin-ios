import Foundation

/// Provider region verification is explicit composition data, not inferred from language,
/// a server coordinate, or a remote permission toggle. No location permission is granted here.
@MainActor struct NativeCityWalkingConfiguration {
    let owner: RuntimeDependencyContext
    let revision: UUID
    let expiresAt: Date
    let verifiedMapKitWGS84Regions: Set<String>
    func matches(_ context: RuntimeDependencyContext) -> Bool {
        owner == context && Date() < expiresAt && !verifiedMapKitWGS84Regions.isEmpty &&
            verifiedMapKitWGS84Regions.allSatisfy { $0.count == 2 && $0.utf8.allSatisfy { (65...90).contains($0) } }
    }
}

/// Each kind retains its own provider-region approval. A city approval cannot widen a story or fallback source.
@MainActor struct NativeCityWalkingSourceRouter: WalkingTargetAuthorizing {
    struct Source { let reader: any WalkingTargetAuthorizing; let regions: Set<String> }
    let city: Source?
    let story: Source?
    let fallback: Source?
    func authorize(_ reference: WalkingTargetReference) async throws -> AuthorizedWalkingTarget {
        let selected: Source?
        switch reference.kind { case .cityNode: selected = city ?? fallback; case .storyNode: selected = story ?? fallback; default: selected = fallback }
        guard let selected else { throw WalkingTargetReadFailure.unsupportedKind }
        let target = try await selected.reader.authorize(reference)
        guard target.reference == reference, selected.regions.contains(target.coordinate.region), target.coordinate.datum == .wgs84 else {
            throw WalkingNavigationFailure.coordinateUnsupported
        }
        return target
    }
}
