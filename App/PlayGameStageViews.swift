import SwiftUI

private struct PlayGameStageKey: EnvironmentKey { static let defaultValue: PlayGameStage? = nil }

extension EnvironmentValues {
    /// The station a game is played at. Hosts that know the route set it; a game
    /// opened without it simply shows no story header.
    var playGameStage: PlayGameStage? {
        get { self[PlayGameStageKey.self] }
        set { self[PlayGameStageKey.self] = newValue }
    }
}

/// 「第N站」 (route-wide, the station list's number) with the chapter as its own small label,
/// then — on the start screen — the station image and the game title written once, then the
/// station's lead line in the chapter story's typography. Everything is synchronous text from the
/// current route read, so it is present on the first frame and never shifts the game below.
@MainActor struct PlayGameStageHeader: View {
    let stage: PlayGameStage
    /// The start screen draws the hero image and the title; a game screen has its own title.
    var showsTitle = false
    var showsArtwork = false
    var loadsArtwork = true
    /// The title the page already shows, so the station line never repeats it.
    var pageTitle: String? = nil
    private var title: String? { showsTitle ? stage.title : nil }
    private var stationLabel: String? { stage.stationLabel(besides: title ?? PlayGameStage.displayTitle(pageTitle)) }
    var body: some View {
        if !stage.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                if showsArtwork, let image = stage.image {
                    PlayStationArtwork(image: image, loads: loadsArtwork).accessibilityIdentifier("playGame.stage.image")
                }
                if stage.ordinal != nil || stationLabel != nil || stage.chapterTitle != nil {
                    VStack(alignment: .leading, spacing: 2) {
                        if let ordinal = stage.ordinal {
                            Text("playGame.stage.stationNumber \(ordinal)").font(.subheadline.weight(.semibold)).foregroundStyle(.tint)
                        } else if let stationLabel {
                            Text(verbatim: stationLabel).font(.subheadline.weight(.semibold)).foregroundStyle(.tint)
                        }
                        if let chapter = stage.chapterTitle {
                            Text(verbatim: chapter).font(.footnote).foregroundStyle(.secondary)
                                .accessibilityIdentifier("playGame.stage.chapter")
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(title == nil ? .isHeader : [])
                    .accessibilityIdentifier("playGame.stage.station")
                }
                if let title {
                    Text(verbatim: title).font(.title2.bold())
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("playGame.stage.title")
                }
                if let lead = stage.lead, lead != title {
                    Text(verbatim: lead).font(.body).lineSpacing(8)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("playGame.stage.lead")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("playGame.stage.header")
        }
    }
}

/// One primary action style for every game: the system prominent button at the
/// large control size. Native press feedback only; no second animation is added.
struct PlayGamePrimaryButton: ViewModifier {
    func body(content: Content) -> some View {
        content.buttonStyle(.borderedProminent).controlSize(.large)
    }
}

extension View {
    func playGamePrimaryButton() -> some View { modifier(PlayGamePrimaryButton()) }
}

/// The finished game, told in the story's voice. The server's verdict decides the
/// line; this view only words it, and fades in with the shared content token
/// (or appears at once under Reduce Motion).
@MainActor struct PlayGameResultLine: View {
    let outcome: PlayGameOutcome
    /// The game still accepts another attempt.
    var open = false
    var body: some View {
        Label {
            Text(LocalizedStringKey(outcome.key(open: open))).font(.body).lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol).foregroundStyle(outcome == .passed ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        }
        .accessibilityIdentifier("playkit.result.story")
    }
    private var symbol: String {
        switch outcome {
        case .passed: return "checkmark.circle.fill"
        case .notPassed: return "arrow.uturn.backward.circle"
        case .recorded: return "bookmark.circle"
        case .noVerdict: return "ellipsis.circle"
        }
    }
}

/// The game area keeps a stable minimum height while an image is on its way, so
/// arriving artwork never pushes the controls around.
@MainActor struct PlayGameImagePlaceholder: View {
    let titleKey: LocalizedStringKey
    var systemImage = "photo"
    var loading = false
    var body: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.quaternary)
            .aspectRatio(4.0 / 3.0, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay {
                VStack(spacing: 8) {
                    if loading { ProgressView() } else { Image(systemName: systemImage).font(.title).foregroundStyle(.secondary) }
                    Text(titleKey).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.padding()
            }
            .accessibilityElement(children: .combine)
    }
}
