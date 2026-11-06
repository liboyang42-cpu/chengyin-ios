import SwiftUI
import AVKit
import AVFoundation
import CryptoKit
import UniformTypeIdentifiers

/// App-owned local media files for unsent posts. Files live in Application Support with complete
/// file protection and no backup; the registry hands out opaque IDs, never paths, to Core.
@MainActor final class SquarePostMediaFileRegistry {
    private let directory: URL
    init(directory: URL? = nil) throws {
        let base = try directory ?? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("SquarePostMedia", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true,
                                                attributes: [.protectionKey: FileProtectionType.complete])
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        var mutable = base; try? mutable.setResourceValues(values)
        self.directory = base
    }
    func url(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString.lowercased() + ".media") }
    /// Copies a picked movie inside the provider callback (its temporary URL expires on return),
    /// bounded by `maximumBytes` and hashed while copying. Returns the registry ID.
    nonisolated static func copyMovie(from provider: NSItemProvider, to destination: URL, maximumBytes: Int64) async throws -> (sha256: String, byteCount: Int64) {
        guard maximumBytes > 0, provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) else { throw SquarePostLocalMediaIssue.kindNotAllowed }
        return try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, error in
                do {
                    guard error == nil, let url, url.isFileURL else { throw SquarePostLocalMediaIssue.inspectionFailed }
                    let input = try FileHandle(forReadingFrom: url); defer { try? input.close() }
                    FileManager.default.createFile(atPath: destination.path, contents: nil, attributes: [.protectionKey: FileProtectionType.complete])
                    let output = try FileHandle(forWritingTo: destination); defer { try? output.close() }
                    var hasher = SHA256(), total: Int64 = 0
                    while let chunk = try input.read(upToCount: 256 * 1024), !chunk.isEmpty {
                        total += Int64(chunk.count)
                        guard total <= maximumBytes else { throw SquarePostLocalMediaIssue.byteLimit }
                        hasher.update(data: chunk); try output.write(contentsOf: chunk)
                    }
                    guard total > 0 else { throw SquarePostLocalMediaIssue.noBytes }
                    continuation.resume(returning: (hasher.finalize().map { String(format: "%02x", $0) }.joined(), total))
                } catch {
                    try? FileManager.default.removeItem(at: destination)
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    /// Restore check: re-hash the retained file; nil when it no longer exists.
    func digest(_ id: UUID) -> (sha256: String, byteCount: Int64)? {
        guard let input = try? FileHandle(forReadingFrom: url(id)) else { return nil }
        defer { try? input.close() }
        var hasher = SHA256(), total: Int64 = 0
        while let chunk = try? input.read(upToCount: 256 * 1024), !chunk.isEmpty { hasher.update(data: chunk); total += Int64(chunk.count) }
        return (hasher.finalize().map { String(format: "%02x", $0) }.joined(), total)
    }
    func remove(_ id: UUID) { try? FileManager.default.removeItem(at: url(id)) }
}

/// Reads facts from the actual file with AVFoundation; caller descriptions are not evidence.
enum SquarePostVideoInspector {
    static func inspect(_ url: URL, byteCount: Int64) async throws -> (SquarePostVideoInspection, CGImage?) {
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let (duration, playable, tracks) = try await asset.load(.duration, .isPlayable, .tracks)
        let video = tracks.first { $0.mediaType == .video }
        var width = 0, height = 0
        if let video {
            let (size, transform) = try await video.load(.naturalSize, .preferredTransform)
            let rect = CGRect(origin: .zero, size: size).applying(transform)
            width = Int(abs(rect.width).rounded()); height = Int(abs(rect.height).rounded())
        }
        let type = UTType(filenameExtension: url.pathExtension) ?? .quickTimeMovie
        let mime = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType?.preferredMIMEType) ?? type.preferredMIMEType ?? "video/quicktime"
        let seconds = duration.seconds
        let inspection = SquarePostVideoInspection(byteCount: byteCount, mimeType: mime,
            durationMilliseconds: seconds.isFinite ? Int64((seconds * 1000).rounded()) : 0,
            width: width, height: height, hasVideoTrack: video != nil, isPlayable: playable)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 512, height: 512)  // UI thumbnail size, not a media rule
        let poster = try? await generator.image(at: .zero).image
        return (inspection, poster)
    }
}

/// Composer-side video slot: select → copy/process → inspect → (review) → save/restore.
/// Upload is never attempted: `SquarePostVideoUploadAvailability` has no reviewed transport.
@MainActor final class SquarePostVideoComposerModel: ObservableObject {
    enum State: Equatable {
        case empty, working, policyUnavailable, failed
        case ready(SquarePostMediaDraftItem, [SquarePostVideoInspection.Rejection])
        case restored(SquarePostMediaDraftItem, SquarePostMediaRestoreStatus)
    }
    @Published private(set) var state: State = .empty
    @Published private(set) var poster: CGImage?
    let policy: SquarePostLocalMediaPolicy?
    private var generation = 0
    init(policy: SquarePostLocalMediaPolicy?) { self.policy = policy; if policy?.maximumVideoBytes == nil { state = .policyUnavailable } }
    var upload: SquarePostVideoUploadAvailability { .current(policy: policy) }
    var item: SquarePostMediaDraftItem? {
        switch state { case .ready(let item, _), .restored(let item, _): return item; default: return nil }
    }
    var acceptable: Bool { if case .ready(_, let rejections) = state { return rejections.isEmpty }; return false }
    func select(_ provider: NSItemProvider, registry: SquarePostMediaFileRegistry) async {
        guard let maximum = policy?.maximumVideoBytes else { state = .policyUnavailable; return }
        generation += 1; let operation = generation, id = UUID()
        state = .working; poster = nil
        do {
            let copied = try await SquarePostMediaFileRegistry.copyMovie(from: provider, to: registry.url(id), maximumBytes: maximum)
            let (inspection, image) = try await SquarePostVideoInspector.inspect(registry.url(id), byteCount: copied.byteCount)
            guard operation == generation else { registry.remove(id); return }
            accept(inspection, registryID: id, sha256: copied.sha256, poster: image)
        } catch {
            registry.remove(id)
            if operation == generation { state = .failed }
        }
    }
    /// Shared by the real inspector and offline fixtures.
    func accept(_ inspection: SquarePostVideoInspection, registryID: UUID, sha256: String, poster: CGImage?) {
        let item = SquarePostMediaDraftItem(kind: .video, registryID: registryID, sha256: sha256, byteCount: inspection.byteCount,
                                            mimeType: inspection.mimeType, width: inspection.width, height: inspection.height,
                                            durationMilliseconds: inspection.durationMilliseconds)
        self.poster = poster
        state = .ready(item, inspection.rejections(policy: policy))
    }
    func remove() { generation += 1; poster = nil; state = policy?.maximumVideoBytes == nil ? .policyUnavailable : .empty }
    func save(store: SquarePostMediaDraftStore, session: SquareWorkspaceSession, draftID: String) throws {
        try store.save(item.map { [$0] } ?? [], session: session, draftID: draftID)
    }
    func restore(store: SquarePostMediaDraftStore, session: SquareWorkspaceSession, draftID: String,
                 digest: (UUID) -> (sha256: String, byteCount: Int64)?) throws {
        guard let (item, status) = try store.restore(session: session, draftID: draftID, fileDigest: digest).first(where: { $0.0.mediaKind == .video }) else { return }
        generation += 1; poster = nil; state = .restored(item, status)
    }
}

struct SquarePostVideoComposerSection: View {
    @ObservedObject var model: SquarePostVideoComposerModel
    var body: some View {
        Section("square.video.title") {
            switch model.state {
            case .policyUnavailable:
                Label("square.video.policyUnavailable", systemImage: "video.slash").accessibilityIdentifier("square.video.policyUnavailable")
            case .empty: Text("square.video.empty").foregroundStyle(.secondary)
            case .working: ProgressView("square.video.processing")
            case .failed: Label("square.video.failed", systemImage: "exclamationmark.triangle").accessibilityIdentifier("square.video.failed")
            case .ready(let item, let rejections):
                preview(item)
                if rejections.isEmpty { Label("square.video.withinPolicy", systemImage: "checkmark.circle").accessibilityIdentifier("square.video.accepted") }
                ForEach(rejections, id: \.self) { rejection in
                    Text(LocalizedStringKey("square.video.reject." + String(describing: rejection))).foregroundStyle(.red)
                        .accessibilityIdentifier("square.video.reject")
                }
            case .restored(let item, let status):
                preview(item)
                Text(LocalizedStringKey("square.video.restore." + String(describing: status))).accessibilityIdentifier("square.video.restored")
            }
            if model.item != nil {
                Button("square.video.remove", role: .destructive) { model.remove() }.accessibilityIdentifier("square.video.remove")
            }
            // Upload is disabled until a reviewed video transport exists (uploadOSS is JPEG/PNG only).
            Button("square.video.upload") {}.disabled(true).accessibilityIdentifier("square.video.upload")
            if case .unavailable(let blocker) = model.upload {
                Text(LocalizedStringKey("square.video.uploadBlocked." + blocker.rawValue)).font(.footnote).foregroundStyle(.secondary)
                    .accessibilityIdentifier("square.video.uploadBlocked")
            }
        }
    }
    @ViewBuilder private func preview(_ item: SquarePostMediaDraftItem) -> some View {
        HStack(spacing: 12) {
            if let poster = model.poster { Image(decorative: poster, scale: 1).resizable().scaledToFill().frame(width: 96, height: 72).clipped().cornerRadius(8) }
            else { Image(systemName: "film").font(.largeTitle).frame(width: 96, height: 72).accessibilityHidden(true) }
            VStack(alignment: .leading, spacing: 2) {
                if let ms = item.durationMilliseconds { Text("square.video.duration \(Int(ms / 1000))") }
                Text(verbatim: "\(item.width)×\(item.height)").font(.caption)
                Text(verbatim: ByteCountFormatter.string(fromByteCount: item.byteCount, countStyle: .file)).font(.caption).foregroundStyle(.secondary)
            }
        }.accessibilityElement(children: .combine).accessibilityIdentifier("square.video.preview")
    }
}

/// Read + play path for registered post videos. Nothing loads until the viewer taps play, and only an
/// absolute https source with a host is handed to AVPlayer; object keys without a host stay unavailable.
struct SquarePostVideoList: View {
    let videos: [SquarePostVideo]
    var body: some View {
        ForEach(videos) { video in SquarePostVideoPlayerRow(video: video) }
    }
}

struct SquarePostVideoPlayerRow: View {
    let video: SquarePostVideo
    @State private var player: AVPlayer?
    static func playableURL(_ raw: String) -> URL? {
        guard let url = URL(string: raw), url.scheme == "https", url.host?.isEmpty == false, url.user == nil, url.password == nil else { return nil }
        return url
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch video.review {
            case .approved:
                if let player {
                    VideoPlayer(player: player).frame(height: 220).accessibilityIdentifier("square.video.player.\(video.id)")
                } else if let url = Self.playableURL(video.source) {
                    Button { player = AVPlayer(url: url) } label: {
                        Label("square.video.play", systemImage: "play.rectangle").frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }.accessibilityIdentifier("square.video.play.\(video.id)")
                } else {
                    Label("square.video.sourceUnavailable", systemImage: "video.slash").accessibilityIdentifier("square.video.sourceUnavailable")
                }
            case .pending: Label("square.video.review.pending", systemImage: "hourglass")
            case .rejected(let reason):
                Label("square.video.review.rejected", systemImage: "xmark.octagon")
                if let reason { Text(verbatim: reason).font(.caption) }
            case .unavailable, .unknown: Label("square.video.sourceUnavailable", systemImage: "video.slash")
            }
            if let ms = video.durationMilliseconds { Text("square.video.duration \(ms / 1000)").font(.caption).foregroundStyle(.secondary) }
        }
        .onDisappear { player?.pause(); player = nil }
    }
}

#if DEBUG
/// Offline fixture (`--uitesting-module square --uitesting-square-scenario mediaChain`): synthetic inspections,
/// in-memory storage, no files, network or upload. Exercises process → review → save → restore → read.
@MainActor struct SquarePostMediaFixtureHost: View {
    @StateObject private var model: SquarePostVideoComposerModel
    @State private var store = SquarePostMediaDraftStore(storage: SquareWorkspaceMemoryStorage())
    @State private var restoreSource: [UUID: (String, Int64)] = [:]
    private let session = try! SquareWorkspaceSession(accountID: 9001, namespace: "fixture", epoch: 1)
    private let readSample: [SquarePostVideo]
    init() {
        let policy = try? SquarePostLocalMediaPolicy(mimeTypes: [.video: ["video/mp4", "video/quicktime"]], maximumItems: 9, maximumImages: 9,
            maximumVideos: 1, allowsMixed: false, maximumImageBytes: 10 * 1024 * 1024, maximumVideoBytes: 50 * 1024 * 1024,
            maximumTotalBytes: 50 * 1024 * 1024, maximumVideoDurationMilliseconds: 60_000)  // synthetic fixture rules only
        _model = StateObject(wrappedValue: SquarePostVideoComposerModel(policy: policy))
        let post = try? JSONDecoder().decode(SquarePost.self, from: Data(#"{"post":{"id":901,"authorId":9001,"version":1},"media":[{"id":51,"media_type":"VIDEO","derived_object_key":"https://media.example.invalid/v/51.mp4","duration_ms":15000},{"id":52,"media_type":"VIDEO","object_key":"community/52.mp4","review_state":"PENDING"}]}"#.utf8))
        readSample = post?.videos ?? []
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("square.video.fixture.pickValid") { pick(durationMs: 15_000, bytes: 4_000_000) }.accessibilityIdentifier("square.video.fixture.valid")
                    Button("square.video.fixture.pickLong") { pick(durationMs: 120_000, bytes: 4_000_000) }.accessibilityIdentifier("square.video.fixture.long")
                    Button("square.video.fixture.save") { try? model.save(store: store, session: session, draftID: "fixture-draft") }.accessibilityIdentifier("square.video.fixture.save")
                    Button("square.video.fixture.restore") {
                        try? model.restore(store: store, session: session, draftID: "fixture-draft") { id in restoreSource[id].map { ($0.0, $0.1) } }
                    }.accessibilityIdentifier("square.video.fixture.restore")
                    Button("square.video.fixture.loseFile") { restoreSource = [:] }.accessibilityIdentifier("square.video.fixture.loseFile")
                }
                SquarePostVideoComposerSection(model: model)
                Section("square.video.readTitle") { SquarePostVideoList(videos: readSample) }
            }.appNavigationTitle("square.video.title")
        }
    }
    private func pick(durationMs: Int64, bytes: Int64) {
        let id = UUID(), digest = String(repeating: "a", count: 64)
        restoreSource[id] = (digest, bytes)
        model.accept(.init(byteCount: bytes, mimeType: "video/mp4", durationMilliseconds: durationMs, width: 1080, height: 1920,
                           hasVideoTrack: true, isPlayable: true), registryID: id, sha256: digest, poster: nil)
    }
}
#endif
