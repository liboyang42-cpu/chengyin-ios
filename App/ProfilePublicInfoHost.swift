import SwiftUI

/// The whole destination owns its reader; list-row recycling cannot retire the profile.
@MainActor struct ProfilePublicInfoHost<Content: View>: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var reader: ProfilePublicInfoReader?
    private let content: (ProfilePublicInfoReader) -> Content
    init(reader: ProfilePublicInfoReader?, @ViewBuilder content: @escaping (ProfilePublicInfoReader) -> Content) {
        _reader = State(initialValue: reader); self.content = content
    }
    var body: some View {
        ZStack {
            if let reader {
                if reader.hasAppeared { content(reader) }
                else { ProgressView() }
            } else { SocialIssueView(error: APIError.unauthorized) }
        }
        .onAppear { reader?.appear(foreground: scenePhase == .active) }
        .onDisappear { reader?.disappear() }
        .onChange(of: scenePhase) { _, phase in reader?.setForeground(phase == .active) }
        .refreshable { reader?.requestRefresh() }
    }
}
