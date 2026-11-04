import Foundation

/// Bound display identity for an original stored result. Current publications are never substituted.
public enum MerchantGamePlayerReceipt {
    public static func canAcknowledge(_ result: MerchantGamePlayerOriginal, record: OperationPendingRecord, merchantID: Int) -> Bool {
        // Match the existing writer: retryable outcomes retain the original
        // request lock, even when their displayed status is FAILED or REJECTED.
        result.terminal && !result.retryable && result.merchantID == merchantID && result.requestID == record.operationID
    }
}
