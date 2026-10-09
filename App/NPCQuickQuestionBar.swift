import SwiftUI

/// Shared local composer controls; the existing parent send/review buttons own
/// transmission. There is no model/transport reference in this view.
@MainActor struct NPCQuickQuestionBar: View {
    @Binding var draft: String
    let context: NPCQuickQuestionContext
    let enabled: Bool
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var replacement: NPCQuickQuestionReplacement?
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) { questions }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { questions }
                    VStack(alignment: .leading, spacing: 6) { questions }
                }
            }
            Text("npcQuick.composeOnly").font(.caption).foregroundStyle(.secondary)
            if case .gameNode = context {
                Text("npcQuick.publicRulesBoundary").font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("npcQuick.bar")
        .confirmationDialog("npcQuick.replaceTitle", isPresented: Binding(get: { replacement != nil }, set: { if !$0 { replacement = nil } }), titleVisibility: .visible, presenting: replacement) { pending in
            Button("npcQuick.replace") { confirmReplacement(pending) }
                .accessibilityIdentifier("npcQuick.replace")
            Button("action.cancel", role: .cancel) { replacement = nil }
        } message: { _ in Text("npcQuick.replaceMessage") }
        .onChange(of: draft) { _, _ in replacement = nil }
        .onChange(of: context) { _, _ in replacement = nil }
        .onChange(of: enabled) { _, _ in replacement = nil }
        .onChange(of: locale.identifier) { _, _ in replacement = nil }
        .onDisappear { replacement = nil }
    }
    private var questions: some View {
        ForEach(context.questions) { question in
            Button(LocalizedStringKey(question.titleKey)) { select(question) }
                .buttonStyle(.bordered).frame(minHeight: 44)
                .disabled(!enabled)
                .accessibilityHint("npcQuick.accessibilityHint")
                .accessibilityIdentifier("npcQuick." + question.rawValue)
        }
    }
    private func select(_ question: NPCQuickQuestion) {
        let localized = NPCQuickQuestionText.question(question, locale: locale)
        switch NPCQuickQuestionPolicy.select(question, localizedQuestion: localized, originalText: draft,
                                             context: context, localeIdentifier: locale.identifier, enabled: enabled) {
        case .insert(let text): draft = text; replacement = nil
        case .confirmReplacement(let pending): replacement = pending
        case .unchanged, .unavailable: replacement = nil
        }
    }
    private func confirmReplacement(_ pending: NPCQuickQuestionReplacement) {
        replacement = nil
        if let text = NPCQuickQuestionPolicy.confirm(pending, currentText: draft, context: context,
                                                     localeIdentifier: locale.identifier, enabled: enabled) { draft = text }
    }
}

enum NPCQuickQuestionText {
    static func question(_ question: NPCQuickQuestion, locale: Locale) -> String {
        appLocalized(String.LocalizationValue(stringLiteral: question.questionKey), locale: locale)
    }
}
