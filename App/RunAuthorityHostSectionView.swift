import SwiftUI
#if canImport(QuestifyCore)
import QuestifyCore
#endif

/// Authoritative Run State & CAS Recovery SwiftUI Section View (`H-W03` / W03.1–W03.3).
///
/// Renders `RunAuthorityHostCoordinator` capability gate status, CAS `stateVersion`,
/// version/payload conflict recovery requirement, and pending intent idempotency status
/// using `Text(verbatim:)` throughout (0 new `.xcstrings` keys).
@MainActor
public struct RunAuthorityHostSectionView: View {
    public let coordinator: RunAuthorityHostCoordinator

    public init(coordinator: RunAuthorityHostCoordinator) {
        self.coordinator = coordinator
    }

    public var capabilityBadgeText: String {
        coordinator.isEnabled
            ? "RunAuthority Gate: ENABLED"
            : "RunAuthority Gate: DISABLED (Fail-Closed)"
    }

    public var casVersionText: String {
        "Run \(coordinator.projection.runId) • CAS v\(coordinator.projection.stateVersion)"
    }

    public var runStatusText: String {
        "Run Status: \(coordinator.projection.status.rawValue)"
    }

    public var conflictRecoveryText: String {
        switch coordinator.state {
        case .disabled:
            return "Recovery: Capability gate disabled; no run mutations permitted"
        case .ready:
            return "Recovery: In sync with authoritative state v\(coordinator.projection.stateVersion)"
        case .inFlight(let intent):
            return "Recovery: Awaiting receipt for node \(intent.nodeId) at expected v\(intent.expectedStateVersion)"
        case .unknownOutcome(let intent):
            return "Recovery: Outcome unknown — retry same requestId \(intent.requestId) or read receipt"
        case .refreshRequired(let serverVersion):
            return "Recovery: CAS conflict — refresh required from server v\(serverVersion)"
        case .rejected(let reasonCode):
            let code = reasonCode.isEmpty ? "UNSPECIFIED" : reasonCode
            return "Recovery: Server rejected action (\(code))"
        case .payloadConflict:
            return "Recovery: Payload conflict — requestId reused with mismatched intent"
        }
    }

    public var pendingIdempotencyText: String {
        if let intent = coordinator.pendingIntent {
            return "Pending Intent: \(intent.payload.kind) on \(intent.nodeId) • req \(intent.requestId) (expected v\(intent.expectedStateVersion))"
        }
        return "Pending Intent: None (idempotency queue idle)"
    }

    public var nodeSummaryText: String {
        let sortedNodes = coordinator.projection.nodes.keys.sorted()
        guard !sortedNodes.isEmpty else {
            return "Nodes: 0 tracked"
        }
        let pairs = sortedNodes.compactMap { key -> String? in
            guard let status = coordinator.projection.nodes[key] else { return nil }
            return "\(key)=\(status.rawValue)"
        }
        return "Nodes (\(pairs.count)): " + pairs.joined(separator: ", ")
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: "Authoritative Run & CAS Host")
                    .font(.headline)
                Spacer()
                Text(verbatim: capabilityBadgeText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(coordinator.isEnabled ? Color.green : Color.secondary)
                    .accessibilityIdentifier("runAuthorityHost.capabilityBadge")
            }

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(verbatim: casVersionText)
                    .font(.subheadline.monospacedDigit())
                    .accessibilityIdentifier("runAuthorityHost.casVersion")
                Spacer()
                Text(verbatim: runStatusText)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("runAuthorityHost.runStatus")
            }

            Text(verbatim: conflictRecoveryText)
                .font(.footnote)
                .foregroundStyle(conflictRecoveryTint)
                .accessibilityIdentifier("runAuthorityHost.conflictRecovery")

            Text(verbatim: pendingIdempotencyText)
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("runAuthorityHost.pendingIdempotency")

            Text(verbatim: nodeSummaryText)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("runAuthorityHost.nodeSummary")
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("runAuthorityHost.section")
    }

    private var conflictRecoveryTint: Color {
        switch coordinator.state {
        case .disabled:
            return .secondary
        case .ready:
            return .primary
        case .inFlight, .unknownOutcome, .refreshRequired:
            return .orange
        case .rejected, .payloadConflict:
            return .red
        }
    }
}
