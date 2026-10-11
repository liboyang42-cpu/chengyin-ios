import Foundation
import Combine

/// One explicitly requested supplementary merchant read. The already loaded node
/// stays in the detail view; this object never reloads it or performs mutations.
@MainActor final class RoamMerchantDetailRetryModel: ObservableObject {
    @Published private(set) var isLoading = false
    private let owner = ManualMapReadTaskOwner()
    private var generation = UUID()

    @discardableResult func retry(merchantID: Int, reader: any RoamReading,
                                 isCurrent: @escaping @MainActor () -> Bool,
                                 completion: @escaping @MainActor (Result<RoamMerchantDetail, Error>) -> Void) -> Bool {
        guard merchantID > 0, !isLoading, !Task.isCancelled, isCurrent() else { return false }
        generation = UUID()
        let captured = generation
        isLoading = true
        owner.start { [weak self] in
            guard let self else { return }
            defer { if self.generation == captured { self.isLoading = false } }
            guard !Task.isCancelled, self.generation == captured, isCurrent() else { return }
            do {
                let detail = try await reader.roamMerchantDetail(id: merchantID)
                try Task.checkCancellation()
                guard self.generation == captured, isCurrent() else { return }
                guard detail.merchant.id == merchantID else { throw APIError.malformedResponse }
                completion(.success(detail))
            } catch is CancellationError {
                // Closing or replacing the presentation is not a visible read failure.
            } catch {
                guard !Task.isCancelled, self.generation == captured, isCurrent() else { return }
                completion(.failure(error))
            }
        }
        return true
    }
    func cancel() {
        generation = UUID(); owner.cancel(); isLoading = false
    }
}
