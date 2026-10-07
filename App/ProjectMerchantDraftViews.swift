import SwiftUI

@MainActor struct ProjectMerchantDraftField: View {
    @Environment(\.locale) private var locale
    @StateObject private var controller: ProjectMerchantDraftController
    init(context: ProjectMerchantDraftContext) { _controller = StateObject(wrappedValue: .init(context: context)) }
    private func text(_ key: ProjectMerchantDraftCopy.Key) -> String { ProjectMerchantDraftCopy.value(key, locale: locale) }
    var body: some View {
        let original = controller.review
        VStack(alignment: .leading, spacing: 8) {
            Button(text(.choose)) { controller.open() }
                .buttonStyle(.borderless).disabled(!controller.available).accessibilityIdentifier("projectMerchantDraft.choose")
            Text(text(controller.available ? .localReferenceOnly : .unconfigured)).font(.caption)
        }.sheet(item: controller.presentation(original)) { original in
            ProjectMerchantDraftPanel(controller: controller, original: original)
        }
    }
}
@MainActor private struct ProjectMerchantDraftPanel: View {
    @Environment(\.locale) private var locale
    @ObservedObject var controller: ProjectMerchantDraftController
    let original: ProjectMerchantDraftController.Review
    private func text(_ key: ProjectMerchantDraftCopy.Key) -> String { ProjectMerchantDraftCopy.value(key, locale: locale) }
    var body: some View {
        NavigationStack {
            Form {
                if controller.isCurrent(original) {
                    Section(text(.original)) {
                        Text(verbatim: original.original.name)
                        LabeledContent("projectEdit.templateID", value: original.original.templateID.map(String.init) ?? "—")
                    }
                    Section(text(.list)) {
                        Text(text(.pageCurrent)).font(.caption)
                        Button(text(.refresh)) { controller.refresh(original) }
                            .disabled(controller.state == .resolving).accessibilityIdentifier("projectMerchantDraft.refresh")
                        if controller.state == .loading { ProgressView(text(.loading)) }
                        if controller.state == .resolving { ProgressView(text(.resolving)) }
                        if controller.state == .ready && controller.rows.isEmpty { Text(text(.empty)).accessibilityIdentifier("projectMerchantDraft.empty") }
                        if let key = errorKey { Text(text(key)).accessibilityIdentifier("projectMerchantDraft.error") }
                        ForEach(controller.rows) { row in
                            if let choice = row.choice {
                                Button { controller.select(row, review: original) } label: {
                                    VStack(alignment: .leading) {
                                        Text(verbatim: choice.title)
                                        Text(verbatim: "#\(row.memberTemplateID)").font(.caption)
                                    }
                                }.buttonStyle(.borderless).disabled(controller.state != .ready)
                                    .accessibilityIdentifier("projectMerchantDraft.option.\(row.sourceID)")
                            } else {
                                VStack(alignment: .leading) {
                                    Text(verbatim: "#\(row.memberTemplateID)")
                                    Text(text(.unavailableRow)).font(.caption)
                                }.accessibilityIdentifier("projectMerchantDraft.unavailable.\(row.sourceID)")
                            }
                        }
                        if controller.nextBeforeSourceID != nil {
                            Button(text(.loadMore)) { controller.loadMore(original) }
                                .disabled(controller.state != .ready).accessibilityIdentifier("projectMerchantDraft.loadMore")
                        }
                    }
                    if let selected = controller.selection {
                        Section(text(.review)) {
                            Text(verbatim: selected.choice.title)
                            LabeledContent("projectEdit.templateID", value: String(selected.choice.memberTemplateID))
                            Text(text(.noPublicationAuthority)).font(.caption)
                            Button(text(.apply)) { controller.apply(selected, review: original) }
                                .disabled(controller.state != .ready).accessibilityIdentifier("projectMerchantDraft.apply")
                        }
                    }
                } else { Text(text(.stale)).accessibilityIdentifier("projectMerchantDraft.stale") }
            }.navigationTitle(text(.choose)).scrollDismissesKeyboard(.interactively)
                .toolbar { ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { controller.cancel(original) }.accessibilityIdentifier("projectMerchantDraft.cancel")
                } }
                .task(id: original.id) { controller.refresh(original) }
                .onDisappear { controller.cancel(original) }
        }
    }
    private var errorKey: ProjectMerchantDraftCopy.Key? {
        switch controller.state {
        case .failed: return .failed
        case .unauthorized: return .unauthorized
        case .forbidden: return .forbidden
        case .changed: return .changed
        default: return nil
        }
    }
}

/// Literal resource keys, a dedicated table and the view's explicit locale.
/// Root installs the bilingual catalog proposal with the composition hunk.
enum ProjectMerchantDraftCopy {
    enum Key { case choose, localReferenceOnly, unconfigured, original, list, pageCurrent, refresh, loading, resolving, empty, unavailableRow, loadMore, review, noPublicationAuthority, apply, stale, failed, unauthorized, forbidden, changed, otherGameplay }
    static func value(_ key: Key, locale: Locale) -> String {
        switch key {
        case .choose: return String(localized: LocalizedStringResource("projectMerchantDraft.choose", defaultValue: "Choose a merchant draft", table: "ProjectMerchantDraft", locale: locale))
        case .localReferenceOnly: return String(localized: LocalizedStringResource("projectMerchantDraft.localReferenceOnly", defaultValue: "Choose one of your store’s saved AI drafts. This changes only this node’s local template reference.", table: "ProjectMerchantDraft", locale: locale))
        case .unconfigured: return String(localized: LocalizedStringResource("projectMerchantDraft.unconfigured", defaultValue: "Owner draft reading is not configured for this account. Your existing template reference is retained.", table: "ProjectMerchantDraft", locale: locale))
        case .original: return String(localized: LocalizedStringResource("projectMerchantDraft.original", defaultValue: "Current node", table: "ProjectMerchantDraft", locale: locale))
        case .list: return String(localized: LocalizedStringResource("projectMerchantDraft.list", defaultValue: "Your store’s saved drafts", table: "ProjectMerchantDraft", locale: locale))
        case .pageCurrent: return String(localized: LocalizedStringResource("projectMerchantDraft.pageCurrent", defaultValue: "Pages are checked as they load. Refresh to see newly saved drafts. Source facts remain historical; choosing a draft does not confirm them.", table: "ProjectMerchantDraft", locale: locale))
        case .refresh: return String(localized: LocalizedStringResource("projectMerchantDraft.refresh", defaultValue: "Refresh drafts", table: "ProjectMerchantDraft", locale: locale))
        case .loading: return String(localized: LocalizedStringResource("projectMerchantDraft.loading", defaultValue: "Loading drafts…", table: "ProjectMerchantDraft", locale: locale))
        case .resolving: return String(localized: LocalizedStringResource("projectMerchantDraft.resolving", defaultValue: "Checking the selected draft…", table: "ProjectMerchantDraft", locale: locale))
        case .empty: return String(localized: LocalizedStringResource("projectMerchantDraft.empty", defaultValue: "No saved AI drafts were returned for this store.", table: "ProjectMerchantDraft", locale: locale))
        case .unavailableRow: return String(localized: LocalizedStringResource("projectMerchantDraft.unavailableRow", defaultValue: "This source is no longer an unchanged, available draft. It cannot be selected.", table: "ProjectMerchantDraft", locale: locale))
        case .loadMore: return String(localized: LocalizedStringResource("projectMerchantDraft.loadMore", defaultValue: "Load older drafts", table: "ProjectMerchantDraft", locale: locale))
        case .review: return String(localized: LocalizedStringResource("projectMerchantDraft.review", defaultValue: "Review template reference", table: "ProjectMerchantDraft", locale: locale))
        case .noPublicationAuthority: return String(localized: LocalizedStringResource("projectMerchantDraft.noPublicationAuthority", defaultValue: "This reference grants no publication or usage rights. Existing save, facts confirmation, review and release checks still apply.", table: "ProjectMerchantDraft", locale: locale))
        case .apply: return String(localized: LocalizedStringResource("projectMerchantDraft.apply", defaultValue: "Check and use this reference", table: "ProjectMerchantDraft", locale: locale))
        case .stale: return String(localized: LocalizedStringResource("projectMerchantDraft.stale", defaultValue: "The node, draft or account has changed. Close this chooser and reopen it.", table: "ProjectMerchantDraft", locale: locale))
        case .failed: return String(localized: LocalizedStringResource("projectMerchantDraft.failed", defaultValue: "Drafts could not be read. Refresh to try again.", table: "ProjectMerchantDraft", locale: locale))
        case .unauthorized: return String(localized: LocalizedStringResource("projectMerchantDraft.unauthorized", defaultValue: "Sign in again before reading these drafts.", table: "ProjectMerchantDraft", locale: locale))
        case .forbidden: return String(localized: LocalizedStringResource("projectMerchantDraft.forbidden", defaultValue: "This account is not the current owner of this store.", table: "ProjectMerchantDraft", locale: locale))
        case .changed: return String(localized: LocalizedStringResource("projectMerchantDraft.changed", defaultValue: "The selected source has changed. Refresh and choose again.", table: "ProjectMerchantDraft", locale: locale))
        case .otherGameplay: return String(localized: LocalizedStringResource("projectMerchantDraft.otherGameplay", defaultValue: "Other gameplay creation and editing are not connected in this field.", table: "ProjectMerchantDraft", locale: locale))
        }
    }
}
