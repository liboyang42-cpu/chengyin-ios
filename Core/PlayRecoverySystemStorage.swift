#if canImport(Security) && canImport(Darwin)
import Foundation

/// Only this fixed-root factory can construct the OS-provenance seal. Injected primitives
/// (even real OS primitives with arbitrary roots) cannot authorize production dispatch.
struct PlayRecoverySystemStorage {
    let anchors: ContentDraftSystemAnchors
    let ciphertexts: ContentDraftSystemCiphertexts
    let baseURL: URL
    fileprivate init(anchors: ContentDraftSystemAnchors, ciphertexts: ContentDraftSystemCiphertexts, baseURL: URL) {
        self.anchors = anchors; self.ciphertexts = ciphertexts; self.baseURL = baseURL
    }
}
@MainActor enum PlayRecoverySystemFactory {
    static func make(session: PlayExperienceSession, scope: PlaySessionScope,
                     regionalConfiguration: RegionalConfiguration, storageScope: RegionalSessionStorageScope) throws -> PlayDurableRecovery {
        guard scope.isValid, storageScope.matches(configuration: regionalConfiguration),
              session.namespace.utf8.elementsEqual(storageScope.service.utf8),
              let baseURL = regionalConfiguration.apiConfiguration?.baseURL else { throw PlayExperienceError.persistenceUnavailable }
        let root = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).resolvingSymlinksInPath()
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("PlayRecovery-v1", isDirectory: true)
        let system = PlayRecoverySystemStorage(anchors: ContentDraftSystemAnchors(service: "questify.play.recovery.v1"),
            ciphertexts: ContentDraftSystemCiphertexts(root: root, createApplicationSupport: true), baseURL: baseURL)
        return try PlayDurableRecovery(owner: .init(session: session), key: PlayRunStorageKey.make(session: session, scope: scope), system: system)
    }
}
#endif
