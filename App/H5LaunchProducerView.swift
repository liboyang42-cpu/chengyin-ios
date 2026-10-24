import SwiftUI

/// Presents the existing parent shell when the launch POST exists. The close
/// control stays on that shell, outside the page. No gradient, glow, or emoji.
/// A closed launch shows the same waiting text and still reads the original
/// install receipt. This view does not restyle the shell.
@MainActor struct H5LaunchProducerView: View {
    let identity: WorkshopInstallIdentity
    let source: any WorkshopOriginalInstallReading
    let onClose: () -> Void
    @State private var producer: H5LaunchProducer

    init(producer: H5LaunchProducer,
         identity: WorkshopInstallIdentity,
         source: any WorkshopOriginalInstallReading,
         onClose: @escaping () -> Void) {
        self.identity = identity
        self.source = source
        self.onClose = onClose
        var current = producer
        _ = current.produce()
        _producer = State(initialValue: current)
    }

    var originalReceipt: WorkshopOriginalInstallFact? { producer.receipt }
    var launchClosed: H5LaunchProducer.Close? { producer.launchClosed }

    var body: some View {
        Group {
            if let shellURL = producer.presentedShellURL, let launch = producer.presentedLaunch {
                H5ShellParentFlowView(requestID: producer.owned.requestID,
                                      shellURL: shellURL,
                                      launch: launch,
                                      identity: identity,
                                      source: source,
                                      entry: producer.entry,
                                      onClose: onClose)
            } else {
                Text("h5.launchTicket")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: taskIdentity) { await readReceipt() }
    }

    private var taskIdentity: String {
        "\(producer.owned.requestID)|\(producer.presentedShellURL?.absoluteString ?? "")|\(producer.presentedLaunch?.nonce ?? "")"
    }

    private func readReceipt() async {
        var current = producer
        defer { producer = current }
        do {
            _ = try await current.readOriginalReceipt(identity: identity, source: source)
        } catch {
            return
        }
    }
}
