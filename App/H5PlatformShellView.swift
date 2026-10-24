import SwiftUI
#if canImport(WebKit)
import UIKit
import WebKit
#endif

/// Platform shell. The close control stays outside the page. No universal script bridge.
struct H5PlatformShellView: View {
    let shellURL: URL?
    let launch: H5LaunchDescription?
    let onClose: () -> Void
    private var request: URLRequest? {
        guard let shellURL, let launch else { return nil }
        return H5ShellLoad.request(shellURL: shellURL, launch: launch)
    }

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
