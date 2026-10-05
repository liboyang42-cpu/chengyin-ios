import SwiftUI

/// No default destination, session or read grant. Normal composition supplies the
/// existing personal-template reader, never the owned shelf or public library.
struct ClubStoryTemplateContext {
    var viewerRevision: UInt64 = 0
    var reader: (any MemberTemplateReading)? = nil
    var destination: ((MemberPlayTemplateID) -> AnyView)? = nil
    var imageReader: (any RetainedPublicImageReading)? = nil
    @MainActor var readerIdentity: ObjectIdentifier? { reader.map { ObjectIdentifier($0) } }
    @MainActor var readerScope: UUID? { reader?.scope }
    @MainActor var isAvailable: Bool {
        destination != nil && reader?.isAuthenticated == true && reader?.isConfigured == true
    }
}
private struct ClubStoryTemplateKey: EnvironmentKey {
    static let defaultValue = ClubStoryTemplateContext()
}
extension EnvironmentValues {
    var clubStoryTemplates: ClubStoryTemplateContext {
        get { self[ClubStoryTemplateKey.self] }
        set { self[ClubStoryTemplateKey.self] = newValue }
    }
}
@MainActor extension AppSession {
    func clubStoryTemplateContext(viewerRevision: UInt64) -> ClubStoryTemplateContext {
        .init(viewerRevision: viewerRevision, reader: playerJourneyReader, destination: { [weak self] id in
            guard let self else { return AnyView(Text("club.story.templateUnavailable")) }
            return AnyView(SessionMemberTemplateDetailView(id: id).environmentObject(self))
        })
    }
}

enum ClubStoryTab: Hashable { case route, play }
struct ClubStorySourceRevision: Equatable {
    let snapshot: ClubGovernanceSnapshot?
    let context: ClubGovernanceReadContext
    let snapshotGeneration: UInt64
    let sourceIsCurrent: Bool
    let readerScope: UUID?
    let destinationAvailable: Bool
}
/// This extra app fence captures the current player reader's session scope. A
/// source refresh or session/reader replacement cannot dispatch a queued route.
struct ClubStoryTemplateSelection: Identifiable, Hashable {
    let route: ClubStoryTemplateRoute
    let readerScope: UUID
    var id: UUID { route.id }
    @MainActor init?(gameplay: ClubStoryGameplay, snapshot: ClubGovernanceSnapshot,
          context: ClubGovernanceReadContext, snapshotGeneration: UInt64, templates: ClubStoryTemplateContext) {
        guard templates.isAvailable, let readerScope = templates.readerScope,
              context.readerIdentity == templates.readerIdentity,
              let route = ClubStoryTemplateRoute(gameplay: gameplay, snapshot: snapshot,
                  context: context, snapshotGeneration: snapshotGeneration) else { return nil }
        self.route = route; self.readerScope = readerScope
    }
    @MainActor func isCurrent(snapshot: ClubGovernanceSnapshot?, context: ClubGovernanceReadContext,
                   snapshotGeneration: UInt64, templates: ClubStoryTemplateContext) -> Bool {
        templates.isAvailable && templates.readerScope == readerScope && context.readerIdentity == templates.readerIdentity &&
        route.isCurrent(snapshot: snapshot, context: context, snapshotGeneration: snapshotGeneration)
    }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct ClubStoryEmptyState: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Text(detail).font(.subheadline).foregroundStyle(.secondary)
        }.padding(.vertical, 12)
    }
}
struct ClubStoryChapterTitle: View {
    let chapter: ClubStoryChapter
    var body: some View {
        Group {
            if let name = chapter.name, name.hasPrefix("第"), name.contains("章") { Text(verbatim: name) }
            else if let name = chapter.name { Text("club.story.chapter \(chapter.id + 1)") + Text(verbatim: " · " + name) }
            else { Text("club.story.chapter \(chapter.id + 1)") }
        }.accessibilityIdentifier("club.gov.fact.title")
    }
}
struct ClubStoryChapterHeader: View {
    let chapter: ClubStoryChapter
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ClubStoryChapterTitle(chapter: chapter).font(.headline)
            if chapter.stops.isEmpty { Text("club.story.awaitingMerchants") }
            else {
                Text("club.story.stopCount \(chapter.stops.count)")
                if let minutes = chapter.totalTime { Text("club.story.minutes \(minutes.formatted(.number.precision(.fractionLength(0...2))))") }
            }
        }.textCase(nil)
    }
}
@MainActor struct ClubStoryCover: View {
    let raw: String?
    let imageReader: (any RetainedPublicImageReading)?
    var body: some View {
        Group {
            if let raw {
                NativeMediaImage(raw: raw, reader: imageReader ?? RetainedPublicImageReader(), zoomable: false)
            } else {
                ZStack {
                    Rectangle().fill(.quaternary)
                    Label("club.story.noImage", systemImage: "photo").font(.caption).foregroundStyle(.secondary)
                }
            }
        }.frame(height: 132).clipShape(RoundedRectangle(cornerRadius: 12)).accessibilityHidden(true)
    }
}
@MainActor struct ClubStoryStopCard: View {
    let stop: ClubStoryStop
    let imageReader: (any RetainedPublicImageReading)?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("club.story.stop \(stop.sequence)", systemImage: "mappin.circle.fill").font(.caption.weight(.semibold))
            ClubStoryCover(raw: stop.imgUrl, imageReader: imageReader)
            if let name = stop.name { Text(verbatim: name).font(.headline) }
            else { Text("club.story.unnamedStop").font(.headline) }
            if let time = stop.businessTime { Label { Text(verbatim: time) } icon: { Image(systemName: "clock") } }
            else { Text("club.story.hoursUnavailable").foregroundStyle(.secondary) }
            if let address = stop.address { Label { Text(verbatim: address) } icon: { Image(systemName: "mappin.and.ellipse") } }
            else { Text("club.story.addressUnavailable").foregroundStyle(.secondary) }
        }.padding(.vertical, 6).fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .contain).accessibilityIdentifier("club.story.stop.\(stop.id)")
    }
}
@MainActor struct ClubStoryGameplayCard: View {
    let play: ClubStoryGameplay
    let imageReader: (any RetainedPublicImageReading)?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ClubStoryCover(raw: play.imgUrl, imageReader: imageReader)
            HStack(alignment: .firstTextBaseline) {
                if let code = play.validationMethod, let method = TemplateAuthoringMethod(rawValue: code) { Text(LocalizedStringKey(method.labelKey)) }
                else if let label = play.validationMethodLabel { Text(verbatim: label) }
                else { Text("club.story.play") }
                if !play.isAnswerable { Text("club.story.noAnswer").foregroundStyle(.secondary) }
            }.font(.caption.weight(.semibold))
            Group {
                if let title = play.title { Text(verbatim: title) }
                else { Text("discovery.untitledPlay") }
            }.font(.headline).accessibilityIdentifier("club.gov.fact.title")
            Text("club.story.stop \(play.sequence)").font(.subheadline)
                .accessibilityIdentifier("club.story.play.\(play.id)")
            if let name = play.nodeName { Text(verbatim: name).font(.subheadline) }
            if let players = play.players { Label { Text(verbatim: players) } icon: { Image(systemName: "person.2") } }
            if let duration = play.duration { Label { Text("club.story.minutes \(duration.formatted(.number.precision(.fractionLength(0...2))))") } icon: { Image(systemName: "clock") } }
            if let difficulty = play.difficulty { Text("club.story.difficulty \(difficulty)") }
        }.fixedSize(horizontal: false, vertical: true)
    }
}
