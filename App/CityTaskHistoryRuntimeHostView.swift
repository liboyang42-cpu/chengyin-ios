import SwiftUI

/// Host remains alive while its independently retained original-result destination is on screen.
@MainActor struct CityTaskHistoryRuntimeHostView: View {
    @EnvironmentObject private var session: AppSession
    @Bindable var owner: CityTaskHistoryRuntimeOwner
    let revision: UInt64
    var body: some View {
        Group {
            if owner.isCurrent, let controller = owner.controller {
                CityTaskHistoryView(controller: controller)
            } else {
                Text("cityHistory.status.disabled", tableName: "CityTaskHistory")
            }
        }
        .onAppear { owner.synchronize() }
        .onChange(of: session.currentRuntimeDependencyContext) { _, _ in owner.synchronize() }
        .onChange(of: revision) { _, _ in owner.synchronize() }
        // Child handles foreground/disappearance. Retiring here would incorrectly destroy original-result navigation.
    }
}
