/// A one-shot delivery gate for an untrusted, unmodified scanner payload.
///
/// Validation belongs to the receiving feature. In particular, accepting text here
/// does not authorize opening a URL, redeeming a code, or writing to a service.
struct ScanPayloadGate {
    private(set) var isFinished = false

    mutating func take(_ payload: String?) -> String? {
        guard !isFinished, let payload, !payload.isEmpty else { return nil }
        isFinished = true
        return payload
    }

    mutating func cancel() {
        isFinished = true
    }
}
