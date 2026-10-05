#if DEBUG
import SwiftUI

@MainActor struct PublicTemplateDetailFixtureHost: View {
    @State private var coordinator: PublicTopicTemplateCoordinator
    init() {
        let args = ProcessInfo.processInfo.arguments
        _coordinator = State(initialValue: PublicTopicTemplateCoordinator(id: 801) { _ in
            if args.contains("--public-template-loading") { try await Task.sleep(for: .seconds(60)) }
            if args.contains("--public-template-error") { throw APIError.httpStatus(503) }
            if args.contains("--public-template-unavailable") { throw DiscoveryTemplateUnavailable.offline }
            let json = args.contains("--public-template-empty") ? #"{"id":801}"# : PublicTopicTemplateFixtures.content(merchant: args.contains("--public-template-merchant"))
            return try JSONDecoder().decode(PublicTopicTemplateDetail.self, from: Data(json.utf8))
        })
    }
    var body: some View {
        VStack {
            Button("Change account context") { coordinator.invalidate() }
                .accessibilityIdentifier("discovery.publicFixture.invalidate")
            DiscoveryTopicTemplatePreview(coordinator: coordinator)
        }
    }
}
#endif
