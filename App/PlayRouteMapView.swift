import SwiftUI
import MapKit
import CoreFoundation

/// One existing route action the route page reads with GET /api/play/route-action.
/// The page sends that GET on the host of the held https APIConfiguration.
/// A caller-held row is not a network read. This request does not insert an action.
struct RouteActionPageReadRequest {
    var sessionID: Int64?
    var memberID: Int64?
    var actionID: String?
    /// Missing or non-https closes only this read. No host is invented.
    var apiBaseURL: URL?
    var transport: (any HTTPTransport)?
    var token: String?
    /// Signed-in account. Zero closes only this read.
    var accountID: Int?
    /// Exact grant for api/play/route-action. Nil, or any other path, refuses the send.
    var approval: OperationEndpointApproval?
    /// Namespace the approval was issued for. Missing refuses the send.
    var approvalNamespace: String?
}

/// Supplementary map for the personal orientation runtime. It never requests
/// location, directions or a new capability; all actions use the existing node host.
@MainActor struct PlayRouteMapView: View {
    @Bindable var model: PlayExperienceCoordinator
    let nodeDestination: (Int) -> AnyView
    var actionRead: RouteActionPageReadRequest? = nil
    @State private var selected: PlayRouteMapDestination?
    @State private var actionReadAppeared = false
    @State private var shownActionRow: RouteActionOriginalRow?
    @State private var showMap = true
    @State private var cameraControlsExpanded = false
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var cameraGate = PlayRouteMapCamera.Gate()
    @State private var cameraPreview: PlayRouteMapCamera.Preview?
    @State private var cameraIssue: PlayRouteMapCamera.CameraIssue?
    #if DEBUG
    @State private var cameraWitness = "none"
    #endif
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let context = model.interactionContext
        List {
            if !model.unresolved, let context, let snapshot = model.snapshot,
               let presentation = PlayRouteMapPresentation(snapshot: snapshot) {
                Section {
                    Text("playRoute.explanation").font(.footnote).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("playRoute.explanation")
                    if let id = presentation.currentNodeID,
                       let current = presentation.stops.first(where: { $0.id == id }) {
                        Label("playRoute.current", systemImage: "flag.fill").font(.headline)
                        stopName(current)
                        Button("playRoute.openCurrent") { choose(id, snapshot: snapshot, context: context) }
                            .accessibilityIdentifier("playRoute.openCurrent")
                    } else { Text("playRoute.noCurrent").accessibilityIdentifier("playRoute.noCurrent") }
                }
                Section {
                    Button(cameraControlsExpanded ? LocalizedStringKey("playRouteCamera.hideControls") : LocalizedStringKey("playRouteCamera.showControls")) { cameraControlsExpanded.toggle() }
                        .frame(minHeight: 44).accessibilityIdentifier("playRouteCamera.controls")
                    if cameraControlsExpanded { cameraControls(presentation, snapshot: snapshot, context: context) }
                }
                if !presentation.mappedStops.isEmpty {
                    Section("playRoute.map") {
                        Button(showMap ? LocalizedStringKey("playRoute.hideMap") : LocalizedStringKey("playRoute.showMap")) { showMap.toggle() }
                            .frame(minHeight: 44).accessibilityIdentifier("playRoute.toggleMap")
                        if showMap {
                            map(presentation, snapshot: snapshot, context: context)
                                .frame(height: typeSize.isAccessibilitySize ? 240 : 320)
                                .listRowInsets(EdgeInsets())
                        }
                    }
                } else {
                    Section { Text("playRoute.noCoordinates").accessibilityIdentifier("playRoute.noCoordinates") }
                }
                Section("playRoute.list") {
                    if presentation.stops.isEmpty { Text("playRoute.empty").accessibilityIdentifier("playRoute.empty") }
                    ForEach(presentation.stops) { stop in
                        if stop.canOpen {
                            Button { choose(stop.id, snapshot: snapshot, context: context) } label: { stopLabel(stop) }
                                .accessibilityIdentifier("playRoute.stop.\(stop.id)")
                                .accessibilityHint(Text("playRoute.openHint"))
                        } else {
                            stopLabel(stop).accessibilityElement(children: .combine)
                                .accessibilityIdentifier("playRoute.stop.\(stop.id)")
                        }
                    }
                }
            } else {
                Section {
                    Text("playRoute.unavailable").accessibilityIdentifier("playRoute.unavailable")
                    if model.phase == .loading { ProgressView("playx.loading") }
                }
            }
            if actionRead != nil {
                Section {
                    if let shownActionRow {
                        Text(verbatim: shownActionRow.actionID)
                            .font(.body)
                            .accessibilityIdentifier("playRoute.actionRead")
                    } else {
                        Text("playRoute.unavailable")
                            .font(.body)
                            .accessibilityIdentifier("playRoute.actionRead")
                    }
                }
            }
            Section {
                Button("playx.refresh") {
                    selected = nil
                    Task {
                        await model.load()
                        appearActionRead()
                        await readThisAction()
                    }
                }
                    .disabled(!model.available || model.phase == .loading || model.phase == .submitting)
                    .accessibilityIdentifier("playRoute.refresh")
                Button("playRoute.back") { selected = nil; dismiss() }
                    .accessibilityIdentifier("playRoute.back")
            }
        }
        .privacySensitive().appNavigationTitle(key: "playRoute.title")
        .navigationBarTitleDisplayMode(.inline).accessibilityIdentifier("playRoute.screen")
        .navigationDestination(item: $selected) { choice in
            let nodeID = choice.nodeID(in: model)
            Group {
                if let nodeID {
                    nodeDestination(nodeID)
                } else { Text("playRoute.unavailable").accessibilityIdentifier("playRoute.selectionUnavailable") }
            }
            // The map is covered while its task is pushed. Observe retirement on
            // the visible destination too, including a read retired before mount.
            .onChange(of: nodeID, initial: true) { _, _ in
                choice.retireSelectionIfNeeded(&selected, in: model)
            }
        }
        .onChange(of: context) { _, _ in clearRetiredSelection() }
        .onChange(of: model.snapshot) { _, _ in clearRetiredSelection() }
        .onChange(of: model.phase) { _, _ in clearRetiredSelection() }
        .onChange(of: cameraRead) { _, _ in resetCamera() }
        .task(id: actionReadToken) {
            appearActionRead()
            await readThisAction()
        }
        .onAppear { cameraGate.appear(); appearActionRead() }
        .onDisappear { cameraGate.disappear(); cameraPreview = nil; cameraIssue = nil }
    }
    private var actionReadToken: String {
        let base = actionRead?.apiBaseURL?.absoluteString ?? ""
        let account = actionRead?.accountID ?? 0
        let tokenMark = actionRead?.token?.utf8.reduce(UInt64(0)) { ($0 &* 131) &+ UInt64($1) } ?? 0
        let transport = actionRead?.transport == nil ? "0" : "1"
        let approved = actionRead?.approval?.paths.contains("api/play/route-action") == true ? "1" : "0"
        return "\(actionRead?.sessionID ?? -1)|\(actionRead?.memberID ?? -1)|\(actionRead?.actionID ?? "")|\(base)|\(account)|\(tokenMark)|\(transport)|\(approved)"
    }
    /// Appearance records the route page only. It does not read and does not write.
    private func appearActionRead() {
        actionReadAppeared = true
    }
    /// Sends GET /api/play/route-action on the held https host.
    /// A missing configuration, a non-https URL, a blank token, or account id 0
    /// closes only this read and does not invent a domain.
    /// An unknown approval refuses the send. A response whose session id, member id,
    /// or action id differs shows nothing.
    private func readThisAction() async {
        guard actionReadAppeared, let request = actionRead else {
            shownActionRow = nil
            return
        }
        let trimmed = request.actionID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let token = request.token?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let configuration = readConfiguration(request.apiBaseURL) else {
            shownActionRow = nil
            return
        }
        guard let transport = request.transport, !token.isEmpty, AuthRequestBuilder.isValidToken(token) else {
            shownActionRow = nil
            return
        }
        guard let accountID = request.accountID, accountID != 0 else {
            shownActionRow = nil
            return
        }
        guard let sessionID = request.sessionID, sessionID > 0,
              let memberID = request.memberID, memberID > 0,
              memberID == Int64(accountID), !trimmed.isEmpty else {
            shownActionRow = nil
            return
        }
        guard let url = routeActionURL(configuration, sessionID: sessionID, memberID: memberID, actionID: trimmed) else {
            shownActionRow = nil
            return
        }
        let namespace = request.approvalNamespace?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let approval = request.approval, !namespace.isEmpty,
              approval.allows(configuration: configuration, namespace: namespace, accountID: accountID, path: "api/play/route-action") else {
            shownActionRow = nil
            return
        }
        var wire = URLRequest(url: url)
        wire.httpMethod = "GET"
        wire.cachePolicy = .reloadIgnoringLocalCacheData
        wire.timeoutInterval = 20
        wire.setValue("application/json", forHTTPHeaderField: "Accept")
        wire.setValue(token, forHTTPHeaderField: "Authorization")
        let body: Data
        let status: Int
        do {
            (body, status) = try await transport.send(wire)
        } catch {
            shownActionRow = nil
            return
        }
        guard !Task.isCancelled,
              actionRead?.sessionID == sessionID,
              actionRead?.memberID == memberID,
              actionRead?.accountID == accountID else {
            shownActionRow = nil
            return
        }
        guard (200..<300).contains(status),
              let decoded = decodedRouteAction(body, sessionID: sessionID, memberID: memberID, actionID: trimmed) else {
            shownActionRow = nil
            return
        }
        var reader = OriginalActionReader(selectActionByAction: { queriedSession, queriedMember, queriedAction in
            guard queriedSession == sessionID,
                  queriedMember == memberID,
                  queriedAction == trimmed else { return nil }
            guard decoded.sessionID == sessionID,
                  decoded.memberID == memberID,
                  decoded.actionID == trimmed else { return nil }
            return decoded
        })
        var page = RouteActionPageRead()
        do {
            let row = try page.shownRow(
                sessionID: request.sessionID,
                memberID: request.memberID,
                actionID: request.actionID,
                selectAction: reader.selectAction)
            guard let row, row.actionID == trimmed else {
                shownActionRow = nil
                return
            }
            if let rowSession = row.sessionID, rowSession != request.sessionID {
                shownActionRow = nil
                return
            }
            if let rowMember = row.memberID, rowMember != request.memberID {
                shownActionRow = nil
                return
            }
            shownActionRow = row
        } catch {
            shownActionRow = nil
        }
    }
    /// Missing or non-https closes only this read. The supplied URL is kept.
    /// This read does not invent a domain.
    private func readConfiguration(_ baseURL: URL?) -> APIConfiguration? {
        guard let baseURL else { return nil }
        guard let configuration = try? APIConfiguration(baseURL: baseURL) else { return nil }
        guard configuration.baseURL.scheme == "https", configuration.baseURL == baseURL else { return nil }
        return configuration
    }
    /// GET /api/play/route-action on the configuration host.
    /// The query carries the session id, the current member id, and the action id.
    private func routeActionURL(_ configuration: APIConfiguration, sessionID: Int64, memberID: Int64, actionID: String) -> URL? {
        let endpoint = configuration.baseURL.appendingPathComponent("api/play/route-action")
        guard var parts = URLComponents(url: endpoint, resolvingAgainstBaseURL: false),
              parts.scheme == "https",
              let host = parts.host, host == configuration.baseURL.host,
              parts.user == nil, parts.password == nil, parts.fragment == nil else { return nil }
        parts.queryItems = [
            URLQueryItem(name: "sessionId", value: String(sessionID)),
            URLQueryItem(name: "memberId", value: String(memberID)),
            URLQueryItem(name: "actionId", value: actionID)
        ]
        guard let url = parts.url, url.scheme == "https", url.host == configuration.baseURL.host else { return nil }
        return url
    }
    /// A row exists only when the response session id, member id, and action id equal the request.
    private func decodedRouteAction(_ body: Data, sessionID: Int64, memberID: Int64, actionID: String) -> RouteActionOriginalRow? {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return nil }
        guard jsonCode(object["code"]) == 200, let data = object["data"] as? [String: Any] else { return nil }
        guard let responseSession = jsonInt64(data["sessionId"]), responseSession == sessionID else { return nil }
        guard let responseMember = jsonInt64(data["memberId"]), responseMember == memberID else { return nil }
        guard let responseAction = data["actionId"] as? String, responseAction == actionID else { return nil }
        let responseJSON = data["responseJson"] as? String
        return RouteActionOriginalRow(
            actionID: responseAction, responseJSON: responseJSON,
            sessionID: responseSession, memberID: responseMember)
    }
    private func jsonCode(_ value: Any?) -> Int? {
        if isJSONBool(value) { return nil }
        if let number = value as? NSNumber { return number.intValue }
        if let text = value as? String, let code = Int(text), String(code) == text { return code }
        return nil
    }
    private func jsonInt64(_ value: Any?) -> Int64? {
        if isJSONBool(value) { return nil }
        if let number = value as? NSNumber {
            let intValue = number.int64Value
            guard intValue > 0, Double(intValue) == number.doubleValue else { return nil }
            return intValue
        }
        if let text = value as? String, let intValue = Int64(text), intValue > 0, String(intValue) == text {
            return intValue
        }
        return nil
    }
    private func isJSONBool(_ value: Any?) -> Bool {
        guard let number = value as? NSNumber else { return false }
        return CFGetTypeID(number as CFTypeRef) == CFBooleanGetTypeID()
    }
    private var cameraRead: PlayRouteMapCamera.Read? {
        guard !model.unresolved else { return nil }
        return .init(snapshot: model.snapshot, context: model.interactionContext)
    }
    private func resetCamera() {
        cameraGate.invalidate(); cameraPreview = nil; cameraIssue = nil; cameraPosition = .automatic
        #if DEBUG
        cameraWitness = "none"
        #endif
    }
    private func cameraControls(_ presentation: PlayRouteMapPresentation, snapshot: PlaySnapshot, context: PlayInteractionContext) -> some View {
        let read = PlayRouteMapCamera.Read(snapshot: snapshot, context: context)
        let renderedGate = cameraGate
        return PlayRouteMapCameraControls(presentation: presentation,
            preview: cameraPreview?.resolve(current: cameraRead), issue: cameraRead == read ? cameraIssue : nil,
            request: { renderedGate.request($0, read: read) }, onFocus: focus,
            onOpen: { choose($0, snapshot: snapshot, context: context) })
    }
    private func focus(_ request: PlayRouteMapCamera.Gate.Request) {
        guard let decision = cameraGate.consume(request, current: cameraRead) else { return }
        cameraControlsExpanded = true
        cameraPreview = decision.preview; cameraIssue = decision.issue
        if let fit = decision.fit {
            cameraPosition = .region(.init(center: .init(latitude: fit.latitude, longitude: fit.longitude),
                span: .init(latitudeDelta: fit.latitudeSpan, longitudeDelta: fit.longitudeSpan)))
            showMap = true
        }
        #if DEBUG
        let action: String
        switch decision.action {
        case .overview: action = "overview"
        case .current: action = "current"
        case .preview(let id): action = "preview:\(id)"
        }
        cameraWitness = action + (decision.fit == nil ? ";camera=unchanged" : ";camera=fitted")
        #endif
    }
    private func clearRetiredSelection() {
        if let selected, selected.nodeID(in: model) == nil { self.selected = nil }
    }
    private func choose(_ id: Int, snapshot: PlaySnapshot, context: PlayInteractionContext) {
        guard !model.unresolved, model.interactionContext == context, model.snapshot == snapshot,
              let choice = PlayRouteMapDestination(nodeID: id, model: model),
              choice.nodeID(in: model) != nil else { return }
        selected = choice
    }
    private func map(_ presentation: PlayRouteMapPresentation, snapshot: PlaySnapshot, context: PlayInteractionContext) -> some View {
        Map(position: $cameraPosition, interactionModes: [.pan, .zoom]) {
            ForEach(presentation.segments) { segment in
                MapPolyline(coordinates: [coordinate(segment.start), coordinate(segment.end)])
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [6, 5]))
            }
            ForEach(presentation.mappedStops) { stop in
                if let location = stop.coordinate {
                    Annotation("", coordinate: coordinate(location)) {
                        let request = cameraGate.request(.preview(stop.id), read: .init(snapshot: snapshot, context: context))
                        let inspecting = cameraPreview?.resolve(current: cameraRead)?.id == stop.id
                        Button { if let request { focus(request) } } label: {
                            VStack(spacing: 3) {
                                Image(systemName: stop.state.symbol).font(.title2)
                                Text(verbatim: String(stop.order)).font(.caption.bold())
                            }.foregroundStyle(stop.state == .current ? Color.white : Color.primary)
                                .frame(minWidth: 44, minHeight: 44)
                                .padding(4).background(stop.state == .current ? Color.accentColor : Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(inspecting ? Color.primary : Color.clear, lineWidth: 2))
                        }.buttonStyle(.plain).disabled(request == nil)
                            .accessibilityLabel(stopName(stop) + Text(verbatim: ", ") + Text(LocalizedStringKey(stop.state.labelKey)))
                            .accessibilityIdentifier("playRoute.pin.\(stop.id)")
                            .accessibilityAddTraits(inspecting ? .isSelected : [])
                    }
                }
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControls { MapCompass() }
        .accessibilityIdentifier("playRoute.map")
        #if DEBUG
        .accessibilityValue(Text(verbatim: cameraWitness))
        #endif
        .id(context.lifetimeIdentity)
    }
    private func coordinate(_ value: PlayRouteMapPresentation.Coordinate) -> CLLocationCoordinate2D {
        .init(latitude: value.latitude, longitude: value.longitude)
    }
    private func stopName(_ stop: PlayRouteMapPresentation.Stop) -> Text {
        if stop.state == .locked { return Text("playRoute.lockedStop") }
        if let name = stop.name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return Text(verbatim: name) }
        return Text("playRoute.unnamedStop")
    }
    private func stopLabel(_ stop: PlayRouteMapPresentation.Stop) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            stopName(stop).font(.headline)
            Label(LocalizedStringKey(stop.state.labelKey), systemImage: stop.state.symbol).font(.subheadline)
            if let address = stop.address, !address.isEmpty { Text(verbatim: address).font(.footnote) }
            if stop.state != .locked && stop.coordinate == nil { Text("playRoute.noStopCoordinate").font(.footnote).foregroundStyle(.secondary) }
            if stop.state == .available || stop.state == .unknown { Text("playRoute.useJourney").font(.footnote).foregroundStyle(.secondary) }
        }.fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).padding(.vertical, 4)
    }
}

/// The existing task temporarily withdraws command context during review/submission.
/// Preserve its already-open presentation through those phases, without granting
/// any command authority. A new read, owner, scope or mode still retires the page.
struct PlayRouteMapDestination: Hashable, Identifiable {
    let id: UUID
    private let choice: PlayRouteMapSelection
    private let owner: PlayExperiencePresentationKey
    private let coordinator: PlayExperienceCoordinator
    private let snapshot: PlaySnapshot
    private let openedNodeID: Int
    @MainActor init?(nodeID: Int, model: PlayExperienceCoordinator) {
        guard !model.unresolved, let snapshot = model.snapshot,
              let choice = PlayRouteMapSelection(nodeID: nodeID, snapshot: snapshot, context: model.interactionContext) else { return nil }
        id = choice.id; self.choice = choice; coordinator = model; owner = PlayExperiencePresentationKey(model: model)
        self.snapshot = snapshot; openedNodeID = nodeID
    }
    @MainActor func nodeID(in model: PlayExperienceCoordinator) -> Int? {
        guard coordinator === model, owner == PlayExperiencePresentationKey(model: model), model.snapshot == snapshot else { return nil }
        if model.phase == .reviewing || model.phase == .submitting { return openedNodeID }
        guard !model.unresolved else { return nil }
        return choice.resolve(snapshot: model.snapshot, context: model.interactionContext)
    }
    @MainActor func retireSelectionIfNeeded(_ selected: inout Self?, in model: PlayExperienceCoordinator) {
        // A queued callback from a disappearing destination cannot pop a newer
        // selection, even when both destinations open the same node ID.
        guard selected?.id == id, nodeID(in: model) == nil else { return }
        selected = nil
    }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
