#if DEBUG
import SwiftUI

enum ModuleFixture: String {
    case discovery, profile, messaging, roam
    static var selected: Self? {
        let args=ProcessInfo.processInfo.arguments
        guard let i=args.firstIndex(of:"--uitesting-module"),args.indices.contains(i+1) else { return nil }
        return Self(rawValue:args[i+1])
    }
}

@MainActor
struct ModuleFixtureRootView: View {
    let module: ModuleFixture
    @State private var discovery=DiscoveryFixtureReader()
    @State private var roam=RoamFixtureReader()
    var body: some View {
        VStack(spacing:0) {
            Text("activity.fixtureNotice").font(.caption.bold()).padding(8)
                .frame(maxWidth:.infinity).background(.yellow.opacity(0.2))
                .accessibilityIdentifier("module.fixture.notice")
            switch module {
            case .discovery: DiscoveryHomeView(reader:discovery)
            case .profile: ProfileFixtureHostView()
            case .messaging: MessagingFixtureHostView()
            case .roam: RoamBrowserView(reader:roam)
            }
        }
    }
}
#endif
