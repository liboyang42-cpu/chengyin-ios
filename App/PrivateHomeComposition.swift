import Foundation

/// Separately reviewed source input. Authentication, role selection and server flags never mint
/// this grant. It opens only the owner's exact GET/PUT/DELETE api/native/home contract.
struct PrivateHomeTransportGrant {
    let storageScope: RegionalSessionStorageScope
    let accountID: Int
    let role: String
    init(storageScope: RegionalSessionStorageScope, accountID: Int, role: String) throws {
        guard accountID > 0, !role.isEmpty,
              role.utf8.count <= 64, role.utf8.allSatisfy({ (0x21...0x7e).contains($0) }) else {
            throw APIError.invalidConfiguration
        }
        self.storageScope = storageScope; self.accountID = accountID; self.role = role
    }
    func matches(storageScope: RegionalSessionStorageScope, accountID: Int?, role: String?) -> Bool {
        self.storageScope == storageScope && self.accountID == accountID && self.role == role
    }
}

extension AppCompositionRoot {
    /// No in-memory/plaintext journal fallback, even for read-only entry. Tests inject the same
    /// concrete durable-journal adapter over a synthetic Keychain primitive, never Security.
    func makePrivateHomeCoordinator(context: RuntimeDependencyContext, transport: any HTTPTransport,
                                    current: @escaping () -> RuntimeDependencyContext?) -> PrivateHomeCoordinator? {
        guard let reviewed, let api = reviewed.regional.apiConfiguration, let grant = reviewed.privateHome,
              grant.matches(storageScope: reviewed.storageScope, accountID: context.session.accountID, role: context.role),
              context.market == reviewed.regional.market, context.baseURL == api.baseURL,
              context.session.namespace == reviewed.storageScope.service,
              let primitive = storage.privateHomeKeychain,
              let journal = try? PrivateHomeKeychainJournal(storageScope: reviewed.storageScope,
                  owner: context.session, primitive: primitive), current() == context else { return nil }
        // PlayExperienceSession has no role field. Compare the entire captured context first,
        // so a same-account role change revokes every old coordinator/service reference too.
        let owner: () -> PlayExperienceSession? = { current() == context ? context.session : nil }
        let service = PrivateHomeService(api: api, transport: transport, owner: context.session,
                                         enabled: true, current: owner)
        return PrivateHomeCoordinator(service: service, journal: journal, owner: context.session,
                                      enabled: true, current: owner)
    }
}
