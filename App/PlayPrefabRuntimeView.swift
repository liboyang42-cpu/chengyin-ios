import SwiftUI

/// Interactive source scenes use the same story-state engine as PrefabPreview. This
/// view never reads preview storage; photo/arrival/sync travel through the live adapter.
@MainActor struct PlayPrefabRuntimeView: View {
    @Bindable var model: PlayPrefabRuntimeCoordinator
    var dice: () -> [Int] = { [Int.random(in: 1...6), Int.random(in: 1...6)] }
    @State private var scene = PlayPrefabSceneMachine(story: .init())
    @State private var loaded = false
    @State private var profile = PrefabPreviewProfile()
    @State private var text = ""
    @State private var count = ""
    @State private var photoKey: String?
    @State private var confirmPhoto = false
    @State private var confirmSync = false
    @State private var localIssue: PlayExperienceError?
    @Environment(\.scenePhase) private var scenePhase
    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }
    var body: some View {
        List {
            Section {
                Text("playx.prefab.runtimeNotice").font(.footnote)
                if let station = model.station {
                    if let name = station.name { Text(verbatim: name).font(.headline) }
                    if let address = station.address { Text(verbatim: address) }
                }
                if let issue = model.issue ?? localIssue { PlayExperienceIssueView(issue: issue) }
                if model.phase == "unknown" { Text("playx.unknown.body"); Button("playx.reconcile") { Task { await model.load() } } }
                if !model.canCapture { Text("playx.device.disabled") }
            }
            if loaded {
                Section {
                    Text(LocalizedStringKey("templateAuthor.prefab.scene." + scene.story.scene.rawValue)).font(.title2.bold())
                    sceneBody
                }.disabled(model.phase != "ready")
                Section("templateAuthor.prefab.state") {
                    LabeledContent("templateAuthor.prefab.hp") { Text(verbatim: String(scene.story.hp)) }
                    LabeledContent("templateAuthor.prefab.luck") { Text(verbatim: String(scene.story.luck)) }
                    LabeledContent("templateAuthor.prefab.dreams") { Text(verbatim: String(scene.story.dreams)) }
                    ForEach(scene.story.skills.keys.sorted(), id: \.self) { key in
                        LabeledContent(LocalizedStringKey("templateAuthor.prefab.skill." + key)) { Text(verbatim: String(scene.story.skills[key] ?? 0)) }
                    }
                }
                Section("templateAuthor.prefab.observations") {
                    ForEach(Array(scene.story.observations.enumerated()), id: \.offset) { _, item in Text(verbatim: item.text) }
                }
                if let check = scene.check {
                    Section("playx.prefab.check") {
                        LabeledContent("playx.prefab.dice") { Text(verbatim: check.dice.map(String.init).joined(separator: " + ")) }
                        LabeledContent("playx.prefab.score") { Text(verbatim: "\(check.score) / \(check.dc)") }
                        Text(LocalizedStringKey(check.ok ? "playx.prefab.check.success" : "playx.prefab.check.failure"))
                        Button("playx.prefab.continue") { scene.closeCheck(); save() }
                    }
                }
            }
        }.privacySensitive().navigationTitle("playx.prefab.title").accessibilityIdentifier("playx.prefab.runtime")
            .overlay(alignment: .bottom) {
                TimelineView(.periodic(from: .now, by: 0.08)) { context in
                    Color.clear.frame(height: 0).onChange(of: context.date) { _, _ in
                        guard scenePhase == .active, loaded, model.phase == "ready" else { return }
                        if scene.tick(now: now) { save() }
                    }
                }.accessibilityHidden(true)
            }
            .task { await model.load(); restoreIfAvailable() }
            .onChange(of: model.phase) { _, phase in if phase == "ready" { restoreIfAvailable() } }
            .onChange(of: model.record?.story.photos) { _, photos in
                guard loaded, let key = photoKey, let url = photos?[key] else { return }
                do { try scene.receivePhoto(key: key, url: url, now: now); photoKey = nil; save() }
                catch { localIssue = .invalidAction }
            }
            .onChange(of: scenePhase) { _, phase in if phase != .active { scene.interrupt(); save(); model.cancelDeviceWork() } }
            .onDisappear { scene.interrupt(); save(); model.cancelDeviceWork() }
            .confirmationDialog("playx.prefab.photo", isPresented: $confirmPhoto, titleVisibility: .visible) {
                Button("playx.prefab.photo.upload") {
                    if photoKey == "hall" { Task { await model.arriveAndCaptureHallPhoto() } }
                    else if let photoKey { Task { await model.captureStoryPhoto(key: photoKey) } }
                }
            } message: { Text("playx.prefab.photo.consent") }
            .confirmationDialog("playx.prefab.sync", isPresented: $confirmSync, titleVisibility: .visible) {
                Button("playx.submit") { Task { await model.syncCompletion() } }
            } message: { Text("playx.prefab.sync.notice") }
    }
    @ViewBuilder private var sceneBody: some View {
        switch scene.story.scene {
        case .prologue:
            Text("playx.prefab.prologue")
            Button("playx.prefab.continue") { act { try scene.next() } }
        case .register:
            TextField("templateAuthor.field.profileName", text: $profile.name)
            TextField("templateAuthor.field.profilePlace", text: $profile.place)
            TextField("playx.prefab.gender", text: $profile.gender)
            TextField("templateAuthor.field.profileDream", text: $profile.dream)
            if scene.story.step != 5 {
                Button("playx.prefab.register") { act { try scene.register(profile: profile) } }
            } else { Button("playx.prefab.continue") { act { try scene.next() } } }
        case .boot:
            Text("playx.prefab.boot.instructions")
            Text(verbatim: PlayPrefabSceneMachine.bootTarget).font(.title3.monospaced())
            TextField("playx.prefab.boot.input", text: Binding(get: { scene.bootText }, set: { scene.typeBoot($0, now: now); if scene.bootDone { try? scene.next(); save() } }))
                .textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("playx.prefab.boot.input")
            if scene.bootFailed { Text("playx.prefab.boot.retry") }
            if scene.bootDone { Button("playx.prefab.continue") { act { try scene.next() } } }
        case .walk:
            Text("playx.prefab.walk.local")
            ProgressView(value: Double(scene.story.walkProgress), total: 100)
            if scene.waitingForRoute {
                choice("playx.prefab.route.direct") { try scene.chooseRoute(0, now: now) }
                choice("playx.prefab.route.detour") { try scene.chooseRoute(1, now: now) }
            } else if scene.waitingForSign {
                choice("playx.prefab.sign.skip") { try scene.skipSign(now: now) }
                photoButton("sign", label: "playx.prefab.sign.photo")
            } else { Button("playx.prefab.walk.start") { scene.startWalk(now: now) }.disabled(scene.walking) }
        case .hall:
            Text("playx.prefab.hall.instructions")
            photoButton("hall", label: "playx.prefab.hall.arrivePhoto")
        case .birth:
            if scene.story.step == 0 {
                ForEach(0..<3, id: \.self) { value in choice("playx.prefab.birth.\(value)") { try scene.chooseBirth(value) } }
            } else if scene.story.step == 1 { holdControl }
            else if scene.story.step == 2 { photoButton("window", label: "playx.prefab.window.photo") }
            else {
                TextField("playx.prefab.window.note", text: $text, axis: .vertical)
                choice("playx.prefab.window.save") { try scene.leaveWindowNote(text); text = "" }
            }
        case .dream1, .dream2, .dream3:
            Text(LocalizedStringKey("playx.prefab." + scene.story.scene.rawValue + "." + String(scene.dreamIndex)))
            holdControl
        case .learning:
            if scene.story.step == 0 {
                ForEach(0..<2, id: \.self) { value in choice("playx.prefab.quiz.\(scene.quizIndex).\(value)") { try scene.answerQuiz(value) } }
            } else if scene.story.step == 1 {
                TextField("playx.prefab.count", text: $count).keyboardType(.numberPad)
                choice("playx.prefab.count.save") { guard let value = Int(count) else { throw PlayExperienceError.invalidAction }; try scene.recordCount(value, now: now) }
            } else if scene.story.step == 2 {
                Text("playx.prefab.teacher.timer")
                ForEach(0..<4, id: \.self) { value in choice("playx.prefab.teacher.\(value)") { try scene.chooseTeacher(value, rolls: dice()) } }
            } else { ForEach(0..<2, id: \.self) { value in choice("playx.prefab.teacherWindow.\(value)") { try scene.chooseTeacherWindow(value, rolls: dice()) } } }
        case .career:
            if scene.story.step == 0 {
                Text("playx.prefab.sticker.instructions")
                choice("playx.prefab.sticker.place") { try scene.placeSticker("未加载地图") }
            } else {
                ForEach(Array(PlayPrefabSceneMachine.jobs.enumerated()), id: \.offset) { index, name in choice("playx.prefab.job.\(index)") { try scene.chooseCareer(name) } }
            }
        case .work:
            if scene.story.step == 0 {
                ForEach(0..<4, id: \.self) { value in choice("playx.prefab.boss.\(value)") { try scene.chooseBoss(value, rolls: dice()) } }
            } else { Text("playx.prefab.phone.privacy"); photoButton("phone", label: "playx.prefab.phone.photo") }
        case .flow:
            Text("playx.prefab.flow")
            if model.record?.story.synced == true { Label("playx.prefab.synced", systemImage: "checkmark.seal") }
            else { Button("playx.prefab.sync") { confirmSync = true }.disabled(model.record?.hallPhotoURL == nil || model.phase != "ready") }
            Text("playx.prefab.endings.guide").font(.headline)
            Text("playx.prefab.endings.fixed").font(.caption)
            ForEach(0..<6, id: \.self) { index in
                VStack(alignment: .leading, spacing: 4) {
                    Text(LocalizedStringKey("playx.prefab.ending." + String(index) + ".title")).font(.headline)
                    Text(LocalizedStringKey("playx.prefab.ending." + String(index) + ".quote"))
                    Text(LocalizedStringKey("playx.prefab.ending." + String(index) + ".condition")).font(.caption)
                }
            }
        }
    }
    private var holdControl: some View {
        VStack {
            ProgressView(value: scene.holdProgress).accessibilityLabel(Text("playx.prefab.hold.progress"))
            Button(LocalizedStringKey(scene.holding ? "playx.prefab.hold.cancel" : "playx.prefab.hold.start")) {
                if scene.holding { scene.stopHold() } else { scene.beginHold(now: now) }
            }
            Text(LocalizedStringKey(scene.story.scene.isDream ? "playx.prefab.hold.dream" : "playx.prefab.hold.birth")).font(.caption)
        }
    }
    private func photoButton(_ key: String, label: String) -> some View {
        Button(LocalizedStringKey(label)) { photoKey = key; confirmPhoto = true }.disabled(key == "hall" ? !model.canCapture : !model.canCapturePhoto)
    }
    private func choice(_ key: String, action: @escaping () throws -> Void) -> some View { Button(LocalizedStringKey(key)) { act(action) }.disabled(scene.check != nil) }
    private func act(_ action: () throws -> Void) { do { try action(); save(); localIssue = nil } catch { localIssue = .invalidAction } }
    private func save() { guard loaded, model.phase == "ready" else { return }; do { try model.updateStory(scene.story) } catch { localIssue = .staleSession } }
    private func restoreIfAvailable() {
        guard !loaded, let record = model.record else { return }
        scene = .init(story: record.story); profile = record.story.profile; loaded = true
    }
}
