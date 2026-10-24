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
    func previewPresentation(for offered: Preview?) -> Binding<Preview?> {
        Binding(get: {
            guard let offered, self.canShare, self.preview?.id == offered.id else { return nil }
            return offered
        }, set: { next in
            if next == nil, let offered { self.close(offered) }
        })
    }
    func handoffIsCurrent(_ offered: Handoff, previewID: UUID) -> Bool {
        canShare && preview?.id == previewID && offered.previewID == previewID && handoff?.id == offered.id
    }
    func handoffPresentation(for offered: Handoff?, previewID: UUID) -> Binding<Handoff?> {
        Binding(get: {
            guard let offered, self.handoffIsCurrent(offered, previewID: previewID) else { return nil }
            return offered
        }, set: { next in
            if next == nil, let offered, offered.previewID == previewID { self.finishHandoff(offered) }
        })
    }
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

/// The page captures one reader/owner context; a recycled row cannot acquire a new one.
struct ProfileIdentitySharePageContext: Equatable {
    let memberID: Int
    let readerID: ObjectIdentifier
    let accountID: Int?
    let epoch: UInt64
    let role: [UInt8]?
    let revision: UInt64
    let configured: Bool
    let parentCurrent: Bool
    @MainActor init(memberID: Int, reader: any SocialAccountReading, isCurrent: Bool) {
        self.memberID = memberID; readerID = ObjectIdentifier(reader)
        accountID = reader.identity.accountID; epoch = reader.identity.epoch
        role = reader.identity.role.map { Array($0.utf8) }; revision = reader.presentationRevision
        configured = reader.isConfigured; parentCurrent = isCurrent
    }
    var permitsSelf: Bool { memberID > 0 && accountID == memberID && configured && parentCurrent }
}

struct ProfileIdentityShareSourceTicket: Equatable {
    let id = UUID()
    let context: ProfileIdentitySharePageContext
    let source: ProfileIdentityShareSource
}

/// Retained by the whole profile page, never by a lazy List row.
@MainActor final class ProfileIdentitySharePageOwner: ObservableObject {
    @Published private(set) var model: ProfileIdentityShareModel?
    @Published private(set) var visible = false
    @Published private(set) var active = false
    private var context: ProfileIdentitySharePageContext?
    @Published private(set) var sourceTicket: ProfileIdentityShareSourceTicket?
    private var sourceRead: UUID?
    /// Called only by the existing page read, never by a row action.
    func beginSourceRead(_ expected: ProfileIdentitySharePageContext) -> UUID? {
        guard context == nil || context == expected else { return nil }
        clear(); sourceTicket = nil
        let id = UUID(); sourceRead = id; return id
    }
    func acceptSource(_ profile: SocialPublicProfile, reader: any SocialAccountReading,
                      expected: ProfileIdentitySharePageContext, readID: UUID?, isCurrent: Bool) {
        guard let readID, sourceRead == readID, !Task.isCancelled,
              context == nil || context == expected,
              expected == ProfileIdentitySharePageContext(memberID: profile.id, reader: reader, isCurrent: isCurrent),
              expected.permitsSelf else { return }
        sourceRead = nil; clear()
        sourceTicket = .init(context: expected, source: .init(profile: profile))
    }
    func ticket(profile: SocialPublicProfile, expected: ProfileIdentitySharePageContext) -> ProfileIdentityShareSourceTicket? {
        guard let sourceTicket, permits(expected), sourceTicket.context == expected,
              sourceTicket.source == ProfileIdentityShareSource(profile: profile) else { return nil }
        return sourceTicket
    }
    func appear(_ next: ProfileIdentitySharePageContext, active: Bool) {
        if context != next { clear(); if sourceTicket?.context != next { sourceTicket = nil } }
        if !visible, let prior = sourceTicket {
            sourceTicket = .init(context: prior.context, source: prior.source)
        }
        context = next; visible = true; self.active = active
    }
    func update(_ next: ProfileIdentitySharePageContext) {
        guard context != next else { return }
        clear(); sourceRead = nil; sourceTicket = nil; context = next
    }
    func disappear(_ expected: ProfileIdentitySharePageContext) {
        guard context == expected else { return }
        visible = false; active = false; sourceRead = nil; clear()
    }
    func sceneChanged(_ expected: ProfileIdentitySharePageContext, active: Bool) {
        guard context == expected, visible else { return }
        self.active = active
        if !active { clear() }
    }
    private func clear() { model?.retire(); model = nil }
    func permits(_ expected: ProfileIdentitySharePageContext) -> Bool {
        visible && active && context == expected && expected.permitsSelf
    }
    func open(profile: SocialPublicProfile, reader: any SocialAccountReading,
              expected: ProfileIdentitySharePageContext, source: ProfileIdentityShareSourceTicket?, title: String,
              isCurrent: @escaping @MainActor () -> Bool) {
        guard permits(expected), let source, source == ticket(profile: profile, expected: expected),
              expected == ProfileIdentitySharePageContext(memberID: profile.id, reader: reader, isCurrent: isCurrent()),
              model?.preview == nil, model?.handoff == nil else { return }
        clear()
        let next = ProfileIdentityShareModel(profile: profile, reader: reader, isCurrent: { [weak self] in
            self?.permits(expected) == true && isCurrent()
        })
        guard next.canShare else { return }
        model = next; next.open(title: title)
    }
}

@MainActor struct ProfileIdentitySharePageHost<Content: View>: View {
    @ObservedObject var owner: ProfileIdentitySharePageOwner
    let context: ProfileIdentitySharePageContext
    @ViewBuilder let content: () -> Content
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        ZStack { content() }
            .background {
                if let model = owner.model {
                    ProfileIdentitySharePagePresentation(model: model).id(ObjectIdentifier(model))
                }
            }
            .onAppear { owner.appear(context, active: scenePhase != .background) }
            .onDisappear { owner.disappear(context) }
            .onChange(of: context) { _, value in owner.update(value) }
            .onChange(of: scenePhase) { _, phase in
                // Inactive also occurs while the explicit system share sheet is shown.
                owner.sceneChanged(context, active: phase != .background)
            }
    }
}

@MainActor private struct ProfileIdentitySharePagePresentation: View {
    @ObservedObject var model: ProfileIdentityShareModel
    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .background {
                if let preview = model.preview {
                    ProfileIdentityPreviewPresentationOwner(model: model, preview: preview).id(preview.id)
                }
            }
            .onChange(of: model.canShare) { _, current in if !current { model.retire() } }
    }
}

/// A row only offers an explicit action. Recycling it cannot dismiss a page-owned sheet.
@MainActor struct ProfileIdentityShareSection: View {
    let profile: SocialPublicProfile
    let reader: any SocialAccountReading
    let isCurrent: @MainActor () -> Bool
    @ObservedObject var owner: ProfileIdentitySharePageOwner
    @Environment(\.locale) private var locale
    var body: some View {
        let expected = ProfileIdentitySharePageContext(memberID: profile.id, reader: reader, isCurrent: isCurrent())
        let source = owner.ticket(profile: profile, expected: expected)
        Button("profile.identityShare.open", systemImage: "square.and.arrow.up") {
            owner.open(profile: profile, reader: reader, expected: expected, source: source,
                       title: appLocalized("profile.identityShare.title", locale: locale), isCurrent: isCurrent)
        }
        .disabled(source == nil || ProfileIdentityShareCard(profile: profile, owner: reader.identity) == nil)
        .accessibilityIdentifier("profile.identityShare.open")
    }
}

/// A concrete owner is created only after a nonnil preview UUID exists.
@MainActor private struct ProfileIdentityPreviewPresentationOwner: View {
    @ObservedObject var model: ProfileIdentityShareModel
    let preview: ProfileIdentityShareModel.Preview
    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .sheet(item: model.previewPresentation(for: preview), onDismiss: { model.close(preview) }) { offered in
                ProfileIdentitySharePreview(model: model, value: offered)
            }
    }
}

@MainActor private struct ProfileIdentityHandoffPresentationOwner: View {
    @ObservedObject var model: ProfileIdentityShareModel
    let previewID: UUID
    let handoff: ProfileIdentityShareModel.Handoff
    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .sheet(item: model.handoffPresentation(for: handoff, previewID: previewID),
                   onDismiss: { model.finishHandoff(handoff) }) { offered in
                if model.handoffIsCurrent(offered, previewID: previewID) {
                    ProfileIdentitySystemShare(text: offered.text,
                        isCurrent: { model.handoffIsCurrent(offered, previewID: previewID) },
                        completion: { model.finishHandoff(offered) })
                }
            }
    }
}

@MainActor private struct ProfileIdentitySharePreview: View {
    @ObservedObject var model: ProfileIdentityShareModel
    let value: ProfileIdentityShareModel.Preview
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
            .background {
                if let handoff = model.handoff, model.handoffIsCurrent(handoff, previewID: value.id) {
                    ProfileIdentityHandoffPresentationOwner(model: model, previewID: value.id, handoff: handoff)
                        .id(handoff.id)
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
