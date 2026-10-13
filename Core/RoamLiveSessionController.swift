import Foundation

/// Foreground-only state machine. Opening a screen performs no location/network work.
/// Uncertain writes survive cancellation/relaunch; recovery is read-only and never awards locally.
@MainActor public final class RoamLiveSessionController {
    public private(set) var phase: RoamLivePhase = .ready
    public private(set) var record: RoamLiveRecord?
    public private(set) var settlement: RoamSessionFact?
    public private(set) var completedHistory: RoamFinishedHistoryReference?
    public private(set) var places: [RoamPlace] = []
    public private(set) var registeredShops: [RoamRouteNode] = []
    public private(set) var placesReadError: Error?
    public private(set) var registeredShopsReadError: Error?
    public var placesReadFailed: Bool { placesReadError != nil }
    public var registeredShopsReadFailed: Bool { registeredShopsReadError != nil }
    public var nearbyReadFailed: Bool { placesReadFailed || registeredShopsReadFailed }
    public private(set) var track: [RoamHistoryPoint] = []
    public private(set) var lastFix: RoamDeviceFix?
    public private(set) var error: Error?
    public private(set) var presenceError = false
    public private(set) var presenceEnabled = false
    public private(set) var foreground = true
    public private(set) var busy = false
    public var onChange: (() -> Void)?
    public var isAvailable: Bool { service?.isAvailable == true && location != nil }
    public var presenceAvailable: Bool { service?.presenceAvailable == true }
    public var pendingActionCount: Int { record?.unresolvedActions.count ?? 0 }
    public var explorationPercent: Int { min(99, Int((Double(grid.count) / 400 * 100).rounded())) }
    private let service: (any RoamLiveServing)?
    private let location: (any RoamDeviceLocationProviding)?
    private let journal: RoamLiveJournal
    private let history: RoamHistoryStore?
    private let now: () -> Date
    private let key: () -> String
    private var boundIdentity: RoamExperienceIdentity?
    private var generation = 0
    private var operation: UUID?
    private struct UnstartedContinuation {
        let identity: RoamExperienceIdentity
        let generation: Int
        let snapshot: RoamUnstartedJournalSnapshot
    }
    private var unstartedContinuation: UnstartedContinuation?
    private var previousFix: RoamDeviceFix?
    private var origin: RoamCoordinate?
    private var grid: Set<String> = []
    private var lastReveal: Date?
    private var lastPresence: Date?
    private var lastPlaces: Date?
    public init(service: (any RoamLiveServing)? = nil, location: (any RoamDeviceLocationProviding)? = nil,
                journal: RoamLiveJournal, history: RoamHistoryStore? = nil,
                now: @escaping () -> Date = Date.init,
                key: @escaping () -> String = { UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased() }) {
        self.service = service; self.location = location; self.journal = journal; self.history = history; self.now = now; self.key = key
    }
    /// Uses the already supplied local store; no new transport, grant or factory setup.
    public func makeFinishedHistoryReader(offlineExample: Bool = false) -> RoamFinishedHistoryReader {
        RoamFinishedHistoryReader(store: history, offlineExample: offlineExample, currentIdentity: { [weak self] in
            guard let self, self.phase == .finished, self.completedHistory != nil, self.isAvailable,
                  let bound = self.boundIdentity, let current = self.service?.identity,
                  current.scope.storageKey == bound.scope.storageKey, current.epoch == bound.epoch else { return nil }
            return current
        }, completion: { [weak self] in self?.completedHistory })
    }
    public func prepare() {
        guard record == nil, phase != .finished else { return }
        boundIdentity = service?.identity
        guard isAvailable, let identity = boundIdentity else { phase = .unavailable; changed(); return }
        do { record = try journal.read(scope: identity.scope); phase = record == nil ? .ready : .recoveryRequired; error = nil }
        catch { self.error = error; phase = .recoveryRequired }
        changed()
    }
    public func start(purposeAccepted: Bool, presenceAccepted: Bool = false) async {
        guard phase == .ready || phase == .locationDenied, record == nil else { return }
        guard purposeAccepted else { error = RoamLiveFailure.consentRequired; changed(); return }
        guard let token = begin() else { return }
        defer { end(token) }
        do {
            try checkForeground(); guard let location, let identity = boundIdentity else { throw RoamLiveFailure.unavailable }
            phase = .acquiring; error = nil; changed()
            let raw = try await location.currentFix(); try check(token)
            let fix = try accepted(raw)
            let draft = RoamLiveRecord(scope: identity.scope, clientSessionKey: key(), startedAt: now())
            try journal.write(draft); record = draft
            presenceEnabled = presenceAccepted && presenceAvailable
            phase = .active; _ = try accumulate(fix)
            try await flushReveal(token)
            try await refreshPlaces(fix, token: token)
        } catch { fail(error, token: token, locationFailure: record == nil) }
    }
    public func pulse() async {
        guard phase == .active, let token = begin() else { return }
        defer { end(token) }
        do {
            try checkForeground(); guard let location else { throw RoamLiveFailure.unavailable }
            let raw = try await location.currentFix(); try check(token)
            let fix = try accepted(raw); guard try accumulate(fix) else { return }
            if lastReveal == nil || now().timeIntervalSince(lastReveal!) >= 10 || (record?.pendingTiles.count ?? 0) >= 50 { try await flushReveal(token) }
            if lastPlaces == nil || now().timeIntervalSince(lastPlaces!) >= 30 { try await refreshPlaces(fix, token: token) }
            if presenceEnabled, let id = record?.sessionID, lastPresence == nil || now().timeIntervalSince(lastPresence!) >= 30 {
                lastPresence = now()
                do { try await service!.presence(sessionID: id, fix: fix, explorationPercent: explorationPercent); try check(token); presenceError = false }
                catch { try check(token); presenceError = true } // No claim of disappearance; server expiry is five minutes.
            }
        } catch { fail(error, token: token, locationFailure: true) }
    }
    public func pause() {
        unstartedContinuation = nil
        generation += 1; operation = nil; busy = false; location?.stop()
        previousFix = nil; lastFix = nil; presenceEnabled = false
        if phase != .finished && record != nil { phase = record?.pendingWrite == nil ? .paused : .recoveryRequired }
        else if phase == .acquiring { phase = .ready }
        changed()
    }
    public func setForeground(_ value: Bool) { foreground = value; if !value { pause() } }
    public func resume(purposeAccepted: Bool, presenceAccepted: Bool = false) async {
        guard phase == .paused, record?.finishRequested == false else { return }
        guard purposeAccepted else { error = RoamLiveFailure.consentRequired; changed(); return }
        guard record?.pendingWrite == nil else { phase = .recoveryRequired; changed(); return }
        presenceEnabled = presenceAccepted && presenceAvailable; previousFix = nil; phase = .active
        await pulse()
    }
    public func recover() async {
        guard record != nil, phase != .active, let token = begin() else { return }
        defer { end(token) }
        do {
            guard let record else { throw RoamLiveFailure.recoveryRequired }
            // Capture the complete bytes before the asynchronous fact read. A concurrent journal
            // change must not be overwritten by either proof creation or the eventual user action.
            let unstartedSnapshot: RoamUnstartedJournalSnapshot?
            if RoamLiveJournal.canContinueUnstarted(record) { unstartedSnapshot = try journal.captureUnstarted(record) }
            else { unstartedSnapshot = nil }
            try check(token) // Storage callbacks cannot switch the owner before the fact request.
            phase = .recovering; error = nil; changed()
            let fact = try await service!.fact(key: record.clientSessionKey); try check(token)
            try validate(fact, record: record)
            if fact.state == .finished { try archive(fact); return }
            // A missing server row is not permission to erase an uncertain local write.
            // Keep its durable marker: a second lookup or a new controller must see it too.
            if fact.state == .notFound, record.sessionID == nil,
               record.pendingWrite != nil, record.pendingTiles.isEmpty, record.allTiles.isEmpty,
               record.unresolvedActions.isEmpty, record.confirmedPOIIDs.isEmpty,
               record.confirmedShops.isEmpty, record.distanceMeters == 0 {
                throw RoamLiveFailure.recoveryRequired
            }
            if fact.state == .notFound, let snapshot = unstartedSnapshot {
                guard fact.sessionID == nil,
                      fact.clientSessionKey == nil || fact.clientSessionKey == record.clientSessionKey,
                      try journal.matchesUnstarted(snapshot), let identity = boundIdentity else {
                    throw RoamLiveFailure.journalUnavailable
                }
                try check(token)
                phase = .paused
                unstartedContinuation = .init(identity: identity, generation: generation, snapshot: snapshot)
                return // Pending-free NOT_FOUND preparation does not rewrite the journal.
            }
            var draft = record
            if fact.state == .active { draft.sessionID = fact.sessionID }
            else if record.sessionID != nil { throw RoamLiveFailure.recoveryRequired }
            // A keyed reveal is idempotent; keep the actual batch for an explicit resume.
            // An ACTIVE read is proof that a prior finish did not settle at read time, never automatic retry authority.
            draft.pendingWrite = nil; try persist(draft); phase = .paused
        } catch { fail(error, token: token) }
    }
    /// A NOT_FOUND reply is authority only for this exact unchanged, pending-free local intent.
    public var canContinueUnstartedRoam: Bool {
        guard let proof = unstartedContinuation else { return false }
        return acceptsUnstartedContinuation(proof)
    }
    private func acceptsUnstartedContinuation(_ proof: UnstartedContinuation) -> Bool {
        guard !busy, foreground, phase == .paused, isAvailable,
              proof.generation == generation, let current = service?.identity,
              current == proof.identity, boundIdentity == proof.identity,
              current.scope.storageKey == proof.identity.scope.storageKey,
              let record, record == proof.snapshot.record,
              record.scope.storageKey == proof.identity.scope.storageKey else { return false }
        return RoamLiveJournal.canContinueUnstarted(record)
    }
    /// Explicit user gesture changes local intent only. Resume/location remains a separate consented action.
    public func continueUnstartedRoam() {
        guard let proof = unstartedContinuation else { return }
        guard acceptsUnstartedContinuation(proof) else { unstartedContinuation = nil; changed(); return }
        unstartedContinuation = nil // Consume before any storage callback or failure; never blind-retry.
        do {
            let draft = try journal.continueUnstarted(proof.snapshot) { self.acceptsUnstartedContinuation(proof) }
            guard acceptsUnstartedContinuation(proof) else { throw RoamLiveFailure.staleIdentity }
            record = draft; error = nil; phase = .paused
        } catch {
            guard service?.identity == proof.identity, boundIdentity == proof.identity,
                  service?.identity?.scope.storageKey == proof.identity.scope.storageKey else { invalidate(); return }
            self.error = error; phase = .recoveryRequired
        }
        changed()
    }
    public func finish() async {
        guard [.active, .paused].contains(phase), let token = begin() else { return }
        defer { end(token) }
        location?.stop(); previousFix = nil; lastFix = nil; presenceEnabled = false
        do {
            guard var draft = record, draft.pendingWrite == nil else { throw RoamLiveFailure.recoveryRequired }
            draft.finishRequested = true; try persist(draft); phase = .finishing; error = nil; changed()
            while record?.pendingTiles.isEmpty == false { try await flushReveal(token) }
            guard let id = record?.sessionID else { throw RoamLiveFailure.recoveryRequired }
            draft = record!; draft.pendingWrite = .finish; try persist(draft)
            try await service!.finish(sessionID: id, poiIDs: draft.confirmedPOIIDs, distanceMeters: Int(draft.distanceMeters.rounded()))
            try check(token)
            let fact = try await service!.fact(key: draft.clientSessionKey); try check(token)
            try validate(fact, record: draft); guard fact.state == .finished else { throw RoamLiveFailure.recoveryRequired }
            try archive(fact)
        } catch { fail(error, token: token) }
    }
    /// Read retry needs the same already accepted foreground fix. It never asks for a location.
    public var canRetryNearbyRead: Bool {
        guard nearbyReadFailed, phase == .active, foreground, !busy, isAvailable,
              let current = service?.identity, let boundIdentity, current == boundIdentity,
              current.scope.storageKey == boundIdentity.scope.storageKey,
              let record, record.scope.storageKey == boundIdentity.scope.storageKey,
              record.sessionID != nil, !record.finishRequested, record.pendingWrite == nil,
              let fix = lastFix, fix.datum == .gcj02, fix.accuracyMeters <= 80,
              (-2...30).contains(now().timeIntervalSince(fix.measuredAt)) else { return false }
        return true
    }
    public func retryNearbyRead() async {
        guard canRetryNearbyRead, let fix = lastFix, let token = begin() else { return }
        defer { end(token) }
        do {
            try checkForeground(); try check(token)
            try await refreshPlaces(fix, token: token)
        } catch {
            // Source failures are recorded by refreshPlaces. Its only escaping errors invalidate
            // this read's lifecycle; cancellation/stale ownership must not replace a global error.
            return
        }
    }
    /// No automatic proximity rewards. The user chooses each verified source POI.
    public func discover(_ place: RoamPlace) async { await visit(place, shop: false) }
    public func visitShop(_ place: RoamPlace) async { await visit(place, shop: true) }
    public func gapMeters(_ place: RoamPlace, shop: Bool) -> Int? {
        guard let current = lastFix, let point = place.coordinate else { return nil }
        let radius = shop ? 130 : Double((place.radiusM ?? 0) > 0 ? place.radiusM! : 120) + 30
        return max(0, Int(ceil(RoamExperienceMath.distanceMeters(current.coordinate, point) - radius)))
    }
    public func actionUnresolved(_ place: RoamPlace, shop: Bool) -> Bool { record?.unresolvedActions.contains(actionKey(place, shop: shop)) == true }
    public func actionConfirmed(_ place: RoamPlace, shop: Bool) -> Bool {
        shop ? record?.confirmedShops.contains(actionKey(place, shop: true)) == true : record?.confirmedPOIIDs.contains(place.id) == true
    }
    private func visit(_ place: RoamPlace, shop: Bool) async {
        guard phase == .active, place.isSupported, !shop || place.type == 2,
              places.contains(where: { $0.id == place.id && $0 == place }), !actionConfirmed(place, shop: shop), let token = begin() else { return }
        defer { end(token) }
        do {
            try checkForeground()
            guard !actionUnresolved(place, shop: shop) else { throw RoamLiveFailure.unresolvedVisit }
            guard let location, var draft = record, let id = draft.sessionID else { throw RoamLiveFailure.recoveryRequired }
            let raw = try await location.currentFix(); try check(token)
            let fix = try accepted(raw); lastFix = fix
            guard gapMeters(place, shop: shop) == 0 else { throw RoamLiveFailure.outOfRange }
            let action = actionKey(place, shop: shop)
            draft.unresolvedActions.append(action); try persist(draft) // Before dispatch, even if canceled or killed.
            if shop {
                let receipt = try await service!.shopVisit(sessionID: id, sourceType: 1, sourceID: place.id, fix: fix)
                try check(token); guard receipt.recorded else { throw RoamLiveFailure.unresolvedVisit }
                draft.confirmedShops.append(action)
            } else {
                let receipt = try await service!.discover(sessionID: id, poiID: place.id, fix: fix)
                try check(token); guard receipt.poiId == place.id else { throw APIError.malformedResponse }
                draft.confirmedPOIIDs.append(place.id)
            }
            draft.unresolvedActions.removeAll { $0 == action }; try persist(draft); error = nil
        } catch {
            guard operation == token else { return }
            self.error = error // Keep uncertain target locked; only final server settlement can reconcile aggregate rewards.
        }
    }
    public func registeredShopGap(_ shop: RoamRouteNode) -> Int? {
        guard let current = lastFix, let coordinate = shop.coordinate else { return nil }
        return max(0, Int(ceil(RoamExperienceMath.distanceMeters(current.coordinate, coordinate) - 130)))
    }
    public func registeredShopConfirmed(_ shop: RoamRouteNode) -> Bool { record?.confirmedShops.contains("shop:2:\(shop.id)") == true }
    public func registeredShopUnresolved(_ shop: RoamRouteNode) -> Bool { record?.unresolvedActions.contains("shop:2:\(shop.id)") == true }
    public func visitRegisteredShop(_ shop: RoamRouteNode) async {
        guard phase == .active, registeredShops.contains(shop), !registeredShopConfirmed(shop), let token = begin() else { return }
        defer { end(token) }
        do {
            try checkForeground()
            guard !registeredShopUnresolved(shop) else { throw RoamLiveFailure.unresolvedVisit }
            guard let location, var draft = record, let id = draft.sessionID else { throw RoamLiveFailure.recoveryRequired }
            let raw = try await location.currentFix(); try check(token)
            let fix = try accepted(raw); lastFix = fix
            guard registeredShopGap(shop) == 0 else { throw RoamLiveFailure.outOfRange }
            let action = "shop:2:\(shop.id)"
            draft.unresolvedActions.append(action); try persist(draft)
            let receipt = try await service!.shopVisit(sessionID: id, sourceType: 2, sourceID: shop.id, fix: fix)
            try check(token); guard receipt.recorded else { throw RoamLiveFailure.unresolvedVisit }
            draft.confirmedShops.append(action); draft.unresolvedActions.removeAll { $0 == action }; try persist(draft); error = nil
        } catch { guard operation == token else { return }; self.error = error }
    }
    private func actionKey(_ place: RoamPlace, shop: Bool) -> String { "\(shop ? "shop:1" : "poi"):\(place.id)" }
    private func accepted(_ raw: RoamDeviceFix) throws -> RoamDeviceFix {
        guard raw.accuracyMeters <= 80, (-2...30).contains(now().timeIntervalSince(raw.measuredAt)) else { throw RoamLiveFailure.locationQuality }
        return try RuntimeLocationProjection.gcj02(raw, now: now())
    }
    private func accumulate(_ fix: RoamDeviceFix) throws -> Bool {
        guard var draft = record, let tile = RoamExperienceMath.tileKey(fix.coordinate), draft.allTiles.count < 10_000 else { throw RoamLiveFailure.capacityReached }
        if let previous = previousFix {
            guard fix.measuredAt >= previous.measuredAt else { throw RoamLiveFailure.locationQuality }
            if fix.measuredAt == previous.measuredAt { return false }
            let distance = RoamExperienceMath.distanceMeters(previous.coordinate, fix.coordinate)
            if distance < 3 { lastFix = fix; return false }
            if distance > 120 { previousFix = fix; lastFix = nil; return false } // Reset anchor; do not turn a GPS jump into distance/reveals.
            draft.distanceMeters += distance
        }
        previousFix = fix; lastFix = fix
        if origin == nil { origin = fix.coordinate }
        if !draft.allTiles.contains(tile) { draft.allTiles.append(tile); draft.pendingTiles.append(tile) }
        try persist(draft)
        track.append(RoamHistoryPoint(coordinate: fix.coordinate)); if track.count > 2000 { track.removeFirst() }
        updateGrid(fix.coordinate)
        return true
    }
    private func updateGrid(_ point: RoamCoordinate) {
        guard let origin else { return }
        let x = (point.longitude - origin.longitude) * 111_320 * cos(origin.latitude * .pi / 180)
        let y = (point.latitude - origin.latitude) * 111_320
        // Retain the mini's bounded 20×20 local exploration grid; never derive a percent from lifetime tile count.
        guard abs(x) <= 700, abs(y) <= 700 else { return }
        for gx in Int(floor((x - 55) / 60))...Int(floor((x + 55) / 60)) {
            for gy in Int(floor((y - 55) / 60))...Int(floor((y + 55) / 60)) where abs(gx * 60) <= 600 && abs(gy * 60) <= 600 { grid.insert("\(gx),\(gy)") }
        }
    }
    private func flushReveal(_ token: UUID) async throws {
        guard var draft = record, !draft.pendingTiles.isEmpty else { return }
        guard draft.pendingWrite == nil else { throw RoamLiveFailure.recoveryRequired }
        let batch = Array(draft.pendingTiles.prefix(200))
        draft.pendingWrite = .reveal; try persist(draft)
        let receipt = try await service!.reveal(sessionID: draft.sessionID, clientSessionKey: draft.clientSessionKey, tiles: batch)
        try check(token)
        guard draft.sessionID == nil || receipt.sessionId == draft.sessionID else { throw APIError.malformedResponse }
        draft.sessionID = receipt.sessionId; draft.pendingTiles.removeFirst(batch.count); draft.pendingWrite = nil
        try persist(draft); lastReveal = now()
    }
    private func refreshPlaces(_ fix: RoamDeviceFix, token: UUID) async throws {
        do { let values = try await service!.places(fix: fix); try check(token); places = values; lastPlaces = now(); placesReadError = nil }
        catch { try check(token); placesReadError = error } // This source owns only its own read failure, never a visit/location/finish error.
        do { let values = try await service!.registeredShops(fix: fix); try check(token); registeredShops = values; registeredShopsReadError = nil }
        catch { try check(token); registeredShopsReadError = error }
    }
    private func validate(_ fact: RoamSessionFact, record: RoamLiveRecord) throws {
        guard RoamRecoveryQuery.clientSessionKey(record.clientSessionKey).matches(fact),
              record.sessionID == nil || fact.state == .notFound || fact.sessionID == record.sessionID else { throw APIError.malformedResponse }
    }
    private func archive(_ fact: RoamSessionFact) throws {
        guard let record, fact.hasCompleteSettlement, record.pendingTiles.isEmpty, let id = fact.sessionID else { throw RoamExperienceFailure.incompleteSettlement }
        settlement = fact
        guard let history, history.scope == record.scope else { throw RoamLiveFailure.journalUnavailable }
        var fields: [String: Any] = ["ts": Int64(record.startedAt.timeIntervalSince1970 * 1000), "serverSessionID": id,
            "distance": record.distanceMeters / 1000, "shops": fact.result!.sessionShops!, "track": [], "pois": [], "photos": []]
        if let medal = fact.result?.medal { fields["medal"] = medal }
        if let name = fact.result?.shopMedal?.name { fields["shopMedalName"] = name }
        let archived = try JSONDecoder().decode(RoamHistoryRecord.self, from: JSONSerialization.data(withJSONObject: fields))
        try history.prependSettled(archived, fact: fact)
        try journal.clear(scope: record.scope)
        completedHistory = .init(timestamp: archived.ts, serverSessionID: id)
        self.record = nil; phase = .finished; error = nil; lastFix = nil; previousFix = nil; track = []; places = []; registeredShops = []; grid = []; presenceEnabled = false
    }
    private func persist(_ draft: RoamLiveRecord) throws { try journal.write(draft); record = draft }
    private func checkForeground() throws { guard foreground else { throw RoamLiveFailure.foregroundRequired } }
    private func begin() -> UUID? {
        guard !busy else { return nil }
        unstartedContinuation = nil
        guard isAvailable, let identity = service?.identity, identity == boundIdentity else { invalidate(); phase = .unavailable; changed(); return nil }
        let token = UUID(); operation = token; busy = true; changed(); return token
    }
    private func check(_ token: UUID) throws {
        try Task.checkCancellation()
        guard operation == token, boundIdentity != nil, service?.identity == boundIdentity, isAvailable else { throw RoamLiveFailure.staleIdentity }
    }
    private func end(_ token: UUID) { if operation == token { operation = nil; busy = false; changed() } }
    private func fail(_ error: Error, token: UUID, locationFailure: Bool = false) {
        guard operation == token else { return }
        guard service?.identity == boundIdentity, isAvailable else { invalidate(); return }
        location?.stop(); previousFix = nil; lastFix = nil; presenceEnabled = false; self.error = error
        phase = record?.pendingWrite != nil ? .recoveryRequired : (record == nil ? (locationFailure ? .locationDenied : .unavailable) : .paused)
        if phase == .paused, record?.finishRequested == true { phase = .recoveryRequired }
    }
    public func invalidate() {
        unstartedContinuation = nil
        placesReadError = nil; registeredShopsReadError = nil
        completedHistory = nil
        generation += 1; operation = nil; busy = false; location?.stop(); record = nil; settlement = nil; places = []; registeredShops = []; track = []
        lastFix = nil; previousFix = nil; origin = nil; grid = []; boundIdentity = nil; presenceEnabled = false; error = nil; phase = .unavailable; changed()
    }
    private func changed() { onChange?() }
}
