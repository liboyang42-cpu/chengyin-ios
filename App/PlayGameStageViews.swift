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

/// 「第N站 · 站名」 with its chapter, then the station's lead line in the same
/// typography as the chapter story. Everything is synchronous text from the current
/// route read, so it is present on the first frame and never shifts the game below.
@MainActor struct PlayGameStageHeader: View {
    let stage: PlayGameStage
    var body: some View {
        if !stage.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                if stage.ordinal != nil || stage.stationName != nil || stage.chapterTitle != nil {
                    VStack(alignment: .leading, spacing: 2) {
                        stationLine.font(.subheadline.weight(.semibold)).foregroundStyle(.tint)
                        if let chapter = stage.chapterTitle {
                            Text(verbatim: chapter).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)
                }
                if let lead = stage.lead {
                    Text(verbatim: lead).font(.body).lineSpacing(8)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("playGame.stage.lead")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("playGame.stage.header")
        }
    }
    @ViewBuilder private var stationLine: some View {
        switch (stage.ordinal, stage.stationName) {
        case let (ordinal?, name?): Text("playGame.stage.station \(ordinal) \(name)")
        case let (ordinal?, nil): Text("playGame.stage.stationNumber \(ordinal)")
        case let (nil, name?): Text(verbatim: name)
        case (nil, nil): EmptyView()
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
