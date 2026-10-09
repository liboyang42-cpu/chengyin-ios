import SwiftUI
import CoreImage.CIFilterBuiltins
import UIKit
import CryptoKit

/// A display-only check of the server envelope, not local signature verification or
/// permission to issue/consume a code. Keep the original UTF-8 bytes intact.
struct MerchantStationLiveCodeReceipt {
    let code: String
    let nodeName: String
    let expiresAt: Date
    private let acceptedAt: Date
    private let acceptedUptime: TimeInterval
    private let deadlineUptime: TimeInterval

    init?(snapshot: MerchantContentSnapshot, now: Date, uptime: TimeInterval) {
        guard case .liveCode(let activityID, let nodeID) = snapshot.query,
              activityID > 0, activityID <= 9_007_199_254_740_991, nodeID > 0, nodeID <= 9_007_199_254_740_991,
              snapshot.value["nodeId"].safeInteger == nodeID,
              let ttl = snapshot.value["ttlMs"].safeInteger, (1...60_000).contains(ttl),
              let code = snapshot.value["code"].text, !code.isEmpty, code.utf8.count <= 2_048,
              code.utf8.allSatisfy({ (33...126).contains($0) }),
              now.timeIntervalSince1970.isFinite, snapshot.observedAt.timeIntervalSince1970.isFinite,
              uptime.isFinite, uptime >= 0, snapshot.observedAt <= now else { return nil }
        let parts = code.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 6, parts[0] == "v1", parts[1] == String(nodeID), parts[2] == "play_checkin",
              parts[3].range(of: #"^[1-9][0-9]{0,15}$"#, options: .regularExpression) != nil,
              let milliseconds = Int64(parts[3]), milliseconds <= 9_007_199_254_740_991,
              let nonce = Int64(parts[4]), String(nonce) == parts[4],
              parts[5].range(of: #"^[A-Za-z0-9_-]{43}$"#, options: .regularExpression) != nil else { return nil }
        let expiry = Date(timeIntervalSince1970: Double(milliseconds) / 1_000)
        // The signed absolute Unix-ms expiry wins over any relative TTL. Reject clock
        // skew rather than extending the server lifetime; no service-window conversion.
        guard expiry > now, expiry <= snapshot.observedAt.addingTimeInterval(Double(ttl) / 1_000) else { return nil }
        self.code = code; nodeName = snapshot.value["nodeName"].text ?? ""
        expiresAt = expiry; acceptedAt = now; acceptedUptime = uptime
        deadlineUptime = uptime + expiry.timeIntervalSince(now)
    }

    func remainingSeconds(now: Date, uptime: TimeInterval) -> Int {
        guard now.timeIntervalSince1970.isFinite, uptime.isFinite,
              now >= acceptedAt, uptime >= acceptedUptime else { return 0 }
        let remaining = min(expiresAt.timeIntervalSince(now), deadlineUptime - uptime)
        return remaining > 0 ? Int(ceil(remaining)) : 0
    }
}

/// Deferred cleanup keeps no raw token or QR image after the display lease retires.
/// Metadata plus a fingerprint identifies only the original owner's exact receipt.
private struct MerchantStationLiveCodeCleanupIdentity {
    let scope: UUID
    let query: MerchantContentQuery
    let access: MerchantAccess
    let observedAt: Date
    let valueFingerprint: SHA256.Digest

    init?(snapshot: MerchantContentSnapshot) {
        guard let fingerprint = Self.fingerprint(snapshot.value) else { return nil }
        scope = snapshot.scope; query = snapshot.query; access = snapshot.access
        observedAt = snapshot.observedAt; valueFingerprint = fingerprint
    }
    func matches(_ snapshot: MerchantContentSnapshot) -> Bool {
        snapshot.scope == scope && snapshot.query == query && snapshot.access == access &&
        snapshot.observedAt == observedAt && Self.fingerprint(snapshot.value) == valueFingerprint
    }
    private static func fingerprint(_ value: MerchantContentValue) -> SHA256.Digest? {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value) else { return nil }
        return SHA256.hash(data: data)
    }
}

/// Binds this in-memory receipt to exactly the document which obtained it. The
/// content service remains the sole issuance/access authority; this class never loads.
@MainActor final class MerchantStationLiveCodeLease: ObservableObject {
    @Published private(set) var retired = false
    private weak var owner: MerchantContentViewModel?
    private var baseline: MerchantContentSnapshot?
    private var receipt: MerchantStationLiveCodeReceipt?
    private var cleanupIdentity: MerchantStationLiveCodeCleanupIdentity?
    private let ownerRevision: Int

    init(owner: MerchantContentViewModel, snapshot: MerchantContentSnapshot,
         now: Date = Date(), uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        self.owner = owner; ownerRevision = owner.revision; baseline = snapshot
        cleanupIdentity = MerchantStationLiveCodeCleanupIdentity(snapshot: snapshot)
        receipt = MerchantStationLiveCodeReceipt(snapshot: snapshot, now: now, uptime: uptime)
        if display(now: now, uptime: uptime) == nil { retire() }
    }

    func display(now: Date = Date(), uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) -> MerchantStationLiveCodeReceipt? {
        guard !retired, let owner, let baseline, let receipt,
              owner.revision == ownerRevision, owner.coordinator.isCurrent,
              owner.coordinator.service.isConfigured, owner.coordinator.service.isAuthenticated,
              owner.coordinator.service.scope == baseline.scope,
              owner.coordinator.query == baseline.query,
              owner.coordinator.snapshot == baseline,
              owner.coordinator.snapshot?.observedAt == baseline.observedAt,
              baseline.access.active, (baseline.access.merchantID ?? 0) > 0,
              !owner.coordinator.busy, !owner.coordinator.locked, owner.coordinator.review == nil,
              receipt.remainingSeconds(now: now, uptime: uptime) > 0 else { return nil }
        return receipt
    }

    func tick(now: Date = Date(), uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        if display(now: now, uptime: uptime) == nil { retire() }
    }

    func retire(clearOwnedSnapshot: Bool = false) {
        receipt = nil; baseline = nil; retired = true
        // Leaving this leaf/scene also drops the original raw receipt. Never clear a
        // newer load or another document. No cancellation/revocation request is sent.
        if clearOwnedSnapshot, let cleanupIdentity, let owner,
           let current = owner.coordinator.snapshot, cleanupIdentity.matches(current) {
            self.cleanupIdentity = nil
            owner.invalidate()
        }
    }
}

@MainActor struct MerchantStationLiveCodeView: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var owner: MerchantContentViewModel
    @StateObject private var lease: MerchantStationLiveCodeLease

    init(owner: MerchantContentViewModel, snapshot: MerchantContentSnapshot) {
        self.owner = owner
        _lease = StateObject(wrappedValue: MerchantStationLiveCodeLease(owner: owner, snapshot: snapshot))
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let uptime = ProcessInfo.processInfo.systemUptime
            VStack(alignment: .leading, spacing: 16) {
                if scenePhase == .active, let receipt = lease.display(now: context.date, uptime: uptime) {
                    if !receipt.nodeName.isEmpty { Text(verbatim: receipt.nodeName).font(.headline) }
                    MerchantStationLiveQRCode(code: receipt.code)
                    LabeledContent("merchant.stationLiveCode.remaining") {
                        Text(receipt.remainingSeconds(now: context.date, uptime: uptime), format: .number).monospacedDigit()
                    }
                    Text("merchant.content.liveCodeWarning").font(.footnote)
                } else {
                    Text("merchant.stationLiveCode.unavailable").accessibilityIdentifier("merchant.stationLiveCode.unavailable")
                }
                Text("merchant.stationLiveCode.refreshHint").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .privacySensitive()
        .task(id: scenePhase) {
            guard scenePhase == .active else { lease.retire(clearOwnedSnapshot: true); return }
            while !Task.isCancelled {
                lease.tick()
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { lease.retire(clearOwnedSnapshot: true) }
        }
        .onChange(of: owner.revision) { _, _ in lease.tick() }
        .onDisappear { lease.retire(clearOwnedSnapshot: true) }
        .accessibilityIdentifier("merchant.stationLiveCode.view")
    }
}

@MainActor private struct MerchantStationLiveQRCode: View {
    let code: String
    private var image: UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(code.utf8); filter.correctionLevel = "M"
        guard let output = filter.outputImage,
              let bitmap = CIContext(options: [.cacheIntermediates: false]).createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: bitmap)
    }
    var body: some View {
        if let image {
            Image(uiImage: image).resizable().interpolation(.none).scaledToFit()
                .frame(maxWidth: 280).padding(24).background(.white)
                .accessibilityLabel("merchant.stationLiveCode.image")
                .accessibilityIdentifier("merchant.stationLiveCode.qr")
        } else { Text("verificationCode.renderFailed") }
    }
}
