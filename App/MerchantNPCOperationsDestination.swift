import SwiftUI

/// Additive destination router: preserve all existing editors and their reader ownership.
/// Host replaces only its destination constructor, not MerchantOperationsHomeView's access filter.
@MainActor struct MerchantNPCOperationsDestination: View {
    let reader: any MerchantOperationsReading
    let destination: MerchantOperationsDestination
    let scope: MerchantNPCScope
    let currentScope: () -> MerchantNPCScope?
    let grants: () -> MerchantNPCGrants
    var client = MerchantNPCHTTPClient()
    var journal: any OperationPendingJournal = OperationDefaultsJournal(defaults: .standard)
    var image: MerchantNPCMediaReference?
    var makeVoiceSamples: ((MerchantNPCResourcesCoordinator) -> MerchantNPCVoiceSamplesCoordinator)?
    var samples: [MerchantNPCMediaReference] = []
    var body: some View {
        if destination == .assets {
            MerchantNPCResourceEditor(coordinator: .init(scope: scope, client: client, reader: reader, journal: journal, currentScope: currentScope, grants: grants), samples: samples, image: image, makeVoiceSamples: makeVoiceSamples)
                .id(scope.epoch)
        } else {
            MerchantOperationsDocumentView(reader: reader, destination: destination)
        }
    }
}
