import SwiftUI

/// Host remains alive while its independently retained original-result destination is on screen.
@MainActor struct CityOnsiteTaskRuntimeHostView: View {
    @EnvironmentObject private var session: AppSession
    let arrivalFactory: (@MainActor (CityReadBoard) -> CityArrivalEvidenceController)?
    @Bindable var owner: CityOnsiteTaskRuntimeOwner
    let revision: UInt64
    var body: some View {
        Group {
            if owner.isCurrent, let controller = owner.controller {
                CityOnsiteTaskView(controller: controller, board: owner.board, arrivalFactory: arrivalFactory)
            } else {
                Text("cityOnsite.status.disabled", tableName: "CityOnsiteTask")
            }
        }
        .onAppear { owner.synchronize() }
        .onChange(of: session.currentRuntimeDependencyContext) { _, _ in owner.synchronize() }
        .onChange(of: revision) { _, _ in owner.synchronize() }
        // Child handles foreground/disappearance. Retiring here would incorrectly destroy original-result navigation.
    }
}
