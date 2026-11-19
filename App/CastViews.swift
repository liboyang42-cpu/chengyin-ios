import SwiftUI
import UIKit

/// Cast contract (hengyin docs/design/cast-contract-1119.md). Chapter text stays a
/// book-style reading column: no bubbles, no avatars in the text, no 「某某：」 prefix.
private struct QuestifyCastKey: EnvironmentKey { static let defaultValue: CastStoryContext? = nil }
extension EnvironmentValues {
    /// Nil whenever the theme has no enabled cast; every cast surface then stays hidden.
    var questifyCast: CastStoryContext? {
        get { self[QuestifyCastKey.self] }
        set { self[QuestifyCastKey.self] = newValue }
    }
}

extension Color {
    /// Only the six palette colours reach here (`CastMember.color` is validated in Core).
    init(castHex hex: String) {
        let value = UInt32(hex.dropFirst(), radix: 16) ?? 0x8E8E93
        self.init(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }
}

/// Coloured initial, or the author's avatar through the existing gated public-image reader.
@MainActor struct CastAvatar: View {
    let member: CastMember
    var size: CGFloat = 54
    var reader: (any RetainedPublicImageReading)? = nil
    @State private var image: UIImage?
    var body: some View {
        ZStack {
            Circle().fill(Color(castHex: member.color))
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            else { Text(verbatim: member.initial).font(.system(size: size * 0.42, weight: .semibold)).foregroundStyle(.white) }
        }
        .frame(width: size, height: size).clipShape(Circle())
        .accessibilityHidden(true)
        .task(id: member.avatarURL) {
            image = nil
            guard let reader, reader.enabled, let raw = member.avatarURL, raw.hasPrefix("https://"), let url = URL(string: raw) else { return }
            if let bytes = try? await reader.image(url: url), let clean = try? RetainedImageSanitizer.sanitize(bytes), !Task.isCancelled {
                image = UIImage(data: clean.jpeg)
            }
        }
    }
}

/// Five ticks filled by trust, in the cast colour only.
struct CastTrustTicks: View {
    let trust: Int
    let color: String
    var body: some View {
        let filled = CastTrust.filledTicks(trust)
        HStack(spacing: 4) {
            ForEach(0..<CastTrust.tickCount, id: \.self) { index in
                Capsule().fill(index < filled ? AnyShapeStyle(Color(castHex: color)) : AnyShapeStyle(.quaternary))
                    .frame(width: 14, height: 4)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("cast.trust.accessibility \(filled) \(CastTrust.tickCount)"))
    }
}

/// One reading-column paragraph. The speaker name sits small and faint in the leading
/// margin, level with the first line. Tapping a cast name opens the character card.
struct ChapterStoryLineView: View {
    let name: String?
    let text: String
    let margin: CGFloat
    var italic = false
    var onTapName: (() -> Void)? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Group {
                if let name {
                    if let onTapName {
                        Button(action: onTapName) { marginName(name) }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text("cast.card.open \(name)"))
                            .accessibilityIdentifier("cast.marginName")
                    } else { marginName(name) }
                }
            }
            .frame(width: margin, alignment: .leading)
            Text(verbatim: text).font(.body).lineSpacing(8).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
    private func marginName(_ name: String) -> some View {
        Text(verbatim: name).font(.caption2).foregroundStyle(.tertiary)
            .lineLimit(2).minimumScaleFactor(0.8).padding(.trailing, 6)
            .contentShape(Rectangle())
    }
}

/// Plays one line's voice: the author's https recording, else the lazily requested TTS.
/// Hidden when nothing is configured or the server says TTS is unavailable. No error toast.
@MainActor struct CastVoiceButton: View {
    let line: ChapterStoryLine
    let member: CastMember?
    let chapterID: Int
    @Bindable var model: PlayExperienceCoordinator
    let mediaScope: UUID
    let makeAudio: (@MainActor () -> PlatformAudioPlayback)?
    var compact = false
    @State private var audio: PlatformAudioPlayback?
    @State private var unavailable = false
    @State private var loading = false
    private var recording: String? { line.audioURL.flatMap { $0.hasPrefix("https://") ? $0 : nil } }
    private var possible: Bool {
        guard makeAudio != nil, !unavailable else { return false }
        if recording != nil { return true }
        // A `media-asset:N` recording or a preset voice is resolved by the voice endpoint.
        return line.blockKey != nil && (line.audioURL != nil || member?.hasPresetVoice == true)
    }
    var body: some View {
        if possible {
            Button { Task { await play() } } label: {
                if compact { Label("cast.voice.play", systemImage: "play.fill").labelStyle(.iconOnly).font(.caption) }
                else if audio?.state == .playing { Label("cast.voice.pause", systemImage: "pause.fill") }
                else { Label("cast.voice.play", systemImage: "play.fill") }
            }
            .foregroundStyle(compact ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.tint))
            .disabled(loading)
            .accessibilityLabel(Text("cast.voice.play"))
            .accessibilityIdentifier(compact ? "cast.voice.inline" : "cast.voice.card")
            .onDisappear { audio?.dispose(); audio = nil }
        }
    }
    private func play() async {
        if let audio, audio.state == .playing || audio.state == .paused { audio.toggle(); return }
        loading = true
        defer { loading = false }
        var url = recording
        if url == nil, let key = line.blockKey { url = await model.castVoiceURL(chapterID: chapterID, blockKey: key) }
        guard let url, let source = URL(string: url), let makeAudio else { unavailable = true; return }
        let player = audio ?? makeAudio()
        audio = player
        player.select(PlatformMediaSource(url: source, scope: mediaScope))
        // A gated origin stays silent rather than showing an error for a decorative voice.
        guard player.state != .gated else { unavailable = true; return }
        player.approveSelectedMedia(); player.toggle()
    }
}

/// E4 character card: a medium-detent sheet.
@MainActor struct CastCharacterCard: View {
    let member: CastMember
    let trust: Int
    let reachedChapters: Set<Int>
    let line: ChapterStoryLine?
    let chapterID: Int
    @Bindable var model: PlayExperienceCoordinator
    let mediaScope: UUID
    let makeAudio: (@MainActor () -> PlatformAudioPlayback)?
    var imageReader: (any RetainedPublicImageReading)? = nil
    var body: some View {
        let known = member.knownClues(reachedChapters: reachedChapters)
        let remaining = member.remainingClueCount(reachedChapters: reachedChapters)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 14) {
                    CastAvatar(member: member, size: 56, reader: imageReader)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: member.name).font(.title3.weight(.semibold)).accessibilityAddTraits(.isHeader)
                        if let identity = member.identity { Text(verbatim: identity).font(.subheadline).foregroundStyle(.secondary) }
                    }
                    Spacer(minLength: 0)
                }
                if let line { CastVoiceButton(line: line, member: member, chapterID: chapterID, model: model, mediaScope: mediaScope, makeAudio: makeAudio) }
                VStack(alignment: .leading, spacing: 8) {
                    Text("cast.card.trust").font(.footnote).foregroundStyle(.secondary)
                    CastTrustTicks(trust: trust, color: member.color)
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("cast.card.clues").font(.footnote).foregroundStyle(.secondary)
                    ForEach(Array(known.enumerated()), id: \.offset) { _, clue in
                        Text(verbatim: clue.text).font(.body)
                        Divider()
                    }
                    if remaining > 0 { Text("cast.card.locked \(remaining)").font(.footnote).foregroundStyle(.tertiary) }
                    else if known.isEmpty { Text("cast.card.noClues").font(.footnote).foregroundStyle(.tertiary) }
                }
            }
            .padding(24)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("cast.card")
    }
}

/// Spec C start step: one question per screen, full-screen and dark.
@MainActor struct CastStartView: View {
    let config: CastConfig
    var suggestedName = ""
    let finish: (_ name: String, _ identityKey: String?) -> Void
    @QuestifyReduceMotion private var reduceMotion
    @State private var name = ""
    @State private var askingIdentity = false
    @State private var identityKey: String?
    @FocusState private var nameFocused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Spacer()
            if askingIdentity || !config.playerName { identityStep.transition(.opacity) }
            else { nameStep.transition(.opacity) }
            Spacer()
        }
        .padding(28)
        .frame(maxWidth: 560).frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .animation(reduceMotion ? nil : QuestifyMotion.content, value: askingIdentity)
        .onAppear { if name.isEmpty { name = suggestedName } }
        .accessibilityIdentifier("cast.start")
    }
    private var nameStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("cast.start.nameQuestion").font(.largeTitle.bold()).foregroundStyle(.primary).accessibilityAddTraits(.isHeader)
            TextField("cast.start.namePlaceholder", text: $name)
                .font(.title.weight(.medium)).textInputAutocapitalization(.never).autocorrectionDisabled()
                .submitLabel(.go).focused($nameFocused).onSubmit(advance)
                .onChange(of: name) { _, next in if next.count > 12 { name = String(next.prefix(12)) } }
                .accessibilityIdentifier("cast.start.name")
            Divider()
            Button(action: advance) { Text("cast.start.go").frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .accessibilityIdentifier("cast.start.go")
        }
    }
    private var identityStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("cast.start.identityQuestion").font(.title.bold()).accessibilityAddTraits(.isHeader)
            ForEach(config.identities) { identity in
                Button { identityKey = identity.key } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: identity.title).font(.headline)
                        if let sub = identity.sub { Text(verbatim: sub).font(.subheadline).foregroundStyle(.secondary) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(identityKey == identity.key ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary), lineWidth: identityKey == identity.key ? 2 : 1))
                }
                .buttonStyle(QuestifyCardButtonStyle())
                .accessibilityAddTraits(identityKey == identity.key ? .isSelected : [])
                .accessibilityIdentifier("cast.start.identity." + identity.key)
            }
            Button { finish(name, identityKey) } label: { Text("cast.start.go").frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent).controlSize(.large).disabled(identityKey == nil)
                .accessibilityIdentifier("cast.start.confirmIdentity")
        }
    }
    private func advance() {
        if config.asksIdentity { askingIdentity = true; nameFocused = false }
        else { finish(name, nil) }
    }
}

/// E1 登场人物 playbill: shown once before chapter 1 and reopened as 「人物表」.
@MainActor struct CastPlaybillView: View {
    let config: CastConfig
    let profile: CastPlayerProfile?
    var routeName: String? = nil
    let start: () -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let routeName { Text(verbatim: routeName).font(.footnote).foregroundStyle(.secondary).tracking(1.5) }
                Text("cast.playbill.title").font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(config.cast) { member in row(name: member.name, identity: member.identity) }
                    Divider()
                    playerRow
                }.padding(.top, 8)
                Button(action: start) { Text("cast.playbill.start").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).controlSize(.large).padding(.top, 12)
                    .accessibilityIdentifier("cast.playbill.start")
            }
            .padding(28).frame(maxWidth: 560).frame(maxWidth: .infinity)
        }
        .background(Color.black.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .accessibilityIdentifier("cast.playbill")
    }
    @ViewBuilder private var playerRow: some View {
        let identity = config.identity(profile?.identityKey)?.title
        if let name = profile?.name { row(name: name, identity: identity) }
        else {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("cast.player.you").font(.body.weight(.semibold))
                leader
                if let identity { Text(verbatim: identity).foregroundStyle(.secondary) }
            }
        }
    }
    private func row(name: String, identity: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(verbatim: name).font(.body.weight(.semibold))
            leader
            if let identity { Text(verbatim: identity).foregroundStyle(.secondary).multilineTextAlignment(.trailing) }
        }
        .accessibilityElement(children: .combine)
    }
    /// Dotted leader between the name and the identity.
    private var leader: some View {
        Line().stroke(style: StrokeStyle(lineWidth: 1, dash: [1, 4])).foregroundStyle(.tertiary)
            .frame(minWidth: 16, maxWidth: .infinity, minHeight: 1, maxHeight: 1).accessibilityHidden(true)
    }
    private struct Line: Shape {
        func path(in rect: CGRect) -> Path { Path { $0.move(to: CGPoint(x: 0, y: rect.midY)); $0.addLine(to: CGPoint(x: rect.maxX, y: rect.midY)) } }
    }
}

/// E5 route detail 「人物」 row: horizontal avatars, names and the identity's first clause.
struct CastTopicRow: View {
    let config: CastConfig
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 16) {
                ForEach(config.cast) { member in
                    VStack(spacing: 6) {
                        CastAvatar(member: member, size: 54)
                        Text(verbatim: member.name).font(.footnote.weight(.semibold)).lineLimit(1)
                        if let lead = member.identityLead { Text(verbatim: lead).font(.caption2).foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.center) }
                    }
                    .frame(width: 72)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.vertical, 4)
        }
        .accessibilityIdentifier("topic.cast")
    }
}

/// E6 completion 「他们怎么看你」: book-style closing lines, names in the margin, ticks below.
struct CastEndingSection: View {
    let config: CastConfig
    let result: CastEndingResult
    var body: some View {
        let rows = result.rows(config)
        if !rows.isEmpty {
            Section("cast.ending.title") {
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 8) {
                        if let line = row.line { ChapterStoryLineView(name: row.member.name, text: line, margin: 52) }
                        else {
                            HStack(spacing: 10) {
                                CastAvatar(member: row.member, size: 28)
                                Text(verbatim: row.member.name).font(.subheadline.weight(.semibold))
                            }
                        }
                        CastTrustTicks(trust: row.trust, color: row.member.color).padding(.leading, row.line == nil ? 0 : 52)
                    }
                    .padding(.vertical, 4)
                }
                if let count = result.endingCount, let owner = config.member(result.endingFor) {
                    Text("cast.ending.footer \(count) \(owner.name)").font(.footnote).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .accessibilityIdentifier("cast.ending")
        }
    }
}
