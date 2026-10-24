import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Parent opens the platform shell, then reads the original install receipt for the
/// same request id. The shell loads only when the shell URL and launch exist and
/// `H5ShellLoad` accepts them: same HTTPS host, and the body is the nonce.
/// A different host does not load. A page or JavaScript self-report is not installed.
/// This type does not invent a domain, a certificate, a zip, or an approval.
public struct H5ShellParentFlow: Equatable {
    public private(set) var entry: WorkshopInstallRecoverEntry
    public let requestID: String
    public private(set) var shellLoaded = false
    public private(set) var receipt: WorkshopOriginalInstallFact?
    public var opensZip: Bool { entry.opensZip }
    public var clientResultIsServerPass: Bool { entry.clientResultIsServerPass }

    public init(requestID: String, entry: WorkshopInstallRecoverEntry = WorkshopInstallRecoverEntry()) {
        self.requestID = requestID
        self.entry = entry
    }

    /// Request the existing shell loader will post. Nil means do not present or load.
    public static func loadRequest(shellURL: URL?, launch: H5LaunchDescription?) -> URLRequest? {
        guard let shellURL, let launch,
              let request = H5ShellLoad.request(shellURL: shellURL, launch: launch),
              request.httpMethod == "POST",
              let body = request.httpBody,
              let text = String(data: body, encoding: .utf8),
              let encoded = launch.nonce.addingPercentEncoding(withAllowedCharacters: .alphanumerics),
              text == "nonce=\(encoded)" else { return nil }
        return request
    }

    @discardableResult
    public mutating func open(shellURL: URL?, launch: H5LaunchDescription?) -> URLRequest? {
        let request = Self.loadRequest(shellURL: shellURL, launch: launch)
        shellLoaded = request != nil
        return request
    }

    public mutating func readOriginalReceipt(identity: WorkshopInstallIdentity,
                                            source: any WorkshopOriginalInstallReading) async throws -> WorkshopOriginalInstallFact {
        guard shellLoaded else { throw WorkshopOriginalInstallError.invalidRequest }
        let fact = try await entry.recover(requestID: requestID, identity: identity, source: source)
        guard fact.requestID == requestID else { throw WorkshopOriginalInstallError.unknown }
        receipt = fact
        return fact
    }

    /// A self-report clear is rejected. It does not install and does not replace the receipt.
    public mutating func rejectSelfReportClear() throws {
        let installed = entry.release.journey.machine.installCount
        let kept = entry.receipt
        var failure: Error?
        do {
            try entry.rejectPageClear(requestID: requestID)
        } catch {
            failure = error
        }
        do {
            try entry.rejectJavaScriptClear(requestID: requestID)
        } catch {
            if failure == nil { failure = error }
        }
        guard entry.release.journey.machine.installCount == installed, entry.receipt == kept else {
            throw WorkshopOriginalInstallError.unknown
        }
        throw failure ?? WorkshopOriginalInstallError.unknown
    }

    public func clientResultInstalled(_ payload: [String: String]) -> Bool {
        entry.recordClientResult(payload)
    }
}
