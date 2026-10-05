import SwiftUI

/// Normal Account destination. Reading the observable approval through reader.identity
/// tracks revocation/expiry even when an already-loaded screen is otherwise idle.
/// No lifecycle action coordinator or external-map provider is mounted here.
@MainActor struct SessionOwnedOrdersView: View {
    @ObservedObject var session: AppSession
    var body: some View {
        ProfileOrdersView(reader: session.ownedOrderReader)
            .id(session.ownedOrderReader.identity)
    }
}
