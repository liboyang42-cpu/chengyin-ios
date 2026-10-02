import SwiftUI

@MainActor struct SessionRoamStampCameraView: View {
    @EnvironmentObject private var session: AppSession
    @State private var coordinator: RoamStampCaptureCoordinator?
    var body: some View {
        RoamStampCameraView(coordinator: coordinator, cameraEnabled: false)
            .id(coordinator.map { ObjectIdentifier($0) })
            .task(id: session.walletCommerceScope) { coordinator?.cancel(); coordinator = session.makeRoamStampCaptureCoordinator() }
            .onChange(of: session.walletCommerceScope) { _, _ in coordinator?.cancel(); coordinator = nil }
    }
}
@MainActor struct SessionRoamPosterView: View {
    @EnvironmentObject private var session: AppSession
    let node: RoamNodeDetail
    @State private var coordinator: RoamPosterCoordinator?
    var body: some View {
        RoamPosterScanView(node: node, coordinator: coordinator, cameraEnabled: false)
            .id(coordinator.map { ObjectIdentifier($0) })
            .task(id: session.walletCommerceScope) { coordinator?.cancel(); coordinator = session.makeRoamPosterCoordinator(node: node) }
            .onChange(of: session.walletCommerceScope) { _, _ in coordinator?.cancel(); coordinator = nil }
    }
}
@MainActor final class DisabledRoamPosterLocation: RoamDeviceLocationProviding {
    func currentFix() async throws -> RoamDeviceFix { throw RoamExperienceFailure.capabilityUnavailable }
    func stop() {}
}
