import Foundation

/// C11 exclusive support-desk locator. Reads ORIGINAL audit events only.
/// Current projection APPLIED+SUCCESS is contrast, never original success.
/// Missing unsigned originals stay WAITING_SOURCE (v12.docx / 232.pack / e2d86c4).
public enum C11SourceInventory {
    public static let waitingSource = "WAITING_SOURCE"
    public static let v12Docx = "v12.docx"
    public static let pack232 = "232.pack"
    public static let unpushedIosSHA = "e2d86c4"
    public static var v12DocxPresent: Bool { false }
    public static var pack232Present: Bool { false }
    public static var unpushedIosSHAPresent: Bool { false }
}

/// Untrusted identifiers stay Optional.none. Never coerce missing requestId to "".
public enum SupportUntrusted {
    public static func requestID(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if trimmed.count > 64 { return nil }
        return trimmed
    }

    public static func jsonValue(_ raw: String?) -> Any {
        requestID(raw).map { $0 as Any } ?? NSNull()
    }
}

/// Isolated original `business_audit_event` row. Not a Java domain type.
public struct OriginalAuditEvent: Equatable, Sendable {
    public var requestId: String?
    public var targetType: String?
    public var targetId: Int64?
    public var action: String?
    public var afterJson: String?

    public init(
        requestId: String?,
        targetType: String? = nil,
        targetId: Int64? = nil,
        action: String? = nil,
        afterJson: String? = nil
    ) {
        self.requestId = SupportUntrusted.requestID(requestId)
        self.targetType = SupportUntrusted.requestID(targetType)
        self.targetId = targetId
        self.action = SupportUntrusted.requestID(action)
        self.afterJson = SupportUntrusted.requestID(afterJson)
    }
}

public struct SupportCurrentProjection: Equatable, Sendable {
    public var requestId: String?
    public var appliedState: String?

    public init(requestId: String?, appliedState: String?) {
        self.requestId = SupportUntrusted.requestID(requestId)
        self.appliedState = appliedState
    }
}

public enum SupportLocateFailure: Error, Equatable {
    case originalMissing(requestId: String)
}

public struct LocatedEvent: Equatable, Sendable {
    public var requestId: String?
    public var originalEvents: [OriginalAuditEvent]
    public var originalOutcome: String
    public var currentProjectionClaimsSuccess: Bool
    public var runId: Int64?
    public var orderId: Int64?

    public var originalIsNotProjectionSuccess: Bool {
        originalOutcome != "SUCCESS" && originalOutcome != SupportEventLocator.projectionAppliedSuccess
    }

    public func asRequeryableView() -> [String: Any] {
        [
            "requestId": SupportUntrusted.jsonValue(requestId),
            "originalOutcome": originalOutcome,
            "runId": runId.map { $0 as Any } ?? NSNull(),
            "orderId": orderId.map { $0 as Any } ?? NSNull(),
            "originalEventCount": originalEvents.count,
            "usedCurrentProjectionAsSuccess": false,
        ]
    }
}

/// Locate by requestId against ORIGINAL audit events. Requery keeps the same original outcome.
public struct SupportEventLocator {
    public static let projectionAppliedSuccess = "APPLIED+SUCCESS"

    public protocol OriginalEventSource {
        func findByRequestId(_ requestId: String) -> [OriginalAuditEvent]
        func findByTarget(targetType: String, targetId: Int64) -> OriginalAuditEvent?
    }

    private let originalEvents: OriginalEventSource

    public init(originalEvents: OriginalEventSource) {
        self.originalEvents = originalEvents
    }

    /// Missing requestId stays Optional.none, never "".
    public func locateByRequestId(
        _ requestId: String?,
        currentProjection: SupportCurrentProjection?
    ) throws -> LocatedEvent? {
        guard let id = SupportUntrusted.requestID(requestId) else { return nil }
        let originals = originalEvents.findByRequestId(id)
        guard !originals.isEmpty else {
            throw SupportLocateFailure.originalMissing(requestId: id)
        }
        let head = originals[0]
        let outcome = Self.originalOutcome(head)
        let projectionClaims = currentProjection?.requestId == id
            && currentProjection?.appliedState == Self.projectionAppliedSuccess
        return LocatedEvent(
            requestId: id,
            originalEvents: originals,
            originalOutcome: outcome,
            currentProjectionClaimsSuccess: projectionClaims,
            runId: Self.firstTargetId(originals, targetType: "RUN"),
            orderId: Self.firstTargetId(originals, targetType: "ORDER")
        )
    }

    public func requery(
        _ requestId: String?,
        currentProjection: SupportCurrentProjection?
    ) throws -> LocatedEvent? {
        try locateByRequestId(requestId, currentProjection: currentProjection)
    }

    public func recoverOriginal(
        originalRequestID requestId: String?,
        currentProjection: SupportCurrentProjection?
    ) throws -> LocatedEvent? {
        try requery(requestId, currentProjection: currentProjection)
    }

    public func locateByRunId(
        _ runId: Int64?,
        currentProjection: SupportCurrentProjection?
    ) throws -> LocatedEvent? {
        guard let runId, runId > 0 else { return nil }
        guard let found = originalEvents.findByTarget(targetType: "RUN", targetId: runId) else {
            throw SupportLocateFailure.originalMissing(requestId: "RUN:\(runId)")
        }
        return try locateByRequestId(found.requestId, currentProjection: currentProjection)
    }

    public func locateByOrderId(
        _ orderId: Int64?,
        currentProjection: SupportCurrentProjection?
    ) throws -> LocatedEvent? {
        guard let orderId, orderId > 0 else { return nil }
        guard let found = originalEvents.findByTarget(targetType: "ORDER", targetId: orderId) else {
            throw SupportLocateFailure.originalMissing(requestId: "ORDER:\(orderId)")
        }
        return try locateByRequestId(found.requestId, currentProjection: currentProjection)
    }

    private static func originalOutcome(_ event: OriginalAuditEvent) -> String {
        if let after = SupportUntrusted.requestID(event.afterJson) { return after }
        if let action = SupportUntrusted.requestID(event.action) { return action }
        return "UNKNOWN"
    }

    private static func firstTargetId(_ events: [OriginalAuditEvent], targetType: String) -> Int64? {
        for event in events {
            if event.targetType == targetType, let targetId = event.targetId {
                return targetId
            }
        }
        return nil
    }
}
