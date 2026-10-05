import SwiftUI

struct SquareRelatedTopicContext {
    let squareScope: UUID
    let reader: any TopicReading
}
private struct SquareRelatedTopicContextKey: EnvironmentKey {
    static let defaultValue: SquareRelatedTopicContext? = nil
}
extension EnvironmentValues {
    var squareRelatedTopic: SquareRelatedTopicContext? {
        get { self[SquareRelatedTopicContextKey.self] }
        set { self[SquareRelatedTopicContextKey.self] = newValue }
    }
}

@MainActor struct SquareRelatedTopicLink: View {
    let post: SquarePost
    let source: SquareContentRoute
    let squareReader: any SquareReading
    let onSelect: (SquareRelatedTopicSelection) -> Void
    @Environment(\.squareRelatedTopic) private var context
    var body: some View {
        Group {
            if let context, context.squareScope == squareReader.scope,
               let route = SquareRelatedTopicRoute(post: post, source: source) {
                let selected = SquareRelatedTopicSelection(route: route, squareScope: context.squareScope, topicScope: context.reader.scope)
                Button {
                    guard selected.isCurrent(squareScope: squareReader.scope, topicScope: context.reader.scope) else { return }
                    onSelect(selected)
                } label: { Label("activity.viewTopic", systemImage: "map") }
                    .accessibilityIdentifier("square.openRelatedTopic")
            }
        }
    }
}

@MainActor struct SquareRelatedTopicDestination: View {
    let selection: SquareRelatedTopicSelection
    let squareReader: any SquareReading
    let topicReader: any TopicReading
    var body: some View {
        Group {
            if selection.isCurrent(squareScope: squareReader.scope, topicScope: topicReader.scope) {
                // Existing reader enforces topic access. No publishing, purchase,
                // review, self-play or platform provider is injected here.
                TopicDetailView(id: selection.route.topicID, reader: topicReader)
                    .id(selection)
            } else { SocialIssueView(error: SocialActionBlock.changed) }
        }
        .privacySensitive()
    }
}
