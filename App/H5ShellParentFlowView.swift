import SwiftUI

/// Parent surface. Presents `H5PlatformShellView` only when the shell URL and launch
/// share the same HTTPS host. The close control stays on that shell, outside the page.
/// No gradient, glow, or emoji. A different host does not load. After the shell opens,
/// the original install receipt is read for the same request id.
@MainActor struct H5ShellParentFlowView: View {
    let requestID: String
    let shellURL: URL?
    let launch: H5LaunchDescription?
    let identity: WorkshopInstallIdentity
    let source: any WorkshopOriginalInstallReading
    let onClose: () -> Void
    @State private var flow: H5ShellParentFlow

    init(requestID: String,
         shellURL: URL?,
         launch: H5LaunchDescription?,
         identity: WorkshopInstallIdentity,
         source: any WorkshopOriginalInstallReading,
         entry: WorkshopInstallRecoverEntry = WorkshopInstallRecoverEntry(),
         onClose: @escaping () -> Void) {
        self.requestID = requestID
        self.shellURL = shellURL
        self.launch = launch
        self.identity = identity
        self.source = source
        self.onClose = onClose
        _flow = State(initialValue: H5ShellParentFlow(requestID: requestID, entry: entry))
    }

    var originalReceipt: WorkshopOriginalInstallFact? { flow.receipt }
    var shellLoaded: Bool { flow.shellLoaded }

    var body: some View {
        Group {
            if let shellURL, let launch,
               let parent = H5ShellParentFlow.loadRequest(shellURL: shellURL, launch: launch),
               let shell = H5ShellLoad.request(shellURL: shellURL, launch: launch),
               parent.httpMethod == shell.httpMethod, parent.httpBody == shell.httpBody {
                H5PlatformShellView(shellURL: shellURL,
                                   launch: launch,
                                   requestID: requestID,
                                   identity: identity,
                                   source: source,
                                   onClose: onClose)
            } else {
                Text("h5.launchTicket")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: loadIdentity) { await readBack() }
    }

    mutating func rejectSelfReportClear() throws {
        try flow.rejectSelfReportClear()
    }

    private var loadIdentity: String {
        "\(requestID)|\(shellURL?.absoluteString ?? "")|\(launch?.parentOrigin ?? "")|\(launch?.nonce ?? "")"
    }

    private func readBack() async {
        var current = flow
        defer { flow = current }
        guard current.open(shellURL: shellURL, launch: launch) != nil else { return }
        do {
            _ = try await current.readOriginalReceipt(identity: identity, source: source)
        } catch {
            return
        }
    }
}
