import SwiftUI

/// Only mounted after the existing Photos writer has confirmed this exact card.
/// No clipboard assignment, external-app launch or upload is performed here.
struct RoamShareAlbumGuideView: View {
    let guide: RoamShareAlbumGuideState.Guide
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Label("roam.albumGuide.saved", systemImage: "checkmark.circle")
                        .font(.headline).accessibilityIdentifier("roam.albumGuide.saved")
                    Text(LocalizedStringKey(guide.destination == .moments ? "roam.albumGuide.momentsSteps" : "roam.albumGuide.xiaohongshuSteps"))
                    Text("roam.albumGuide.notPosted").foregroundStyle(.secondary)
                        .accessibilityIdentifier("roam.albumGuide.notPosted")
                    Text("roam.albumGuide.copyTitle").font(.headline)
                    Text(verbatim: RoamShareAlbumGuideCopy.text(guide.copy, locale: locale))
                        .textSelection(.enabled)
                        .accessibilityIdentifier("roam.albumGuide.copy")
                    Text("roam.albumGuide.copyHint").font(.caption).foregroundStyle(.secondary)
                }.padding()
            }.navigationTitle(LocalizedStringKey(guide.destination == .moments ? "roam.albumGuide.moments" : "roam.albumGuide.xiaohongshu"))
                .toolbar { ToolbarItem(placement: .confirmationAction) {
                    Button("action.done") { dismiss() }.accessibilityIdentifier("roam.albumGuide.done")
                } }
        }
    }
}

enum RoamShareAlbumGuideCopy {
    static func text(_ copy: RoamShareAlbumGuideState.Copy, locale: Locale) -> String {
        var parts: [String] = []
        if let date = copy.recordedAt { parts.append(date.formatted(.dateTime.year().month().day().locale(locale))) }
        if let shops = copy.shops {
            parts.append(String(localized: "roam.experience.shops", locale: locale) + ": " + shops.formatted(.number.locale(locale)))
        }
        if let distance = copy.kilometers {
            parts.append(distance.formatted(.number.precision(.fractionLength(0...1)).locale(locale)) + " km")
        }
        if let exploration = copy.explorationPercent {
            parts.append(String(localized: "roam.albumGuide.exploration", locale: locale) + ": " + exploration.formatted(.number.locale(locale)) + "%")
        }
        parts.append("#城瘾CityFog")
        return parts.joined(separator: " · ")
    }
}
