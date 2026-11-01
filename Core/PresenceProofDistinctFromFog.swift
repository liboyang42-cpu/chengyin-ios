import Foundation

/// Fog is exploration memory, never presence proof, visit evidence, or territory ownership.
/// Consumes existing roam tile-key rules without rewriting RoamTileMemoryPager.
public enum PresenceProofFailure: Error, Equatable {
    case fogIsNotPresence
    case proofRequired
    case fakeGPSRejected
    case presenceCapabilityDisabled
}

public struct FogExplorationMemory: Equatable, Sendable {
    public let tiles: Set<String>
    public init?(tiles: Set<String>) {
        guard tiles.count <= 2000, tiles.allSatisfy(RoamExperienceMath.isValidTile) else { return nil }
        self.tiles = tiles
    }
}

public enum PresenceProofDistinctFromFog {
    /// Owner-scoped exploration memory only.
    public static func isExplorationMemory(_ tile: String) -> Bool {
        RoamExperienceMath.isValidTile(tile)
    }
    public static func roamPresenceCapabilityEnabled() -> Bool {
        RoamExperienceCapabilities.presence
    }
    /// Revealed fog tiles never certify arrival. GPS must be attested, never simulated.
    public static func certifyPresence(memory: FogExplorationMemory, proof: SideQuestProof?) throws {
        _ = memory
        guard roamPresenceCapabilityEnabled() == false else {
            throw PresenceProofFailure.presenceCapabilityDisabled
        }
        guard let proof else { throw PresenceProofFailure.fogIsNotPresence }
        guard proof.attested, proof.kind != .gps || proof.attested else {
            throw PresenceProofFailure.fakeGPSRejected
        }
        _ = proof
    }
    public static func certifyPresenceFromFogTiles(_ tiles: Set<String>) throws -> Never {
        _ = tiles
        throw PresenceProofFailure.fogIsNotPresence
    }
    public static func rejectSimulatedGPS() throws -> Never {
        throw PresenceProofFailure.fakeGPSRejected
    }
    public static func proofRequiredWithoutFog() throws -> Never {
        throw PresenceProofFailure.proofRequired
    }
}
