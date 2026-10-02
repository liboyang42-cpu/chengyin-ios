import SwiftUI

/// Passed only by the normal session host. No closure starts a request by construction.
@MainActor struct IMExpandedNavigationContext {
    let coordinator: (Int) -> IMExpandedCoordinator?
    let uploadCoordinator: (Int) -> IMImageUploadCoordinator?
    let starter: () -> IMConversationStarter?
    let topicReader: any TopicReading
}
extension AppSession {
    var imExpandedNavigation: IMExpandedNavigationContext {
        .init(coordinator: { [weak self] in self?.imExpandedCoordinator(for: $0) },
              uploadCoordinator: { [weak self] in self?.imImageUploadCoordinator(for: $0) },
              starter: { [weak self] in self?.imConversationStarter() }, topicReader: topicReader)
    }
}
