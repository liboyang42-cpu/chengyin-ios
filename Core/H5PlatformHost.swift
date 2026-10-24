import Foundation

/// Platform-owned H5 shell. It checks the message envelope and does not treat a
/// client result as a server pass. A missing one-time launch ticket blocks only
/// the shell load. The main session token is never accepted here.
public struct H5LaunchDescription: Equatable {
    public let parentOrigin: String
    public let nonce: String

    public init?(parentOrigin: String, nonce: String, mainToken: String?) {
        let token = mainToken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard token.isEmpty, !nonce.isEmpty, nonce.count <= 128,
              let url = URL(string: parentOrigin), url.scheme == "https",
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else { return nil }
        self.parentOrigin = parentOrigin
        self.nonce = nonce
    }
}

public enum H5HostOutcome: Equatable {
    case waitingLaunchTicket
    case shellReady
    case progressStoredNonAuthoritative
    case resultSubmitted
    case closed
    case rejected(String)

    public var capabilityText: String {
        switch self {
        case .waitingLaunchTicket: return "h5.launchTicket"
        case .shellReady: return "h5.shellReady"
        case .progressStoredNonAuthoritative: return "h5.progressStored"
        case .resultSubmitted: return "h5.submitted"
        case .closed: return "h5.closed"
        case .rejected(let reason): return reason
        }
    }
}

public struct H5PlatformHost: Equatable {
    public private(set) var shellReady = false
    public private(set) var passed = false
    private var nextSequence = 1

    public init() {}

    public mutating func open(admitted: Bool, launch: H5LaunchDescription?) -> H5HostOutcome {
        guard admitted else { return .rejected("h5.notAdmitted") }
        guard launch != nil else { return .waitingLaunchTicket }
        shellReady = true
        passed = false
        nextSequence = 1
        return .shellReady
    }

    public mutating func receive(protocolVersion: String, requestID: String, sequence: Int,
                                 method: String, payload: [String: String]) -> H5HostOutcome {
        guard shellReady else { return .rejected("h5.notReady") }
        guard protocolVersion == "1.0", UUID(uuidString: requestID) != nil, sequence == nextSequence else {
            return .rejected("h5.invalid")
        }
        switch method {
        case "runtime.ready":
            nextSequence += 1
            return .shellReady
        case "progress.save":
            nextSequence += 1
            return .progressStoredNonAuthoritative
        case "result.submit":
            if payload["score"] != nil || payload["rewardId"] != nil || payload["userId"] != nil {
                return .rejected("h5.resultRejected")
            }
            nextSequence += 1
            passed = false
            return .resultSubmitted
        case "runtime.close":
            nextSequence += 1
            shellReady = false
            return .closed
        default:
            return .rejected("h5.methodForbidden")
        }
    }
}
