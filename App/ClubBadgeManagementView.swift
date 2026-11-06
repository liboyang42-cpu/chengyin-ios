import SwiftUI

@MainActor struct ClubBadgeManagementView: View {
    @StateObject private var model: ClubBadgeHostModel
    @State private var visible = false
    @State private var creating = false
    @State private var pendingReview: ClubBadgeGrantReview?
    @State private var draft = ClubBadgeCreateDraft()
    @Environment(\.scenePhase) private var scenePhase
    init(host: ClubBadgeHost) { _model = StateObject(wrappedValue: ClubBadgeHostModel(host: host)) }
    var body: some View {
        let _ = model.revision
        List {
            if model.working { ProgressView { Text("loading", tableName: "ClubBadge") } }
            if let flow = model.flow, flow.isCurrent {
                if flow.error != nil || flow.refreshError != nil || flow.memberError != nil {
                    Text("readError", tableName: "ClubBadge")
                    Button { model.perform { await $0.refresh() } } label: { Text("refresh", tableName: "ClubBadge") }
                }
                resultStatus(flow.resultPresentation)
                if flow.canCreate {
                    Button { draft = .init(); creating = true } label: { Text("create", tableName: "ClubBadge") }
                }
                ForEach(flow.badges) { badge in
                    VStack(alignment: .leading) {
                        if let name = badge.badgeName, !name.isEmpty { Text(verbatim: name) }
                        else { Text("unnamed", tableName: "ClubBadge") }
                        if flow.canGrant {
                            Button { model.perform { await $0.openGrant(badge) } } label: { Text("grant", tableName: "ClubBadge") }
                        }
                    }
                }
                if flow.pickerOpen {
                    Section {
                        ForEach(flow.members) { member in
                            Button {
                                flow.selectMember(member); pendingReview = flow.review; model.changed()
                            } label: { Text(verbatim: member.trimmedNickname ?? String(member.memberId)) }
                        }
                        Button { flow.closePicker(); pendingReview = nil; model.changed() } label: { Text("cancel", tableName: "ClubBadge") }
                    } header: { Text("recipient", tableName: "ClubBadge") }
                }
            } else { Text("readError", tableName: "ClubBadge") }
        }
        .disabled(model.working)
        .navigationTitle(Text("title", tableName: "ClubBadge"))
        .privacySensitive()
        .toolbar { Button { model.perform { await $0.refresh() } } label: { Text("refresh", tableName: "ClubBadge") } }
        .onAppear { visible = true; if scenePhase == .active { model.start() } }
        .onDisappear { visible = false; creating = false; pendingReview = nil; draft = .init(); model.retire() }
        .onChange(of: scenePhase) { _, phase in
            guard visible else { return }
            creating = false; pendingReview = nil; draft = .init()
            if phase == .active { model.start() } else { model.retire() }
        }
        .onChange(of: model.flow?.isCurrent) { _, current in
            if current == false { creating = false; pendingReview = nil; draft = .init(); model.retire() }
        }
        .sheet(isPresented: $creating) { createForm }
        .confirmationDialog(Text("confirmGrant", tableName: "ClubBadge"), isPresented: Binding(
            get: { pendingReview != nil }, set: { if !$0 { pendingReview = nil } })) {
                if let review = pendingReview {
                    Button { pendingReview = nil; model.perform { await $0.confirmGrant(review) } } label: { Text("grant", tableName: "ClubBadge") }
                }
                Button(role: .cancel) { pendingReview = nil; model.flow?.cancelReview(); model.changed() } label: { Text("cancel", tableName: "ClubBadge") }
            } message: {
                if let review = pendingReview {
                    Text(verbatim: (review.member.trimmedNickname ?? String(review.member.memberId)) + " · " + (review.badge.badgeName ?? review.badge.badgeCode))
                }
            }
    }
    @ViewBuilder private func resultStatus(_ result: ClubBadgeResultPresentation) -> some View {
        switch result {
        case .none: EmptyView()
        case .storageUnavailable:
            Text("storageUnavailable", tableName: "ClubBadge")
        case .unknown:
            Section {
                Text("unknown", tableName: "ClubBadge")
                Button { model.perform { await $0.refresh() } } label: { Text("recover", tableName: "ClubBadge") }
            }
        case .needsReview: Text("actionNeedsReview", tableName: "ClubBadge")
        case .notSent: Text("notSent", tableName: "ClubBadge")
        case .confirmed(let receipt):
            Text(LocalizedStringKey("receipt." + receipt.state), tableName: "ClubBadge")
        case .historical(let receipt):
            Section {
                Text(LocalizedStringKey("receipt." + receipt.state), tableName: "ClubBadge")
            } header: { Text("historicalResult", tableName: "ClubBadge") }
        }
    }
    private var createForm: some View {
        NavigationStack {
            Form {
                TextField(text: $draft.name) { Text("name", tableName: "ClubBadge") }
                TextField(text: $draft.description, axis: .vertical) { Text("description", tableName: "ClubBadge") }
                Text("limits", tableName: "ClubBadge")
                Button {
                    let submitted = draft; creating = false
                    model.perform { await $0.create(submitted) }
                } label: { Text("confirmCreate", tableName: "ClubBadge") }
                .disabled(draft.validation != nil || model.flow?.canCreate != true)
                Button { creating = false } label: { Text("cancel", tableName: "ClubBadge") }
            }.navigationTitle(Text("create", tableName: "ClubBadge"))
        }
    }
}
