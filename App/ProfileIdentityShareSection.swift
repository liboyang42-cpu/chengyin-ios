import SwiftUI
import UIKit

@MainActor final class ProfileIdentityShareModel: ObservableObject {
    struct Preview: Identifiable {
        let id = UUID()
        let text: String
    }
    struct Handoff: Identifiable {
        let id = UUID()
        let previewID: UUID
        let text: String
    }
    @Published private(set) var preview: Preview?
    @Published private(set) var handoff: Handoff?
    private let reader: any SocialAccountReading
    private let identity: SocialAccountIdentity
    private let revision: UInt64
    private let card: ProfileIdentityShareCard?
    private let isCurrent: @MainActor () -> Bool
    private var active = true

    init(profile: SocialPublicProfile, reader: any SocialAccountReading,
         isCurrent: @escaping @MainActor () -> Bool) {
        self.reader = reader; identity = reader.identity; revision = reader.presentationRevision
        card = ProfileIdentityShareCard(profile: profile, owner: reader.identity)
        self.isCurrent = isCurrent
    }
    var canShare: Bool { active && contextIsCurrent }
    private var contextIsCurrent: Bool {
        card != nil && reader.isConfigured && isCurrent()
            && reader.identity.accountID == identity.accountID && reader.identity.epoch == identity.epoch
            && reader.identity.role.map { Array($0.utf8) } == identity.role.map { Array($0.utf8) }
            && reader.presentationRevision == revision
    }
    func activate() { active = contextIsCurrent }
    func open(title: String) {
        guard canShare, preview == nil, handoff == nil, let card else { return }
        preview = Preview(text: card.text(title: title))
    }
    func beginHandoff(_ value: Preview) {
        guard canShare, preview?.id == value.id, handoff == nil else { return }
        handoff = Handoff(previewID: value.id, text: value.text)
    }
    func finishHandoff(_ value: Handoff) {
        guard handoff?.id == value.id else { return }
        handoff = nil
        if !canShare { retire() }
        // Completion/cancellation never means that a recipient received this text.
    }
    func close(_ value: Preview) {
        guard preview?.id == value.id else { return }
        handoff = nil; preview = nil
    }
    func retire() { active = false; handoff = nil; preview = nil }
}

struct ProfileIdentityShareViewIdentity: Hashable {
    let source: ProfileIdentityShareSource
    let readerID: ObjectIdentifier
    let accountID: Int?
    let epoch: UInt64
    let role: [UInt8]?
    let revision: UInt64
    @MainActor init(profile: SocialPublicProfile, reader: any SocialAccountReading) {
        source = .init(profile: profile); readerID = ObjectIdentifier(reader)
        accountID = reader.identity.accountID; epoch = reader.identity.epoch
        role = reader.identity.role.map { Array($0.utf8) }; revision = reader.presentationRevision
    }
}

/// A real normal-page action. No provider, grant, network operation or image loader.
@MainActor struct ProfileIdentityShareSection: View {
    @StateObject private var model: ProfileIdentityShareModel
    @Environment(\.scenePhase) private var scenePhase
    init(profile: SocialPublicProfile, reader: any SocialAccountReading,
         isCurrent: @escaping @MainActor () -> Bool) {
        _model = StateObject(wrappedValue: ProfileIdentityShareModel(profile: profile, reader: reader, isCurrent: isCurrent))
    }
    private var previewBinding: Binding<ProfileIdentityShareModel.Preview?> {
        let captured = model.preview
        return Binding(get: { model.preview }, set: { next in
            if next == nil, let captured { model.close(captured) }
        })
    }
    var body: some View {
        Button("profile.identityShare.open", systemImage: "square.and.arrow.up") {
            model.open(title: String(localized: "profile.identityShare.title"))
        }
        .disabled(!model.canShare)
        .accessibilityIdentifier("profile.identityShare.open")
        .sheet(item: previewBinding) { value in
            ProfileIdentitySharePreview(model: model, value: value)
        }
        .onChange(of: model.canShare) { _, valid in if !valid { model.retire() } }
        .onChange(of: scenePhase) { _, phase in
            // Inactive is also used while the user selects a system sharing target.
            if phase == .background { model.retire() }
            else if phase == .active { model.activate() }
        }
        .onAppear { model.activate() }
        .onDisappear { model.retire() }
    }
}

@MainActor private struct ProfileIdentitySharePreview: View {
    @ObservedObject var model: ProfileIdentityShareModel
    let value: ProfileIdentityShareModel.Preview
    private var handoffBinding: Binding<ProfileIdentityShareModel.Handoff?> {
        let captured = model.handoff
        return Binding(get: { model.handoff }, set: { next in
            if next == nil, let captured { model.finishHandoff(captured) }
        })
    }
    var body: some View {
        NavigationStack {
            List {
                Section("profile.identityShare.preview") {
                    Text(verbatim: value.text).textSelection(.enabled)
                        .accessibilityIdentifier("profile.identityShare.text")
                }
                Section {
                    Text("profile.identityShare.disclosure").font(.footnote)
                    Text("profile.identityShare.destination").font(.footnote).foregroundStyle(.secondary)
                    Button("profile.identityShare.continue", systemImage: "square.and.arrow.up") { model.beginHandoff(value) }
                        .disabled(!model.canShare || model.handoff != nil)
                        .accessibilityIdentifier("profile.identityShare.continue")
                }
            }
            .navigationTitle("profile.identityShare.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button("action.close") { model.close(value) }.accessibilityIdentifier("profile.identityShare.close")
            } }
            .sheet(item: handoffBinding) { item in
                if model.canShare {
                    ProfileIdentitySystemShare(text: item.text, isCurrent: { model.canShare && model.handoff?.id == item.id }) { model.finishHandoff(item) }
                }
            }
        }
    }
}

@MainActor private struct ProfileIdentitySystemShare: UIViewControllerRepresentable {
    let text: String
    let isCurrent: @MainActor () -> Bool
    let completion: @MainActor () -> Void
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: isCurrent() ? [text] : [], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in
            Task { @MainActor in completion() }
        }
        return controller
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {
        if !isCurrent() { controller.dismiss(animated: false) }
    }
}
