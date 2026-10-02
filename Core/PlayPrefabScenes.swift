import Foundation

/// Source scene interactions layered on the shared PrefabPreviewState. This is local
/// narrative state only. It never creates server completion, GPS or upload evidence.
public struct PlayPrefabSceneMachine: Equatable {
    public private(set) var story: PrefabPreviewState
    public private(set) var bootText = ""
    public private(set) var bootFailed = false
    public private(set) var bootDone = false
    public private(set) var walking = false
    public private(set) var waitingForRoute = false
    public private(set) var waitingForSign = false
    public private(set) var holding = false
    public private(set) var holdProgress: Double = 0
    public private(set) var quizIndex = 0
    public private(set) var quizScore = 0
    public private(set) var dreamIndex = 0
    public private(set) var check: PrefabPreviewCheck?
    public private(set) var checkLabel: String?
    private var bootAnchor: TimeInterval?
    private var walkAnchor: TimeInterval?
    private var holdAnchor: TimeInterval?
    private var dreamAnchor: TimeInterval?
    private var teacherAnchor: TimeInterval?
    private var checkDestination: String?
    public init(story: PrefabPreviewState) {
        self.story = story
        waitingForRoute = story.scene == .walk && story.walkProgress == 50 && story.picks["route"] == nil
        waitingForSign = story.scene == .walk && story.walkProgress == 74 && story.picks["signAsked"]?.bool == true && story.picks["sign"] == nil
    }
    public static let bootTarget = "hello world"
    public static let quizOptions = [["模型比例是 1:100", "模型比例是 1:500"], ["人民广场", "陆家嘴"], ["一条已经走过的路", "一块你从没去过的地方"]]
    public static let quizAnswers = [1, 0, 1]
    public static let jobs = ["设计师", "程序员", "医生", "老师", "销售", "会计"]
    public mutating func next() throws {
        guard story.scene == .prologue || (story.scene == .register && story.step == 5) || (story.scene == .boot && bootDone) else { throw PlayExperienceError.invalidAction }
        advance()
    }
    public mutating func register(profile: PrefabPreviewProfile) throws {
        guard story.scene == .register, story.step != 5, !profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw PlayExperienceError.invalidAction }
        var clean = profile; clean.avatar = story.profile.avatar
        story.applyProfile(clean); story.step = 5
    }
    public mutating func typeBoot(_ input: String, now: TimeInterval) {
        guard story.scene == .boot, !bootDone, now.isFinite else { return }
        if input == bootText { return }
        let isOneAppend = input.count == bootText.count + 1 && input.hasPrefix(bootText)
        let isOneDelete = input.count == max(0, bootText.count - 1) && bootText.hasPrefix(input)
        guard isOneAppend || isOneDelete else { resetBoot(failed: true); return }
        if bootAnchor == nil { bootAnchor = now }; bootText = input
        guard Self.bootTarget.hasPrefix(input), now - (bootAnchor ?? now) < 10 else { resetBoot(failed: true); return }
        if input == Self.bootTarget {
            if now - (bootAnchor ?? now) < 6 { let current = story.skills["precision"] ?? 0; story.skills["precision"] = current == Int.max ? Int.max : current + 1 }
            bootDone = true; bootAnchor = nil; bootFailed = false
        }
    }
    public mutating func startWalk(now: TimeInterval) {
        guard story.scene == .walk, !waitingForRoute, !waitingForSign, story.walkProgress < 100 else { return }
        walking = true; walkAnchor = now
    }
    public mutating func chooseRoute(_ value: Int, now: TimeInterval) throws {
        guard story.scene == .walk, waitingForRoute, (0...1).contains(value) else { throw PlayExperienceError.invalidAction }
        story.picks["route"] = .number(Double(value)); if value == 1 { story.gain(luck: 1) }
        waitingForRoute = false; startWalk(now: now)
    }
    public mutating func skipSign(now: TimeInterval) throws {
        guard story.scene == .walk, waitingForSign else { throw PlayExperienceError.invalidAction }
        story.picks["sign"] = .string("skip"); waitingForSign = false; startWalk(now: now)
    }
    public mutating func chooseBirth(_ value: Int) throws {
        guard story.scene == .birth, story.step == 0, (0...2).contains(value) else { throw PlayExperienceError.invalidAction }
        story.picks["first"] = .number(Double(value)); if value == 1 { story.gain(thought: "afternoon") }; story.step = 1
    }
    public mutating func beginHold(now: TimeInterval) {
        guard (story.scene == .birth && story.step == 1) || story.scene.isDream else { return }
        holding = true; holdAnchor = now; holdProgress = 0
    }
    public mutating func stopHold() { holding = false; holdAnchor = nil; holdProgress = 0 }
    public mutating func receivePhoto(key: String, url: String, now: TimeInterval) throws {
        guard PlayExperienceService.validHTTPS(url) else { throw PlayExperienceError.invalidAction }
        switch (story.scene, key) {
        case (.hall, "hall"): story.photos[key] = url; advance()
        case (.walk, "sign") where waitingForSign:
            story.photos[key] = url; story.picks["sign"] = .string("photo"); story.gain(luck: 1); waitingForSign = false; startWalk(now: now)
        case (.birth, "window") where story.step == 2: story.photos[key] = url; story.step = 3
        case (.work, "phone") where story.step == 1: story.photos[key] = url; advance()
        case (.register, "avatar"): story.profile.avatar = url
        default: throw PlayExperienceError.invalidAction
        }
    }
    public mutating func leaveWindowNote(_ text: String) throws {
        guard story.scene == .birth, story.step == 3, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= 40 else { throw PlayExperienceError.invalidAction }
        story.note = text.trimmingCharacters(in: .whitespacesAndNewlines); story.observe(where: "展示馆的窗", text: story.note); advance()
    }
    public mutating func answerQuiz(_ choice: Int) throws {
        guard story.scene == .learning, story.step == 0, (0...1).contains(choice), quizIndex < 3 else { throw PlayExperienceError.invalidAction }
        if choice == Self.quizAnswers[quizIndex] { quizScore += 1 }; quizIndex += 1
        if quizIndex == 3 { story.picks["quiz"] = .number(Double(quizScore)); if quizScore >= 2 { story.gain(luck: 1) }; story.step = 1 }
    }
    public mutating func recordCount(_ count: Int, now: TimeInterval) throws {
        guard story.scene == .learning, story.step == 1, (0...999).contains(count) else { throw PlayExperienceError.invalidAction }
        story.picks["count"] = .number(Double(count)); story.observe(where: "展示馆", text: "模型前，有 \(count) 个人在低头看手机。")
        story.step = 2; teacherAnchor = now
    }
    public mutating func chooseTeacher(_ value: Int, rolls: [Int]) throws {
        guard story.scene == .learning, story.step == 2, (0...3).contains(value) else { throw PlayExperienceError.invalidAction }
        teacherAnchor = nil; story.picks["teacher"] = .number(Double(value))
        switch value {
        case 1: story.step = 3
        case 0: beginCheck(skill: "rule", dc: 9, label: "standard", destination: "teacherStandard", rolls: rolls)
        case 2: beginCheck(skill: "heart", dc: 10, label: "noanswer", destination: "teacherQuestion", rolls: rolls)
        default: advance()
        }
    }
    public mutating func chooseTeacherWindow(_ value: Int, rolls: [Int]) throws {
        guard story.scene == .learning, story.step == 3, (0...1).contains(value) else { throw PlayExperienceError.invalidAction }
        story.picks["window"] = .number(Double(value))
        if value == 0 { advance() } else { beginCheck(skill: "precision", dc: 10, label: "precise", destination: "teacherPrecision", rolls: rolls) }
    }
    public mutating func placeSticker(_ label: String) throws {
        guard story.scene == .career, story.step == 0, !label.isEmpty else { throw PlayExperienceError.invalidAction }
        // Source stores a board-space marker at x=150,y=388. It is not a GPS coordinate.
        story.sticker = PrefabPreviewSticker(label: label, x: 150, y: 388); story.step = 1
    }
    public mutating func chooseCareer(_ name: String) throws {
        guard story.scene == .career, story.step == 1, Self.jobs.contains(name) else { throw PlayExperienceError.invalidAction }
        story.job = name; advance()
    }
    public mutating func chooseBoss(_ value: Int, rolls: [Int]) throws {
        guard story.scene == .work, story.step == 0, (0...3).contains(value) else { throw PlayExperienceError.invalidAction }
        story.picks["boss"] = .number(Double(value))
        switch value {
        case 1: beginCheck(skill: "rule", dc: 10, label: "rule", destination: "boss", rolls: rolls)
        case 2: beginCheck(skill: "heart", dc: 11, label: "heart", destination: "boss", rolls: rolls)
        case 3: story.gain(thought: "afternoon"); story.step = 1
        default: story.step = 1
        }
    }
    public mutating func closeCheck() {
        guard let check, let destination = checkDestination else { return }
        switch destination {
        case "teacherStandard": if check.ok { story.gain(thought: "standard") } else { story.gain(hp: -1) }; advance()
        case "teacherQuestion": if check.ok { story.gain(thought: "noanswer") }; advance()
        case "teacherPrecision": if check.ok { story.gain(thought: "precise") } else { story.gain(hp: -1) }; advance()
        case "boss": if !check.ok { story.gain(hp: -1) }; story.step = 1
        default: break
        }
        self.check = nil; checkLabel = nil; checkDestination = nil
    }
    /// Returns true only at source commit/checkpoint boundaries, not every visual tick.
    public mutating func tick(now: TimeInterval) -> Bool {
        guard now.isFinite else { return false }
        if story.scene == .boot, let anchor = bootAnchor, now - anchor >= 10 { resetBoot(failed: true) }
        if story.scene == .walk, walking, let anchor = walkAnchor, now - anchor >= 0.08 {
            walkAnchor = now; story.walkProgress = min(100, story.walkProgress + 2)
            if story.walkProgress == 50, story.picks["route"] == nil { walking = false; waitingForRoute = true; return true }
            if story.walkProgress == 74, story.picks["signAsked"]?.bool != true { story.picks["signAsked"] = .bool(true); walking = false; waitingForSign = true; return true }
            if story.walkProgress == 100 { walking = false; advance(); return true }
        }
        if holding, let anchor = holdAnchor {
            let target = story.scene.isDream ? 1.5 : 3.0; holdProgress = min(1, max(0, (now - anchor) / target))
            if holdProgress >= 1 { stopHold(); if story.scene.isDream { finishDream() } else { story.step = 2 }; return true }
        }
        if story.scene.isDream {
            if dreamAnchor == nil { dreamAnchor = now }
            let lengths: [PrefabPreviewScene: Int] = [.dream1: 10, .dream2: 12, .dream3: 4]
            let count = lengths[story.scene] ?? 0, elapsed = max(0, now - (dreamAnchor ?? now))
            dreamIndex = min(max(0, count - 1), Int(elapsed / 1.8))
            if count > 0, elapsed >= Double(count - 1) * 1.8 + 2.2 { finishDream(); return true }
        }
        if story.scene == .learning, story.step == 2 {
            if teacherAnchor == nil { teacherAnchor = now }
            if now - (teacherAnchor ?? now) >= 8 { try? chooseTeacher(3, rolls: []); return true }
        }
        return false
    }
    public mutating func interrupt() {
        resetBoot(failed: false); walking = false; walkAnchor = nil; stopHold(); dreamAnchor = nil; teacherAnchor = nil
    }
    private mutating func beginCheck(skill: String, dc: Int, label: String, destination: String, rolls: [Int]) {
        check = story.check(skill: skill, dc: dc, rolls: rolls); checkLabel = label; checkDestination = destination
    }
    private mutating func finishDream() { story.gain(dreams: 1); dreamAnchor = nil; dreamIndex = 0; advance() }
    private mutating func advance() {
        story.advance(); teacherAnchor = nil; dreamAnchor = nil; holdAnchor = nil; walking = false
        waitingForRoute = false; waitingForSign = false; quizIndex = 0; quizScore = 0
    }
    private mutating func resetBoot(failed: Bool) { bootAnchor = nil; bootText = ""; bootFailed = failed }
}
