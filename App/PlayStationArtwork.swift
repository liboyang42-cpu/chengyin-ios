import SwiftUI

/// Station / station-game picture from `PlayStationImageResolver`. Fixed aspect ratio, fill
/// cropping and a dark textured surface behind the image while it loads, when it fails, or when
/// the chain has no image at all; no person placeholder, no empty area and no layout shift.
struct PlayStationArtwork: View {
    let image: PlayStationImage
    var aspectRatio: CGFloat = 16.0 / 9.0
    var cornerRadius: CGFloat = 14
    /// False keeps the texture only (e.g. a stale play snapshot that must not start new loads).
    var loads: Bool = true
    @QuestifyReduceMotion private var reduceMotion

    private var url: URL? {
        guard loads, let source = image.source else { return nil }
        return QuestifyCardArtwork.safeURL(PlayStationImageResolver.secured(source))
    }

    var body: some View {
        PlayStationTexture()
            .aspectRatio(aspectRatio, contentMode: .fit)
            .overlay {
                if let url {
                    AsyncImage(url: url, transaction: Transaction(animation: reduceMotion ? nil : QuestifyMotion.content)) { phase in
                        if let picture = phase.image {
                            picture.resizable().scaledToFill().transition(.opacity)
                        } else { Color.clear }
                    }
                }
            }
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// The chain's last tier: the same dark surface `QuestifyImageEntityCard` uses, with a soft light falloff.
struct PlayStationTexture: View {
    var body: some View {
        ZStack {
            Color(red: 0.16, green: 0.17, blue: 0.20)
            RadialGradient(colors: [.white.opacity(0.08), .clear], center: .topLeading, startRadius: 0, endRadius: 320)
            LinearGradient(colors: [.clear, .black.opacity(0.35)], startPoint: .top, endPoint: .bottom)
        }
        .accessibilityHidden(true)
    }
}
