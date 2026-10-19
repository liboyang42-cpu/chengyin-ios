#if DEBUG
import SwiftUI

/// Mini-program merchant template tab for a staff role without `merchant:project:manage`.
@MainActor struct TemplateTabStaffFixtureHost: View {
    @State private var reader = DiscoveryFixtureReader()
    var body: some View {
        NavigationStack {
            DiscoveryTemplateBrowserView(reader: reader, templateTabScope: .merchant(canManageProjects: false))
        }
    }
}
#endif
