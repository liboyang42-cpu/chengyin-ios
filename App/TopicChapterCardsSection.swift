import SwiftUI

/// Route detail "节点介绍": a horizontal row of chapter cards (owner request 2026-11-19).
/// Tapping a card discloses its description in place; tapping again collapses it, and only one
/// card is open at a time. Ending chapters are already excluded by `TopicChapterCards`.
struct TopicChapterCardsSection: View {
    let cards: [TopicChapterCard]
    @State private var openID: Int?
    @QuestifyReduceMotion private var reduceMotion

    var body: some View {
        if !cards.isEmpty {
            Section("topic.chapterCards") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(cards) { card in
                            TopicChapterCardView(card: card, isOpen: openID == card.id) { toggle(card.id) }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .accessibilityIdentifier("topic.chapterCards")
            }
        }
    }

    private func toggle(_ id: Int) {
        let next = TopicChapterCards.toggle(open: openID, tapped: id)
        guard !reduceMotion else { openID = next; return }
        let animation = next == nil
            ? QuestifyMotionToken.curve(QuestifyMotionToken.easeAccelerate, QuestifyMotionToken.collapse)
            : QuestifyMotionToken.curve(QuestifyMotionToken.easeEmphasizedDecelerate, QuestifyMotionToken.expand)
        withAnimation(animation) { openID = next }
    }
}

struct TopicChapterCardView: View {
    let card: TopicChapterCard
    let isOpen: Bool
    let toggle: () -> Void
    private static let width: CGFloat = 150

    var body: some View {
        Button(action: toggle) {
            VStack(alignment: .leading, spacing: 6) {
                TopicChapterCardImage(source: card.imageSource)
                    .frame(width: Self.width, height: Self.width * 0.74)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                Text(verbatim: card.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if let metaText { metaText.font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                if isOpen, let description = card.description {
                    Text(verbatim: description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .frame(width: Self.width, alignment: .leading)
        }
        .buttonStyle(QuestifyCardButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(isOpen ? "topic.chapterCard.expanded" : "topic.chapterCard.collapsed"))
        .accessibilityIdentifier("topic.chapterCard.\(card.id)")
    }

    /// 含 N 个玩法 · 约 M 分钟; a missing part is left out, never written as zero.
    private var metaText: Text? {
        let games = card.gameCount.map { Text("topic.chapterCard.games \($0)") }
        let minutes = card.minutes.map { Text("topic.chapterCard.minutes \($0)") }
        switch (games, minutes) {
        case let (g?, m?): return g + Text(verbatim: " · ") + m
        case let (g?, nil): return g
        case let (nil, m?): return m
        default: return nil
        }
    }
}

/// Fixed-size picture with a placeholder tone. Only absolute https sources load; object keys
/// stay on the tone because no storage host or signed URL is invented here.
struct TopicChapterCardImage: View {
    let source: String?

    var body: some View {
        ZStack {
            Rectangle().fill(Color(.secondarySystemFill))
            if let url {
                AsyncImage(url: url) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() }
                }
            }
        }
        .accessibilityHidden(true)
    }

    private var url: URL? {
        guard let source, let url = URL(string: source), url.scheme == "https", url.host != nil,
              url.user == nil, url.password == nil else { return nil }
        return url
    }
}
