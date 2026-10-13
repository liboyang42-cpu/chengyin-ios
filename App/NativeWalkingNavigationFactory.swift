import Foundation
import SwiftUI
import Security
import CryptoKit

/// Exact approved context and device-tested coordinate/coverage regions are composition data,
/// not remote toggles. Empty defaults cannot create a network/location-capable coordinator.
@MainActor struct NativeWalkingNavigationDependencies {
    let owner: RuntimeDependencyContext
    let verifiedMapKitWGS84Regions: Set<String>
    let targets: any WalkingTargetAuthorizing
    var makeLocation: @MainActor () -> any WalkingLocationProviding = { WalkingForegroundLocationProvider(enabled: true) }
    var makePlanner: (@MainActor (Set<String>) -> any SearchRoutePlanning)? = nil
}

@MainActor final class NativeWalkingNavigationFactory {
    private let dependencies: NativeWalkingNavigationDependencies?
    private let context: () -> RuntimeDependencyContext?
    private let checkpoints: any WalkingCheckpointStoring
    init(dependencies: NativeWalkingNavigationDependencies? = nil, checkpoints: (any WalkingCheckpointStoring)? = nil,
         context: @escaping () -> RuntimeDependencyContext? = { nil }) {
        self.dependencies = dependencies; self.context = context
        self.checkpoints = checkpoints ?? WalkingSystemCheckpointStore()
    }
    var available: Bool {
        guard let dependencies, context() == dependencies.owner else { return false }
        return !dependencies.verifiedMapKitWGS84Regions.isEmpty
    }
    func make(reference: WalkingTargetReference) -> WalkingNavigationCoordinator? {
        guard reference.isValid, available, let dependencies else { return nil }
        let owner = dependencies.owner
        let planner = dependencies.makePlanner?(dependencies.verifiedMapKitWGS84Regions)
            ?? MapKitWalkingRoutePlanner(verifiedRegions: dependencies.verifiedMapKitWGS84Regions)
        return WalkingNavigationCoordinator(reference: reference, ownerNamespace: namespace(owner),
            authorizer: RegionBoundWalkingTargets(base: dependencies.targets, regions: dependencies.verifiedMapKitWGS84Regions),
            location: dependencies.makeLocation(), planner: planner,
            current: { [weak self] in self?.available == true && self?.context() == owner })
    }
    func makePreviewPlanner(reference: WalkingTargetReference) -> (any SearchRoutePlanning)? {
        guard reference.isValid, available, let dependencies else { return nil }
        let owner = dependencies.owner
        let planner = dependencies.makePlanner?(dependencies.verifiedMapKitWGS84Regions)
            ?? MapKitWalkingRoutePlanner(verifiedRegions: dependencies.verifiedMapKitWGS84Regions)
        return AuthorizedWalkingPreviewPlanner(reference: reference,
            targets: RegionBoundWalkingTargets(base: dependencies.targets, regions: dependencies.verifiedMapKitWGS84Regions),
            planner: planner, current: { [weak self] in self?.available == true && self?.context() == owner })
    }
    func restore(_ checkpoint: WalkingNavigationCheckpoint) -> WalkingNavigationCoordinator? {
        guard let dependencies, checkpoint.ownerNamespace == namespace(dependencies.owner) else { return nil }
        // Coordinates are not persisted. Caller must explicitly resume, reauthorizing the target.
        return make(reference: checkpoint.reference)
    }
    /// This identity is only a presentation fence. No credential is serialized to Keychain.
    var checkpointPresentationID: String {
        guard let owner = dependencies?.owner else { return "unavailable" }
        return namespace(owner) + ":" + SHA256.hash(data: Data(owner.session.token.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    func savedDestinationIsCurrent(_ saved: WalkingSavedDestination) -> Bool {
        available && context() == saved.owner && dependencies?.owner == saved.owner
    }
    func savedDestination() throws -> WalkingSavedDestination? {
        let owner = try checkpointOwner()
        let scope = try storedScope(owner), key = storageKey(scope)
        guard let bytes = try checkpoints.read(key: key) else { return nil }
        let record = try WalkingSavedDestinationRecord.decode(bytes, ownerScope: scope)
        guard try checkpointOwner() == owner else { throw WalkingCheckpointFailure.unavailable }
        return .init(record: record, bytes: bytes, owner: owner)
    }
    func saveDestination(from model: WalkingNavigationCoordinator) throws -> WalkingSavedDestination {
        let owner = try checkpointOwner()
        guard model.ownerNamespace == namespace(owner), model.foreground,
              model.phase == .navigating || model.phase == .nearDestination,
              model.cameraSnapshot != nil, let checkpoint = model.checkpoint else {
            throw WalkingCheckpointFailure.unavailable
        }
        let scope = try storedScope(owner), key = storageKey(scope)
        let previous = try checkpoints.read(key: key)
        // Corrupt or foreign data is never silently replaced.
        if let previous { _ = try WalkingSavedDestinationRecord.decode(previous, ownerScope: scope) }
        let record = try WalkingSavedDestinationRecord(reference: checkpoint.reference, ownerScope: scope)
        let bytes = try record.encoded()
        guard try checkpointOwner() == owner, model.checkpoint == checkpoint,
              model.cameraSnapshot != nil else { throw WalkingCheckpointFailure.unavailable }
        guard try checkpoints.replace(key: key, expected: previous, replacement: bytes) else {
            throw WalkingCheckpointFailure.changed
        }
        return .init(record: record, bytes: bytes, owner: owner)
    }
    func restoreSavedDestination(_ saved: WalkingSavedDestination) -> WalkingNavigationCoordinator? {
        guard let owner = try? checkpointOwner(), owner == saved.owner,
              let scope = try? storedScope(owner), scope == saved.record.ownerScope,
              let bytes = try? checkpoints.read(key: storageKey(scope)), bytes == saved.bytes,
              let decoded = try? WalkingSavedDestinationRecord.decode(bytes, ownerScope: scope),
              decoded == saved.record else { return nil }
        // Restore only the reference into ready state. start() performs all fresh authorization.
        return restore(.init(reference: saved.record.reference, ownerNamespace: namespace(owner)))
    }
    func removeSavedDestination(_ saved: WalkingSavedDestination) throws {
        let owner = try checkpointOwner()
        guard owner == saved.owner, try storedScope(owner) == saved.record.ownerScope else {
            throw WalkingCheckpointFailure.unavailable
        }
        guard try checkpoints.replace(key: storageKey(saved.record.ownerScope), expected: saved.bytes, replacement: nil) else {
            throw WalkingCheckpointFailure.changed
        }
    }
    private func checkpointOwner() throws -> RuntimeDependencyContext {
        guard available, let owner = dependencies?.owner, context() == owner else {
            throw WalkingCheckpointFailure.unavailable
        }
        return owner
    }
    private func storedScope(_ owner: RuntimeDependencyContext) throws -> Data {
        // Durable account/realm scope, distinct from the fresh in-memory token/epoch fence.
        try JSONEncoder().encode([owner.baseURL.absoluteString, owner.session.namespace,
                                  String(owner.session.accountID), owner.market.rawValue, owner.role])
    }
    private func storageKey(_ scope: Data) -> String {
        SHA256.hash(data: scope).map { String(format: "%02x", $0) }.joined()
    }
    private func namespace(_ context: RuntimeDependencyContext) -> String {
        // Epoch intentionally included: a stale credential/account snapshot cannot resume.
        "\(context.baseURL.absoluteString):\(context.session.namespace):\(context.session.accountID):\(context.session.epoch):\(context.market.rawValue):\(context.role)"
    }
}
@MainActor private struct RegionBoundWalkingTargets: WalkingTargetAuthorizing {
    let base: any WalkingTargetAuthorizing
    let regions: Set<String>
    func authorize(_ reference: WalkingTargetReference) async throws -> AuthorizedWalkingTarget {
        let value = try await base.authorize(reference)
        guard regions.contains(value.coordinate.region), value.coordinate.datum == .wgs84 else {
            throw WalkingNavigationFailure.coordinateUnsupported
        }
        return value
    }
}
private struct WalkingNavigationFactoryKey: EnvironmentKey {
    static let defaultValue: NativeWalkingNavigationFactory? = nil
}
extension EnvironmentValues {
    var walkingNavigationFactory: NativeWalkingNavigationFactory? {
        get { self[WalkingNavigationFactoryKey.self] }
        set { self[WalkingNavigationFactoryKey.self] = newValue }
    }
}


@MainActor struct WalkingSavedDestination: Equatable, Identifiable {
    let record: WalkingSavedDestinationRecord
    let bytes: Data
    let owner: RuntimeDependencyContext
    var id: UUID { record.revision }
}

/// One small encrypted local item per account/realm. No synchronized or plaintext fallback.
@MainActor private final class WalkingSystemCheckpointStore: WalkingCheckpointStoring {
    private func query(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "questify.walking.destination.v1", kSecAttrAccount as String: key,
         kSecAttrSynchronizable as String: false, kSecUseDataProtectionKeychain as String: true]
    }
    private func tag(_ bytes: Data) -> Data { Data(SHA256.hash(data: bytes)) }
    func read(key: String) throws -> Data? {
        var request = query(key)
        request[kSecReturnData as String] = true; request[kSecReturnAttributes as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        request[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let item = result as? [String: Any],
              let bytes = item[kSecValueData as String] as? Data, bytes.count <= 4_096,
              let storedTag = item[kSecAttrGeneric as String] as? Data, storedTag == tag(bytes),
              (item[kSecAttrAccessible as String] as? String) == (kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String),
              (item[kSecAttrSynchronizable as String] as? NSNumber)?.boolValue == false else {
            throw WalkingCheckpointFailure.unavailable
        }
        return bytes
    }
    func replace(key: String, expected: Data?, replacement: Data?) throws -> Bool {
        guard expected.map({ $0.count <= 4_096 }) ?? true,
              replacement.map({ $0.count <= 4_096 }) ?? true else { throw WalkingCheckpointFailure.invalidRecord }
        var request = query(key)
        request[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        let status: OSStatus
        if let expected {
            request[kSecAttrGeneric as String] = tag(expected)
            if let replacement {
                status = SecItemUpdate(request as CFDictionary,
                    [kSecValueData as String: replacement, kSecAttrGeneric as String: tag(replacement)] as CFDictionary)
            } else { status = SecItemDelete(request as CFDictionary) }
            if status == errSecItemNotFound { return false }
        } else {
            guard let replacement else { return try read(key: key) == nil }
            request[kSecValueData as String] = replacement; request[kSecAttrGeneric as String] = tag(replacement)
            request[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(request as CFDictionary, nil)
            if status == errSecDuplicateItem { return false }
        }
        guard status == errSecSuccess else { throw WalkingCheckpointFailure.unavailable }
        return true
    }
}
