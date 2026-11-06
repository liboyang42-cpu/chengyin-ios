import SwiftUI

/// Delegates legal images to the original approved-origin/no-redirect media UI and reader.
/// Revocation/recall is rechecked by that reader and the current source, never local deletion.
@MainActor struct NativeChannelMessageAttachmentView: View {
    let snapshot: NativeChannelMessageSnapshot
    let reader: any SocialMessageMediaReading
    let expectedIdentity: MessagingReadIdentity
    let currentSnapshot: () -> NativeChannelMessageSnapshot?
    let permitsAccess: () -> Bool
    private var current: Bool { permitsAccess() && reader.identity == expectedIdentity && currentSnapshot() == snapshot && snapshot.status == 0 }
    var body: some View {
        Group {
            if current, case .existingImage = NativeChannelMessageAttachmentAvailability.project(snapshot) {
                SocialMessageMediaView(message: snapshot.message, reader: reader, expectedIdentity: expectedIdentity,
                    isMessageCurrent: { current })
            } else {
                Text("attachment.sourceRequired", tableName: "NativeChannelMessage")
                    .nativeChannelNotice(systemImage: "doc.badge.ellipsis").padding(Theme.Space.s3)
            }
        }.nativeChannelScreen().privacySensitive().accessibilityIdentifier("ncm47.attachment")
    }
}
