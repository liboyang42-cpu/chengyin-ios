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

/// Local synthetic controls never open the user's photo library or call an upload endpoint.
@MainActor struct ProfileLocalCoverFixtureHost: View {
    @State private var reader = ProfileAuthorPostsRefreshFixtureReader()
    private let store = ProfileLocalCoverFixtureStore()
    private let ownerA = try! ProfileLocalCoverOwner(accountID: 81, namespace: "synthetic-local-cover")
    private let ownerB = try! ProfileLocalCoverOwner(accountID: 82, namespace: "synthetic-local-cover")
    @State private var model: ProfileLocalCoverModel?
    @State private var showsCover = true
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
                        guard let model, let image = try? ProfileLocalCoverSyntheticImage.make() else { return }
                        model.open(); model.controller.prepare(image)
                    }.accessibilityIdentifier("profile.localCoverFixture.prepare")
                    if let model {
                        Text(verbatim: "Writes: \(store.writes)").accessibilityIdentifier("profile.localCoverFixture.writes")
                        Text(verbatim: model.controller.saved == nil ? "Default" : "Saved").accessibilityIdentifier("profile.localCoverFixture.state")
                        Button("Reload synthetic saved cover") { model.controller.load() }.accessibilityIdentifier("profile.localCoverFixture.reload")
                    }
                }
                if showsCover, let model, key.isOwnAccount {
                    ProfileLocalCoverEnabledSection(model: model).id(key)
                }
            }.task(id: key) {
                let captured = key, reader = reader, owner = owner
                let created = ProfileLocalCoverModel(context: captured, store: store, current: { .init(owner: owner, reader: reader) })
                created.controller.load(); model = created
            }
        }
    }
}
#endif
