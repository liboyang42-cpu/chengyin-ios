import SwiftUI

/// Mini-program `pages/topic/index` sections layered onto the existing topic detail list.
enum TopicXcxTab: Int, CaseIterable, Identifiable {
    case details, nodes, route
    var id: Int { rawValue }
    var titleKey: LocalizedStringKey { switch self { case .details: return "topicXcx.tab.details"; case .nodes: return "topicXcx.tab.nodes"; case .route: return "topicXcx.tab.route" } }
    var anchor: String { "topicXcx.anchor.\(rawValue)" }
}

/// Source in-page tabs; here they scroll to the matching section so every existing row stays reachable.
struct TopicXcxTabs: View {
    let proxy: ScrollViewProxy
    @State private var selection: TopicXcxTab = .details
    var body: some View {
        Picker("topicXcx.tabs", selection: $selection) {
            ForEach(TopicXcxTab.allCases) { tab in Text(tab.titleKey).tag(tab) }
        }.pickerStyle(.segmented).accessibilityIdentifier("topic.tabs")
            .onChange(of: selection) { _, tab in withAnimation { proxy.scrollTo(tab.anchor, anchor: .top) } }
    }
}

struct TopicXcxHero: View {
    let topic: TopicDetail
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(topic.productType == 2 ? "topicXcx.type.explore" : "topicXcx.type.orienteering").font(.caption.bold()).foregroundStyle(.secondary)
            if !topic.categoryNames.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack { ForEach(topic.categoryNames, id: \.self) { Text(verbatim: $0).font(.caption).padding(.horizontal, 8).padding(.vertical, 3).background(Capsule().fill(Color.secondary.opacity(0.15))) } }
                }
            }
            if let club = topic.clubName { Label { Text("topicXcx.clubHost \(club)") } icon: { Image(systemName: "person.3") }.font(.subheadline) }
        }
    }
}

struct TopicXcxStatBar: View {
    let cells: [TopicXcxFacts.StatCell]
    var body: some View {
        if !cells.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                        VStack(alignment: .leading, spacing: 2) {
                            switch cell {
                            case .rating(let value, let stars):
                                Text("topicXcx.stat.rating").font(.caption2).foregroundStyle(.secondary)
                                Text(verbatim: String(format: "%.1f", value)).font(.headline)
                                HStack(spacing: 1) { ForEach(0..<stars, id: \.self) { _ in Image(systemName: "star.fill").font(.caption2) } }.accessibilityHidden(true)
                            case .hours(let text):
                                Text("topicXcx.stat.hours").font(.caption2).foregroundStyle(.secondary)
                                Text(verbatim: text).font(.headline); Text("topicXcx.stat.hoursUnit").font(.caption2)
                            case .open(let start, let end):
                                Text("topicXcx.stat.open").font(.caption2).foregroundStyle(.secondary)
                                Text(verbatim: start + "-" + end).font(.headline)
                            case .mileage(let text):
                                Text("topicXcx.stat.mileage").font(.caption2).foregroundStyle(.secondary)
                                Text(verbatim: text).font(.headline); Text("topicXcx.stat.mileageUnit").font(.caption2)
                            case .merchants(let count):
                                Text("topicXcx.stat.merchants").font(.caption2).foregroundStyle(.secondary)
                                Text(verbatim: String(count)).font(.headline); Text("topicXcx.stat.merchantsUnit").font(.caption2)
                            }
                        }.accessibilityElement(children: .combine)
                    }
                }
            }.accessibilityIdentifier("topic.statBar")
        }
    }
}

struct TopicXcxDurationText: View {
    let seconds: Int?
    var body: some View {
        switch TopicXcxFacts.duration(seconds: seconds) {
        case .zero: Text("topicXcx.duration.zero")
        case .underMinute: Text("topicXcx.duration.underMinute")
        case .minutes(let m): Text("topicXcx.duration.minutes \(m)")
        case .hours(let h): Text("topicXcx.duration.hours \(h)")
        case .hoursMinutes(let h, let m): Text("topicXcx.duration.hoursMinutes \(h) \(m)")
        }
    }
}

struct TopicXcxIncludes: View {
    let rows: [TopicXcxFacts.Include]
    var body: some View {
        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
            switch row {
            case .chapters(let n): Label { Text("topicXcx.include.chapters \(n)") } icon: { Image(systemName: "book") }
            case .stops(let n): Label { Text("topicXcx.include.stops \(n)") } icon: { Image(systemName: "mappin.and.ellipse") }
            case .plays(let n): Label { Text("topicXcx.include.plays \(n)") } icon: { Image(systemName: "gamecontroller") }
            case .audioMinutes(let n): Label { Text("topicXcx.include.audioMinutes \(n)") } icon: { Image(systemName: "headphones") }
            case .audio: Label("topicXcx.include.audio", systemImage: "headphones")
            case .medal(let name?): Label { Text("topicXcx.include.medal \(name)") } icon: { Image(systemName: "medal") }
            case .medal(nil): Label("topicXcx.include.medalFallback", systemImage: "medal")
            case .coupon: Label("topicXcx.include.coupon", systemImage: "ticket")
            }
        }
    }
}

struct TopicXcxLineup: View {
    let members: [TopicXcxFacts.LineupMember]
    var body: some View {
        ForEach(Array(members.enumerated()), id: \.offset) { _, member in
            LabeledContent {
                Text(member.kind == .club ? "topicXcx.lineup.club" : "topicXcx.lineup.merchant").foregroundStyle(.secondary)
            } label: { Text(verbatim: member.name) }
        }
    }
}

/// Source bottom bar. Purchase/sign-up keep their existing flows; nothing here dispatches a write.
struct TopicXcxActionBar: View {
    let topic: TopicDetail
    var openSessions: () -> Void
    var openSelfPlay: () -> Void
    var openPricing: (() -> Void)?
    var body: some View {
        VStack(spacing: 6) {
            if topic.merchantClosed && !topic.isSignUp { Text("topicXcx.merchantClosed").font(.footnote).foregroundStyle(.orange) }
            HStack {
                switch TopicXcxFacts.action(topic) {
                case .ticketWallet:
                    Label("topicXcx.cta.ticketWallet", systemImage: "ticket").frame(maxWidth: .infinity)
                case .locked(let lifecycle):
                    if TopicXcxFacts.opensPricing(topic), let openPricing {
                        Button(action: openPricing) { Text("topicXcx.cta.confirmPrice").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("topic.cta.pricing")
                    } else {
                        Text(LocalizedStringKey("topicXcx.cta.locked." + String(lifecycle))).frame(maxWidth: .infinity).foregroundStyle(.secondary)
                    }
                case .selfPlay(let price):
                    Button(action: openSessions) { Text("topicXcx.cta.sessions").frame(maxWidth: .infinity) }.buttonStyle(.bordered)
                    Button(action: openSelfPlay) {
                        if let price { Text("topicXcx.cta.selfPlay \(NSDecimalNumber(decimal: price).stringValue)").frame(maxWidth: .infinity) }
                        else { Text("topicXcx.cta.selfPlayNoPrice").frame(maxWidth: .infinity) }
                    }.buttonStyle(.borderedProminent).disabled(!topic.canOfferPurchase)
                case .signUp:
                    Button(action: openSessions) { Text("topicXcx.cta.signUp").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent)
                        .disabled(topic.merchantClosed)
                }
            }.accessibilityIdentifier("topic.actionBar")
        }.padding(.horizontal).padding(.vertical, 8).background(.bar)
    }
}

private struct TopicPricingDestinationKey: EnvironmentKey { static let defaultValue: ((Int) -> AnyView)? = nil }
extension EnvironmentValues {
    /// Owner-only final-price page (source `pages/topic/pricing`); nil hides the entry.
    var topicPricingDestination: ((Int) -> AnyView)? {
        get { self[TopicPricingDestinationKey.self] }
        set { self[TopicPricingDestinationKey.self] = newValue }
    }
}

/// Source tab "路线": every stop in order with its walking estimate.
struct TopicXcxRouteSection: View {
    let topic: TopicDetail
    var body: some View {
        Section("topicXcx.tab.route") {
            if topic.chapters.allSatisfy({ $0.nodes.isEmpty }) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("topicXcx.route.emptyTitle").font(.headline)
                    Text("topicXcx.route.emptyDetail").font(.footnote).foregroundStyle(.secondary)
                }.accessibilityIdentifier("topic.route.empty")
            }
            ForEach(Array(topic.chapters.enumerated()), id: \.offset) { _, chapter in
                if !chapter.nodes.isEmpty { Text(verbatim: chapter.title).font(.subheadline.bold()) }
                ForEach(TopicChapterItinerary(chapter: chapter).stops) { stop in
                    VStack(alignment: .leading, spacing: 2) {
                        if let minutes = stop.estimatedWalkingMinutes { Text("topicXcx.route.walk \(minutes)").font(.caption2).foregroundStyle(.secondary) }
                        HStack(alignment: .top) {
                            Text(verbatim: String(stop.id + 1)).font(.caption.bold()).frame(width: 22, height: 22).background(Circle().fill(Color.secondary.opacity(0.2)))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: stop.node.name)
                                if let hours = stop.node.businessTime { Text(verbatim: hours).font(.caption) }
                                if let address = stop.node.address { Label { Text(verbatim: address).lineLimit(1) } icon: { Image(systemName: "mappin") }.font(.caption) }
                            }
                        }
                    }
                }
            }
        }
    }
}
