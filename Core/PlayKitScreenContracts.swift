import Foundation

/// Presentation is chosen by the task, not by Flutter's historical fullscreen route.
/// Forms and progress readbacks remain ordinary native navigation destinations.
public enum PlayKitScreenKind: String, CaseIterable, Identifiable {
    case coinFlip, diceRoll, reaction, ballShake, quietHold, countdown, stopwatch
    case qa, branch, estimate, pricePair, hiddenObject, predict, random, scan, walk, bingo
    case profile, photoCheck, note, typeIn, dailySign, steps
    case sort, match, classify, compare, compass, shout, hangman
    case blindTaste, diyName, silentOrder, slowTask, musicCorner, timeWindow
    /// Source priority, preserving main tasks before ambient topic progress.
    public static let priority: [Self] = [.qa, .branch, .predict, .random, .estimate, .pricePair, .sort, .match, .classify, .compare, .hangman, .hiddenObject, .scan, .profile, .photoCheck, .note, .typeIn, .coinFlip, .diceRoll, .reaction, .ballShake, .quietHold, .compass, .shout, .countdown, .stopwatch, .blindTaste, .diyName, .silentOrder, .steps, .walk, .slowTask, .musicCorner, .dailySign, .timeWindow, .bingo]
    public static func present(in state: PlayAdvancedState) -> [Self] {
        priority.filter { state.playKit[$0.rawValue].object != nil || ($0 == .branch && state.config["branch"]["enabled"].bool == true) || ($0 == .random && state.config["random"]["enabled"].bool == true) }
    }
    public var id: String { rawValue }
    public var isChallenge: Bool { [.reaction, .ballShake, .quietHold, .countdown, .stopwatch, .typeIn, .shout].contains(self) }
    public var isFocusedStage: Bool { isChallenge || self == .hiddenObject || self == .compass }
    public var isProgress: Bool { [.bingo, .steps, .walk].contains(self) }
}

public struct PlayKitOption: Identifiable, Equatable {
    public let id: String; public let label: String; public let raw: PlayWireValue
    public static func read(_ values: PlayWireValue, idKey: String = "id", labelKey: String = "label") -> [Self] {
        var seen = Set<String>()
        return (values.array ?? []).compactMap { row in
            guard let id = row[idKey].text, !id.isEmpty, seen.insert(id).inserted else { return nil }
            return .init(id: id, label: row[labelKey].text ?? row["t"].text ?? id, raw: row)
        }
    }
}

public struct PlayKitScreenProjection: Equatable {
    public let kind: PlayKitScreenKind; public let segment: PlayWireValue
    public init(kind: PlayKitScreenKind, segment: PlayWireValue) { self.kind = kind; self.segment = segment }
    public var title: String { segment["title"].text ?? segment["question"].text ?? segment["kicker"].text ?? "" }
    public var complete: Bool {
        switch kind {
        case .qa, .pricePair, .sort, .compare: return segment["finished"].bool == true
        case .branch: return segment["currentStep"]["terminal"].bool == true || segment["ended"].bool == true
        case .estimate: return segment["submitted"].bool == true
        case .predict: return !(segment["myOptionKey"].text ?? "").isEmpty
        case .scan: return segment["scanned"].bool == true
        case .blindTaste: return segment["solved"].bool == true
        case .diyName: return !(segment["name"].text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .slowTask: return segment["claimed"].bool == true
        case .musicCorner, .silentOrder, .timeWindow: return false
        case .profile, .note, .compass: return segment["done"].bool == true
        case .photoCheck: return segment["passed"].bool == true || segment["flagged"].bool == true
        case .typeIn:
            let cap = segment["tries"].integer ?? 0
            return segment["passed"].bool == true || (cap > 0 && (segment["attempts"].integer ?? 0) >= cap)
        case .hiddenObject:
            let total = segment["total"].integer ?? 0
            return total > 0 && Set((segment["foundIds"].array ?? []).compactMap(\.text)).count >= total
        case .random:
            let total = segment["drawCount"].integer ?? 0
            return total > 0 && (segment["drawn"].array ?? []).count >= total
        case .dailySign: return !(segment["claimedDate"].text ?? "").isEmpty
        case .coinFlip: return segment["flipped"].bool == true
        case .diceRoll: return segment["rolled"].bool == true
        case .walk, .steps: return segment["reached"].bool == true
        case .bingo: return PlayKitBingoBoard(segment).filled.count == 9
        case .match, .classify: return segment["passed"].bool == true
        case .hangman: return segment["solved"].bool == true
        case .reaction, .ballShake, .quietHold, .countdown, .stopwatch, .shout: return segment["submitted"].bool == true
        }
    }
    /// An attempt cap is configuration, not proof an attempt occurred. In
    /// particular stopwatch exposes tries before it has an attempts field.
    public var reportedPass: Bool? {
        if kind == .photoCheck {
            if segment["degraded"].bool == true { return nil }
            if segment["passed"].bool == true { return true }
            if segment["flagged"].bool == true { return nil } // Explicit fallback readback has its own wording.
            return (segment["tries"].integer ?? 0) > 0 ? segment["passed"].bool : nil
        }
        let hasAttempt = (segment["attempts"].integer ?? 0) > 0
        guard complete || segment["submitted"].bool == true || segment["finished"].bool == true || hasAttempt else { return nil }
        return segment["passed"].bool
    }
    /// d6 and d20 use different authoritative wire fields. Never derive a
    /// missing total from pips, borrow the other mode's field, or reveal a
    /// configured/unacknowledged value before the server reports a roll.
    public var diceTotal: Int? {
        guard kind == .diceRoll, segment["rolled"].bool == true else { return nil }
        let mode = segment["mode"].text ?? "d6"
        if mode == "d20" { return segment["total"].integer }
        guard mode == "d6", let count = segment["diceCount"].integer, (1...2).contains(count),
              let sum = segment["sum"].integer, (count...(count * 6)).contains(sum) else { return nil }
        return sum
    }
    /// Only an authoritative attempt/result can select retry or terminal copy.
    /// Attempt limits alone never end a round; finished remains server-owned.
    public var reasoningResultKey: String? {
        guard [.sort, .match, .classify].contains(kind),
              let attempts = segment["attempts"].integer, attempts > 0,
              let passed = segment["passed"].bool else { return nil }
        if kind == .sort {
            guard let finished = segment["finished"].bool else { return nil }
            if passed { return finished ? "playkit.result.passed" : nil }
            if finished { return "playkit.reasoning.finishedNotPassed" }
        }
        if passed { return "playkit.result.passed" }
        return "playkit.reasoning.tryAgain"
    }
    /// Type-in verdict copy follows the server's submission flag, never the
    /// configured attempt cap or the locally measured text/time.
    public var typeInResultKey: String? {
        guard kind == .typeIn,
              let attempts = segment["attempts"].integer, attempts > 0,
              let submitted = segment["submitted"].bool,
              let passed = segment["passed"].bool else { return nil }
        if passed { return submitted ? "playkit.result.passed" : nil }
        return submitted ? "playkit.type.finishedNotPassed" : "playkit.type.retry"
    }
    /// The server's estimate tier is a readback, not a pass/fail or reward rule.
    /// Never infer a tier from a local guess, attempts, score or completion.
    public var estimateResultKey: String? {
        guard kind == .estimate, segment["submitted"].bool == true else { return nil }
        switch segment["tier"].text {
        case "HIT": return "playkit.estimate.result.hit"
        case "CLOSE": return "playkit.estimate.result.close"
        case "MISS": return "playkit.estimate.result.miss"
        default: return nil
        }
    }
    public var feedback: String? { segment["lastFeedback"].text ?? segment["feedback"].text }
    public var options: [PlayKitOption] {
        if kind == .predict || kind == .blindTaste { return PlayKitOption.read(segment["options"], idKey: "key") }
        if kind == .branch { return PlayKitOption.read(segment["currentStep"]["options"]) }
        if kind == .pricePair { return PlayKitOption.read(segment["items"], labelKey: "name") }
        return PlayKitOption.read(segment["options"])
    }
}

/// A retry verdict belongs to the submitted draft. Once that draft changes,
/// keep the old verdict hidden until a later server attempt or terminal result.
/// This only controls presentation; it never alters completion or submit gates.
public struct PlayKitReasoningFeedbackState: Equatable {
    private var editedKind: PlayKitScreenKind?
    private var editedAttempt: Int?
    public init() {}

    public mutating func markEdited(_ projection: PlayKitScreenProjection) {
        guard [.sort, .match, .classify].contains(projection.kind), !projection.complete else { return }
        editedKind = projection.kind
        editedAttempt = projection.segment["attempts"].integer
    }

    public func showsResult(for projection: PlayKitScreenProjection) -> Bool {
        guard editedKind == projection.kind else { return true }
        // An authoritative terminal result always remains visible, including
        // sort's finished-without-passing outcome. No attempt cap is consulted.
        if projection.complete { return true }
        guard let attempts = projection.segment["attempts"].integer else { return false }
        return attempts > max(0, editedAttempt ?? 0)
    }
}

/// A bounded picker over the public estimate range, matching mini's unit / ten /
/// power-of-ten ticks and inclusive upper endpoint. It never reads an answer,
/// tolerance, score or verdict. Numerically unsafe ranges have no picker.
public struct PlayKitEstimateWheel: Equatable {
    public static let maximumTicks = 2002
    public let minimum: Double
    public let maximum: Double
    public let ticks: [Double]
    public var initialIndex: Int { ticks.count / 2 }
    public init?(segment: PlayWireValue) {
        guard let lo = segment["min"].double, let hi = segment["max"].double,
              lo.isFinite, hi.isFinite, hi >= lo else { return nil }
        let span = hi - lo
        // Mini's decimal digit rule switches to exponent text at 1e21 and
        // would generate an unbounded list there. Reject that unsupported range.
        guard span.isFinite, span < 1e21 else { return nil }
        let step: Double
        if span <= 2000 { step = 1 }
        else if span <= 20000 { step = 10 }
        else {
            // Decimal powers up to 1e21 are exactly representable here. Using
            // log10 can round a just-below-power span into the next digit count.
            var scale = 1.0
            var decimalThreshold = 1000.0
            let roundedSpan = span.rounded()
            while roundedSpan >= decimalThreshold {
                scale *= 10; decimalThreshold *= 10
            }
            step = scale
        }
        guard step.isFinite, step > 0 else { return nil }
        let intervals = floor(span / step)
        // Check before converting or allocating, including for enormous ranges.
        guard intervals.isFinite, intervals >= 0, intervals <= Double(Self.maximumTicks - 2) else { return nil }
        var values: [Double] = []
        var value = lo
        while value <= hi {
            guard values.count < Self.maximumTicks - 1 else { return nil }
            values.append(value)
            if value == hi { break }
            // Match mini's repeated addition, including fractional lower bounds.
            let next = value + step
            guard next.isFinite, next > value else { return nil }
            value = next
        }
        if values.last != hi { values.append(hi) }
        guard values.count <= Self.maximumTicks else { return nil }
        minimum = lo; maximum = hi; ticks = values
    }
    public func value(at index: Int) -> Double? {
        guard ticks.indices.contains(index) else { return nil }
        return ticks[index]
    }
}

/// The board is a server-projected topic-progress readback. Tapping a tile cannot
/// mark it complete, award a line, redeem a reward or fabricate a backend action.
public struct PlayKitBingoBoard: Equatable {
    public static let lines = [[0,1,2], [3,4,5], [6,7,8], [0,3,6], [1,4,7], [2,5,8], [0,4,8], [2,4,6]]
    public let filled: Set<Int>
    public let segment: PlayWireValue
    public init(_ segment: PlayWireValue) {
        self.segment = segment
        filled = Set((segment["filledPositions"].array ?? []).compactMap(\.integer).filter { (0..<9).contains($0) })
    }
    public var completedLines: [[Int]] { Self.lines.filter { Set($0).isSubset(of: filled) } }
    public var linePositions: Set<Int> { Set(completedLines.flatMap { $0 }) }
    public func title(at index: Int) -> String {
        let specs = segment["cellSpecs"].array ?? [], labels = segment["labels"].array ?? []
        return specs.indices.contains(index) ? (specs[index]["t"].text ?? "") : labels.indices.contains(index) ? (labels[index].text ?? "") : ""
    }
    public func instruction(at index: Int) -> String {
        let specs = segment["cellSpecs"].array ?? []
        return specs.indices.contains(index) ? (specs[index]["how"].text ?? "") : ""
    }
}

/// Immutable review identity: it cannot silently acquire a new server version while
/// a confirmation sheet, keyboard or camera is on screen. No answer data is persisted.
public struct PlayKitActionReview: Equatable, Identifiable {
    public let id: UUID
    public let sessionID: Int; public let version: Int
    public let kind: String; public let action: String
    public let payload: [String: PlayWireValue]
    public let compareQuestion: PlayCompareQuestion?
    let owner: PlayExperienceSession
    init(state: PlayAdvancedState, owner: PlayExperienceSession, kind: String, action: String, payload: [String: PlayWireValue]) {
        id = UUID(); sessionID = state.sessionID; version = state.version
        self.owner = owner; self.kind = kind; self.action = action; self.payload = payload
        compareQuestion = kind == "compare" ? (try? PlayCompareQuestion(state.playKit["compare"])) : nil
    }
}

public enum PlayKitInputContract {
    public static func validate(kind: String, action: String, payload: [String: PlayWireValue], segment: PlayWireValue) throws {
        guard let kind = PlayKitScreenKind(rawValue: kind) else { return } // Other existing kits keep their established boundary.
        guard segment.object != nil, !PlayKitScreenProjection(kind: kind, segment: segment).complete else { throw PlayExperienceError.invalidAction }
        let keys = Set(payload.keys)
        func require(_ condition: Bool) throws { if !condition { throw PlayExperienceError.invalidAction } }
        func text(_ key: String, max: Int = 4096) -> Bool {
            guard let value = payload[key]?.text else { return false }
            return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.utf16.count <= max
        }
        func finite(_ key: String, range: ClosedRange<Double>) -> Bool {
            guard let value = payload[key]?.double else { return false }; return value.isFinite && range.contains(value)
        }
        if action == "START_CHALLENGE" {
            try require(kind.isChallenge && keys == ["game"] && payload["game"]?.text == kind.rawValue); return
        }
        let projection = PlayKitScreenProjection(kind: kind, segment: segment)
        switch kind {
        case .qa:
            let mode = (segment["mode"].text ?? "TYPE").uppercased()
            if mode == "SHOT" { try require(keys == ["imageUrl"] && PlayExperienceService.validHTTPS(payload["imageUrl"]?.text ?? "")) }
            else if mode == "PICK", segment["multi"].bool == true {
                let ids = (payload["optionIds"]?.array ?? []).compactMap(\.text)
                try require(keys == ["optionIds"] && !ids.isEmpty && ids.count == payload["optionIds"]?.array?.count && Set(ids).count == ids.count && Set(ids).isSubset(of: Set(projection.options.map(\.id))))
            } else if mode == "PICK" { try require(keys == ["optionId"] && projection.options.contains { $0.id == payload["optionId"]?.text }) }
            else {
                try require(keys == ["input"] && text("input"))
                if let pool = try PlayQuestionLetterPool(question: segment) {
                    let picked = (payload["input"]?.text ?? "").map(String.init)
                    try require(picked.count == pool.answerLength && LetterPoolState.fits(picked, in: pool.chars))
                }
            }
        case .branch: try require(keys == ["optionId"] && projection.options.contains { $0.id == payload["optionId"]?.text })
        case .pricePair: try require(keys == ["pickId"] && projection.options.contains { $0.id == payload["pickId"]?.text })
        case .predict: try require(keys == ["optionKey"] && projection.options.contains { $0.id == payload["optionKey"]?.text })
        case .estimate:
            guard let lo = segment["min"].double, let hi = segment["max"].double, lo.isFinite, hi.isFinite, hi >= lo else { throw PlayExperienceError.malformed }
            try require(keys == ["value"] && finite("value", range: lo...hi))
        case .hiddenObject: try require(keys == ["x", "y"] && finite("x", range: 0...1) && finite("y", range: 0...1))
        case .scan: try require(keys == ["code"] && text("code", max: 4096))
        case .photoCheck:
            // CG-ALL-12: a RECORD station takes only SUBMIT_PHOTO_RECORD, an ordinary one only SUBMIT_PHOTO_CHECK.
            try require(action == PlayKitPhotoRecordMode.submitAction(for: segment))
            if PlayKitPhotoRecordMode.applies(segment), payload == PlayKitPhotoRecordMode.textConfirmedPayload { break }
            try require(keys == ["imageUrl"] && PlayExperienceService.validHTTPS(payload["imageUrl"]?.text ?? ""))
            // #866 submitPhotoRecord caps the recorded photo URL at 512 characters.
            if PlayKitPhotoRecordMode.applies(segment) { try require((payload["imageUrl"]?.text?.count ?? 0) <= 512) }
        case .profile:
            guard keys == ["answers", "avatarUrl"], let answers = payload["answers"]?.object else { throw PlayExperienceError.invalidAction }
            let questions = segment["questions"].array ?? [], questionKeys = Set(questions.compactMap { $0["key"].text })
            try require(Set(answers.keys).isSubset(of: questionKeys))
            for question in questions {
                guard let key = question["key"].text, !key.isEmpty else { throw PlayExperienceError.malformed }
                let answer = answers[key]?.text ?? ""
                // Current mini-program projection marks every profile question required.
                try require(!answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                let limit = question["maxLength"].integer ?? 0
                try require(answer.utf16.count <= (limit > 0 ? limit : 4096))
                if question["kind"].text == "pick" { try require(PlayKitOption.read(question["options"], idKey: "key").contains { $0.id == answer }) }
            }
            let avatar = payload["avatarUrl"]?.text ?? ""
            try require(avatar.isEmpty || PlayExperienceService.validHTTPS(avatar))
            if segment["avatar"]["required"].bool == true { try require(!avatar.isEmpty) }
        case .note:
            let limit = segment["maxLength"].integer ?? 40
            try require(keys == ["text"] && text("text", max: limit > 0 ? limit : 40))
        case .typeIn: try require(keys == ["text", "elapsedMs"] && text("text") && finite("elapsedMs", range: 0...3_600_000))
        case .reaction:
            let times = payload["roundsMs"]?.array ?? [], expected = segment["rounds"].integer ?? 3
            try require(keys == ["roundsMs"] && times.count == (expected > 0 ? expected : 3) && times.allSatisfy { ($0.integer ?? -1) >= 120 && ($0.integer ?? Int.max) <= 60_000 })
        case .ballShake: try require(keys == ["hits"] && finite("hits", range: 0...100_000))
        case .quietHold, .shout: try require(keys == ["heldMs"] && finite("heldMs", range: 0...3_600_000))
        case .countdown, .coinFlip, .diceRoll, .random: try require(payload.isEmpty)
        case .stopwatch: try require(keys == ["stoppedMs"] && finite("stoppedMs", range: 0...3_600_000))
        case .dailySign:
            let limit = segment["textMax"].integer ?? 40
            try require(keys == ["text", "photoUrl"] && text("text", max: limit > 0 ? limit : 40))
            let photo = payload["photoUrl"]?.text ?? ""; try require(photo.isEmpty || PlayExperienceService.validHTTPS(photo))
        case .sort:
            let ids = PlayKitOption.read(segment["items"]).map(\.id), order = (payload["order"]?.array ?? []).compactMap(\.text)
            try require(keys == ["order"] && !ids.isEmpty && order.count == ids.count && order.count == payload["order"]?.array?.count && Set(order) == Set(ids))
        case .match:
            let left = Set(PlayKitOption.read(segment["left"]).map(\.id)), right = Set(PlayKitOption.read(segment["right"]).map(\.id))
            let pairs = payload["pairs"]?.array ?? []
            let rows = pairs.compactMap { $0.array?.compactMap(\.text) }
            try require(keys == ["pairs"] && !left.isEmpty && rows.count == left.count && rows.count == pairs.count && pairs.allSatisfy { $0.array?.count == 2 } && rows.allSatisfy { $0.count == 2 })
            try require(Set(rows.map { $0[0] }) == left && Set(rows.map { $0[1] }) == right)
        case .classify:
            let items = Set(PlayKitOption.read(segment["items"]).map(\.id)), bins = Set(PlayKitOption.read(segment["bins"]).map(\.id))
            let placement = payload["placement"]?.object ?? [:]
            try require(keys == ["placement"] && !items.isEmpty && Set(placement.keys) == items && placement.values.allSatisfy { bins.contains($0.text ?? "") })
        case .compare:
            try require(action == "SUBMIT_COMPARE")
            try PlayCompareQuestion(segment).validate(payload)
        case .compass: try require(keys == ["bearing"] && finite("bearing", range: 0...359))
        case .hangman:
            try require(action == "SUBMIT_HANGMAN")
            try PlayHangmanProjection(segment).validate(payload)
        case .blindTaste: try require(keys == ["key"] && projection.options.contains { $0.id == payload["key"]?.text })
        case .diyName: try require(keys == ["name"] && text("name", max: max(1, segment["maxLength"].integer ?? 16)))
        case .slowTask:
            try require(payload.isEmpty)
            if action == "START_SLOW_TASK" { try require(segment["started"].bool != true) }
            else if action == "CLAIM_SLOW_TASK" { try require(segment["started"].bool == true && segment["daysLeft"].integer == 0) }
            else { throw PlayExperienceError.unsupported }
        case .silentOrder, .musicCorner, .timeWindow: throw PlayExperienceError.unsupported
        case .bingo, .walk, .steps: throw PlayExperienceError.unsupported // WeChat encrypted step proof has no approved native replacement.
        }
    }
    /// Match the backend's UTF-16 limits without splitting a visible grapheme.
    public static func limitText(_ text: String, toUTF16 limit: Int) -> String {
        var result = "", used = 0
        for character in text {
            let value = String(character), units = value.utf16.count
            guard used + units <= max(0, limit) else { break }
            result += value; used += units
        }
        return result
    }
    /// Aspect-fit image hit testing. Letterboxing and out-of-image taps are rejected,
    /// not clamped into a valid-looking corner hit.
    public static func imagePoint(x: Double, y: Double, viewWidth: Double, viewHeight: Double, imageWidth: Double, imageHeight: Double) -> (Double, Double)? {
        guard [x,y,viewWidth,viewHeight,imageWidth,imageHeight].allSatisfy(\.isFinite), viewWidth > 0, viewHeight > 0, imageWidth > 0, imageHeight > 0 else { return nil }
        let scale = min(viewWidth / imageWidth, viewHeight / imageHeight)
        let width = imageWidth * scale, height = imageHeight * scale
        let localX = x - (viewWidth - width) / 2, localY = y - (viewHeight - height) / 2
        guard (0...width).contains(localX), (0...height).contains(localY) else { return nil }
        return ((localX / width * 10_000).rounded() / 10_000, (localY / height * 10_000).rounded() / 10_000)
    }
}

/// Read-only receipt for the current server segment. This does not select a
/// local card, determine completion, or retain results across revisions.
public struct PlayKitPricePairResult: Equatable {
    public let lastPickID: String
    public let passed: Bool
    public let finished: Bool
    public let answerID: String?
    public init?(segment: PlayWireValue) {
        guard let rows = segment["items"].array, !rows.isEmpty,
              let attempts = segment["attempts"].integer, attempts > 0,
              let finished = segment["finished"].bool,
              let passed = segment["passed"].bool,
              let lastPick = segment["lastPickId"].text, !lastPick.isEmpty else { return nil }
        let ids = rows.compactMap { $0["id"].text }
        guard ids.count == rows.count, ids.allSatisfy({ !$0.isEmpty }),
              Set(ids).count == ids.count, ids.contains(lastPick),
              !passed || finished else { return nil }
        var answer: String?
        if finished {
            // Both successful and exhausted rounds publish the answer. Missing,
            // unknown or contradictory receipts must never highlight a card.
            guard let reported = segment["answerId"].text, ids.contains(reported),
                  passed ? reported == lastPick : reported != lastPick else { return nil }
            answer = reported
        }
        lastPickID = lastPick; self.passed = passed; self.finished = finished; answerID = answer
    }
}

/// CG-ALL-12 / CG-02-D-4 (aligned to hengyin #866): `photoCheck.mode == "RECORD"` marks a
/// keepsake photo station. The server never runs the vision model there and rejects
/// SUBMIT_PHOTO_CHECK; every submission is SUBMIT_PHOTO_RECORD with either the uploaded
/// photo `{imageUrl}` or, when the player has no camera or declines it, `{textConfirmed:true}`.
/// The server then marks the step passed with verdict RECORDED (not a verified photo).
/// Any other mode (absent, CARD) stays an ordinary photo check.
public enum PlayKitPhotoRecordMode {
    public static let mode = "RECORD"
    public static let action = "SUBMIT_PHOTO_RECORD"
    public static func applies(_ segment: PlayWireValue) -> Bool { segment["mode"].text == mode }
    /// The submit action for this photo segment.
    public static func submitAction(for segment: PlayWireValue) -> String { applies(segment) ? action : "SUBMIT_PHOTO_CHECK" }
    /// Text confirmation instead of a photo; only valid on a RECORD station.
    public static let textConfirmedPayload: [String: PlayWireValue] = ["textConfirmed": .bool(true)]
}

/// CG-09-P2-5 / CG-10-D-3: an optional reference picture an author attaches to a
/// puzzle for players who cannot see the real object clearly. Absent = no entry.
public enum PlayKitReferenceImage {
    public static let keys = ["referenceImage", "referenceImageUrl"]
    public static func source(in segment: PlayWireValue) -> String? {
        for key in keys {
            if let value = segment[key].text?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty { return value }
        }
        return nil
    }
}

/// CG-07-P2-2: the server's per-node `completionMode` as a player label. Skipped and
/// revealed nodes are assisted completions, not answer proof. Unknown values keep the
/// server text verbatim (`nil` here). Desk and alternate-station starts are a run-level
/// fact (`runStartMode`, see `PlayRunStartMode`), not a per-node completion mode.
public enum PlayCompletionModePresentation: String, Equatable, CaseIterable {
    case solved, assisted
    public init?(raw: String?) {
        switch raw?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
        case "SOLVED", "LEGITIMATE_COMPLETION": self = .solved
        case "SKIPPED", "REVEALED", "ASSISTED", "ASSISTED_COMPLETION": self = .assisted
        default: return nil
        }
    }
    public var labelKey: String { "playx.completion." + rawValue }
    public var isAssisted: Bool { self != .solved }
}

/// CG-01-P2-9 / CG-09-P2-6 / CG-10-P2-6: player-side stage events, named exactly as the
/// hengyin #866 `ApiAnalyticsController` whitelist. No answers, typed text or photos are
/// recorded: properties carry only codes (nodeId, kit, issueKind).
public enum PlayStageEvent: String, Equatable, CaseIterable {
    case stageEnter = "stage_enter", hintOpen = "hint_open", stageSkip = "stage_skip"
    case assistedComplete = "assisted_complete", wrongAnswer = "wrong_answer"
    case stageIssueReport = "stage_issue_report", materialView = "material_view"
}
/// `stage_issue_report` categories; the server rejects the event without one of these.
public enum PlayStageIssueKind: String, Equatable, CaseIterable {
    case altMaterial = "ALT_MATERIAL", notFound = "NOT_FOUND", unreadable = "UNREADABLE", logicError = "LOGIC_ERROR"
    public var labelKey: String {
        switch self {
        case .altMaterial: return "playkit.issue.altMaterial"
        case .notFound: return "playkit.issue.notFound"
        case .unreadable: return "playkit.issue.unreadable"
        case .logicError: return "playkit.issue.logicError"
        }
    }
}
public struct PlayStageEventRecord: Equatable {
    public let id: UUID
    public let event: PlayStageEvent; public let nodeID: Int?; public let kind: String?
    public let issueKind: PlayStageIssueKind?
    public let occurredAt: Date
    public init(event: PlayStageEvent, nodeID: Int?, kind: String?, issueKind: PlayStageIssueKind? = nil, id: UUID = UUID(), occurredAt: Date = Date()) {
        self.id = id; self.event = event; self.nodeID = nodeID; self.kind = kind
        self.issueKind = event == .stageIssueReport ? issueKind : nil; self.occurredAt = occurredAt
    }
}
/// Bounded on-device queue. Events leave the device only through
/// `PlayStageAnalyticsUploader`, which the app runs only under an approved runtime grant.
public final class PlayStageEventLog {
    public static let shared = PlayStageEventLog()
    public static let capacity = 200
    private let lock = NSLock()
    private var storage: [PlayStageEventRecord] = []
    public init() {}
    public var entries: [PlayStageEventRecord] { lock.lock(); defer { lock.unlock() }; return storage }
    public func record(_ event: PlayStageEvent, nodeID: Int? = nil, kind: String? = nil, issueKind: PlayStageIssueKind? = nil, now: Date = Date()) {
        // The server refuses an issue report without a category; never queue one.
        if event == .stageIssueReport, issueKind == nil { return }
        lock.lock(); defer { lock.unlock() }
        storage.append(.init(event: event, nodeID: nodeID, kind: kind, issueKind: issueKind, occurredAt: now))
        if storage.count > Self.capacity { storage.removeFirst(storage.count - Self.capacity) }
    }
    public func remove(_ ids: Set<UUID>) { lock.lock(); storage.removeAll { ids.contains($0.id) }; lock.unlock() }
    public func removeAll() { lock.lock(); storage.removeAll(); lock.unlock() }
}

/// `POST /api/analytics/events/batch` body (hengyin #866 `AnalyticsBatchDTO`): at most 50
/// events, each with an idempotency key, `bizType=topic_node` and `bizId=<node id>`.
/// No actorScope is sent (optional for these events); events older than the server's
/// 14-day window are dropped rather than sent, since one stale event fails the batch.
public enum PlayStageAnalyticsBatch {
    public static let path = "api/analytics/events/batch"
    public static let maxBatch = 50
    public static let maxAge: TimeInterval = 13 * 24 * 60 * 60
    public static func sendable(_ records: [PlayStageEventRecord], now: Date = Date()) -> (send: [PlayStageEventRecord], stale: [PlayStageEventRecord]) {
        let fresh = records.filter { now.timeIntervalSince($0.occurredAt) <= maxAge && $0.occurredAt.timeIntervalSince(now) <= 60 }
        let freshIDs = Set(fresh.map(\.id))
        return (Array(fresh.prefix(maxBatch)), records.filter { !freshIDs.contains($0.id) })
    }
    public static func event(_ record: PlayStageEventRecord) throws -> [String: Any] {
        var properties: [String: Any] = [:]
        if let node = record.nodeID { properties["nodeId"] = node }
        if let kind = record.kind, kind.range(of: "^[A-Za-z][A-Za-z0-9_]{0,39}$", options: .regularExpression) != nil { properties["kit"] = kind }
        if let issue = record.issueKind { properties["issueKind"] = issue.rawValue }
        var value: [String: Any] = [
            "eventName": record.event.rawValue, "source": "ios",
            "idempotencyKey": "ios-stage-" + record.id.uuidString.lowercased(),
            "occurredAt": Int64((record.occurredAt.timeIntervalSince1970 * 1000).rounded()),
            "propertiesJson": String(decoding: try JSONSerialization.data(withJSONObject: properties, options: [.sortedKeys]), as: UTF8.self)
        ]
        if let node = record.nodeID, node > 0 { value["bizType"] = "topic_node"; value["bizId"] = node }
        return value
    }
    public static func body(_ records: [PlayStageEventRecord]) throws -> Data {
        guard !records.isEmpty, records.count <= maxBatch else { throw APIError.invalidRequest }
        return try JSONSerialization.data(withJSONObject: ["events": try records.map(event)], options: [.sortedKeys])
    }
}

/// Drains `PlayStageEventLog` to the #866 batch endpoint. A transport failure keeps the
/// events for a later flush; a definitive server answer (accepted or refused) removes the
/// batch so a refused event can never block the queue.
@MainActor public struct PlayStageAnalyticsUploader {
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    private let token: () -> String?
    public init(configuration: APIConfiguration, transport: any HTTPTransport, token: @escaping () -> String?) {
        self.configuration = configuration; self.transport = transport; self.token = token
    }
    @discardableResult
    public func flush(_ log: PlayStageEventLog = .shared, now: Date = Date()) async -> Int {
        let split = PlayStageAnalyticsBatch.sendable(log.entries, now: now)
        log.remove(Set(split.stale.map(\.id)))
        guard !split.send.isEmpty, let token = token(),
              let body = try? PlayStageAnalyticsBatch.body(split.send),
              let request = try? OperationAdapterHTTP.json(configuration: configuration, path: PlayStageAnalyticsBatch.path, body: body, token: token),
              let response = try? await transport.send(request) else { return 0 }
        let status = response.1
        guard (200..<500).contains(status), status != 401, status != 429 else { return 0 }
        log.remove(Set(split.send.map(\.id)))
        return split.send.count
    }
}
