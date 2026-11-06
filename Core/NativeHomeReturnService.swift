import Foundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Independent, revocable reviewed grant. Never inferred from login or PrivateHome read access.
@available(macOS 14.0, *) @MainActor @Observable public final class NativeHomeReturnApproval {
    public let context: RuntimeDependencyContext
    public let revision = UUID()
    public let expiresAt: Date
    public private(set) var revoked = false
    public init(context: RuntimeDependencyContext, expiresAt: Date) throws {
        _ = try APIConfiguration(baseURL: context.baseURL)
        guard context.market == .china, ["player", "club", "merchant"].contains(context.role),
              context.role.utf8.elementsEqual(context.session.role.utf8),
              context.session.accountID > 0, AuthRequestBuilder.isValidToken(context.session.token),
              expiresAt > Date(), expiresAt.timeIntervalSinceNow <= 86400 else { throw NativeHomeReturnFailure.disabled }
        self.context = context; self.expiresAt = expiresAt
    }
    public func revoke() { revoked = true }
    public func matches(_ value: RuntimeDependencyContext) -> Bool {
        !revoked && Date() < expiresAt && context.market == value.market &&
        context.baseURL.absoluteString.utf8.elementsEqual(value.baseURL.absoluteString.utf8) &&
        context.role.utf8.elementsEqual(value.role.utf8) &&
        value.role.utf8.elementsEqual(value.session.role.utf8) && context.session == value.session
    }
}

/// Six exact native routes. Owner is exclusively the authenticated token, never a body/query field.
@available(macOS 14.0, *) @MainActor public final class NativeHomeReturnService: NativeHomeReturnRunServing {
    public static let path = "api/native/home/return"
    private let approval: NativeHomeReturnApproval
    private let transport: any HTTPTransport
    private let current: () -> RuntimeDependencyContext?
    private let selected: (RuntimeDependencyContext) -> NativeHomeReturnApproval?
    public init(approval: NativeHomeReturnApproval, transport: any HTTPTransport,
                current: @escaping () -> RuntimeDependencyContext?, selected: @escaping (RuntimeDependencyContext) -> NativeHomeReturnApproval?) {
        self.approval = approval; self.transport = transport; self.current = current; self.selected = selected
    }
    public func isCurrent() -> Bool {
        guard let value = current(), approval.matches(value), let live = selected(value) else { return false }
        return live.revision == approval.revision && live.matches(value)
    }
    public func runs(beforeRunId: String? = nil) async throws -> NativeHomeReturnRuns {
        guard beforeRunId.map(NativeHomeResourceScope.decimalID) ?? true else { throw NativeHomeReturnFailure.invalid }
        let query: [URLQueryItem] = beforeRunId.map { [.init(name: "beforeRunId", value: $0)] } ?? []
        let value: NativeHomeReturnRuns = try await required("runs", query: query); try value.validate(); return value
    }
    public func policy() async throws -> NativeHomeReturnPolicy? {
        let value: NativeHomeReturnPolicy = try await required("policy"); try value.validate(); return value
    }
    public func account(for scope: NativeHomeResourceScope) async throws -> NativeHomeResourceAccount {
        try scope.validateNative()
        let value: NativeHomeResourceAccount = try await required("account", query: [.init(name: "runId", value: scope.wire["scopeId"])])
        try value.validate(for: scope)
        guard value.current > 0 else { throw NativeHomeReturnFailure.runUnavailable }; return value
    }
    public func verify(_ check: NativeHomeReturnCheck) async throws -> NativeHomeReturnVerification {
        try check.scope.validateNative()
        guard let fix = check.fix, let version = check.expectedAccountVersion, ReformWire.version(version),
              ReformWire.version(check.homeVersion), ReformWire.requestID(check.requestId),
              ReformWire.label(check.policyVersion, limit: 64), check.challengeId.map(ReformWire.id) ?? true else { throw NativeHomeReturnFailure.invalid }
        var body: [String: Any] = ["requestId": check.requestId, "homeVersion": check.homeVersion,
            "expectedAccountVersion": version, "scopeType": "RUN", "scopeId": check.scope.wire["scopeId"]!,
            "resourceType": "sys.hp", "policyVersion": check.policyVersion, "latitude": try NativeHomeReturnFix.wireNumber(fix.latitude, rounding: .plain),
            "longitude": try NativeHomeReturnFix.wireNumber(fix.longitude, rounding: .plain), "datum": "WGS84",
            "accuracyMeters": try NativeHomeReturnFix.wireNumber(fix.accuracyMeters, rounding: .up),
            "capturedAtMillis": Int64(fix.capturedAt.timeIntervalSince1970 * 1000)]
        if let challenge = check.challengeId { body["challengeId"] = challenge }
        let value: NativeHomeReturnVerification = try await required("verify", body: JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]))
        // Decision-specific proof/challenge checks are also performed by the coordinator.
        try value.validateIdentity(for: check)
        return value
    }
    public func restore(_ request: NativeHomeRestoreRequest) async throws -> NativeHomeRestoreReceipt {
        try request.validateNative()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let value: NativeHomeRestoreReceipt = try await required("restore", body: encoder.encode(request))
        try value.validate(for: request); return value
    }
    public func restoreReceipt(for request: NativeHomeRestoreRequest) async throws -> NativeHomeRestoreReceipt? {
        try request.validateNative()
        let value: NativeHomeRestoreReceipt? = try await execute("receipt", query: [.init(name: "requestId", value: request.requestId)])
        try value?.validate(for: request); return value
    }
    private struct Envelope<T: Decodable>: Decodable {
        let code: Int; let data: T?; let msg: String?
        enum CodingKeys: String, CodingKey { case code, data, msg }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            code = try c.decode(Int.self, forKey: .code)
            // AjaxResult.success(null) may omit data entirely, notably for an absent receipt.
            data = try c.decodeIfPresent(T.self, forKey: .data)
            msg = try c.decodeIfPresent(String.self, forKey: .msg)
        }
    }
    private func required<T: Decodable>(_ suffix: String, query: [URLQueryItem] = [], body: Data? = nil) async throws -> T {
        guard let value: T = try await execute(suffix, query: query, body: body) else { throw NativeHomeReturnFailure.invalid }
        return value
    }
    /// Only fixed server reason codes are mapped. Raw text is never shown or logged.
    private static func failure(status: Int, code: Int, message: String?) -> NativeHomeReturnFailure {
        if status == 401 || status == 403 || code == 401 || code == 403 { return .disabled }
        switch message {
        case "HOME_RUN_NOT_FOUND", "HOME_RUN_UNAVAILABLE", "HOME_RUN_NOT_ALLOWED", "HOME_RUN_BUSY", "HOME_RETURN_VERSION_CONFLICT": return .runUnavailable
        case "HOME_RETURN_CHALLENGE_EXPIRED", "HOME_RETURN_VERIFICATION_EXPIRED": return .proofExpired
        case "HOME_RETURN_POLICY_CHANGED", "HOME_RETURN_NOT_APPROVED", "PRIVATE_HOME_NOT_APPROVED": return .disabled
        default:
            if (status == 400 || code == 400), message?.hasPrefix("INVALID_HOME_") == true { return .invalid }
            return .network
        }
    }
    private func execute<T: Decodable>(_ suffix: String, query: [URLQueryItem] = [], body: Data? = nil) async throws -> T? {
        guard isCurrent() else { throw NativeHomeReturnFailure.disabled }; try Task.checkCancellation()
        guard var url = URLComponents(url: approval.context.baseURL.appendingPathComponent(Self.path + "/" + suffix), resolvingAgainstBaseURL: false) else { throw NativeHomeReturnFailure.invalid }
        if !query.isEmpty { url.queryItems = query }
        guard let endpoint = url.url else { throw NativeHomeReturnFailure.invalid }
        var request = URLRequest(url: endpoint)
        request.httpMethod = body == nil ? "GET" : "POST"; request.httpBody = body
        request.cachePolicy = .reloadIgnoringLocalCacheData; request.timeoutInterval = 30
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(approval.context.session.token, forHTTPHeaderField: "Authorization")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, status) = try await transport.send(request)
        guard isCurrent() else { throw NativeHomeReturnFailure.disabled }; try Task.checkCancellation()
        guard data.count <= 65_536 else { throw NativeHomeReturnFailure.network }
        if status == 401 || status == 403 { throw NativeHomeReturnFailure.disabled }
        if (200..<300).contains(status) {
            // Validate the original envelope before Foundation can collapse duplicate identity/decision keys.
            // Reuse the bounded grammar parser; keep the original bytes for typed decoding.
            guard let text = String(data: data, encoding: .utf8),
                  let root = try? ContentDraftJSON.parse(text), case .object = root else { throw NativeHomeReturnFailure.invalid }
        }
        let value = try JSONDecoder().decode(Envelope<T>.self, from: data)
        guard (200..<300).contains(status), value.code == 200 else {
            throw Self.failure(status: status, code: value.code, message: value.msg)
        }
        return value.data
    }
}

/// Dedicated final-forward boundary. It cannot inherit home CRUD or general read permissions.
/// The AppSession-provided current closure also captures its viewer revision, including role ABA.
@available(macOS 14.0, *) @MainActor public final class NativeHomeReturnTransport: HTTPTransport {
    private let approval: NativeHomeReturnApproval
    private let underlying: any HTTPTransport
    private let current: () -> RuntimeDependencyContext?
    private let selected: (RuntimeDependencyContext) -> NativeHomeReturnApproval?
    public init(approval: NativeHomeReturnApproval, underlying: any HTTPTransport,
        current: @escaping () -> RuntimeDependencyContext?,
        selected: @escaping (RuntimeDependencyContext) -> NativeHomeReturnApproval?) {
        self.approval = approval; self.underlying = underlying; self.current = current; self.selected = selected
    }
    private func isCurrent() -> Bool {
        guard let context = current(), approval.matches(context), let live = selected(context) else { return false }
        return live.revision == approval.revision && live.matches(context)
    }
    public func send(_ request: URLRequest) async throws -> (Data, Int) {
        try Task.checkCancellation()
        guard isCurrent(), accepts(request) else { throw NativeHomeReturnFailure.disabled }
        let result = try await underlying.send(request)
        try Task.checkCancellation()
        guard isCurrent() else { throw NativeHomeReturnFailure.disabled }
        return result
    }
    private func accepts(_ request: URLRequest) -> Bool {
        guard request.httpBodyStream == nil,
              request.value(forHTTPHeaderField: "Authorization")?.utf8.elementsEqual(approval.context.session.token.utf8) == true,
              request.cachePolicy == .reloadIgnoringLocalCacheData,
              request.value(forHTTPHeaderField: "Cache-Control") == "no-store",
              request.value(forHTTPHeaderField: "Pragma") == "no-cache",
              let url = request.url, var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.user == nil, components.password == nil, components.fragment == nil else { return false }
        let query = components.queryItems ?? []
        components.query = nil
        guard let bare = components.url?.absoluteString,
              let suffix = ["policy", "runs", "account", "receipt", "verify", "restore"].first(where: {
                  bare.utf8.elementsEqual(approval.context.baseURL.appendingPathComponent(NativeHomeReturnService.path + "/" + $0).absoluteString.utf8)
              }) else { return false }
        func single(_ name: String, _ valid: (String) -> Bool) -> Bool {
            query.count == 1 && query[0].name == name && query[0].value.map(valid) == true
        }
        switch suffix {
        case "policy": return request.httpMethod == "GET" && request.httpBody == nil && query.isEmpty
        case "runs": return request.httpMethod == "GET" && request.httpBody == nil &&
            (query.isEmpty || single("beforeRunId", NativeHomeResourceScope.decimalID))
        case "account": return request.httpMethod == "GET" && request.httpBody == nil && single("runId", NativeHomeResourceScope.decimalID)
        case "receipt": return request.httpMethod == "GET" && request.httpBody == nil && single("requestId", Self.id)
        default: break
        }
        guard request.httpMethod == "POST", query.isEmpty,
              request.value(forHTTPHeaderField: "Content-Type") == "application/json",
              let body = request.httpBody, body.count <= 4096,
              let fields = NativeHomeReturnFlatJSON.parse(body),
              let object = try? JSONSerialization.jsonObject(with: body), let value = object as? [String: Any],
              value["scopeType"] as? String == "RUN", value["resourceType"] as? String == "sys.hp",
              let run = value["scopeId"] as? String, NativeHomeResourceScope.decimalID(run),
              let requestID = value["requestId"] as? String, Self.id(requestID) else { return false }
        if suffix == "restore" {
            guard Set(value.keys) == Set(["requestId", "proofId", "homeVersion", "expectedAccountVersion", "scopeType", "scopeId", "resourceType"]),
                  let proof = value["proofId"] as? String, Self.id(proof),
                  fields["homeVersion"]?.isInteger == true, fields["expectedAccountVersion"]?.isInteger == true,
                  (try? JSONDecoder().decode(NativeHomeRestoreRequest.self, from: body)) != nil else { return false }
            return true
        }
        var keys = Set(["requestId", "homeVersion", "expectedAccountVersion", "scopeType", "scopeId", "resourceType", "policyVersion", "latitude", "longitude", "datum", "accuracyMeters", "capturedAtMillis"])
        if value["challengeId"] != nil {
            guard let challenge = value["challengeId"] as? String, Self.id(challenge) else { return false }
            keys.insert("challengeId")
        }
        guard Set(value.keys) == keys, value["datum"] as? String == "WGS84",
              let policy = value["policyVersion"] as? String, Self.id(policy),
              ["homeVersion", "expectedAccountVersion", "capturedAtMillis"].allSatisfy({ fields[$0]?.isInteger == true }),
              ["latitude", "longitude", "accuracyMeters"].allSatisfy({ fields[$0]?.hasServerScale == true }),
              let wire = try? JSONDecoder().decode(VerifyWire.self, from: body),
              ReformWire.version(wire.homeVersion), ReformWire.version(wire.expectedAccountVersion),
              wire.capturedAtMillis >= 0, wire.latitude.isFinite, (-90...90).contains(wire.latitude),
              wire.longitude.isFinite, (-180...180).contains(wire.longitude),
              wire.accuracyMeters.isFinite, wire.accuracyMeters >= 0 else { return false }
        return true
    }
    private struct VerifyWire: Decodable {
        let homeVersion, expectedAccountVersion, capturedAtMillis: Int64
        let latitude, longitude, accuracyMeters: Double
    }
    private static func id(_ value: String) -> Bool {
        value.range(of: "\\A[A-Za-z0-9._:-]{1,64}\\z", options: .regularExpression) != nil
    }
}

/// Strict flat request grammar. Numeric scale is checked from original tokens, never rounded Double.
/// These six routes have no nested, boolean or null request fields. Duplicate decoded keys fail closed.
private enum NativeHomeReturnFlatJSON {
    enum Value {
        case string, number(String)
        var isInteger: Bool {
            guard case .number(let token) = self else { return false }
            return !token.contains(".") && !token.lowercased().contains("e")
        }
        var hasServerScale: Bool {
            guard case .number(let token) = self else { return false }
            let parts = token.lowercased().split(separator: "e", omittingEmptySubsequences: false)
            guard parts.count <= 2 else { return false }
            let exponent: Int
            if parts.count == 2 {
                guard let parsed = Int(parts[1]) else { return false }; exponent = parsed
            } else { exponent = 0 }
            let coefficient = String(parts[0]).replacingOccurrences(of: "-", with: "")
            let decimal = coefficient.split(separator: ".", omittingEmptySubsequences: false)
            let digits = coefficient.filter { $0 != "." }
            if digits.allSatisfy({ $0 == "0" }) { return true }
            let fractional = decimal.count == 2 ? decimal[1].count : 0
            let trailing = digits.reversed().prefix(while: { $0 == "0" }).count
            let (scale, overflow) = (fractional - trailing).subtractingReportingOverflow(exponent)
            return !overflow && scale <= 6
        }
    }
    static func parse(_ data: Data) -> [String: Value]? {
        let bytes = Array(data); var index = 0
        func whitespace() { while index < bytes.count && [UInt8(9), 10, 13, 32].contains(bytes[index]) { index += 1 } }
        func take(_ byte: UInt8) -> Bool {
            guard index < bytes.count && bytes[index] == byte else { return false }; index += 1; return true
        }
        func string() -> String? {
            let start = index
            guard take(34) else { return nil }
            while index < bytes.count {
                let byte = bytes[index]; index += 1
                if byte == 34 { return try? JSONDecoder().decode(String.self, from: Data(bytes[start..<index])) }
                if byte == 92 {
                    guard index < bytes.count else { return nil }
                    index += 1 // Decoder validates the complete escape and UTF-8 sequence.
                }
            }
            return nil
        }
        func number() -> String? {
            let start = index
            _ = take(45)
            if !take(48) {
                guard index < bytes.count && (49...57).contains(bytes[index]) else { return nil }
                while index < bytes.count && (48...57).contains(bytes[index]) { index += 1 }
            }
            if take(46) {
                let digits = index
                while index < bytes.count && (48...57).contains(bytes[index]) { index += 1 }
                guard digits < index else { return nil }
            }
            if take(101) || take(69) {
                if !take(43) { _ = take(45) }
                let digits = index
                while index < bytes.count && (48...57).contains(bytes[index]) { index += 1 }
                guard digits < index else { return nil }
            }
            return String(bytes: bytes[start..<index], encoding: .utf8)
        }
        whitespace(); guard take(123) else { return nil }; whitespace()
        var values: [String: Value] = [:]
        if take(125) { whitespace(); return index == bytes.count ? values : nil }
        while index < bytes.count {
            guard let key = string(), values[key] == nil else { return nil }
            whitespace(); guard take(58) else { return nil }; whitespace()
            if index < bytes.count && bytes[index] == 34 {
                guard string() != nil else { return nil }; values[key] = .string
            } else {
                guard let token = number() else { return nil }; values[key] = .number(token)
            }
            whitespace()
            if take(125) { whitespace(); return index == bytes.count ? values : nil }
            guard take(44) else { return nil }; whitespace()
        }
        return nil
    }
}
