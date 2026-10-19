import SwiftUI

/// Mini-program `cy-post-card` layout for Square list rows: author head, meta line (club · relative time),
/// review lifecycle, clamped body, play card, image strip and read-only counters.
/// Images stay behind the existing gated `NativeMediaGalleryEntry`; avatars use a local placeholder.
struct SquareXcxPostCard: View {
    let post: SquarePost
    var mediaScope: UUID = UUID()
    var now: Date = Date()
    /// List rows place the tappable gallery outside their NavigationLink, so the card omits it there.
    var showsMedia = true
    private var facts: SquarePostCardFacts { SquarePostCardFacts(post) }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            head
            if let lifecycle = facts.lifecycle {
                Text(LocalizedStringKey("square.xcx.lifecycle." + lifecycle.rawValue)).font(.caption).foregroundStyle(.orange)
                    .accessibilityIdentifier("square.card.lifecycle")
            }
            if let contents = post.contents, !contents.isEmpty {
                Text(verbatim: contents).lineLimit(2)
                if facts.bodyExpandable { Text("square.xcx.expand").font(.caption).foregroundStyle(.tint) }
            }
            if facts.isCompletionShare || facts.hasPlayCover { playCard }
            if showsMedia, let preview = facts.leadingRoutePreview {
                NativeMediaGalleryEntry(sources: [preview], scope: mediaScope, titleKey: "media.destination.squareImages", compact: true)
            }
            if !facts.strip.isEmpty {
                if showsMedia { NativeMediaGalleryEntry(sources: facts.strip, scope: mediaScope, titleKey: "media.destination.squareImages", compact: true) }
                if facts.showsCountPill { Text("square.xcx.countPill \(facts.strip.count)").font(.caption2).accessibilityIdentifier("square.card.count") }
            }
            counters
        }.padding(.vertical, 4)
    }
    private var head: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "person.crop.circle.fill").font(.largeTitle).foregroundStyle(.secondary).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if let name = post.nickname?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty { Text(verbatim: name).font(.headline) }
                    else { Text("square.xcx.defaultName").font(.headline) }
                    if post.verified { Image(systemName: "checkmark.seal.fill").foregroundStyle(.tint).accessibilityLabel(Text("square.verified")) }
                    if post.memberLevel > 0 { Text("square.xcx.level \(post.memberLevel)").font(.caption2.bold()) }
                    if let badge = post.authorBadge { Text(verbatim: badge).font(.caption2) }
                    if let badge = post.noticeBadge { Text(verbatim: badge).font(.caption2.bold()) }
                }
                HStack(spacing: 4) {
                    if let club = post.clubName { Text(verbatim: club); Text(verbatim: "·") }
                    SquareXcxRelativeTime(createTime: post.createTime, now: now)
                }.font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    @ViewBuilder private var playCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            if post.isTopicTemplate { Text("square.xcx.templateBadge").font(.caption2.bold()).accessibilityIdentifier("square.card.templateBadge") }
            if let title = post.referenceTitle { Text(verbatim: title).font(.subheadline.bold()) }
            else if facts.isCompletionShare { Text("square.xcx.completionFallback").font(.subheadline.bold()) }
            switch facts.playSubtitle {
            case .completedNodes(let total)?: Text("square.xcx.play.completedNodes \(total)").font(.caption)
            case .progress(let done, let total)?: Text("square.xcx.play.progress \(done) \(total)").font(.caption)
            case .completed?: Text("square.xcx.play.completed").font(.caption)
            case .inProgress?: Text("square.xcx.play.inProgress").font(.caption)
            case nil: EmptyView()
            }
            if showsMedia, let cover = facts.playCover {
                NativeMediaGalleryEntry(sources: [cover], scope: mediaScope, titleKey: "media.destination.squareImages", compact: true)
            }
        }.padding(10).background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.1)))
            .accessibilityElement(children: .contain).accessibilityIdentifier("square.card.play")
    }
    private var counters: some View {
        HStack(spacing: 18) {
            Label { Text(verbatim: String(max(0, post.likeCount))) } icon: { Image(systemName: post.isLiked == 1 ? "heart.fill" : "heart") }
                .accessibilityLabel(Text("square.xcx.likesA11y \(max(0, post.likeCount))"))
            Label { Text(verbatim: String(max(0, post.commentCount))) } icon: { Image(systemName: "bubble.right") }
                .accessibilityLabel(Text("square.xcx.commentsA11y \(max(0, post.commentCount))"))
        }.font(.caption).foregroundStyle(.secondary)
    }
}

struct SquareXcxRelativeTime: View {
    let createTime: String
    let now: Date
    var body: some View {
        switch SquareRelativeAge.of(createTime, now: now) {
        case .justNow?: Text("square.xcx.justNow")
        case .days(let days)?: Text("square.xcx.ageDays \(days)")
        case .hoursMinutes(let hours, let minutes)?:
            if hours > 0 && minutes > 0 { Text("square.xcx.ageHoursMinutes \(hours) \(minutes)") }
            else if hours > 0 { Text("square.xcx.ageHours \(hours)") }
            else { Text("square.xcx.ageMinutes \(minutes)") }
        case nil:
            // Unparseable source time is shown verbatim rather than guessed.
            if !createTime.isEmpty { Text(verbatim: createTime) }
        }
    }
}

/// Source list header strip: official events starting within 24 hours. Read-only; opening uses the host's destination.
@MainActor struct SquareXcxUpcomingStrip: View {
    let reader: any OfficialEventReading
    var destination: ((Int) -> AnyView)? = nil
    @State private var items: [SquareUpcomingBannerItem] = []
    @State private var loadedScope: UUID?
    var body: some View {
        Group {
            if !items.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(items) { item in
                            if let destination {
                                NavigationLink { destination(item.id) } label: { card(item) }.buttonStyle(.plain)
                                    .accessibilityIdentifier("square.upcoming.\(item.id)")
                            } else { card(item).accessibilityIdentifier("square.upcoming.\(item.id)") }
                        }
                    }
                }.accessibilityIdentifier("square.upcoming")
            }
        }
        .task(id: reader.scope) { await load() }
    }
    private func card(_ item: SquareUpcomingBannerItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("square.xcx.upcoming.kicker").font(.caption.bold())
                switch item.countdown(now: Date()) {
                case .days(let n): Text("square.xcx.upcoming.days \(n)").font(.caption)
                case .hours(let n): Text("square.xcx.upcoming.hours \(n)").font(.caption)
                case .minutes(let n): Text("square.xcx.upcoming.minutes \(n)").font(.caption)
                case .soon: Text("square.xcx.upcoming.soon").font(.caption)
                }
            }
            Text(verbatim: item.title).font(.headline).lineLimit(1)
            if let subtitle = item.subtitle { Text(verbatim: subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            HStack(spacing: 4) {
                ForEach(Array(item.avatars.enumerated()), id: \.offset) { _, _ in Image(systemName: "person.circle.fill").accessibilityHidden(true) }
                if item.overflow > 0 { Text("square.xcx.upcoming.overflow \(item.overflow)").font(.caption2) }
                Text("square.xcx.upcoming.participants").font(.caption2).foregroundStyle(.secondary)
            }
        }.padding(12).frame(minWidth: 260, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.secondary.opacity(0.12)))
    }
    private func load() async {
        let scope = reader.scope
        guard reader.isConfigured, loadedScope != scope else { return }
        do {
            let events = try await reader.events(city: nil)
            try Task.checkCancellation()
            guard scope == reader.scope else { return }
            items = SquareUpcomingBannerItem.select(events, now: Date()); loadedScope = scope
        } catch {
            // Source hides the strip on any failure; the feed itself is unaffected.
            guard scope == reader.scope else { return }
            items = []
        }
    }
}
