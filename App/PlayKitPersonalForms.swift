import SwiftUI

extension PlayKitScreen {
    @ViewBuilder var profileForm: some View {
        if raw["avatar"]["enabled"].bool == true {
            if !avatarURL.isEmpty { artwork(avatarURL); Label("playkit.profile.avatarReady", systemImage: "person.crop.circle.badge.checkmark") }
            photoInput { url in avatarURL = url; dirty = true }
        }
        ForEach(Array((raw["questions"].array ?? []).enumerated()), id: \.offset) { _, question in
            if let key = question["key"].text, !key.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text(verbatim: question["label"].text ?? key).font(.headline)
                    if question["kind"].text == "pick" {
                        ForEach(PlayKitOption.read(question["options"], idKey: "key")) { option in
                            Button {
                                answers[key] = option.id; dirty = true
                            } label: {
                                HStack { Image(systemName: answers[key] == option.id ? "checkmark.circle.fill" : "circle"); Text(verbatim: option.label) }
                            }.disabled(!enabled)
                        }
                    } else {
                        TextField("playkit.profile.answer", text: Binding(get: { answers[key] ?? "" }, set: {
                            let maxLength = question["maxLength"].integer ?? 0
                            answers[key] = PlayKitInputContract.limitText($0, toUTF16: maxLength > 0 ? maxLength : 4096); dirty = true
                        }), axis: .vertical).textFieldStyle(.roundedBorder).disabled(!enabled)
                    }
                }
            }
        }
        Text("playkit.profile.lockNotice").font(.footnote)
        let payload: [String: PlayWireValue] = ["answers": .object(answers.mapValues(PlayWireValue.string)), "avatarUrl": .string(avatarURL)]
        submitButton("SUBMIT_PROFILE", payload: payload, valid: valid("SUBMIT_PROFILE", payload))
    }
    @ViewBuilder var noteForm: some View {
        let limit = max(1, raw["maxLength"].integer ?? 40)
        ForEach(Array((raw["previous"].array ?? []).enumerated()), id: \.offset) { _, note in
            if let value = note["text"].text, !value.isEmpty {
                VStack(alignment: .leading) {
                    Text(verbatim: value)
                    if let at = note["at"].double, at.isFinite { Text(Date(timeIntervalSince1970: at / 1000), style: .date).font(.caption).foregroundStyle(.secondary) }
                }.padding().frame(maxWidth: .infinity, alignment: .leading).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        ForEach(Array((raw["presets"].array ?? []).enumerated()), id: \.offset) { _, value in
            if let preset = value.text { Button { text = PlayKitInputContract.limitText(preset, toUTF16: limit); dirty = true } label: { Text(verbatim: preset) }.buttonStyle(.bordered).disabled(!enabled) }
        }
        TextField("playkit.note.placeholder", text: textBinding(limit: limit), axis: .vertical).lineLimit(3...8).textFieldStyle(.roundedBorder).disabled(!enabled)
        LabeledContent("playkit.characters") { Text(verbatim: "\(text.utf16.count) / \(limit)").monospacedDigit() }
        Text("playkit.note.audience").font(.footnote)
        submitButton("SUBMIT_NOTE", payload: ["text": .string(text)], valid: !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
    @ViewBuilder var photoCheckForm: some View {
        if raw["mode"].text == "CARD" { objectCardForm }
        else { ordinaryPhotoCheckForm }
    }
    @ViewBuilder var ordinaryPhotoCheckForm: some View {
        if let note = raw["shotNote"].text, !note.isEmpty { Text(verbatim: note).font(.title3) }
        if let frame = raw["frameUrl"].text, !frame.isEmpty { artwork(frame); Text("playkitCamera.frameGuide").font(.footnote) }
        if let prior = raw["lastUrl"].text, !prior.isEmpty { artwork(prior) }
        if raw["degraded"].bool != true, raw["passed"].bool != true, raw["flagged"].bool != true, (raw["tries"].integer ?? 0) > 0, let reason = raw["lastReason"].text, !reason.isEmpty { Text(verbatim: reason) }
        if let used = raw["tries"].integer, let cap = raw["maxTries"].integer, cap > 0 {
            LabeledContent("playkit.photo.remaining") { Text(verbatim: String(max(0, cap - used))) }
        }
        if raw["flagged"].bool == true { Text("playkit.photo.fallbackRecorded") }
        photoInput(frame: PlayKitPhotoFrame(source: raw["frameUrl"].text, opacityPercent: raw["frameOpacity"].double, approvedHosts: approvedArtworkHosts)) { url in prepare("SUBMIT_PHOTO_CHECK", ["imageUrl": .string(url)]) }
        Text("playkit.photo.serverOnly").font(.footnote)
    }
    @ViewBuilder var scanForm: some View {
        if projection.complete {
            if let reply = raw["reply"].text, !reply.isEmpty { Text(verbatim: reply).font(.title3) }
            artwork(raw["imageUrl"].text)
            PlatformAudioHost(rawURL: raw["audioUrl"].text, scope: mediaScope, makeModel: makeAudio)
            if raw["kind"].text == "OVERLAY" || raw["overlayUrl"].text?.isEmpty == false {
                if let overlay = PlayKitScanOverlay(segment: raw, approvedHosts: approvedArtworkHosts) {
                    PlayKitCameraOverlayButton(overlay: overlay, identity: runtimeIdentity,
                        cameraEnabled: device?.supports(.scan) == true, active: model.isCurrent)
                }
                artwork(raw["overlayUrl"].text)
                Text("playkitLegacy.scan.staticFallback").font(.footnote)
                if ["PLANE", "MARKER"].contains(raw["arMode"].text ?? "") {
                    PlayKitSpatialRevealButton(segment: raw, approval: spatialApproval, identity: runtimeIdentity, active: model.isCurrent)
                }
            }
        } else if let device {
            PlayKitScanInput(model: device, identity: evidenceIdentity, enabled: enabled, onDirty: { dirty = true }) { code in prepare("SUBMIT_SCAN", ["code": .string(code)]) }
        } else { Label("playkit.camera.gated", systemImage: "camera") }
    }
    func photoInput(frame: PlayKitPhotoFrame? = nil, onURL: @escaping (String) -> Void) -> some View {
        Group {
            if let device {
                PlayKitPhotoInput(model: device, identity: evidenceIdentity, enabled: enabled, frame: frame, onDirty: { dirty = true }, onURL: onURL)
            } else { Label("playkit.camera.gated", systemImage: "camera") }
        }
    }
    private var evidenceIdentity: String { "\(model.state?.sessionID ?? -1):\(model.state?.version ?? -1):\(kind.rawValue)" }
    private func valid(_ action: String, _ payload: [String: PlayWireValue]) -> Bool {
        (try? PlayKitInputContract.validate(kind: kind.rawValue, action: action, payload: payload, segment: raw)) != nil
    }
}

@MainActor struct PlayKitPhotoInput: View {
    @Bindable var model: PlayDeviceCaptureCoordinator
    let identity: String; let enabled: Bool; var frame: PlayKitPhotoFrame? = nil; let onDirty: () -> Void; let onURL: (String) -> Void
    @State private var capturedIdentity: String?
    @State private var cameraPurpose = false
    @State private var uploadReview = false
    @State private var mounted = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button("playkit.photo.capture") { cameraPurpose = true }
                .disabled(!enabled || model.busy || !model.supports(.photo))
            Button("playkitCamera.choosePhoto") {
                let expected = identity; capturedIdentity = expected
                Task {
                    await model.capture(.photo, usePhotoLibrary: true)
                    if !mounted || identity != expected { model.cancel() }
                    else if let output = model.output, case .photo = output { onDirty() }
                }
            }.disabled(!enabled || model.busy || !model.supportsLibraryPhotos)
            if !model.supports(.photo) { Text("playkit.camera.gated").font(.footnote) }
            if model.busy { ProgressView("playkit.photo.working") }
            if capturedIdentity == identity, let output = model.output, case .photo(let bytes, _) = output {
                if let image = UIImage(data: bytes) { Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 240).accessibilityLabel(Text("playkit.photo.preview")) }
                if bytes.count > 10 * 1024 * 1024 { Text("playkit.photo.tooLarge") }
                Button("playkit.photo.upload") { uploadReview = true }
                    .disabled(!enabled || !model.canUpload || bytes.isEmpty || bytes.count > 10 * 1024 * 1024)
                if !model.canUpload && model.uploadedPhoto == nil && !model.busy { Text("playkit.photo.uploadGate").font(.footnote) }
                if let evidence = model.reviewedPhoto(), case .photo(let uploadedURL) = evidence {
                    Label("playkit.photo.uploaded", systemImage: "checkmark.circle")
                    Button("playkit.photo.use") { if mounted && capturedIdentity == identity && enabled { onURL(uploadedURL) } }.disabled(!enabled)
                }
            }
            if let issue = model.issue { PlayExperienceIssueView(issue: issue) }
        }
        .confirmationDialog("playkit.camera.purpose", isPresented: $cameraPurpose, titleVisibility: .visible) {
            Button("playkit.photo.capture") {
                let expected = identity; capturedIdentity = expected
                Task {
                    await model.capture(.photo, cameraFrame: frame)
                    if !mounted || identity != expected { model.cancel() }
                    else if let output = model.output, case .photo = output { onDirty() }
                }
            }
            Button("playkit.cancel", role: .cancel) {}
        } message: { Text("playkit.camera.photoPurpose") }
        .confirmationDialog("playkit.photo.uploadReview", isPresented: $uploadReview, titleVisibility: .visible) {
            Button("playkit.photo.upload") {
                guard capturedIdentity == identity, enabled else { return }
                let expected = identity
                Task { await model.uploadPhoto(); if !mounted || identity != expected { model.cancel() } }
            }
            Button("playkit.cancel", role: .cancel) {}
        } message: { Text("playkit.photo.uploadBoundary") }
        .onAppear { mounted = true; model.cancel() }
        .onChange(of: identity) { _, _ in capturedIdentity = nil; cameraPurpose = false; uploadReview = false; model.cancel() }
        .onDisappear { mounted = false; capturedIdentity = nil; model.cancel() }
    }
}

@MainActor struct PlayKitScanInput: View {
    @Bindable var model: PlayDeviceCaptureCoordinator
    let identity: String; let enabled: Bool; let onDirty: () -> Void; let onCode: (String) -> Void
    @State private var purpose = false
    @State private var capturedIdentity: String?
    @State private var mounted = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button("playkit.scan.capture") { purpose = true }.disabled(!enabled || model.busy || !model.supports(.scan))
            if !model.supports(.scan) { Text("playkit.camera.gated") }
            if model.busy { ProgressView("playkit.scan.working") }
            if capturedIdentity == identity, let output = model.output, case .scan(let code) = output {
                Label("playkit.scan.captured", systemImage: "qrcode")
                Button("playkit.review") { if mounted && enabled { onCode(code) } }.disabled(!enabled)
            }
            if let issue = model.issue { PlayExperienceIssueView(issue: issue) }
        }
        .confirmationDialog("playkit.camera.purpose", isPresented: $purpose, titleVisibility: .visible) {
            Button("playkit.scan.capture") {
                let expected = identity; capturedIdentity = expected
                Task {
                    await model.capture(.scan)
                    if !mounted || identity != expected { model.cancel() }
                    else if let output = model.output, case .scan = output { onDirty() }
                }
            }
            Button("playkit.cancel", role: .cancel) {}
        } message: { Text("playkit.camera.scanPurpose") }
        .onAppear { mounted = true; model.cancel() }
        .onChange(of: identity) { _, _ in capturedIdentity = nil; purpose = false; model.cancel() }
        .onDisappear { mounted = false; model.cancel() }
    }
}
