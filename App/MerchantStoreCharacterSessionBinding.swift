import SwiftUI

extension AppSession {
    /// Production AI 店铺角色 destination: read-only. Access, `npc/profile` and `coop-profile` go through
    /// the existing token-scoped merchant operations reader; writes stay absent (gates off, no allowlist).
    func merchantStoreCharacterDestination() -> AnyView {
        AnyView(SessionMerchantStoreCharacterView(reader: merchantOperationsReader))
    }
}

@MainActor struct SessionMerchantStoreCharacterView: View {
    let reader: any MerchantOperationsReading
    var body: some View {
        MerchantStoreCharacterView(coordinator: StoreCharacterCoordinator(reader: StoreCharacterOperationsReader(reader: reader)))
            .id(reader.scope)
    }
}
