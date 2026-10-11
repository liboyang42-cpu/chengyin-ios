import Foundation

/// App-owned, account/deployment-scoped derived JPEGs only. Never photo-library deletion.
/// Backups are excluded so the UI's "this device only" statement remains accurate.
@MainActor public final class ProfileLocalCoverFileStore: ProfileLocalCoverStoring {
    private let directory: URL
    private let files: FileManager
    private struct Envelope: Codable {
        let version: Int
        let owner: ProfileLocalCoverOwner
        let width: Int
        let height: Int
        let jpeg: Data
    }
    public init(directory: URL? = nil, files: FileManager = .default) {
        self.files = files
        self.directory = directory ?? files.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ProfileLocalCovers-v1", isDirectory: true)
    }
    private func file(_ owner: ProfileLocalCoverOwner) -> URL { directory.appendingPathComponent(owner.storageKey + ".cover") }
    public func read(owner: ProfileLocalCoverOwner) throws -> RetainedSelectedImage? {
        let path = file(owner)
        guard files.fileExists(atPath: path.path) else { return nil }
        let properties = try path.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
        guard properties.isRegularFile == true, properties.isSymbolicLink != true,
              let count = properties.fileSize, (1...(RetainedSelectedImage.maximumBytes + 16384)).contains(count) else { throw ProfileLocalCoverFailure.storage }
        let bytes = try Data(contentsOf: path, options: .mappedIfSafe)
        let value = try PropertyListDecoder().decode(Envelope.self, from: bytes)
        guard value.version == 1, value.owner == owner else { throw ProfileLocalCoverFailure.storage }
        let image = try RetainedSelectedImage(jpeg: value.jpeg, width: value.width, height: value.height)
        try ProfileLocalCoverController.validate(image); return image
    }
    public func replace(_ image: RetainedSelectedImage?, owner: ProfileLocalCoverOwner) throws {
        let path = file(owner)
        guard let image else {
            if files.fileExists(atPath: path.path) { try files.removeItem(at: path) }
            return
        }
        try ProfileLocalCoverController.validate(image)
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        var root = directory, values = URLResourceValues(); values.isExcludedFromBackup = true
        try root.setResourceValues(values)
        let encoder = PropertyListEncoder(); encoder.outputFormat = .binary
        let bytes = try encoder.encode(Envelope(version: 1, owner: owner, width: image.width, height: image.height, jpeg: image.jpeg))
        #if os(iOS)
        try bytes.write(to: path, options: [.atomic, .completeFileProtection])
        #else
        try bytes.write(to: path, options: .atomic)
        #endif
    }
}
