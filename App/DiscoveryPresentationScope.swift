import Combine

extension DiscoveryReading {
    var discoveryPresentationIdentity: String { "public-fixture" }
    var discoveryPresentationChanges: AnyPublisher<Void, Never> { Empty<Void, Never>().eraseToAnyPublisher() }
}

extension AppSession {
    /// Epoch plus viewer revision also fences same-account role/credential ABA.
    var discoveryPresentationIdentity: String { "\(sessionRevision):\(contentDetailRevision)" }
    var discoveryPresentationChanges: AnyPublisher<Void, Never> { objectWillChange.eraseToAnyPublisher() }
}
