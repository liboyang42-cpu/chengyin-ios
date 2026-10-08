import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

@MainActor struct SquareWorkspaceView: View {
    @Bindable var coordinator: SquareWorkspaceCoordinator
    var initialPostID: Int? = nil
    var initialLane: SquareWorkspaceLane = .legacy
    @State private var editReady = false
    @State private var draft = SquareWorkspaceDraft()
    @State private var lane: SquareWorkspaceLane = .legacy
    @State private var issue = false
    @State private var showsReview = false
    @State private var acceptsGuideline = false
    @State private var localMedia = SquarePostLocalMediaPresentation()
    @Environment(\.scenePhase) private var scenePhase
    @State private var referenceType = "ACTIVITY"
    @State private var options: [SquareWorkspaceOption] = []
    @State private var revisionsText = ""
    @State private var locationReview: SquareWorkspacePost?
    private func run(_ action: @escaping @MainActor () async throws -> Void) {
        Task { do { try await action() } catch { issue = true } }
    }
    var body: some View {
        // Disable editor actions, not the scroll container: busy content must remain readable.
        Form {
            Group {
                Section {
                    Text("squareWorkspace.boundary").font(.footnote)
                    Text(LocalizedStringKey(coordinator.status)).accessibilityIdentifier("squareWorkspace.status")
                    Picker("squareWorkspace.lane", selection: $lane) {
                        Text("squareWorkspace.legacy").tag(SquareWorkspaceLane.legacy)
                        Text("squareWorkspace.v1").tag(SquareWorkspaceLane.communityV1)
                    }.disabled(draft.postID != nil).accessibilityIdentifier("squareWorkspace.lane")
                    TextEditor(text: $draft.body).frame(minHeight: 130)
                        .accessibilityLabel(Text("squareWorkspace.body")).accessibilityIdentifier("squareWorkspace.body")
                    if let id = draft.postID {
                        if let version = draft.expectedVersion, let lifecycle = draft.sourceLifecycle { Text("#\(id) · v\(version) · \(lifecycle)") }
                        else { Text("#\(id)"); Text("squareWorkspace.legacy") }
                    }
                }
                Section("squareWorkspace.media") {
                    SquarePostLocalMediaPreview(model: localMedia)
                    Button {
                        do {
                            try coordinator.refreshLocal()
                            localMedia.beginPicker(scope: try localMediaScope())
                        } catch { localMedia.invalidate(); issue = true }
                    } label: { SquarePostLocalMediaPickerLabel() }
                        .accessibilityIdentifier("squareWorkspace.selectPhoto")
                    if let selected = localMedia.imageUpload {
                        Button("squareWorkspace.upload") {
                            run {
                                guard localMediaScopeIsCurrent(selected.scope),
                                      localMedia.isCurrentUpload(selected) else { throw SquareWorkspaceFailure.sessionChanged }
                                let result = try await coordinator.upload(bytes: selected.bytes, mimeType: selected.mimeType,
                                    lane: selected.scope.lane, workflowID: selected.scope.draftID, explicitIntent: true)
                                // Never attach a late acknowledgment to another draft/account/lane.
                                guard localMediaScopeIsCurrent(selected.scope) else { throw SquareWorkspaceFailure.sessionChanged }
                                guard localMedia.applyUploadAcknowledgment(selected, apply: { draft.media.append(result) }) else {
                                    throw SquareWorkspaceFailure.staleReview
                                }
                            }
                        }.disabled(!coordinator.grants.live || !coordinator.grants.media || coordinator.busy || draft.media.count >= 6).accessibilityIdentifier("squareWorkspace.upload")
                    }
                    if localMedia.hasSelection {
                        Button("squareWorkspace.removeSelected", role: .destructive) { localMedia.remove() }
                            .accessibilityIdentifier("squarePostLocalMedia.remove")
                    }
                    ForEach(draft.media) { item in
                        VStack(alignment: .leading) {
                            Text(item.objectKey).lineLimit(2)
                            Text(item.existingMediaID != nil ? "squareWorkspace.existingMedia" : item.hasProof ? "squareWorkspace.proofReady" : "squareWorkspace.legacyMedia").font(.caption)
                            Button("squareWorkspace.remove", role: .destructive) { draft.media.removeAll { $0.id == item.id } }
                        }.accessibilityIdentifier("squareWorkspace.media.\(item.id)")
                    }
                    if draft.postID != nil && lane == .legacy { Text("squareWorkspace.editMediaRetained").font(.caption) }
                }
                Section("squareWorkspace.reference") {
                    Picker("squareWorkspace.referenceType", selection: $referenceType) {
                        ForEach(["ACTIVITY", "TOPIC", "ROUTE", "CLUB", "POI"], id: \.self) { Text(LocalizedStringKey("squareWorkspace.type." + $0)).tag($0) }
                    }
                    if let reference = draft.reference { Text("\(reference.type) #\(reference.id)"); Button("squareWorkspace.removeReference") { draft.removeReference() } }
                    Button("squareWorkspace.loadReferences") { run { options = try await coordinator.referenceOptions(type: referenceType) } }.disabled(!coordinator.grants.live)
                    ForEach(options) { option in
                        Button(option.name) {
                            if referenceType == "MEMBER" {
                                if !draft.mentionedMemberIDs.contains(option.id) { draft.mentionedMemberIDs.append(option.id) }
                            } else { draft.reference = .init(type: referenceType, id: option.id) }
                            if referenceType == "POI" { draft.address = option.name; draft.cityCode = option.cityCode }
                            options = []
                        }
                    }
                    Text("squareWorkspace.communityIdentity").font(.caption)
                }
                Section("squareWorkspace.location") {
                    TextField("squareWorkspace.place", text: Binding(get: { draft.address ?? "" }, set: { draft.address = $0.isEmpty ? nil : $0 }))
                    TextField("squareWorkspace.city", text: Binding(get: { draft.cityCode ?? "" }, set: { draft.cityCode = $0.isEmpty ? nil : $0 }))
                    Text("squareWorkspace.noCoordinates").font(.caption)
                    Button("squareWorkspace.clearLocation") { draft.address = nil; draft.cityCode = nil }
                    if let post = coordinator.lastPost, post.lane == .communityV1 {
                        Button("squareWorkspace.withdrawLocation", role: .destructive) { locationReview = post }
                            .disabled(!coordinator.grants.live).accessibilityIdentifier("squareWorkspace.withdraw")
                    }
                }
                if lane == .communityV1 { policyControls }
                Section("squareWorkspace.actions") {
                    Button("squareWorkspace.saveLocal") { run { try coordinator.saveLocal(draft, lane: lane) } }.accessibilityIdentifier("squareWorkspace.saveLocal")
                    Button("squareWorkspace.saveServer") { run { try await coordinator.saveServer(draft); if let resumed = coordinator.local.last(where: { $0.draft.postID == coordinator.lastPost?.id && !$0.pending && $0.receipt == nil }) { draft = resumed.draft } } }.disabled(!coordinator.grants.live || coordinator.busy || localMedia.hasSelection).accessibilityIdentifier("squareWorkspace.saveServer")
                    Button("squareWorkspace.review") { run { _ = try await coordinator.prepare(draft, lane: lane); acceptsGuideline = false; showsReview = true } }
                        .disabled(!coordinator.grants.live || coordinator.busy || localMedia.hasSelection).accessibilityIdentifier("squareWorkspace.review")
                    Button("squareWorkspace.newDraft") { draft = .init(); coordinator.cancelReview(); localMedia.invalidate() }
                        .accessibilityIdentifier("squareWorkspace.newDraft")
                }
                Section("squareWorkspace.localDrafts") {
                    ForEach(coordinator.local) { entry in
                        VStack(alignment: .leading) {
                            Group {
                                if entry.draft.body.isEmpty { Text("squareWorkspace.untitled") }
                                else { Text(verbatim: entry.draft.body) }
                            }.lineLimit(2).accessibilityIdentifier("squareWorkspace.local.\(entry.id)")
                            if entry.pending { Text("squareWorkspace.pending").font(.caption) }
                            Button("squareWorkspace.resume") { run { let resumed = try await coordinator.resume(entry); draft = resumed; lane = entry.lane; coordinator.cancelReview() } }
                                .buttonStyle(.borderless).frame(minHeight: 44)
                                .accessibilityIdentifier("squareWorkspace.resume.\(entry.id)")
                            Button("squareWorkspace.discard", role: .destructive) { run { try coordinator.discard(entry) } }
                                .buttonStyle(.borderless).frame(minHeight: 44).disabled(entry.pending)
                                .accessibilityIdentifier("squareWorkspace.discard.\(entry.id)")
                        }
                    }
                }
                Section("squareWorkspace.serverDrafts") {
                    Button("squareWorkspace.refreshServer") { run { try await coordinator.loadServer() } }.disabled(!coordinator.grants.live)
                    ForEach(coordinator.server) { post in
                        VStack(alignment: .leading) {
                            if let version = post.version, let lifecycle = post.lifecycle { Text("#\(post.id) · v\(version) · \(lifecycle)") }
                            Button("squareWorkspace.resume") { run { draft = try post.editableDraft(); lane = .communityV1 } }
                            Button("squareWorkspace.revisions") { run { let data = try await coordinator.revisions(postID: post.id); revisionsText = String(data: data, encoding: .utf8) ?? "" } }
                            Button("squareWorkspace.withdrawLocation", role: .destructive) { locationReview = post }
                        }
                    }
                    if coordinator.hasMore { Button("squareWorkspace.more") { run { try await coordinator.loadServer(more: true) } } }
                    if !revisionsText.isEmpty { Text(revisionsText).textSelection(.enabled).accessibilityIdentifier("squareWorkspace.revisions") }
                }
            }.disabled(coordinator.busy || (initialPostID != nil && !editReady))
        }
        .navigationTitle("squareWorkspace.title")
        .task(id: initialPostID) {
            do {
                try coordinator.refreshLocal()
                if let initialPostID { lane = initialLane; draft = try await coordinator.editableDraft(postID: initialPostID, lane: initialLane); editReady = true }
            } catch { issue = true }
        }
        .sheet(item: Binding(get: { localMedia.pickerRequest }, set: { if $0 == nil { localMedia.cancelPicker() } })) { request in
            SquarePostLocalMediaPicker(request: request) { provider, captured in
                // Reuse the existing image-only byte bound; it is not a video rule.
                _ = localMedia.accept(provider: provider, request: captured, maximumImageBytes: SquareWorkspaceService.maximumUploadImageBytes,
                    scopeIsCurrent: { localMediaScopeIsCurrent(captured.scope) })
            }
        }
        .onDisappear { localMedia.invalidate() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { localMedia.invalidate() } }
        .onChange(of: draft.workflowID) { _, _ in localMedia.invalidate() }
        .onChange(of: coordinator.session) { _, _ in localMedia.invalidate() }
        .onChange(of: coordinator.status) { _, status in
            if status == "squareWorkspace.sessionChanged" { localMedia.invalidate() }
        }
        .onChange(of: draft) { _, _ in coordinator.cancelReview() }
        .onChange(of: lane) { _, _ in coordinator.cancelReview(); options = []; localMedia.invalidate() }
        .alert("squareWorkspace.issue", isPresented: $issue) { Button("squareWorkspace.close", role: .cancel) {} } message: { Text("squareWorkspace.issueDetail") }
        .confirmationDialog("squareWorkspace.withdrawConfirm", isPresented: Binding(get: { locationReview != nil }, set: { if !$0 { locationReview = nil } })) {
            Button("squareWorkspace.withdrawLocation", role: .destructive) {
                guard let post = locationReview else { return }; locationReview = nil
                run { try await coordinator.withdrawLocation(reviewed: post, explicitIntent: true) }
            }
        }
        .sheet(isPresented: $showsReview, onDismiss: { coordinator.cancelReview() }) {
            if let review = coordinator.review {
                NavigationStack {
                    Form {
                        Text(review.draft.body)
                        Text("squareWorkspace.reviewDetail")
                        if let guideline = review.guideline {
                            Text("#\(guideline.id)")
                            Text(String(data: guideline.raw, encoding: .utf8) ?? "")
                            Toggle("squareWorkspace.acceptGuideline", isOn: $acceptsGuideline).accessibilityIdentifier("squareWorkspace.acceptGuideline")
                        }
                        Button("squareWorkspace.confirm") {
                            run { try await coordinator.confirm(review, unchangedDraft: draft, acceptCurrentGuideline: acceptsGuideline); showsReview = false }
                        }.disabled(review.lane == .communityV1 && (!acceptsGuideline || !coordinator.grants.legal)).accessibilityIdentifier("squareWorkspace.confirm")
                        Button("squareWorkspace.cancel", role: .cancel) { showsReview = false; coordinator.cancelReview() }
                    }.navigationTitle("squareWorkspace.review")
                }
            } else { Text("squareWorkspace.staleReview") }
        }
    }
    private func localMediaScope() throws -> SquarePostLocalMediaScope {
        try .init(session: coordinator.session, draftID: draft.workflowID, lane: lane)
    }
    private func localMediaScopeIsCurrent(_ scope: SquarePostLocalMediaScope) -> Bool {
        guard scope.session == coordinator.session, scope.draftID == draft.workflowID, scope.lane == lane else { return false }
        do { try coordinator.refreshLocal(); return true } catch { return false }
    }
    private var policyControls: some View {
        Section("squareWorkspace.policy") {
            Picker("squareWorkspace.audience", selection: $draft.audience) {
                ForEach(["PUBLIC", "FOLLOWERS", "PRIVATE"] + (draft.communityID == nil ? [] : ["COMMUNITY"]), id: \.self) { Text(LocalizedStringKey("squareWorkspace.policy." + $0)).tag($0) }
            }
            Picker("squareWorkspace.comments", selection: $draft.commentPolicy) {
                ForEach(["EVERYONE", "FOLLOWERS", "MENTIONED", "OFF"] + (draft.communityID == nil ? [] : ["MEMBERS"]), id: \.self) { Text(LocalizedStringKey("squareWorkspace.policy." + $0)).tag($0) }
            }
            Toggle("squareWorkspace.replyApproval", isOn: $draft.replyApprovalEnabled)
            Toggle("squareWorkspace.slowMode", isOn: Binding(get: { draft.slowModeSeconds > 0 }, set: { draft.slowModeSeconds = $0 ? 30 : 0 }))
            Picker("squareWorkspace.disclosure", selection: $draft.disclosureType) {
                ForEach(["NONE", "SPONSORED", "GIFTED", "MERCHANT_OWNER", "MERCHANT_EMPLOYEE"], id: \.self) { Text(LocalizedStringKey("squareWorkspace.policy." + $0)).tag($0) }
            }
            ForEach(["DANGEROUS_ACTIVITY", "SENSITIVE_CONTENT", "FLASHING_IMAGES", "SPOILER", "TEMPORARY_CLOSURE", "ACCESSIBILITY_LIMIT", "WEATHER_RISK"], id: \.self) { label in
                Toggle(LocalizedStringKey("squareWorkspace.safety." + label), isOn: Binding(get: { draft.safetyLabels.contains(label) }, set: { enabled in
                    if enabled && draft.safetyLabels.count < 5 { draft.safetyLabels.append(label) }
                    else if !enabled { draft.safetyLabels.removeAll { $0 == label } }
                }))
            }
            Button("squareWorkspace.chooseMentions") { referenceType = "MEMBER"; run { options = try await coordinator.referenceOptions(type: "MEMBER") } }
            ForEach(draft.mentionedMemberIDs, id: \.self) { id in Button("#\(id) −") { draft.mentionedMemberIDs.removeAll { $0 == id } } }
        }
    }
}
