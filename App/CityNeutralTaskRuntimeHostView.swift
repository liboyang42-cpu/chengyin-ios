import SwiftUI

/// Host remains alive while its independently retained original-result destination is on screen.
@MainActor struct CityNeutralTaskRuntimeHostView: View {
    @EnvironmentObject private var session: AppSession
    @Bindable var owner: CityNeutralTaskRuntimeOwner
    let revision: UInt64
    var body: some View {
        Group {
            if owner.isCurrent, let controller = owner.controller {
                CityNeutralTaskView(controller: controller)
            } else {
                Text("cityNeutral.status.disabled", tableName: "CityNeutralTask")
            }
        }
        .onAppear { owner.synchronize() }
        .onChange(of: session.currentRuntimeDependencyContext) { _, _ in owner.synchronize() }
        .onChange(of: revision) { _, _ in owner.synchronize() }
        // Child handles foreground/disappearance. Retiring here would incorrectly destroy original-result navigation.
    }
}
