import SwiftUI

struct ClubGovernanceFeedContext {
    var viewerRevision: UInt64 = 0
    var readerIdentity: ObjectIdentifier? = nil
    var destination: ((Int) -> AnyView)? = nil
    var imageReader: (any RetainedPublicImageReading)? = nil
}
private struct ClubGovernanceFeedKey: EnvironmentKey {
    static let defaultValue = ClubGovernanceFeedContext()
}
extension EnvironmentValues {
    var clubGovernanceFeed: ClubGovernanceFeedContext {
        get { self[ClubGovernanceFeedKey.self] }
        set { self[ClubGovernanceFeedKey.self] = newValue }
    }
}

@MainActor struct ClubGovernanceFeedPostView: View {
    let post: ClubFeedPost
    let mediaScope: UUID
    let imageReader: any RetainedPublicImageReading
    var openClub: (() -> Void)? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                if let avatar = post.avatar {
                    NativeMediaImage(raw: avatar, reader: imageReader, zoomable: false)
                        .frame(width: 48, height: 48).clipShape(Circle()).accessibilityHidden(true)
                } else { Image(systemName: "person.crop.circle").font(.title2).accessibilityHidden(true) }
                VStack(alignment: .leading, spacing: 4) {
                    if let nickname = post.nickname { Text(verbatim: nickname).font(.headline) }
                    else { Text("square.unknownAuthor").font(.headline) }
                    if let time = post.createTime {
                        Text(verbatim: time).font(.caption).foregroundStyle(.secondary)
                            .accessibilityIdentifier("club.feed.time.\(post.id)")
                    }
                }
            }
            if let content = post.content { Text(verbatim: content).textSelection(.enabled) }
            if !post.images.isEmpty {
                NativeMediaGalleryEntry(sources: post.images, scope: mediaScope, reader: imageReader)
                    .accessibilityIdentifier("club.feed.images.\(post.id)")
            }
            if let openClub {
                Button(action: openClub) { sourceClub }
                    .accessibilityIdentifier("club.feed.source.\(post.id)")
            } else if post.clubName != nil { sourceClub }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("club.feed.post.\(post.id)")
        .id(mediaScope)
    }
    private var sourceClub: some View {
        Label {
            if let name = post.clubName { Text(verbatim: name) }
            else { Text("club.detail") }
        } icon: { Image(systemName: "person.3") }
    }
}
