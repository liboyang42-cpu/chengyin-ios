#if DEBUG
import SwiftUI

/// Sealed recorder under the normal AppSessionContainer/SessionRootView. No live URL or token input.
@MainActor final class CouponRuntimeFixture: ObservableObject, HTTPTransport {
    static let flag = "--uitesting-coupon-runtime"
    static let base = URL(string: "https://coupon-runtime.example/native")!
    let deployment: ReviewedAppDeployment
    let defaults: UserDefaults
    let locks: CouponManagementFileLocks
    let mode: String
    let vault = Vault()
    weak var session: AppSession?
    private var read: CouponManagementReadApproval?, write: CouponManagementWriteApproval?
    @Published private(set) var routes: [String] = []
    @Published private(set) var writes = 0
    @Published private(set) var violations: [String] = []
    private var definition: [String: Any]?
    private var status = 1
    private var couponListSeen = false
    private var couponAccessReads = 0
    @Published private(set) var pendingBeforeWrites: [Bool] = []
    @Published private(set) var publishedDates: [String] = []
    final class Vault: AppTokenStorage {
        var token: String?
        func read() throws -> String? { token }
        func write(_ token: String) throws { self.token = token }
        func clear() throws { token = nil }
    }
    static func selected(_ arguments: [String]) -> CouponRuntimeFixture? {
        guard let i = arguments.firstIndex(of: flag) else { return nil }
        let mode = arguments.indices.contains(i + 1) ? arguments[i + 1] : "readOnly"
        let journalFlag = "--coupon-runtime-journal"
        let journalID: UUID? = arguments.firstIndex(of: journalFlag).flatMap { index in
            arguments.indices.contains(index + 1) ? UUID(uuidString: arguments[index + 1]) : nil
        }
        return try! .init(mode: ["ready", "readOnly", "unknown", "revokeOnConfirm", "commandUnknown", "commandReadOnly", "commandNotFound"].contains(mode) ? mode : "readOnly", journalID: journalID ?? UUID())
    }
    init(mode: String, journalID: UUID = UUID()) throws {
        self.mode = mode
        deployment = try .init(market: .china, baseURL: Self.base.absoluteString,
            approvedBaseURLs: [.china: [Self.base.absoluteString]], verifiedCapabilities: [.domesticChinaPhone],
            bundleIdentifier: "test.coupon-normal-root", realm: "synthetic")
        defaults = UserDefaults(suiteName: "coupon-normal-root-" + UUID().uuidString)!
        locks = try .init(directory: FileManager.default.temporaryDirectory.appendingPathComponent("coupon-normal-root-" + journalID.uuidString))
    }
    func composition() -> AppCompositionRoot {
        .init(deployment: .reviewed(deployment), storage: .init(defaults: defaults, tokenStore: { [vault] _ in vault }),
            makeTransport: { self }, couponLocks: { self.locks },
            couponReadApproval: { self.grants($0); return self.read },
            couponWriteApproval: { self.grants($0); return self.write })
    }
    private func grants(_ context: RuntimeDependencyContext) {
        guard context.baseURL == Self.base, context.market == .china, context.role == "merchant",
              context.session.accountID == 7, context.session.token == "test-7",
              context.session.namespace == deployment.storageScope.service else { read?.revoke(); write?.revoke(); read = nil; write = nil; return }
        if read?.context == context { return }
        read?.revoke(); write?.revoke()
        let command: CouponCommandProtocolApproval?
        if mode.hasPrefix("command") { command = try? CouponCommandProtocolApproval(context: context, merchantID: 21, verifiedVersion: 1, expiresAt: Date().addingTimeInterval(600)) } else { command = nil }
        read = try? .init(context: context, merchantID: 21, expiresAt: Date().addingTimeInterval(600), commandProtocol: command)
        write = ["readOnly", "commandReadOnly", "commandNotFound"].contains(mode) ? nil : try? .init(context: context, merchantID: 21, actions: [.publish, .stop], expiresAt: Date().addingTimeInterval(600))
    }
    var evidence: String {
        let value: [String: Any] = ["routes": routes, "writes": writes, "violations": violations,
            "pendingBeforeWrites": pendingBeforeWrites, "publishedDates": publishedDates, "couponAccessReads": couponAccessReads,
            "account": session?.account?.id ?? 0, "pending": ((try? locks.pending(ownerKey: session?.couponManagementSession?.ownerKey ?? "", resource: "publish")) ?? nil) != nil]
        return String(decoding: try! JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]), as: UTF8.self)
    }
    private func recordPending(_ request: URLRequest, resource: String) throws {
        let pending = try locks.pending(ownerKey: session?.couponManagementSession?.ownerKey ?? "", resource: resource)
        let matches = pending?.wire?.data == request.httpBody && pending?.wire?.contentType == request.value(forHTTPHeaderField: "Content-Type") && pending != nil
        pendingBeforeWrites.append(matches)
        guard matches else { violations.append("missing-or-changed-pending"); throw APIError.invalidRequest }
    }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        guard let url = request.url, url.scheme == Self.base.scheme, url.host == Self.base.host, url.port == Self.base.port, url.path.hasPrefix("/native/"), request.httpMethod == "POST",
              url.query == nil, url.fragment == nil, request.httpBodyStream == nil else { throw APIError.invalidRequest }
        let path = String(url.path.dropFirst("/native/".count))
        let response: [String: Any]
        switch path {
        case "api/sms/send": response = ["code": 200]
        case "api/login/phone": response = ["code":200,"token":"test-7","data":["id":7,"role":"merchant"]]
        case "api/userInfo": response = ["code":200,"appUser":["userId":7,"role":"merchant"]]
        case "api/logout": response = ["code":200]
        case "api/merchant/access/me":
            if couponListSeen { couponAccessReads += 1 }
            // The real MERCHANT_OWNER policy includes PROJECT_MANAGE. Recruiting intentionally
            // keeps both existing project and marketing gates; revocation removes only coupon access.
            let permissions = ["merchant:project:manage", "merchant:marketing:read"] +
                (mode == "revokeOnConfirm" && couponAccessReads >= 2 ? [] : ["merchant:coupon:manage"]) +
                (mode.hasPrefix("command") ? ["merchant:coop:manage"] : [])
            response = ["code":200,"data":["active":true,"merchant":["id":21,"name":"Synthetic compliant merchant"],"roleCode":"MERCHANT_OWNER","permissions":permissions]]
        case "api/merchant/coop-profile":
            guard mode.hasPrefix("command"), request.httpBody == nil else { throw APIError.invalidRequest }
            response = ["code": 200, "data": ["id": 21, "memberId": 9001]]
        case "api/coupon/command-receipt":
            guard mode.hasPrefix("command"), CouponCommandReadRoute(request: request, baseURL: Self.base, merchantID: 21) != nil,
                  let owner = session?.couponManagementSession?.ownerKey,
                  let record = try locks.pending(ownerKey: owner, resource: "publish"), let command = record.command,
                  let type = request.value(forHTTPHeaderField: "Content-Type") else { throw APIError.invalidRequest }
            let expected = try AuthRequestBuilder.makeFormRequest(url: url, fields: ["requestId": command.requestID, "merchantId": "21", "scope": "MERCHANT"], token: nil, boundary: String(type.dropFirst("multipart/form-data; boundary=".count)))
            guard request.httpBody == expected.httpBody else { throw APIError.invalidRequest }
            if mode == "commandNotFound" { response = ["code": 404, "data": ["reasonCode": "COMMAND_NOT_FOUND"]] }
            else {
                response = ["code": 200, "msg": "Synthetic exact command receipt", "data": ["id": 910, "commandReceipt": ["version": 1, "requestId": command.requestID,
                    "operation": "PUBLISH", "scope": "MERCHANT", "merchantId": 21, "ownerMemberId": 9001, "actorMemberId": 7, "payloadHash": command.payloadHash,
                    "outcome": "SUCCEEDED", "reasonCode": "PUBLISHED", "couponId": 910, "couponStatusAtExecution": 1, "completedAt": "2026-10-04T22:00:00.123+08:00"]]]
            }
        case "api/merchant/marketing-home": response = ["code":200,"data":["recruiting":["items":[]]]]
        case "api/coupon/mypublishlist":
            guard CouponManagementReadRoute(request: request, baseURL: Self.base) != nil else { throw APIError.invalidRequest }
            couponListSeen = true
            var row = definition ?? ["id":710,"name":"Synthetic owned coupon","status":1]
            row["status"] = status; response = ["code":200,"data":[row]]
        case "api/coupon/publish":
            guard mode != "readOnly", let data = request.httpBody,
                  var value = try JSONSerialization.jsonObject(with: data) as? [String: Any], value["scope"] as? String == "MERCHANT" else { throw APIError.invalidRequest }
            try recordPending(request, resource: "publish")
            publishedDates = [(value["startTime"] as? String) ?? "", (value["endTime"] as? String) ?? ""]
            writes += 1; value["id"] = 910; value["status"] = 1; definition = value
            routes.append(path)
            if mode == "unknown" || mode == "commandUnknown" { throw URLError(.timedOut) }
            return (try JSONSerialization.data(withJSONObject: ["code":200,"msg":"Synthetic server acknowledgement","data":["id":910]]),200)
        case "api/coupon/stop":
            let ownedID = (definition?["id"] as? Int) ?? 710
            let prefix = "multipart/form-data; boundary="
            guard mode != "readOnly", let body = request.httpBody,
                  let type = request.value(forHTTPHeaderField: "Content-Type"), type.hasPrefix(prefix) else { throw APIError.invalidRequest }
            let expected = try AuthRequestBuilder.makeFormRequest(url: url,
                fields: ["couponId": String(ownedID), "scope": "MERCHANT"], token: "test-7",
                boundary: String(type.dropFirst(prefix.count)))
            guard expected.httpBody == body else { throw APIError.invalidRequest }
            try recordPending(request, resource: "stop:\(ownedID)")
            writes += 1; status = 4; response = ["code":200,"msg":"Synthetic stop acknowledgement"]
        default: violations.append(path); throw APIError.notConfigured
        }
        routes.append(path)
        return (try JSONSerialization.data(withJSONObject: response), 200)
    }
}
@MainActor struct CouponRuntimeEvidence: View {
    @ObservedObject var fixture: CouponRuntimeFixture
    @ObservedObject var session: AppSession
    @Environment(\.locale) private var locale
    var body: some View {
        Text(verbatim: locale.language.languageCode?.identifier == "zh" ? "合成优惠券运行记录" : "Synthetic coupon runtime")
            .font(.caption2).frame(maxWidth: .infinity).background(.regularMaterial)
            .accessibilityIdentifier("couponRuntime.evidence")
            .accessibilityValue(Text(verbatim: fixture.evidence))
    }
}
#endif
