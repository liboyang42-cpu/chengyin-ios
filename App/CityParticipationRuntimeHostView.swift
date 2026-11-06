import SwiftUI

/// Explicit host only. No production factory/navigation registration is added.
/// revision must be the actual composition-viewer/permission revision captured by the owning AppSession factory.
@MainActor struct CityParticipationRuntimeHostView: View {
    @EnvironmentObject private var session: AppSession
    @Bindable var owner: CityParticipationRuntimeOwner
    let revision: UInt64
    var body: some View {
        Group {
            if owner.isCurrent, owner.matches(session.currentRuntimeDependencyContext, revision: revision), let form = owner.form {
                CityParticipationFormView(model: form, identityVersion: revision).id(owner.id)
            } else {
                ContentUnavailableView("参与暂不可用", systemImage: "person.crop.circle.badge.xmark",
                    description: Text("请保留原请求记录。此入口不会重新提交。"))
            }
        }
        .onChange(of: session.currentRuntimeDependencyContext) { _, context in
            if !owner.matches(context, revision: revision) { owner.retire() }
        }
        .onChange(of: revision) { _, value in
            if !owner.matches(session.currentRuntimeDependencyContext, revision: value) { owner.retire() }
        }
        .onDisappear { owner.retire() }
    }
}
