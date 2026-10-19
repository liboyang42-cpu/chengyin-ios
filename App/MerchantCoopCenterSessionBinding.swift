import SwiftUI

extension AppSession {
    /// Source pages/merchant/coop-center. Built only from existing session readers; read-only.
    /// `initialTab` mirrors `?tab=official`, `focusTopicID` mirrors `?topicId=`.
    func merchantCoopCenterDestination(initialTab: MerchantCoopCenterTab = .plaza, focusTopicID: Int? = nil) -> AnyView {
        AnyView(SessionMerchantCoopCenterView(session: self, initialTab: initialTab, focusTopicID: focusTopicID))
    }
}

/// Official reads go through the merchant-membership adapter, which re-checks access and the
/// session revision before each list/detail read; plaza reads go through the content service's
/// fresh `merchant:marketing:read` gate. Identity or scene changes rebuild the page.
@MainActor struct SessionMerchantCoopCenterView: View {
    @ObservedObject var session: AppSession
    @StateObject private var official: MerchantOfficialRecruitmentReader<AppSession>
    @Environment(\.scenePhase) private var scenePhase
    private let initialTab: MerchantCoopCenterTab
    private let focusTopicID: Int?
    init(session: AppSession, initialTab: MerchantCoopCenterTab = .plaza, focusTopicID: Int? = nil) {
        self.session = session; self.initialTab = initialTab; self.focusTopicID = focusTopicID
        let revision = session.sessionRevision
        _official = StateObject(wrappedValue: .init(merchant: session, official: session.officialEventReader,
            sourceIsCurrent: { [weak session] in session?.sessionRevision == revision }))
    }
    var body: some View {
        MerchantCoopCenterView(content: session.merchantContentService, official: official, initialTab: initialTab,
            focusTopicID: focusTopicID, officialActions: session.officialActionCoordinator,
            inboxDestination: { close in
                AnyView(CooperationBrowserView(reader: session.cooperationReader, onClose: close, peerReader: session.cooperationFlowReader)
                    .id(session.cooperationReader.scope))
            })
            .id(official.scope)
            .onChange(of: scenePhase) { _, phase in official.setActive(phase == .active) }
            .onAppear { official.setActive(scenePhase == .active) }
    }
}

/// Host-registered factory so existing merchant screens can open the cooperation center
/// without holding AppSession. Absent (nil) keeps every entry hidden.
private struct MerchantCoopCenterDestinationKey: EnvironmentKey {
    static let defaultValue: ((MerchantCoopCenterTab, Int?) -> AnyView)? = nil
}
extension EnvironmentValues {
    var merchantCoopCenterDestination: ((MerchantCoopCenterTab, Int?) -> AnyView)? {
        get { self[MerchantCoopCenterDestinationKey.self] }
        set { self[MerchantCoopCenterDestinationKey.self] = newValue }
    }
}
