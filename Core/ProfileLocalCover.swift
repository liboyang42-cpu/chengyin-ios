import Foundation
import CryptoKit
import Observation

/// Device-only preference owner. No credential, upload grant or server field is stored.
public struct ProfileLocalCoverOwner: Hashable, Codable {
    public let accountID: Int
    public let namespace: String
    public init(accountID: Int, namespace: String) throws {
        guard accountID > 0, !namespace.isEmpty, namespace.utf8.count <= 4096 else { throw ProfileLocalCoverFailure.invalid }
        self.accountID = accountID; self.namespace = namespace
    }
    public var storageKey: String {
        let value = "profile-local-cover-v1|\(namespace.utf8.count):\(namespace)|\(accountID)"
        return SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
public enum ProfileLocalCoverFailure: Error, Equatable { case invalid, changed, storage, stale }
public struct ProfileLocalCoverContext: Hashable {
    public let owner: ProfileLocalCoverOwner
    public let viewer: SocialAccountIdentity
    public let revision: UInt64
    private let readerID: ObjectIdentifier
    @MainActor public init(owner: ProfileLocalCoverOwner, reader: any SocialAccountReading) {
        self.owner = owner; viewer = reader.identity; revision = reader.presentationRevision
        readerID = ObjectIdentifier(reader)
    }
    public var isOwnAccount: Bool { viewer.accountID == owner.accountID }
}
@MainActor public protocol ProfileLocalCoverStoring: AnyObject {
    func read(owner: ProfileLocalCoverOwner) throws -> RetainedSelectedImage?
    func replace(_ image: RetainedSelectedImage?, owner: ProfileLocalCoverOwner) throws
}
public struct ProfileLocalCoverReview: Equatable, Identifiable {
    public let id = UUID()
    public let context: ProfileLocalCoverContext
    /// nil explicitly means restore this device's default, never delete a server asset.
    public let image: RetainedSelectedImage?
    fileprivate init(context: ProfileLocalCoverContext, image: RetainedSelectedImage?) {
        self.context = context; self.image = image
    }
}

@MainActor @Observable public final class ProfileLocalCoverController {
    public let context: ProfileLocalCoverContext
    public private(set) var saved: RetainedSelectedImage?
    public private(set) var review: ProfileLocalCoverReview?
    public private(set) var messageKey: String?
    public private(set) var loaded = false
    private let store: any ProfileLocalCoverStoring
    private let current: () -> ProfileLocalCoverContext?
    public init(context: ProfileLocalCoverContext, store: any ProfileLocalCoverStoring, current: @escaping () -> ProfileLocalCoverContext?) {
        self.context = context; self.store = store; self.current = current
    }
    public var ownsContext: Bool { context.isOwnAccount && current() == context }
    public var canEdit: Bool { ownsContext && loaded }
    public func load() {
        guard ownsContext else { retire(); return }
        review = nil; messageKey = nil
        do {
            let value = try store.read(owner: context.owner)
            guard ownsContext else { retire(); return }
            _ = try value.map(Self.validate)
            saved = value; loaded = true
        } catch { loaded = false; messageKey = "profile.localCover.failed" }
    }
    public func prepare(_ image: RetainedSelectedImage) {
        guard canEdit else { retire(); return }
        do { try Self.validate(image); review = .init(context: context, image: image); messageKey = nil }
        catch { messageKey = "profile.localCover.invalid" }
    }
    public func prepareDefault() {
        guard canEdit, saved != nil else { return }
        review = .init(context: context, image: nil); messageKey = nil
    }
    public func cancel(_ value: ProfileLocalCoverReview) {
        guard review == value else { return }; review = nil
    }
    /// Synchronous same-owner compare-and-replace; cancellation and stale UI never call storage.
    public func confirm(_ value: ProfileLocalCoverReview) {
        guard !Task.isCancelled, canEdit, value.context == context, review == value else { return }
        do {
            let persisted = try store.read(owner: context.owner)
            guard Self.sameImage(persisted, saved) else { throw ProfileLocalCoverFailure.changed }
            guard ownsContext else { retire(); return }
            try store.replace(value.image, owner: context.owner)
            let verified = try store.read(owner: context.owner)
            guard ownsContext else { retire(); return }
            guard Self.sameImage(verified, value.image) else { throw ProfileLocalCoverFailure.storage }
            saved = verified; review = nil; messageKey = "profile.localCover.saved"
        } catch ProfileLocalCoverFailure.changed { loaded = false; messageKey = "profile.localCover.changed" }
        catch { loaded = false; messageKey = "profile.localCover.failed" }
    }
    public func retire() { saved = nil; review = nil; messageKey = nil; loaded = false }
    public static func validate(_ image: RetainedSelectedImage) throws {
        guard image.width >= 16, image.height >= 9, image.width * 9 == image.height * 16,
              image.width <= RetainedSelectedImage.maximumDimension, image.height <= RetainedSelectedImage.maximumDimension,
              image.jpeg.count <= RetainedSelectedImage.maximumBytes, image.jpeg.starts(with: [255, 216, 255]) else { throw ProfileLocalCoverFailure.invalid }
    }
    public static func sameImage(_ lhs: RetainedSelectedImage?, _ rhs: RetainedSelectedImage?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): return true
        case let (a?, b?): return a.width == b.width && a.height == b.height && a.jpeg == b.jpeg
        default: return false
        }
    }
}
