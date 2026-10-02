import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Production verification is distinct from synthetic mutation execution. This
/// transport cannot update merchant profiles, financial terms, staff or marketing.
@MainActor public final class MerchantVerificationHTTPTransport: HTTPTransport {
    public static let paths: Set<String> = ["api/verify/groupcode/redeem", "api/coupon/verification",
        "api/registration/scan_dynamic_code", "api/registration/scan_qr_code",
        "api/registration/scan_qr_code_chapter", "api/registration/scan_qr_code_station", "api/verify/citynode/redeem"]
    private let baseURL: URL
    private let transport: BusinessRuntimeTransport
    public init(baseURL: URL, transport: BusinessRuntimeTransport) { self.baseURL = baseURL; self.transport = transport }
    public func send(_ request: URLRequest) async throws -> (Data, Int) {
        guard request.httpMethod == "POST", let url = request.url,
              Self.paths.contains(where: { baseURL.appendingPathComponent($0) == url }), transport.permits(request) else { throw MerchantBusinessFailure.disabled }
        return try await transport.send(request)
    }
}
