import SwiftUI

/// Local inspiration from the c6 simple-publish reference. These values are not
/// draft fields, saved records, permissions or generated places.
struct QuickPublishingInterest: Identifiable {
    let id: String
    let chinese: String
    let english: String
    let symbol: String
    let x: CGFloat
    let y: CGFloat
    let diameter: CGFloat
    func title(chinese: Bool) -> String { chinese ? self.chinese : english }
    static let all: [Self] = [
        .init(id: "coffee", chinese: "咖啡", english: "Coffee", symbol: "fork.knife", x: 14, y: 90, diameter: 150),
        .init(id: "food", chinese: "美食", english: "Food", symbol: "bag", x: 36, y: 10, diameter: 132),
        .init(id: "photo", chinese: "拍照", english: "Photography", symbol: "camera", x: 58, y: 110, diameter: 140),
        .init(id: "story", chinese: "老建筑", english: "Old buildings", symbol: "mappin.circle", x: 78, y: 20, diameter: 128),
        .init(id: "night", chinese: "夜游", english: "Night walks", symbol: "star", x: 18, y: 280, diameter: 128),
        .init(id: "walk", chinese: "散步", english: "Walking", symbol: "map", x: 44, y: 250, diameter: 140),
        .init(id: "park", chinese: "公园", english: "Parks", symbol: "leaf", x: 70, y: 280, diameter: 132)
    ]
}

enum QuickPublishingPalette {
    static func selection(in domain: ThemeDomain) -> Color {
        // Existing topic-editor info blue is exactly c6's local #2F6DF0.
        // The global brand token is charcoal and the old AI token is purple.
        Theme.Generated.color("--cy-color-status-info", in: domain) ?? Theme.Color.accent(in: domain)
    }
}

struct QuickPublishingInterestPicker: View {
    let selected: Set<String>
    let toggle: (String) -> Void
    @Environment(\.locale) private var locale
    @Environment(\.themeDomain) private var domain
    @Environment(\.dynamicTypeSize) private var typeSize
    private var chinese: Bool { locale.language.languageCode?.identifier == "zh" }
    var body: some View {
        if typeSize >= .xxxLarge {
            VStack(alignment: .leading, spacing: Theme.Space.s2) {
                ForEach(QuickPublishingInterest.all) { item in interest(item, diameter: nil) }
            }
        } else {
            GeometryReader { geometry in
                let scale = geometry.size.width / 750
                ZStack(alignment: .topLeading) {
                    ForEach(QuickPublishingInterest.all) { item in
                        let edge = item.diameter * scale
                        interest(item, diameter: edge)
                            .position(x: geometry.size.width * item.x / 100, y: item.y * scale + edge / 2)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }.aspectRatio(750.0 / 440.0, contentMode: .fit)
        }
    }
    private func interest(_ item: QuickPublishingInterest, diameter: CGFloat?) -> some View {
        let on = selected.contains(item.id)
        return Button { toggle(item.id) } label: {
            Group {
                if let diameter {
                    Image(systemName: item.symbol).font(on ? .title2.weight(.semibold) : .title3.weight(.semibold))
                        .frame(width: max(44, diameter), height: max(44, diameter))
                        .background(on ? QuickPublishingPalette.selection(in: domain) : Theme.Color.bgSurface(in: domain), in: Circle())
                        .scaleEffect(on ? 1.08 : 1)
                } else {
                    Label(item.title(chinese: chinese), systemImage: item.symbol)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .padding(.horizontal, Theme.Space.s3)
                        .background(on ? QuickPublishingPalette.selection(in: domain) : Theme.Color.bgSurface(in: domain), in: RoundedRectangle(cornerRadius: Theme.Radius.md))
                }
            }.foregroundStyle(on ? Theme.Color.bgSurface(in: domain) : Theme.Color.textPrimary(in: domain))
        }.buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: item.title(chinese: chinese)))
            .accessibilityValue(on ? Text("publishModes.selected") : Text("publishModes.notSelected"))
            .accessibilityAddTraits(on ? .isSelected : [])
            .accessibilityIdentifier("publishModes.quick.interest." + item.id)
    }
}

/// The reference's blue/pink/green canvas is decorative content. Existing domain
/// tokens keep light/dark and increased contrast behavior; no global token edits.
struct QuickPublishingCanvas: View {
    @Environment(\.themeDomain) private var domain
    @Environment(\.colorSchemeContrast) private var contrast
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Theme.Color.bgPage(in: domain)
                if contrast != .increased {
                    RadialGradient(colors: [QuickPublishingPalette.selection(in: domain).opacity(0.16), .clear], center: .init(x: 0.08, y: 0.45), startRadius: 0, endRadius: geometry.size.width * 0.9)
                    RadialGradient(colors: [Theme.Color.danger(in: domain).opacity(0.09), .clear], center: .init(x: 0.92, y: 0.20), startRadius: 0, endRadius: geometry.size.width * 0.85)
                    RadialGradient(colors: [Theme.Color.success(in: domain).opacity(0.12), .clear], center: .init(x: 0.60, y: 0.80), startRadius: 0, endRadius: geometry.size.width)
                }
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

/// Presentation helpers shared only by the publishing journey. They own no state,
/// permissions or request callbacks.
struct PublishingField<Content: View>: View {
    let title: Text
    let content: Content
    var required = false
    @Environment(\.locale) private var locale
    @Environment(\.themeDomain) private var domain
    init(_ key: LocalizedStringKey, required: Bool = false, @ViewBuilder content: () -> Content) {
        title = Text(key); self.required = required; self.content = content()
    }
    init(title: Text, required: Bool = false, @ViewBuilder content: () -> Content) {
        self.title = title; self.required = required; self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s2) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s1) {
                title.font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                if required {
                    Text(verbatim: "*").foregroundStyle(Theme.Color.danger(in: domain))
                        .accessibilityHidden(true)
                }
            }.accessibilityElement(children: .ignore)
                .accessibilityLabel(title + Text(verbatim: required ? (locale.language.languageCode?.identifier == "zh" ? "，必填" : ", required") : ""))
            content.font(Theme.Font.body)
        }.frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, Theme.Space.s1)
    }
}

struct PublishingStatusRow: View {
    let title: Text
    var symbol = "info.circle"
    var isError = false
    @Environment(\.themeDomain) private var domain
    var body: some View {
        Label {
            title.fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol).accessibilityHidden(true)
        }
        .font(isError ? .body : .footnote)
        .foregroundStyle(isError ? Theme.Color.danger(in: domain) : Theme.Color.textSecondary(in: domain))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Theme.Space.s1)
        .accessibilityElement(children: .combine)
    }
}

struct PublishingFormSurface: ViewModifier {
    @Environment(\.themeDomain) private var domain
    func body(content: Content) -> some View {
        content.scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.Color.bgPage(in: domain))
    }
}

@MainActor struct PublishingModePickerSheet: View {
    @Environment(\.themeDomain) private var domain
    @Environment(\.dismiss) private var dismiss
    @State private var selection: ProjectEditProduct
    let confirm: (ProjectEditProduct) -> Void
    init(current: ProjectEditProduct, confirm: @escaping (ProjectEditProduct) -> Void) {
        _selection = State(initialValue: current); self.confirm = confirm
    }
    var body: some View {
        NavigationStack {
            Form {
                Picker("contextPublish.mode.choose", selection: $selection) {
                    Text("projectEdit.city").tag(ProjectEditProduct.city)
                    Text("projectEdit.freeExplore").tag(ProjectEditProduct.freeExplore)
                }.pickerStyle(.inline)
                Text("contextPublish.mode.cityDetail")
                    .font(Theme.Font.body).foregroundStyle(Theme.Color.textSecondary(in: domain))
                    .fixedSize(horizontal: false, vertical: true)
                Text("contextPublish.mode.exploreDetail")
                    .font(Theme.Font.body).foregroundStyle(Theme.Color.textSecondary(in: domain))
                    .fixedSize(horizontal: false, vertical: true)
            }.modifier(PublishingFormSurface()).font(Theme.Font.body).tint(Theme.Color.accent(in: domain))
                .navigationTitle("contextPublish.mode.choose")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("action.cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("contextPublish.mode.use") { confirm(selection) } }
            }
        }
    }
}
@MainActor struct PublishingSubmissionResultSheet: View {
    @Environment(\.themeDomain) private var domain
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var lifecycle = ProjectSubmissionResultLifecycle()
    let receipt: PublishingSubmissionHandoff
    let canNavigate: Bool
    var canVerifyRelease = false
    let close: () -> Void
    var body: some View {
        let capture = lifecycle.capture
        result(capture: capture)
            .onAppear { lifecycle.appear(active: scenePhase == .active) }
            .onDisappear { lifecycle.disappear() }
            .onChange(of: scenePhase) { _, phase in lifecycle.sceneChanged(active: phase == .active) }
            .task(id: capture) {
                guard receipt.bundleAcknowledgment == nil, canNavigate, let capture else { return }
                do { try await Task.sleep(nanoseconds: 2_000_000_000) } catch { return }
                guard !Task.isCancelled else { return }
                lifecycle.finish(capture, action: close)
            }
    }
    @ViewBuilder private func result(capture: UUID?) -> some View {
        if let acknowledgment = receipt.bundleAcknowledgment {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.s4) {
                    Text("contextPublish.result.acknowledged").font(Theme.Font.sheetTitle)
                        .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
                    Text(verbatim: receipt.title).font(Theme.Font.sectionTitle)
                        .fixedSize(horizontal: false, vertical: true)
                    ProjectSubmissionEvidenceView(acknowledgment: acknowledgment, currentVerificationConfigured: canVerifyRelease)
                    Button("action.done") { if let capture { lifecycle.finish(capture, action: close) } }.buttonStyle(.questifyPrimary)
                        .frame(minHeight: 44)
                        .disabled(capture == nil)
                        .accessibilityIdentifier("projectSubmission.done")
                }.frame(maxWidth: .infinity, alignment: .leading).padding(Theme.Space.pageX)
                    .font(Theme.Font.body).tint(Theme.Color.accent(in: domain))
            }.accessibilityIdentifier("projectSubmission.receipt")
                .interactiveDismissDisabled()
        } else { legacyResult(capture: capture) }
    }
    private func legacyResult(capture: UUID?) -> some View {
        ScrollView {
        VStack(alignment: .leading, spacing: Theme.Space.s4) {
            Label("contextPublish.result.acknowledged", systemImage: "checkmark.circle").font(Theme.Font.sheetTitle)
                .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
            Text(verbatim: receipt.title).font(Theme.Font.sectionTitle)
                .fixedSize(horizontal: false, vertical: true)
            LabeledContent("contextPublish.result.chapters", value: String(receipt.chapterCount))
            Text("contextPublish.result.readStatus").font(Theme.Font.body)
                .foregroundStyle(Theme.Color.textSecondary(in: domain)).fixedSize(horizontal: false, vertical: true)
            if !canNavigate {
                Button("action.done") { if let capture { lifecycle.finish(capture, action: close) } }
                    .buttonStyle(.questifyPrimary)
                    .frame(minHeight: 44)
                    .disabled(capture == nil)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(Theme.Space.pageX)
            .font(Theme.Font.body).tint(Theme.Color.accent(in: domain))
        }.interactiveDismissDisabled()
    }
}

/// Presentation-only lease. Backgrounding or closing retires old timer/button captures;
/// becoming visible again starts a fresh full delay without changing the request journal.
@MainActor final class ProjectSubmissionResultLifecycle: ObservableObject {
    @Published private(set) var capture: UUID?
    private var visible = false
    private var active = false
    private var finished = false
    func appear(active: Bool) {
        guard !finished else { return }
        if !visible || self.active != active { capture = active ? UUID() : nil }
        visible = true; self.active = active
    }
    func sceneChanged(active: Bool) {
        guard !finished, self.active != active else { return }
        self.active = active; capture = visible && active ? UUID() : nil
    }
    func disappear() { visible = false; active = false; capture = nil }
    func finish(_ original: UUID, action: () -> Void) {
        guard visible, active, !finished, capture == original else { return }
        finished = true; capture = nil; action()
    }
}
