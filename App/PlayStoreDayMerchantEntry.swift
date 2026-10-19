import SwiftUI

/// Free-exploration store entry into the source pages/play/merchant page. The coordinator is
/// created once per pushed destination, never during the parent list's body evaluation.
@MainActor struct PlayStoreDayMerchantEntry: View {
    let nodeID: Int
    let make: (Int) -> PlayStoreDayCoordinator?
    var makeExternalMaps: (@MainActor () -> PlatformExternalMaps)? = nil
    let mediaScope: UUID
    var body: some View {
        NavigationLink { PlayStoreDayMerchantDestination(nodeID: nodeID, make: make, makeExternalMaps: makeExternalMaps, mediaScope: mediaScope) } label: {
            Text("playStoreDay.title", tableName: "PlayStoreDay")
        }.accessibilityIdentifier("storeDayPage.entry." + String(nodeID))
    }
}

@MainActor private struct PlayStoreDayMerchantDestination: View {
    let nodeID: Int
    let make: (Int) -> PlayStoreDayCoordinator?
    let makeExternalMaps: (@MainActor () -> PlatformExternalMaps)?
    let mediaScope: UUID
    @State private var model: PlayStoreDayCoordinator?
    @State private var resolved = false
    var body: some View {
        Group {
            if let model { PlayStoreDayMerchantView(model: model, makeExternalMaps: makeExternalMaps, mediaScope: mediaScope) }
            else if resolved { Text("playMode.unavailable") }
            else { ProgressView() }
        }
        .onAppear { guard !resolved else { return }; model = make(nodeID); resolved = true }
        .onDisappear { model?.invalidate() }
    }
}
