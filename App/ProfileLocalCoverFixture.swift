#if DEBUG
import SwiftUI
import Observation

@MainActor final class ProfileLocalCoverFixtureStore: ProfileLocalCoverStoring {
    var images: [ProfileLocalCoverOwner: RetainedSelectedImage] = [:]
    var writes = 0
    var fails = false
    func read(owner: ProfileLocalCoverOwner) throws -> RetainedSelectedImage? { images[owner] }
    func replace(_ image: RetainedSelectedImage?, owner: ProfileLocalCoverOwner) throws {
        if fails { throw ProfileLocalCoverFailure.storage }
        writes += 1; images[owner] = image
    }
}
@MainActor enum ProfileLocalCoverSyntheticImage {
    static func make() throws -> RetainedSelectedImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let bytes = UIGraphicsImageRenderer(size: .init(width: 320, height: 180), format: format).jpegData(withCompressionQuality: 0.8) { context in
            UIColor.systemTeal.setFill(); context.fill(.init(x: 0, y: 0, width: 320, height: 180))
            UIColor.systemOrange.setFill(); context.fill(.init(x: 0, y: 0, width: 100, height: 180))
        }
        return try RetainedImageSanitizer.sanitize(bytes)
    }
}

/// DEBUG-only synthetic evidence. No image bytes, file paths, credentials or real account data.
@MainActor @Observable final class ProfileLocalCoverFixtureDiagnostics {
    private(set) var events: [String] = []
    private var modelNumbers: [ObjectIdentifier: Int] = [:]
    private var sequence = 0
    var summary: String { events.joined(separator: "\n") }
    func record(_ event: String, model: ProfileLocalCoverModel?) {
        sequence += 1
        guard let model else {
            events.append("\(sequence) \(event) model=none")
            trim(); return
        }
        let identity = ObjectIdentifier(model)
        let number: Int
        if let known = modelNumbers[identity] { number = known }
        else { number = modelNumbers.count + 1; modelNumbers[identity] = number }
        let controller = model.controller
        events.append("\(sequence) \(event) model=\(number) loaded=\(controller.loaded) owns=\(controller.ownsContext) canEdit=\(controller.canEdit) presented=\(model.isPresented) review=\(controller.review != nil) crop=\(model.crop != nil) saved=\(controller.saved != nil) message=\(controller.messageKey ?? "none")")
        trim()
    }
    private func trim() { if events.count > 64 { events.removeFirst(events.count - 64) } }
}

/// Local synthetic controls never open the user's photo library or call an upload endpoint.
@MainActor struct ProfileLocalCoverFixtureHost: View {
    @State private var reader = ProfileAuthorPostsRefreshFixtureReader()
    private let store = ProfileLocalCoverFixtureStore()
    private let ownerA = try! ProfileLocalCoverOwner(accountID: 81, namespace: "synthetic-local-cover")
    private let ownerB = try! ProfileLocalCoverOwner(accountID: 82, namespace: "synthetic-local-cover")
    @State private var model: ProfileLocalCoverModel?
    @State private var showsCover = true
    @State private var diagnostics = ProfileLocalCoverFixtureDiagnostics()
    private var owner: ProfileLocalCoverOwner { reader.identity.accountID == 82 ? ownerB : ownerA }
    private var key: ProfileLocalCoverContext { .init(owner: owner, reader: reader) }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("Switch synthetic account") { model?.retire(); reader.switchAccount(); model = nil }
                        .accessibilityIdentifier("profile.localCoverFixture.switch")
                    Button("Sign out synthetic account") { model?.retire(); reader.signOut(); model = nil }
                        .accessibilityIdentifier("profile.localCoverFixture.logout")
                    Button("Toggle cover") { showsCover.toggle() }.accessibilityIdentifier("profile.localCoverFixture.toggle")
                    Button("Prepare synthetic cover") {
                        diagnostics.record("prepare.begin", model: model)
                        guard let model else {
                            diagnostics.record("prepare.no-model", model: nil); return
                        }
                        do {
                            let image = try ProfileLocalCoverSyntheticImage.make()
                            diagnostics.record("prepare.image-ready", model: model)
                            model.open()
                            diagnostics.record("prepare.after-open", model: model)
                            model.controller.prepare(image)
                            diagnostics.record("prepare.after-review", model: model)
                        } catch {
                            diagnostics.record("prepare.image-error: \(String(describing: error))", model: model)
                        }
                    }.accessibilityIdentifier("profile.localCoverFixture.prepare")
                        .accessibilityValue(Text(verbatim: diagnostics.summary))
                    if let model {
                        Text(verbatim: "Writes: \(store.writes)").accessibilityIdentifier("profile.localCoverFixture.writes")
                        Text(verbatim: model.controller.saved == nil ? "Default" : "Saved").accessibilityIdentifier("profile.localCoverFixture.state")
                        Button("Reload synthetic saved cover") { model.controller.load() }.accessibilityIdentifier("profile.localCoverFixture.reload")
                    }
                }
                if showsCover, let model, key.isOwnAccount {
                    ProfileLocalCoverEnabledSection(model: model).id(key)
                        .onAppear { diagnostics.record("section-input.appear", model: model) }
                        .onDisappear { diagnostics.record("section-input.disappear", model: model) }
                }
            }.task(id: key) {
                let captured = key, reader = reader, owner = owner
                let created = ProfileLocalCoverModel(context: captured, store: store, current: { .init(owner: owner, reader: reader) })
                let diagnosticSink: (String) -> Void = { [weak created, weak diagnostics] event in
                    diagnostics?.record(event, model: created)
                }
                created.diagnosticEvent = diagnosticSink
                created.pickerHost.diagnosticEvent = diagnosticSink
                diagnostics.record("parent.created", model: created)
                created.controller.load(); model = created
                diagnostics.record("parent.loaded", model: created)
            }
            .onChange(of: model?.isPresented) { _, _ in diagnostics.record("observed.presentation", model: model) }
            .onChange(of: model?.controller.loaded) { _, _ in diagnostics.record("observed.loaded", model: model) }
            .onChange(of: model?.controller.review?.id) { _, _ in diagnostics.record("observed.review", model: model) }
            .onChange(of: key) { _, _ in diagnostics.record("observed.context", model: model) }
        }
    }
}
#endif
