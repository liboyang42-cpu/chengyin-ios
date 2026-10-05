#if DEBUG
import Foundation
import Observation

/// Offline test seam, visibly labelled as synthetic. Does not mount MapKit or fetch tiles.
@MainActor @Observable final class PrivateHomeFixtureMapAdapter: PrivateHomeMapPointPicking {
    enum Choice: String, CaseIterable { case valid, alternate, unknown, gcj02, precision, outOfRange }
    static let source = PrivateHomeMapSource(providerID: "synthetic.private-home", region: "ZZ", datum: .wgs84, contractRevision: "fixture-only-1")
    var approvedSource: PrivateHomeMapSource? = PrivateHomeFixtureMapAdapter.source
    private(set) var starts = 0
    private(set) var cancellations = 0
    private(set) var emissions = 0
    var replaceOwner: (() -> Void)?
    private var receive: ((PrivateHomeMapCandidate) -> Void)?
    private var cancelledReceive: ((PrivateHomeMapCandidate) -> Void)?
    func start(receive: @escaping (PrivateHomeMapCandidate) -> Void) { starts += 1; self.receive = receive }
    func cancel() { cancellations += 1; if let receive { cancelledReceive = receive }; receive = nil }
    func emitCancelledCandidate() { cancelledReceive?(Self.candidate(.valid)) }
    func select(_ choice: Choice) { emissions += 1; receive?(Self.candidate(choice)) }
    static func candidate(_ choice: Choice) -> PrivateHomeMapCandidate {
        switch choice {
        case .valid: return .init(latitude: "12.345678", longitude: "45.678901", source: source)
        case .alternate: return .init(latitude: "-12.345678", longitude: "-45.678901", source: source)
        case .unknown: return .init(latitude: "12.345678", longitude: "45.678901", source: nil)
        case .gcj02: return .init(latitude: "12.345678", longitude: "45.678901", source: .init(providerID: source.providerID, region: "ZZ", datum: .gcj02, contractRevision: source.contractRevision))
        case .precision: return .init(latitude: "12.3456789", longitude: "45.678901", source: source)
        case .outOfRange: return .init(latitude: "91", longitude: "45", source: source)
        }
    }
}
#endif
