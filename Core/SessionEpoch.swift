/// Use on one isolation domain (the main actor in the UI). Not an authorization role.
/// Captured epochs reject stale login/profile completions after logout or another login.
public struct SessionEpoch {
    private var value: UInt64 = 0
    public init() {}
    @discardableResult public mutating func advance() -> UInt64 {
        value &+= 1
        return value
    }
    public func isCurrent(_ candidate: UInt64) -> Bool { value == candidate }
}
