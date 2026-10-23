import Foundation

/// Exclusive C07 projection: invoice file / history reread.
/// Application history is not a file. Missing file is UNKNOWN and must not mint
/// a new requestId. Current projection is not original file success.
public enum InvoiceFileStatus: String, Equatable, Sendable {
    case present = "PRESENT"
    case unknown = "UNKNOWN"
}

public enum InvoiceHistoryKnown {
    public static let submitted = "SUBMITTED"
    public static let issued = "ISSUED"
    public static let manualProvider = "MANUAL"
}

public struct InvoiceApplicationFact: Equatable, Sendable {
    public let originalRequestID: String?
    public let status: String?
    public let invoiceNo: String?
    public let fileLocator: String?
    public let provider: String?
    public init(originalRequestID: String?, status: String?, invoiceNo: String?,
                fileLocator: String?, provider: String?) {
        self.originalRequestID = InvoiceHistoryUnknownProjection.parse(originalRequestID)
        self.status = InvoiceHistoryUnknownProjection.parse(status)
        self.invoiceNo = InvoiceHistoryUnknownProjection.parse(invoiceNo)
        self.fileLocator = InvoiceHistoryUnknownProjection.parse(fileLocator)
        self.provider = InvoiceHistoryUnknownProjection.parse(provider)
    }
}

public struct InvoiceHistoryView: Equatable, Sendable {
    public let originalRequestID: String?
    public let fileStatus: InvoiceFileStatus
    public let startedNewApply: Bool
    public let applicationStatus: String?
    public let historyIsNotAFile: Bool
    public let currentProjectionIsOriginalFileSuccess: Bool
    public func jsonObject() -> [String: Any] {
        [
            "originalRequestID": originalRequestID.map { $0 as Any } ?? NSNull(),
            "fileStatus": fileStatus.rawValue,
            "startedNewApply": startedNewApply,
            "applicationStatus": applicationStatus.map { $0 as Any } ?? NSNull(),
            "historyIsNotAFile": historyIsNotAFile,
            "currentProjectionIsOriginalFileSuccess": currentProjectionIsOriginalFileSuccess
        ]
    }
}

public struct InvoiceHistoryUnknownProjection: Equatable {
    public private(set) var originalByRequestID: [String: InvoiceHistoryView] = [:]
    public init() {}
    public static func parse(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 64 else { return nil }
        return trimmed
    }
    public mutating func reread(_ fact: InvoiceApplicationFact?) -> InvoiceHistoryView {
        let view = compute(fact)
        if let requestID = view.originalRequestID, originalByRequestID[requestID] == nil {
            originalByRequestID[requestID] = view
        }
        return view
    }
    public mutating func requery(_ fact: InvoiceApplicationFact?) -> InvoiceHistoryView {
        reread(fact)
    }
    public func recoverOriginal(originalRequestID: String) -> InvoiceHistoryView {
        let requestID = Self.parse(originalRequestID)
        if let requestID, let original = originalByRequestID[requestID] {
            return original
        }
        return Self.unknown(requestID, nil)
    }
    /// Current projection claiming file success does not replace an UNKNOWN original.
    public func originalUnknownNotReplacedByProjectionSuccess(_ original: InvoiceHistoryView,
                                                              projectionClaimsFileSuccess: Bool) -> Bool {
        if original.fileStatus == .unknown { return true }
        if !projectionClaimsFileSuccess { return true }
        return !original.currentProjectionIsOriginalFileSuccess
    }
    private func compute(_ fact: InvoiceApplicationFact?) -> InvoiceHistoryView {
        guard let fact else { return Self.unknown(nil, nil) }
        let requestID = fact.originalRequestID
        guard let requestID else { return Self.unknown(nil, fact.status) }
        if fact.provider == InvoiceHistoryKnown.manualProvider || fact.fileLocator == nil {
            return InvoiceHistoryView(originalRequestID: requestID, fileStatus: .unknown,
                                      startedNewApply: false, applicationStatus: fact.status,
                                      historyIsNotAFile: true,
                                      currentProjectionIsOriginalFileSuccess: false)
        }
        if fact.status == InvoiceHistoryKnown.issued, fact.fileLocator != nil {
            return InvoiceHistoryView(originalRequestID: requestID, fileStatus: .present,
                                      startedNewApply: false, applicationStatus: fact.status,
                                      historyIsNotAFile: true,
                                      currentProjectionIsOriginalFileSuccess: false)
        }
        return InvoiceHistoryView(originalRequestID: requestID, fileStatus: .unknown,
                                  startedNewApply: false, applicationStatus: fact.status,
                                  historyIsNotAFile: true,
                                  currentProjectionIsOriginalFileSuccess: false)
    }
    private static func unknown(_ requestID: String?, _ status: String?) -> InvoiceHistoryView {
        InvoiceHistoryView(originalRequestID: requestID, fileStatus: .unknown,
                           startedNewApply: false, applicationStatus: status,
                           historyIsNotAFile: true,
                           currentProjectionIsOriginalFileSuccess: false)
    }
}
