import SwiftUI
#if canImport(WebKit)
import UIKit
import WebKit
#endif

/// Platform shell. The close control stays outside the page. No universal script bridge.
/// After the shell request is built, the same request id reads the original install receipt.
struct H5PlatformShellView: View {
    let shellURL: URL?
    let launch: H5LaunchDescription?
    let requestID: String
    let identity: WorkshopInstallIdentity
    let source: any WorkshopOriginalInstallReading
    let onClose: () -> Void
    @State private var flow: H5ShellParentFlow

    init(shellURL: URL?,
         launch: H5LaunchDescription?,
         requestID: String,
         identity: WorkshopInstallIdentity,
         source: any WorkshopOriginalInstallReading,
         onClose: @escaping () -> Void) {
        self.shellURL = shellURL
        self.launch = launch
        self.requestID = requestID
        self.identity = identity
        self.source = source
        self.onClose = onClose
        _flow = State(initialValue: H5ShellParentFlow(requestID: requestID))
    }

    private var request: URLRequest? {
        guard let shellURL, let launch else { return nil }
        return H5ShellLoad.request(shellURL: shellURL, launch: launch)
    }

    var originalReceipt: WorkshopOriginalInstallFact? { flow.receipt }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onClose) { Image(systemName: "xmark") }
                    .accessibilityIdentifier("h5.close")
                Spacer()
            }.padding()
            if let shellURL, let request {
                H5ShellContainer(request: request, shellURL: shellURL)
            } else {
                Text("h5.launchTicket").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: requestID) { await readReceipt() }
    }

    /// The shell request is already built. The receipt read uses that same request id.
    private func readReceipt() async {
        guard request != nil else { return }
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

#if canImport(WebKit)
private struct H5ShellContainer: UIViewRepresentable {
    let request: URLRequest
    let shellURL: URL
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.load(request)
        return view
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(shellURL: shellURL) }
    final class Coordinator: NSObject, WKNavigationDelegate {
        let shellURL: URL
        init(shellURL: URL) { self.shellURL = shellURL }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url, H5ShellLoad.allowsNavigation(to: url, shellURL: shellURL) else {
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}
#else
private struct H5ShellContainer: View {
    let request: URLRequest
    let shellURL: URL
    var body: some View { Text("h5.launchTicket") }
}
#endif
