import SwiftUI
import Network
import Observation

/// Network reachability only. It never reads location, never sends a request, and never
/// changes the chosen manual area; the explorer decides whether a reconnect refreshes.
@MainActor @Observable final class SearchMapConnectivity {
    private(set) var isOnline: Bool
    private let monitor: NWPathMonitor?
    init(forcedOnline: Bool? = nil) {
        if let forcedOnline {
            isOnline = forcedOnline; monitor = nil
        } else {
            isOnline = true
            let monitor = NWPathMonitor(); self.monitor = monitor
            monitor.pathUpdateHandler = { [weak self] path in
                let online = path.status == .satisfied
                Task { @MainActor [weak self] in self?.isOnline = online }
            }
            monitor.start(queue: DispatchQueue(label: "questify.connectivity.searchMap"))
        }
    }
    deinit { monitor?.cancel() }
    /// The current path, read synchronously for the 重试连接 button.
    func recheck() -> Bool {
        if let monitor { isOnline = monitor.currentPath.status == .satisfied }
        return isOnline
    }
    #if DEBUG
    /// Synthetic fixture control only; real builds follow NWPathMonitor.
    func setFixtureOnline(_ online: Bool) { guard monitor == nil else { return }; isOnline = online }
    #endif
}

/// A host or DEBUG fixture may inject a source; otherwise the explorer owns one monitor.
private struct SearchMapConnectivityKey: EnvironmentKey { static let defaultValue: SearchMapConnectivity? = nil }
extension EnvironmentValues {
    var searchMapConnectivity: SearchMapConnectivity? {
        get { self[SearchMapConnectivityKey.self] }
        set { self[SearchMapConnectivityKey.self] = newValue }
    }
}

/// Mini-program offline bar: 当前离线 + cache time + 重试连接.
struct SearchMapOfflineBannerView: View {
    let state: SearchMapOfflineBanner
    let stillOffline: Bool
    let retry: () -> Void
    var body: some View {
        if let key = state.key {
            VStack(alignment: .leading, spacing: 8) {
                Label(LocalizedStringKey(key), systemImage: "wifi.slash")
                    .font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("searchMap.w208.offline.message")
                if case .cached(let date) = state {
                    (Text("searchMap.w208.offline.cachedAt") + Text(verbatim: " ") + Text(date, format: .dateTime.hour().minute()))
                        .font(.footnote).foregroundStyle(.secondary)
                        .accessibilityIdentifier("searchMap.w208.offline.cachedAt")
                }
                if stillOffline {
                    Text("searchMap.w208.offline.stillOffline").font(.footnote)
                        .accessibilityIdentifier("searchMap.w208.offline.stillOffline")
                }
                Button("searchMap.w208.offline.retry", action: retry).buttonStyle(.bordered).frame(minHeight: 44)
                    .accessibilityIdentifier("searchMap.w208.offline.retry")
            }.padding().frame(maxWidth: .infinity, alignment: .leading)
                .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("searchMap.w208.offline")
        }
    }
}
