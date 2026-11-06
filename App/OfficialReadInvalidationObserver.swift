import SwiftUI

/// A view-lifetime subscription. Old readers and callbacks cannot invalidate a
/// newly bound view. It never fetches, logs in, changes a source or changes grants.
@MainActor final class OfficialReadInvalidationObserver: ObservableObject {
    @Published private(set) var revision = UUID()
    private var readerID: ObjectIdentifier?
    private var signalID: ObjectIdentifier?
    private var lifetime = UUID()
    private var subscription: OfficialReadInvalidationSubscription?
    func isBound(to reader: any OfficialEventReading) -> Bool {
        readerID == ObjectIdentifier(reader) && signalID == reader.invalidationSignal.map(ObjectIdentifier.init)
    }
    func bind(_ reader: any OfficialEventReading) {
        guard !isBound(to: reader) else { return }
        stop()
        readerID = ObjectIdentifier(reader)
        signalID = reader.invalidationSignal.map(ObjectIdentifier.init)
        let owner = lifetime
        subscription = reader.invalidationSignal?.observe { [weak self] in
            guard let self, self.lifetime == owner else { return }
            self.revision = UUID()
        }
    }
    func stop() {
        lifetime = UUID(); subscription?.cancel(); subscription = nil
        readerID = nil; signalID = nil
    }
}
