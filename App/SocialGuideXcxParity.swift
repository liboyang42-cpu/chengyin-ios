import SwiftUI

/// Mini-program `subpackageA/pages/infomation` copy: hero line, per-mode tag and description.
extension SocialGuideMode {
    var xcxTagKey: LocalizedStringKey { switch self { case .classic: return "social.guideXcx.classicTag"; case .free: return "social.guideXcx.freeTag"; case .roam: return "social.guideXcx.roamTag" } }
    var xcxDetailKey: LocalizedStringKey { switch self { case .classic: return "social.guideXcx.classicDetail"; case .free: return "social.guideXcx.freeDetail"; case .roam: return "social.guideXcx.roamDetail" } }
}

struct SocialGuideXcxHero: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            (Text("social.guideXcx.heroLead").fontWeight(.light) + Text("social.guideXcx.heroEmphasis").bold()).font(.title2)
            Text("social.guideXcx.heroDetail").font(.subheadline).foregroundStyle(.secondary)
        }.padding(.vertical, 4).accessibilityElement(children: .combine).accessibilityIdentifier("social.guide.hero")
    }
}

/// Source mode card: icon, name, tag pill, description and the small "去看看" action.
struct SocialGuideXcxModeRow: View {
    let mode: SocialGuideMode
    var onOpen: ((SocialGuideDestination) -> Void)?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label(mode.titleKey, systemImage: mode.icon).font(.headline)
                Text(mode.xcxTagKey).font(.caption).padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Capsule().fill(Color.secondary.opacity(0.15)))
            }
            Text(mode.xcxDetailKey).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let onOpen { Button("social.guideXcx.go") { onOpen(mode.destination) }.buttonStyle(.borderedProminent).controlSize(.small).accessibilityIdentifier("social.guide.\(mode.rawValue)") }
        }.padding(.vertical, 5)
    }
}
