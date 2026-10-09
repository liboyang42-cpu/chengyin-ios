import SwiftUI

/// Ordinary story-album entry. It uses the existing approved image pipeline; no
/// binding, template or pending-chapter host can mint this presentation implicitly.
@MainActor struct ProjectAlbumImageAuthorField: View {
    @ObservedObject var model: ProjectEditModel
    let chapterID: String, blockID: String
    @StateObject private var images: ProjectStoryImagePresentation
    @Environment(\.scenePhase) private var scenePhase
    init(model: ProjectEditModel, chapterID: String, blockID: String) {
        self.model = model; self.chapterID = chapterID; self.blockID = blockID
        _images = StateObject(wrappedValue: .init(editor: model))
    }
    var body: some View {
        let opening = images.captureAlbum(chapterID: chapterID, blockID: blockID)
        let original = images.presentation
        VStack(alignment: .leading) {
            Button {
                guard scenePhase == .active, let opening else { return }
                images.open(opening)
            } label: { Text("projectAlbumImage.choose", tableName: "ProjectAlbumImageAuthor") }
                .buttonStyle(.borderless).disabled(opening == nil)
                .accessibilityIdentifier("projectAlbumImage.choose." + blockID)
            Text("projectAlbumImage.scope", tableName: "ProjectAlbumImageAuthor").font(.caption).foregroundStyle(.secondary)
            if opening == nil && original == nil {
                Text("projectAlbumImage.unavailable", tableName: "ProjectAlbumImageAuthor").font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("projectAlbumImage.unavailable." + blockID)
            }
        }
        .sheet(item: images.binding(original)) { captured in
            ProjectStoryImageAuthorView(original: captured, apply: { images.apply($0) }, close: { images.close(captured) })
        }
        .onAppear { images.setAlbumHostActive(scenePhase == .active) }
        .onChange(of: scenePhase) { _, phase in images.setAlbumHostActive(phase == .active) }
        .onDisappear { images.setAlbumHostActive(false) }
    }
}
