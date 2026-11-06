import Foundation

public typealias ProfileCurrentAvatarReadKey = ProfileCurrentMediaReadKey
/// Avatar-only facade. A QR/work reader cannot be relabelled as an avatar source.
@MainActor public final class ProfileCurrentAvatarReader {
    private let reader: ProfileCurrentMediaReader
    public init?(reader: ProfileCurrentMediaReader) {
        guard reader.kind == .avatar else { return nil }; self.reader = reader
    }
    public var isConfigured: Bool { reader.isConfigured }
    public func key(snapshot: ProfileEditSnapshot, identity: ProfileReadIdentity?, viewerRevision: UInt64?) -> ProfileCurrentAvatarReadKey? {
        reader.key(snapshot: snapshot, kind: .avatar, originalIndex: 0, identity: identity, viewerRevision: viewerRevision)
    }
    public func image(snapshot: ProfileEditSnapshot, key: ProfileCurrentAvatarReadKey,
                      currentSnapshot: @escaping () -> ProfileEditSnapshot?) async throws -> Data {
        guard key.kind == .avatar else { throw RetainedImageFailure.disabled }
        return try await reader.image(snapshot: snapshot, key: key, currentSnapshot: currentSnapshot)
    }
}
