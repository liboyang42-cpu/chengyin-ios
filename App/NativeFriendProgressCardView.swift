import SwiftUI

@MainActor struct NativeFriendProgressCardView: View {
    @Environment(\.themeDomain) private var domain
    @Environment(\.locale) private var locale
    private var copy: NativeProgressPrivacyLocalization { .init(locale: locale) }
    @Environment(\.scenePhase) private var scenePhase
    @Bindable var model: NativeFriendProgressCard
    var body: some View {
        Section {
            switch model.state {
            case .awaitingIndex: Text("friendIndexPending", tableName: "NativeChannelProgress")
            case .loading: ProgressView()
            case .hidden: Text("hidden", tableName: "NativeChannelProgress")
            case .unconfirmed: Text("unconfirmed", tableName: "NativeChannelProgress")
            case .closed: Text("closed", tableName: "NativeChannelProgress")
            case .visible(let rows):
                if rows.isEmpty { Text("friendEmpty", tableName: "NativeChannelProgress") }
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: Theme.Space.s1) {
                        Text(verbatim: row.title).font(Theme.Font.body.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                        if let done = row.meter.done, let required = row.meter.required { Text(verbatim: copy.format("p31.friend.fraction", copy.number(done), copy.number(required))) }
                        if let percent = row.meter.percent { Text(verbatim: copy.format("p31.friend.percent", copy.number(percent))) }
                        if let at = row.meter.asOf { Text(verbatim: at).font(Theme.Font.label).foregroundStyle(Theme.Color.textSecondary(in: domain)) }
                        // Original service/card already validates FRIEND/SELF and the current viewer/peer/context.
                        // Display only the returned row; no hidden rows, policy causes or broad permission inferred.
                        if let visibility = row.meter.visibility,
                           visibility.aggregate == "FRIEND", visibility.detail == "SELF" {
                            Text(verbatim: copy.text("p31.friend.currentVisibility"))
                                .font(Theme.Font.label).foregroundStyle(Theme.Color.textSecondary(in: domain))
                                .accessibilityIdentifier("friendProgress.currentVisibility")
                        }
                    }
                }
            }
            Button(copy.text("p31.friend.refresh")) { Task { await model.activate() } }.font(Theme.Font.label).frame(minHeight: 44, alignment: .leading)
        } header: { Text("friendProgress", tableName: "NativeChannelProgress") }
        .font(Theme.Font.body)
        .foregroundStyle(Theme.Color.textPrimary(in: domain))
        .privacySensitive().accessibilityIdentifier("friendProgress.card")
        .task { await model.activate() }
        .onDisappear { model.invalidate() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await model.activate() } } else { model.invalidate() } }
        .themeDomain(domain)
        .tint(Theme.Color.accent(in: domain))
    }
}

/// Stable card ownership across unrelated parent rerenders; private facts are never disk-cached.
@MainActor struct NativeFriendProgressCardHost: View {
    @State private var model: NativeFriendProgressCard
    init(model: NativeFriendProgressCard) { _model = State(initialValue: model) }
    var body: some View { NativeFriendProgressCardView(model: model) }
}
