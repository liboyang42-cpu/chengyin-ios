/// Main-actor-owned operation gate. Opening/closing a login sheet must not cancel bootstrap.
public struct SessionOperationGate {
    public enum Kind: Equatable { case bootstrap, login }
    private var epoch=SessionEpoch()
    public private(set) var activeKind: Kind?
    public init() {}
    public var currentStamp: UInt64 { epoch.currentStamp }
    public mutating func begin(_ kind:Kind) -> UInt64 {
        activeKind=kind
        return epoch.advance()
    }
    public func isCurrent(_ stamp:UInt64) -> Bool { epoch.isCurrent(stamp) }
    public mutating func finish(_ stamp:UInt64) {
        if epoch.isCurrent(stamp) { activeKind=nil }
    }
    @discardableResult public mutating func cancelLogin() -> Bool {
        guard activeKind == .login else { return false }
        invalidate()
        return true
    }
    public mutating func invalidate() { epoch.advance();activeKind=nil }
}
