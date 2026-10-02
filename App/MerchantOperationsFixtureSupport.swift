#if DEBUG
import SwiftUI

@MainActor
struct MerchantOperationsFixtureHostView: View {
    @State private var reader: MerchantOperationsFixtureReader
    @State private var revision = 0
    init() {
        let reader = MerchantOperationsFixtureReader(), args = ProcessInfo.processInfo.arguments
        if args.contains("--merchant-operations-denied") { reader.denied = true }
        if args.contains("--merchant-operations-failure") { reader.failure = .httpStatus(503) }
        if args.contains("--merchant-operations-unknown") { reader.saveFailure = .outcomeUnknown }
        if args.contains("--merchant-operations-rejected") { reader.saveFailure = .rejected(code: 422, message: "Synthetic content review rejected this text") }
        _reader = State(initialValue: reader)
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("merchant.operations.fixture.signOut") { reader.signOut(); revision += 1 }.accessibilityIdentifier("merchant.operations.fixture.signOut")
                Button("merchant.operations.fixture.recover") { reader.failure = nil; revision += 1 }.accessibilityIdentifier("merchant.operations.fixture.recover")
            }.font(.caption).padding(8)
            NavigationStack { MerchantOperationsHomeView(reader: reader) }.id(revision)
        }
    }
}
#endif
