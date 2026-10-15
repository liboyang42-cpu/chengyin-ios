import AVFoundation
import MapKit
import UIKit

/// Internal seams keep lifecycle regressions independent of networking and the device audio session.
protocol NativePlatformAudioDownloading: AnyObject {
    func start(_ url: URL, completion: @escaping @Sendable (Data?) -> Void)
    func cancel()
}
@MainActor protocol NativePlatformAudioPlaying: AnyObject {
    var delegate: (any AVAudioPlayerDelegate)? { get set }
    func prepareToPlay() -> Bool
    func play() -> Bool
    func pause()
    func stop()
}
extension AVAudioPlayer: NativePlatformAudioPlaying {}

@MainActor struct NativePlatformAudioDependencies {
    let notifications: NotificationCenter
    let makeDownload: (PlatformMediaPolicy) -> any NativePlatformAudioDownloading
    let makePlayer: (Data) throws -> any NativePlatformAudioPlaying
    let activateSession: () throws -> Void
    let deactivateSession: () -> Void
    let hasPlaybackConfiguration: () -> Bool
    let enqueue: @Sendable (@escaping @MainActor @Sendable () -> Void) -> Void

    static var live: Self {
        .init(notifications: .default,
              makeDownload: { ApprovedAudioDownload(policy: $0) },
              makePlayer: { try AVAudioPlayer(data: $0) },
              activateSession: {
                  let session = AVAudioSession.sharedInstance()
                  try session.setCategory(.playback, mode: .spokenAudio)
                  try session.setActive(true)
              },
              deactivateSession: {
                  try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
              },
              hasPlaybackConfiguration: {
                  let session = AVAudioSession.sharedInstance()
                  return session.category == .playback && session.mode == .spokenAudio
              },
              enqueue: { operation in Task { @MainActor in operation() } })
    }
}

/// Bounded, ephemeral HTTPS download. Redirects remain inside the reviewed origin allowlist;
/// no cookies, credentials, cache, or automatic retries. HLS is intentionally unsupported.
private final class ApprovedAudioDownload: NSObject, NativePlatformAudioDownloading, URLSessionDataDelegate, @unchecked Sendable {
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
        callback?(error == nil && !bytes.isEmpty ? bytes : nil); session.finishTasksAndInvalidate()
    }
}

/// Authored only: callers must explicitly inject this after runtime and consent approval.
/// Playback-only category, never requests microphone access or background-audio entitlement.
@MainActor final class NativePlatformAudioDriver: NSObject, PlatformAudioDriving, AVAudioPlayerDelegate {
    private let dependencies: NativePlatformAudioDependencies
    private let notifications: NotificationCenter
    private var player: (any NativePlatformAudioPlaying)?
    private var download: (any NativePlatformAudioDownloading)?
    private var generation = 0
    private var sessionActive = false
    private var event: (@MainActor (PlatformAudioEvent) -> Void)?
    private var observers: [NSObjectProtocol] = []
    override convenience init() { self.init(dependencies: .live) }
    init(dependencies: NativePlatformAudioDependencies) {
        self.dependencies = dependencies
        notifications = dependencies.notifications
        super.init()
    }
    private func observeLifecycle(token: Int) {
        let enqueue = dependencies.enqueue
        for name in [AVAudioSession.interruptionNotification, AVAudioSession.routeChangeNotification,
                     AVAudioSession.mediaServicesWereResetNotification, UIApplication.didEnterBackgroundNotification] {
            observers.append(notifications.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                let interruption = (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? NSNumber)?.uintValue
                let route = (notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? NSNumber)?.uintValue
                enqueue { [weak self] in
                    // An already enqueued notification still belongs to the run that registered it.
                    guard let self, self.generation == token, self.event != nil else { return }
                    if name == AVAudioSession.interruptionNotification,
                       interruption == AVAudioSession.InterruptionType.ended.rawValue { return }
                    // setCategory during this driver's own start also emits a route change.
                    // An incompatible category takeover remains a stop-worthy event.
                    if name == AVAudioSession.routeChangeNotification,
                       route == AVAudioSession.RouteChangeReason.categoryChange.rawValue,
                       self.dependencies.hasPlaybackConfiguration() { return }
                    self.finish(.interrupted)
                }
            })
        }
    }
    deinit { observers.forEach(notifications.removeObserver) }
    func start(source: PlatformMediaSource, policy: PlatformMediaPolicy, event: @escaping @MainActor (PlatformAudioEvent) -> Void) {
        stop(); self.event = event
        guard policy.allows(source.url) else { finish(.failed); return }
        let token = generation
        observeLifecycle(token: token)
        let download = dependencies.makeDownload(policy); self.download = download
        let enqueue = dependencies.enqueue
        download.start(source.url) { [weak self] data in
            enqueue { [weak self] in
                guard let self, token == self.generation else { return }
                guard let data else { self.finish(.failed); return }
                do {
                    try self.dependencies.activateSession(); self.sessionActive = true
                    let player = try self.dependencies.makePlayer(data)
                    self.player = player; player.delegate = self
                    guard player.prepareToPlay(), player.play() else { self.finish(.failed); return }
                    self.event?(.playing)
                } catch { self.finish(.failed) }
            }
        }
    }
    func pause() { player?.pause() }
    func resume() {
        guard event != nil else { return }
        guard player?.play() == true else { finish(.failed); return }
        event?(.playing)
    }
    func stop() {
        generation += 1
        observers.forEach(notifications.removeObserver); observers.removeAll()
        download?.cancel(); download = nil
        player?.stop(); player?.delegate = nil; player = nil; event = nil
        let usedSession = sessionActive; sessionActive = false
        if usedSession { dependencies.deactivateSession() }
    }
    private func finish(_ result: PlatformAudioEvent) {
        let callback = event
        stop() // Release before delivering a terminal result, including a reentrant explicit retry.
        callback?(result)
    }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self, weak player] in
            guard let self, let player, self.player === player else { return }; self.finish(flag ? .ended : .failed)
        }
    }
    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor [weak self, weak player] in
            guard let self, let player, self.player === player else { return }; self.finish(.failed)
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
