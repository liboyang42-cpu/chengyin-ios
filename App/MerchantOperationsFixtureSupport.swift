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
        if args.contains("--merchant-template-browser-pages") { try? reader.configureTemplateBrowserFixture() }
        if args.contains("--merchant-template-browser-empty") { try? reader.configureTemplateBrowserFixture(count: 0) }
        if args.contains("--merchant-template-browser-first-failure") { reader.templatePageFailures.insert(1) }
        if args.contains("--merchant-template-browser-more-failure") { reader.templatePageFailures.insert(2) }
        _reader = State(initialValue: reader)
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("merchant.operations.fixture.signOut") { reader.signOut(); revision += 1 }.accessibilityIdentifier("merchant.operations.fixture.signOut")
                Button("merchant.operations.fixture.recover") { reader.failure = nil; revision += 1 }.accessibilityIdentifier("merchant.operations.fixture.recover")
            }.font(.caption).padding(8)
            NavigationStack {
                if ProcessInfo.processInfo.arguments.contains("--merchant-template-assist-fixture") {
                    MerchantOperationsHomeView(reader: reader, destinationFactory: { destination, _ in
                        AnyView(MerchantOperationsDocumentView(reader: reader, destination: destination, templateAssistFactory: merchantTemplateAssistFixture))
                    })
                } else { MerchantOperationsHomeView(reader: reader) }
            }.id(revision)
        }
    }
}
#endif
