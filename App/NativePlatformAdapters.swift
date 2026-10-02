import AVFoundation
import MapKit
import UIKit

/// Bounded, ephemeral HTTPS download. Redirects remain inside the reviewed origin allowlist;
/// no cookies, credentials, cache, or automatic retries. HLS is intentionally unsupported.
private final class ApprovedAudioDownload: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let policy: PlatformMediaPolicy
    private let limit = 20 * 1024 * 1024
    private var bytes = Data()
    private var session: URLSession?
    private var completion: (@Sendable (Data?) -> Void)?
    init(policy: PlatformMediaPolicy) { self.policy = policy }
    func start(_ url: URL, completion: @escaping @Sendable (Data?) -> Void) {
        guard policy.allows(url) else { completion(nil); return }
        self.completion = completion
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil; configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil; configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 20; configuration.timeoutIntervalForResource = 60
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        self.session = session; session.dataTask(with: url).resume()
    }
    func cancel() { session?.invalidateAndCancel() }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url.map { policy.allows($0) } == true ? request : nil)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode),
              response.url.map({ policy.allows($0) }) == true,
              response.expectedContentLength <= Int64(limit) else { completionHandler(.cancel); return }
        completionHandler(.allow)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard bytes.count + data.count <= limit else { dataTask.cancel(); return }; bytes.append(data)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let callback = completion; completion = nil
        callback(error == nil && !bytes.isEmpty ? bytes : nil); session.finishTasksAndInvalidate()
    }
}

/// Authored only: callers must explicitly inject this after runtime and consent approval.
/// Playback-only category, never requests microphone access or background-audio entitlement.
@MainActor final class NativePlatformAudioDriver: NSObject, PlatformAudioDriving, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    private var download: ApprovedAudioDownload?
    private var generation = 0
    private var event: (@MainActor (PlatformAudioEvent) -> Void)?
    private var observers: [NSObjectProtocol] = []
    override init() {
        super.init()
        for name in [AVAudioSession.interruptionNotification, AVAudioSession.routeChangeNotification,
                     AVAudioSession.mediaServicesWereResetNotification, UIApplication.didEnterBackgroundNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }; let event = self.event; self.stop(); event?(.interrupted)
                }
            })
        }
    }
    deinit { observers.forEach(NotificationCenter.default.removeObserver) }
    func start(source: PlatformMediaSource, policy: PlatformMediaPolicy, event: @escaping @MainActor (PlatformAudioEvent) -> Void) {
        stop(); self.event = event
        guard policy.allows(source.url) else { event(.failed); return }
        let token = generation, download = ApprovedAudioDownload(policy: policy); self.download = download
        download.start(source.url) { [weak self] data in
            Task { @MainActor [weak self] in
                guard let self, token == self.generation else { return }
                guard let data else { self.event?(.failed); return }
                do {
                    let audioSession = AVAudioSession.sharedInstance()
                    try audioSession.setCategory(.playback, mode: .spokenAudio)
                    try audioSession.setActive(true)
                    let player = try AVAudioPlayer(data: data)
                    self.player = player; player.delegate = self
                    guard player.prepareToPlay(), player.play() else { self.event?(.failed); return }
                    self.event?(.playing)
                } catch { self.event?(.failed) }
            }
        }
    }
    func pause() { player?.pause() }
    func resume() { event?(player?.play() == true ? .playing : .failed) }
    func stop() {
        generation += 1; download?.cancel(); download = nil
        player?.stop(); player?.delegate = nil; player = nil; event = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self, weak player] in
            guard let self, let player, self.player === player else { return }; self.event?(flag ? .ended : .failed)
        }
    }
    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor [weak self, weak player] in
            guard let self, let player, self.player === player else { return }; self.event?(.failed)
        }
    }
}
@MainActor struct NativePlatformMapOpener: PlatformMapOpening {
    func open(_ destination: PlatformMapDestination) async -> Bool {
        guard destination.hasCoordinates, let latitude = destination.latitude, let longitude = destination.longitude else { return false }
        let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)))
        item.name = destination.name
        // Selected destination only; no location manager, live origin, routing, or permission prompt.
        return item.openInMaps(launchOptions: nil)
    }
}
@MainActor struct NativePlatformAddressCopier: PlatformAddressCopying {
    func copy(_ text: String) throws { UIPasteboard.general.string = text }
}
