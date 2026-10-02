import SwiftUI

@MainActor private final class SettingsLegalViewModel: ObservableObject {
    @Published private(set) var state: SettingsLegalState = .idle
    private let coordinator: SettingsLegalCoordinator
    init(reader: any SettingsLegalReading) {
        coordinator = SettingsLegalCoordinator(reader: reader)
        coordinator.onChange = { [weak self] in self?.state = $0 }
    }
    func load(type: SettingsLegalType, market: RegionalMarket?) async { await coordinator.load(type: type, market: market) }
    func invalidate() { coordinator.invalidate() }
}

/// Read-only source document. Opening, scrolling, or dismissing never accepts an agreement.
@MainActor struct SettingsLegalDocumentView: View {
    let type: SettingsLegalType
    let market: RegionalMarket?
    @StateObject private var model: SettingsLegalViewModel
    init(type: SettingsLegalType, market: RegionalMarket?, reader: any SettingsLegalReading) {
        self.type = type; self.market = market
        _model = StateObject(wrappedValue: SettingsLegalViewModel(reader: reader))
    }
    private var loadID: String { type.rawValue + ":" + (market?.rawValue ?? "missing") }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                switch model.state {
                case .idle, .loading:
                    ProgressView("settingsNative.loading").frame(maxWidth: .infinity)
                        .accessibilityIdentifier("settingsNative.legal.loading")
                case .failed:
                    Label {
                        Text("settingsNative.legal.loadFailed").accessibilityIdentifier("settingsNative.legal.error")
                    } icon: { Image(systemName: "exclamationmark.triangle").accessibilityHidden(true) }
                    Button("settingsNative.retry") { Task { await model.load(type: type, market: market) } }
                        .accessibilityIdentifier("settingsNative.legal.retry")
                case .loaded(.missing(let reason)):
                    Label {
                        Text("settingsNative.legal.missingTitle").accessibilityIdentifier("settingsNative.legal.missing")
                    } icon: { Image(systemName: "doc.questionmark").accessibilityHidden(true) }
                    .font(.headline)
                    Text(LocalizedStringKey(reason.messageKey)).foregroundStyle(.secondary)
                    Text("settingsNative.legal.noAcceptance").font(.footnote).foregroundStyle(.secondary)
                case .loaded(.sourceDocument(let document)):
                    Text("settingsNative.legal.sourceNotice").font(.footnote).foregroundStyle(.secondary)
                        .accessibilityIdentifier("settingsNative.legal.sourceNotice")
                    Text(verbatim: document.title).font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                    HStack(alignment: .firstTextBaseline) {
                        Text("settingsNative.legal.version")
                        Text(verbatim: document.version).accessibilityIdentifier("settingsNative.legal.version")
                    }.font(.caption).foregroundStyle(.secondary)
                    Text(verbatim: document.intro).textSelection(.enabled)
                    ForEach(Array(document.sections.enumerated()), id: \.offset) { index, section in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(verbatim: section.heading).font(.headline).accessibilityAddTraits(.isHeader)
                            ForEach(Array(SettingsLegalLine.lines(in: section.body).enumerated()), id: \.offset) { _, line in
                                HStack(alignment: .top, spacing: 4) {
                                    if let marker = line.marker { Text(verbatim: marker).fixedSize(horizontal: true, vertical: false) }
                                    Text(verbatim: line.text).frame(maxWidth: .infinity, alignment: .leading)
                                }.textSelection(.enabled).accessibilityElement(children: .combine)
                            }
                        }
                        .accessibilityIdentifier("settingsNative.legal.section.\(index)")
                    }
                    HStack {
                        Text("settingsNative.legal.effectiveDate")
                        Text(verbatim: document.effectiveDate)
                    }.font(.caption).foregroundStyle(.secondary)
                    Text("settingsNative.legal.noAcceptance").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: 720, alignment: .leading).padding()
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(Text(LocalizedStringKey(type.titleKey)))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: loadID) { await model.load(type: type, market: market) }
        .onDisappear { model.invalidate() }
    }
}
