import SwiftUI

// qx-u4: the three Questo polish references ported to SwiftUI with Apple-native pieces.
// 1. Onboarding pager (ref 1): round back button, segmented progress pill, Skip, big title with a
//    coloured period, an optional muted line, a pill CTA and a plain text secondary action.
// 2. Gestures (ref 2): interactive native sheets at the brief's peek/half/full heights, and a
//    floating corner widget that coasts to the nearest safe corner like iOS picture-in-picture.
// 3. Motion (ref 3): a control morphs into progress and then into a check that pulses in.
// Light/dark follows the presenting screen (player dark, merchant light); nothing here forces a scheme.
// Every animation is a transition or implicit animation and turns off under Reduce Motion.

// MARK: - Sheets

extension QuestoSheetSize {
    var detent: PresentationDetent { .fraction(CGFloat(fraction)) }
}

extension View {
    /// Native interactive sheet. The system already makes it follow the finger, dismiss on a
    /// downward swipe and rubber-band past the top detent. Heights are fixed to the brief's sizes so
    /// the sheet does not jump when its content changes, and scrolling content scrolls instead of
    /// resizing the sheet, so only the grabber and header resize it (the qx-u1 rule).
    func questoSheet(_ sizes: [QuestoSheetSize]) -> some View {
        presentationDetents(Set(sizes.map(\.detent)))
            .presentationDragIndicator(.visible)
            .presentationContentInteraction(.scrolls)
    }
}

// MARK: - Morph

enum QuestoMorphPhase: Equatable { case idle, working, done }

/// ref 3 morph for success moments that already exist: the control shares one geometry with a
/// progress capsule and then with a check, which pulses in through its transition only.
struct QuestoMorphControl<Idle: View>: View {
    let phase: QuestoMorphPhase
    @ViewBuilder var idle: () -> Idle
    @Namespace private var morph
    @QuestifyReduceMotion private var reduceMotion

    var body: some View {
        ZStack {
            switch phase {
            case .idle:
                idle()
                    .matchedGeometryEffect(id: "questo.morph", in: morph)
            case .working:
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 56, height: 34)
                    .background(.thinMaterial, in: Capsule())
                    .matchedGeometryEffect(id: "questo.morph", in: morph)
                    .accessibilityLabel(questoText("morph.working"))
            case .done:
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
                    .frame(width: 56, height: 34)
                    .matchedGeometryEffect(id: "questo.morph", in: morph)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.4).combined(with: .opacity))
                    .accessibilityLabel(questoText("morph.done"))
            }
        }
        .animation(reduceMotion ? nil : .spring(duration: 0.4, bounce: 0.3), value: phase)
    }
}

// MARK: - Onboarding pager

/// One page of the first-run pager. Text only from the screen's own copy; the hero only from
/// cards and images the screen already has.
struct QuestoOnboardingPage {
    let title: Text
    var line: Text? = nil
    let primary: Text
    let hero: AnyView
}

struct QuestoOnboardingPager: View {
    let pages: [QuestoOnboardingPage]
    @Binding var index: Int
    var onBack: (() -> Void)? = nil
    let onSkip: () -> Void
    let onPrimary: (Int) -> Void
    var secondary: Text? = nil
    var onSecondary: (() -> Void)? = nil
    @QuestifyReduceMotion private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            topBar
            TabView(selection: $index) {
                ForEach(pages.indices, id: \.self) { position in
                    pageBody(pages[position]).tag(position)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            if pages.indices.contains(index) { actions(pages[index]) }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: index)
        .background(Color(.systemBackground).ignoresSafeArea())
    }

    private var canGoBack: Bool { index > 0 || onBack != nil }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                if index > 0 { index -= 1 } else { onBack?() }
            } label: {
                Image(systemName: "chevron.backward")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .background(.thinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .opacity(canGoBack ? 1 : 0)
            .disabled(!canGoBack)
            .accessibilityLabel(questoText("onboarding.back"))
            .accessibilityIdentifier("questo.onboarding.back")
            Spacer(minLength: 0)
            QuestoProgressPill(count: pages.count, index: index)
            Spacer(minLength: 0)
            Button(action: onSkip) { questoText("onboarding.skip").font(.body) }
                .buttonStyle(.plain)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityIdentifier("questo.onboarding.skip")
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func pageBody(_ page: QuestoOnboardingPage) -> some View {
        VStack(spacing: 24) {
            Spacer(minLength: 8)
            page.hero
                .frame(maxWidth: .infinity, maxHeight: 360)
            (page.title + questoText("onboarding.period").foregroundStyle(Color.accentColor))
                .font(.largeTitle.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)
            if let line = page.line {
                line.font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
    }

    private func actions(_ page: QuestoOnboardingPage) -> some View {
        VStack(spacing: 4) {
            Button { onPrimary(index) } label: {
                page.primary
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(QuestoPillButtonStyle())
            .accessibilityIdentifier("questo.onboarding.primary")
            if let secondary, let onSecondary {
                Button(action: onSecondary) { secondary.font(.body).frame(minHeight: 44) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                    .accessibilityIdentifier("questo.onboarding.secondary")
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
    }
}

/// Segmented progress pill: the current page is a long segment, the others are dots.
struct QuestoProgressPill: View {
    let count: Int
    let index: Int
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<max(count, 0), id: \.self) { position in
                Capsule()
                    .fill(position == index ? Color.primary : Color.primary.opacity(0.25))
                    .frame(width: position == index ? 24 : 6, height: 4)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityValue(Text("playQuesto.onboarding.progress \(index + 1) \(count)", tableName: "PlayQuesto"))
    }
}

/// The reference's pill CTA: white on the dark player domain, black on the light merchant domain.
struct QuestoPillButtonStyle: ButtonStyle {
    @QuestifyReduceMotion private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color(.systemBackground))
            .background(Color.primary.opacity(isEnabled ? 1 : 0.4), in: Capsule())
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed && !reduceMotion && isEnabled ? 0.98 : 1)
            .opacity(configuration.isPressed && isEnabled ? 0.88 : 1)
            .animation(reduceMotion ? nil : (configuration.isPressed ? QuestifyMotion.press : QuestifyMotion.release), value: configuration.isPressed)
    }
}

/// ref 1 hero: one tilted, layered, glassy card stack with a soft glow, built only from images
/// the screen already has (for example a theme cover). Decorative, so hidden from VoiceOver.
struct QuestoCardStack: View {
    let imageURLs: [URL]
    @QuestifyReduceMotion private var reduceMotion
    @State private var settled = false

    var body: some View {
        let urls = Array(imageURLs.prefix(3))
        ZStack {
            ForEach(Array((0..<urls.count).reversed()), id: \.self) { depth in
                card(urls[depth])
                    .scaleEffect(1 - CGFloat(depth) * 0.07)
                    .rotationEffect(.degrees(Double(depth) * -7))
                    .offset(x: CGFloat(depth) * -20, y: CGFloat(depth) * -16)
                    .opacity(1 - Double(depth) * 0.22)
            }
        }
        .rotation3DEffect(.degrees(settled || reduceMotion ? 10 : 0), axis: (x: 1, y: -0.6, z: 0), perspective: 0.6)
        .shadow(color: Color.accentColor.opacity(0.35), radius: 36, y: 14)
        .onAppear {
            guard !settled else { return }
            withAnimation(reduceMotion ? nil : .spring(duration: 0.7, bounce: 0.2)) { settled = true }
        }
        .accessibilityHidden(true)
    }

    private func card(_ url: URL) -> some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image { image.resizable().scaledToFill() }
            else { Rectangle().fill(.thinMaterial) }
        }
        .frame(width: 210, height: 270)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
    }
}

// MARK: - Floating corner widget

/// ref 2 picture-in-picture behaviour for a floating player. Place it in an overlay that already
/// respects the safe area, the navigation bar and the tab bar; it parks in one of that area's four
/// corners. Dragging past an edge resists (×0.25) and springs back; a release coasts with momentum
/// to the nearest corner. Reduce Motion clamps to the edges and snaps without a spring.
struct QuestoCornerFloating<Content: View>: View {
    @Binding var corner: QuestoCornerSnap.Corner
    let itemSize: CGSize
    var margin: CGFloat = 16
    @ViewBuilder var content: () -> Content
    @State private var drag: CGSize = .zero
    @QuestifyReduceMotion private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let bounds = (minX: Double(margin), minY: Double(margin),
                          maxX: Double(proxy.size.width - margin), maxY: Double(proxy.size.height - margin))
            let item = (width: Double(itemSize.width), height: Double(itemSize.height))
            let rest = QuestoCornerSnap.center(of: corner, item: item, bounds: bounds)
            let x = QuestoRubberBand.clamp(rest.x + Double(drag.width),
                                           to: (bounds.minX + item.width / 2)...max(bounds.minX + item.width / 2, bounds.maxX - item.width / 2),
                                           reduceMotion: reduceMotion)
            let y = QuestoRubberBand.clamp(rest.y + Double(drag.height),
                                           to: (bounds.minY + item.height / 2)...max(bounds.minY + item.height / 2, bounds.maxY - item.height / 2),
                                           reduceMotion: reduceMotion)
            content()
                .frame(width: itemSize.width, height: itemSize.height)
                .position(x: CGFloat(x), y: CGFloat(y))
                .gesture(
                    DragGesture()
                        .onChanged { drag = $0.translation }
                        .onEnded { value in
                            let released = (x: rest.x + Double(value.translation.width), y: rest.y + Double(value.translation.height))
                            let next = QuestoCornerSnap.target(position: released,
                                                               velocity: (x: Double(value.velocity.width), y: Double(value.velocity.height)),
                                                               item: item, bounds: bounds)
                            withAnimation(reduceMotion ? nil : .spring(duration: 0.45, bounce: 0.15)) {
                                corner = next
                                drag = .zero
                            }
                        }
                )
                .accessibilityAction(named: questoText("floating.move")) {
                    let all = QuestoCornerSnap.Corner.allCases
                    let current = all.firstIndex(of: corner) ?? 0
                    corner = all[(current + 1) % all.count]
                }
        }
    }
}

#if DEBUG
#Preview("Onboarding pager · dark") {
    struct Host: View {
        @State private var index = 0
        var body: some View {
            QuestoOnboardingPager(
                pages: [
                    QuestoOnboardingPage(title: Text(verbatim: "Preview\nPage one"), primary: Text(verbatim: "Continue"),
                                         hero: AnyView(QuestoCardStack(imageURLs: []))),
                    QuestoOnboardingPage(title: Text(verbatim: "Preview\nPage two"), primary: Text(verbatim: "Continue"),
                                         hero: AnyView(Color.clear))
                ],
                index: $index, onSkip: {}, onPrimary: { position in if position + 1 < 2 { index = position + 1 } },
                secondary: Text(verbatim: "Later"), onSecondary: {})
        }
    }
    return Host().preferredColorScheme(.dark)
}

#Preview("Floating corner") {
    struct Host: View {
        @State private var corner = QuestoCornerSnap.Corner.bottomTrailing
        var body: some View {
            Color(.systemGroupedBackground).ignoresSafeArea().overlay {
                QuestoCornerFloating(corner: $corner, itemSize: CGSize(width: 64, height: 64)) {
                    Image(systemName: "music.note").font(.title2)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.thinMaterial, in: Circle())
                }
            }
        }
    }
    return Host()
}

#Preview("Morph") {
    struct Host: View {
        @State private var phase = QuestoMorphPhase.idle
        var body: some View {
            QuestoMorphControl(phase: phase) {
                Button { phase = .working } label: { Text(verbatim: "Unlock") }.buttonStyle(.borderedProminent)
            }
            .onChange(of: phase) { _, next in
                if next == .working { Task { try? await Task.sleep(for: .seconds(1)); phase = .done } }
            }
        }
    }
    return Host()
}
#endif
