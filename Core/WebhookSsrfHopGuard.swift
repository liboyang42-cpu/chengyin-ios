import Foundation

/// C09 exclusive per-hop webhook SSRF gate. Does not resolve DNS, open sockets,
/// or follow real redirects. Callers supply fixture resolved IPs.
public struct WebhookSsrfHopGuard: Equatable {
    public static let maxHops = 3
    public static let httpsPort = 443

    public enum Decision: String, Equatable, Sendable {
        case allow = "ALLOW"
        case rejectScheme = "REJECT_SCHEME"
        case rejectUserinfo = "REJECT_USERINFO"
        case rejectPort = "REJECT_PORT"
        case rejectUnresolved = "REJECT_UNRESOLVED"
        case rejectPrivate = "REJECT_PRIVATE"
        case rejectHopLimit = "REJECT_HOP_LIMIT"
    }

    public struct Hop: Equatable, Sendable {
        public var url: String?
        public var resolved: [String]
        public init(url: String?, resolved: [String] = []) {
            self.url = ImmutableReceiptProducer.parse(url, limit: 2048)
            self.resolved = resolved.compactMap { ImmutableReceiptProducer.parse($0, limit: 64) }
        }
        public static func of(_ url: String, _ addresses: String...) -> Hop {
            Hop(url: url, resolved: addresses)
        }
    }

    public struct HopVerdict: Equatable, Sendable {
        public var url: String?
        public var decision: Decision
        public var reason: String
        public var addresses: [String]
        public func allowed() -> Bool { decision == .allow }
        public static func allow(_ url: String?, _ addresses: [String]) -> HopVerdict {
            HopVerdict(url: url, decision: .allow, reason: "allow", addresses: addresses)
        }
        public static func reject(_ url: String?, _ decision: Decision, _ reason: String) -> HopVerdict {
            HopVerdict(url: url, decision: decision, reason: reason, addresses: [])
        }
    }

    public struct ChainVerdict: Equatable, Sendable {
        public var allowed: Bool
        public var decision: Decision
        public var reason: String
        public var hops: [HopVerdict]
        public static func allow(_ hops: [HopVerdict]) -> ChainVerdict {
            ChainVerdict(allowed: true, decision: .allow, reason: "allow", hops: hops)
        }
        public static func reject(_ decision: Decision, _ reason: String, _ hops: [HopVerdict] = []) -> ChainVerdict {
            ChainVerdict(allowed: false, decision: decision, reason: reason, hops: hops)
        }
    }

    public init() {}

    public func inspect(_ hop: Hop?) -> HopVerdict {
        guard let hop, let raw = hop.url else {
            return .reject(nil, .rejectUnresolved, "缺少跳地址")
        }
        guard let uri = URL(string: raw) else {
            return .reject(raw, .rejectUnresolved, "URL 无法解析")
        }
        guard (uri.scheme ?? "").lowercased() == "https" else {
            return .reject(raw, .rejectScheme, "只允许 https")
        }
        if uri.user != nil || uri.password != nil || raw.contains("@") {
            return .reject(raw, .rejectUserinfo, "禁止 userinfo")
        }
        if let port = uri.port, port != Self.httpsPort {
            return .reject(raw, .rejectPort, "只允许 443")
        }
        guard let host = uri.host, ImmutableReceiptProducer.parse(host, limit: 253) != nil else {
            return .reject(raw, .rejectUnresolved, "缺少 host")
        }
        let addresses = Self.resolveLocally(host: host, provided: hop.resolved)
        if addresses.isEmpty {
            return .reject(raw, .rejectUnresolved, "无夹具解析且非字面量 IP")
        }
        for address in addresses {
            if !Self.publicUnicast(address) {
                return .reject(raw, .rejectPrivate, "私网/回环/链路本地/组播")
            }
        }
        return .allow(raw, addresses)
    }

    public func inspectChain(_ hops: [Hop]?) -> ChainVerdict {
        guard let hops, !hops.isEmpty else {
            return .reject(.rejectUnresolved, "缺少跳")
        }
        if hops.count > Self.maxHops {
            return .reject(.rejectHopLimit, "超过每跳上限 \(Self.maxHops)")
        }
        var inspected: [HopVerdict] = []
        for hop in hops {
            let verdict = inspect(hop)
            inspected.append(verdict)
            if !verdict.allowed() {
                return .reject(verdict.decision, verdict.reason, inspected)
            }
        }
        return .allow(inspected)
    }

    public func assertSafeChain(_ hops: [Hop]?) throws {
        let verdict = inspectChain(hops)
        if !verdict.allowed {
            throw NotifyFailure.ssrfRejected(verdict.reason)
        }
    }

    public func recoverOriginal(originalRequestID: String, hops: [Hop]) -> ChainVerdict {
        _ = ImmutableReceiptProducer.parse(originalRequestID)
        return inspectChain(hops)
    }

    static func resolveLocally(host: String, provided: [String]) -> [String] {
        if let literal = parseIPv4Literal(host) { return [literal] }
        return provided.compactMap { parseIPv4Literal($0) ?? parseIPv6Literal($0) }
    }

    static func parseIPv4Literal(_ host: String) -> String? {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var bytes: [UInt8] = []
        for part in parts {
            guard let n = Int(part), n >= 0, n <= 255, String(n) == part else { return nil }
            bytes.append(UInt8(n))
        }
        guard bytes.count == 4 else { return nil }
        return bytes.map(String.init).joined(separator: ".")
    }

    static func parseIPv6Literal(_ host: String) -> String? {
        let trimmed = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        guard trimmed.contains(":") else { return nil }
        return trimmed
    }

    /// Public unicast only. No DNS. Matches the media-gate isolation contract.
    static func publicUnicast(_ address: String) -> Bool {
        if let v4 = parseIPv4Literal(address) {
            let parts = v4.split(separator: ".").compactMap { Int($0) }
            guard parts.count == 4 else { return false }
            let a = parts[0], b = parts[1]
            if a == 0 { return false }
            if a == 10 { return false }
            if a == 127 { return false }
            if a == 169 && b == 254 { return false }
            if a == 172 && (16...31).contains(b) { return false }
            if a == 192 && b == 168 { return false }
            if a == 100 && (64...127).contains(b) { return false }
            if a >= 224 { return false }
            return true
        }
        let v6 = address.lowercased()
        if v6 == "::1" || v6.hasPrefix("fe80:") || v6.hasPrefix("fc") || v6.hasPrefix("fd") || v6.hasPrefix("ff") {
            return false
        }
        if v6.hasPrefix("::ffff:127.") || v6.hasPrefix("::ffff:10.") || v6.hasPrefix("::ffff:192.168.") {
            return false
        }
        return v6.contains(":")
    }

    public static func publicTestNet() -> String { "203.0.113.10" }
    public static func publicHop() -> Hop {
        Hop(url: "https://hooks.example.test/c09-e", resolved: [publicTestNet()])
    }
}
