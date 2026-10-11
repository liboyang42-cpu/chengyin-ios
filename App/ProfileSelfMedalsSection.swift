import SwiftUI

@MainActor struct ProfileSelfMedalsSection: View {
    let memberID: Int
    let accountReader: any SocialAccountReading
    let profileReader: any ProfileReading
    var isCurrent: @MainActor () -> Bool = { true }
    @State private var model = ProfileSelfMedalsController()
    private var context: ProfileSelfMedalsContext? {
        .capture(memberID: memberID, accountReader: accountReader, profileReader: profileReader, isCurrent: isCurrent())
    }
    var body: some View {
        Group {
            if let context {
                Section("profile.selfMedals.title") {
                    if model.context != context { ProgressView("social.loading") }
                    else {
                        if model.isLoading { ProgressView("social.loading") }
                        if let issue = model.issue {
                            Text(LocalizedStringKey(issue == .signIn ? "social.signIn" : "profile.selfMedals.failed"))
                                .accessibilityIdentifier("profile.selfMedals.issue")
                            if model.medals != nil { Text("profile.selfMedals.retained").font(.caption) }
                            Button("action.retry") { Task { await load() } }.disabled(model.isLoading)
                                .accessibilityIdentifier("profile.selfMedals.retry")
                        }
                        if let medals = model.medals {
                            LabeledContent("profile.selfMedals.loadedCount", value: String(medals.count))
                            if medals.isEmpty { Text("profile.selfMedals.empty").accessibilityIdentifier("profile.selfMedals.empty") }
                            ForEach(Array(medals.enumerated()), id: \.offset) { index, medal in
                                Label {
                                    if medal.medalName.isEmpty { Text("profile.badges.medals") }
                                    else { Text(verbatim: medal.medalName) }
                                } icon: { Image(systemName: "checkmark.seal") }
                                .accessibilityIdentifier("profile.selfMedals.row.\(index)")
                            }
                        }
                        if model.issue == nil {
                            Button("profile.selfMedals.refresh") { Task { await load() } }.disabled(model.isLoading)
                                .accessibilityIdentifier("profile.selfMedals.refresh")
                        }
                    }
                    NavigationLink {
                        ProfileSelfMedalsWallDestination(context: context, memberID: memberID,
                            accountReader: accountReader, profileReader: profileReader, isCurrent: isCurrent)
                    } label: { Label("profile.selfMedals.openWall", systemImage: "medal") }
                        .accessibilityIdentifier("profile.selfMedals.openWall")
                }
            }
        }
        .task(id: context) { await load() }
        .onDisappear { model.suspend() }
    }
    private func load() async {
        await model.load(memberID: memberID, accountReader: accountReader, profileReader: profileReader, isCurrent: isCurrent)
    }
}

/// Prevent an old own-profile link from opening a replacement account's personal wall.
@MainActor struct ProfileSelfMedalsWallDestination: View {
    private let context: ProfileSelfMedalsContext
    @State private var scopedReader: ProfileSelfMedalsScopedReader
    init(context: ProfileSelfMedalsContext, memberID: Int, accountReader: any SocialAccountReading,
         profileReader: any ProfileReading, isCurrent: @escaping @MainActor () -> Bool) {
        self.context = context
        _scopedReader = State(initialValue: .init(context: context, accountReader: accountReader,
            profileReader: profileReader, isCurrent: { isCurrent() && memberID == context.memberID }))
    }
    var body: some View {
        Group {
            if scopedReader.identity == context.owner, scopedReader.isConfigured {
                ObjectBadgeWallView(reader: scopedReader)
            } else { Text("social.changed") }
        }
    }
}
