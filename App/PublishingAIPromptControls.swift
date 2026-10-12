import SwiftUI

@MainActor final class PublishingAIPromptController: ObservableObject {
    @Published private var generation = UUID()
    private var active = false
    func activate() { generation = UUID(); active = true }
    func retire() { active = false; generation = UUID() }
    func canSelect(in flow: PublishingAIDraftFlow) -> Bool { active && flow.canUseIdeaSuggestion }
    func action(_ suggestion: PublishingAIPromptSuggestion, languageCode: String,
                flow: PublishingAIDraftFlow, applied: @escaping () -> Void = {}) -> () -> Void {
        let token = generation
        let select = flow.ideaSuggestionAction(suggestion,languageCode:languageCode)
        return { [weak self, weak flow] in
            guard let self, let flow, token == self.generation, self.canSelect(in:flow), select() else { return }
            self.generation = UUID(); applied()
        }
    }
}

/// The Form row renders actions only. Its recycling never retires the stable sheet owner.
@MainActor struct PublishingAIPromptControls: View {
    @ObservedObject var controller: PublishingAIPromptController
    let flow: PublishingAIDraftFlow
    let applied: () -> Void
    @Environment(\.locale) private var locale
    var body: some View {
        if flow.candidate == nil {
            VStack(alignment:.leading,spacing:8) {
                Text("creatorAIPrompts.title",tableName:"CreatorAIPrompts").font(.caption).foregroundStyle(.secondary)
                ForEach(PublishingAIPromptSuggestion.allCases) { suggestion in
                    Button(action:controller.action(suggestion,languageCode:locale.identifier,flow:flow,applied:applied)) {
                        Label {
                            Text(LocalizedStringKey(suggestion.titleKey),tableName:"CreatorAIPrompts")
                        } icon: { Image(systemName:"arrow.turn.down.right") }
                    }.buttonStyle(.borderless).disabled(!controller.canSelect(in:flow))
                        .accessibilityIdentifier("creatorAIPrompts.select." + suggestion.rawValue)
                }
            }.accessibilityIdentifier("creatorAIPrompts.options")
        }
    }
}

@MainActor struct PublishingAIPromptLifetime: ViewModifier {
    @ObservedObject var controller: PublishingAIPromptController
    @Environment(\.scenePhase) private var scenePhase
    func body(content: Content) -> some View {
        content
            .onAppear { if scenePhase == .active { controller.activate() } else { controller.retire() } }
            .onChange(of:scenePhase) { _,phase in
                if phase == .active { controller.activate() } else { controller.retire() }
            }
            .onDisappear { controller.retire() }
    }
}
