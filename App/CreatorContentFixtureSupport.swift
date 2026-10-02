#if DEBUG
import SwiftUI
@MainActor struct CreatorContentFixtureHostView: View {
    @State private var reader: CreatorContentFixtureReader
    @State private var revision = 0
    @State private var destination: String?
    init() {
        let args = ProcessInfo.processInfo.arguments
        let reader = CreatorContentFixtureReader()
        if args.contains("--creator-failure") { reader.failure = .httpStatus(503) }
        if args.contains("--creator-guest") { reader.isAuthenticated = false }
        if args.contains("--creator-rejected") { reader.centerJSON = #"{"code":200,"data":{"applyStatus":"rejected","rejectReason":"Synthetic rejection reason"}}"# }
        if args.contains("--creator-empty") { reader.projectsJSON = #"{"code":200,"data":{"rows":[],"total":0}}"# }
        _reader = State(initialValue: reader)
    }
    var body: some View {
        VStack {
            HStack {
                Button("creatorContent.fixture.signOut") { reader.signOut(); revision += 1 }.accessibilityIdentifier("creatorContent.fixture.signOut")
                Button("creatorContent.fixture.recover") { reader.failure = nil; revision += 1 }.accessibilityIdentifier("creatorContent.fixture.recover")
            }
            NavigationStack {
                List {
                    NavigationLink("creatorContent.projects") {
                        CreatorContentProjectsView(reader: reader) { route in
                            switch route { case .topic(let id): destination = "topic:\(id)"
                            case .activity(let id): destination = "activity:\(id)"
                            case .playTemplate(let id): destination = "template:\(id)" }
                        }
                    }.accessibilityIdentifier("creatorContent.openProjects")
                    NavigationLink("creatorContent.center") { CreatorContentCenterView(reader: reader) }
                        .accessibilityIdentifier("creatorContent.openCenter")
                }
            }.id(revision)
            if let destination { Text(verbatim: destination).accessibilityIdentifier("creatorContent.fixture.destination") }
        }
    }
}
#endif
