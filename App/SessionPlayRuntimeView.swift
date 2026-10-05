import SwiftUI
import UIKit

/// Observes the actual AppSession publisher so logout/relogin tears down all displayed
/// journey data even while a nested runtime destination is visible. Factories remain off.
@MainActor struct SessionPlayRuntimeView: View {
    enum Destination { case journey(PlaySessionScope), director(Int), prefab(PlaySessionScope) }
    @ObservedObject var session: AppSession
    let destination: Destination
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        Group {
            switch destination {
            case .journey(let scope):
                if let model = session.playExperience(for: scope) {
                    PlayExperienceView(model: model,
                        deviceModel: { nodeID in session.playDevice(scope: scope, nodeID: nodeID, lifetime: model.makeInteractionLifetime()) },
                        advancedModel: { nodeID in session.playAdvanced(scope: scope, nodeID: nodeID, topicID: model.snapshot?.result.topicID, lifetime: model.makeInteractionLifetime()) },
                        motionModel: { nodeID, configuration in session.playStillness(scope: scope, nodeID: nodeID, configuration: configuration, lifetime: model.makeInteractionLifetime()) },
                        preferenceModel: { nodeID in session.playPreference(scope: scope, nodeID: nodeID, lifetime: model.makeInteractionLifetime()) },
                        summaryModel: { session.playOperatingSummary(topicID: $0) },
                        playerModel: session.playPlayer(scope: scope),
                        circleModel: session.playCircle(topicID: model.snapshot?.result.topicID),
                        prefabModel: session.playPrefab(scope: scope),
                        journeyModel: { session.journeyCheck(scope: scope, topicID: model.snapshot?.result.topicID, nodeID: $0) },
                        ambientModel: session.journeyAmbient(scope: scope),
                        narrativeModel: { session.journeyNarrative(scope: scope, topicID: model.snapshot?.result.topicID, query: $0) },
                        narrativeImageReader: session.journeyNarrativeImageReader, shopNPCModel: { session.shopNPCNodeHost(scope: scope, nodeID: $0, runtime: model) },
                        invalidateShopNPC: session.invalidateShopNPCConversations,
                        mediaScope: session.platformConsumers.scope,
                        makeAudio: session.platformConsumers.audioFactory, makeExternalMaps: session.platformConsumers.mapsFactory,
                        approvedArtworkHosts: session.playKitArtworkHosts, makeSensorProvider: session.playKitSensorFactory,
                        spatialApproval: session.playKitSpatialApproval)
                } else { Text("playx.disabled") }
            case .director(let activityID):
                if let model = session.playDirector(activityID: activityID) { PlayDirectorView(model: model) }
                else { Text("playx.disabled") }
            case .prefab(let scope):
                if let model = session.playPrefab(scope: scope) { PlayPrefabRuntimeView(model: model) }
                else { Text("playx.disabled") }
            }
        }.id(session.sessionRevision).privacySensitive()
        .environment(\.nativePlatformRuntime, session.nativePlatformRuntime)
        .task(id: session.sessionRevision) { await session.nativePlatformRuntime?.reconcileOwnedRequests() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in session.nativePlatformRuntime?.clockChanged() }
        .sheet(isPresented: Binding(get: { session.playNativeDeviceProvider.showingCamera }, set: { if !$0 { session.playNativeDeviceProvider.cancel() } })) {
            PlayNativeCameraSheet(provider: session.playNativeDeviceProvider).ignoresSafeArea()
        }
        .sheet(isPresented: Binding(get: { session.playNativeDeviceProvider.showingLibraryPicker }, set: { if !$0 { session.playNativeDeviceProvider.cancel() } })) {
            PlayKitNativePhotoLibrarySheet(provider: session.playNativeDeviceProvider)
        }
        .onChange(of: session.sessionRevision) { _, _ in session.playNativeDeviceProvider.cancel() }
        .onChange(of: scenePhase) { _, phase in if phase == .background { session.nativePlatformRuntime?.suspendMotion() }; if phase == .active { Task { await session.nativePlatformRuntime?.reconcileOwnedRequests() } }; if phase == .background || (phase != .active && !session.playNativeDeviceProvider.authorizationInFlight) { session.playNativeDeviceProvider.cancel() } }
        .onDisappear { session.playNativeDeviceProvider.cancel() }
    }
}
