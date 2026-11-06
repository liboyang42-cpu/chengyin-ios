import Foundation

public enum NativeChannelMessageAttachmentAvailability: Equatable {
    case existingImage(SocialMessageMedia)
    case sourceRequired(kind: NativeChannelMessageKind)
    case withheld
    public static func project(_ snapshot: NativeChannelMessageSnapshot) -> Self {
        guard snapshot.status == 0 else { return .withheld }
        if snapshot.kind == .image, let image = try? SocialMessageMedia(message: snapshot.message) { return .existingImage(image) }
        return .sourceRequired(kind: snapshot.kind)
    }
}

/// The real existing image reader remains the only byte loader. No user file is uploaded
/// and no attachment endpoint/token/URL is fabricated for absent E-16/MSG13 producers.
@MainActor public final class NativeChannelMessageAttachment {
    public let reader: any SocialMessageMediaReading
    public let expectedIdentity: MessagingReadIdentity
    private let current: () -> NativeChannelMessageSnapshot?
    private let permitsAccess: () -> Bool
    public init(reader: any SocialMessageMediaReading, expectedIdentity: MessagingReadIdentity,
                current: @escaping () -> NativeChannelMessageSnapshot?, permitsAccess: @escaping () -> Bool) {
        self.reader = reader; self.expectedIdentity = expectedIdentity; self.current = current; self.permitsAccess = permitsAccess
    }
    public func isCurrent(_ snapshot: NativeChannelMessageSnapshot) -> Bool {
        reader.identity == expectedIdentity && permitsAccess() && current() == snapshot && snapshot.status == 0
    }
    public func image(_ snapshot: NativeChannelMessageSnapshot) async throws -> Data {
        guard isCurrent(snapshot), case .existingImage(let media) = NativeChannelMessageAttachmentAvailability.project(snapshot) else { throw SocialMediaFailure.unavailable }
        try Task.checkCancellation()
        let bytes = try await reader.image(media, expectedIdentity: expectedIdentity)
        try Task.checkCancellation()
        guard isCurrent(snapshot) else { throw CancellationError() }
        return bytes
    }
}
