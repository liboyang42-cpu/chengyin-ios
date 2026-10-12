import SwiftUI

private struct MerchantCustomerContactFactoryKey: EnvironmentKey {
    static let defaultValue: (@MainActor (MerchantCustomerContactSelection, @escaping () -> Bool) -> MerchantCustomerContactFlow?)? = nil
}
extension EnvironmentValues {
    var merchantCustomerContactFactory: (@MainActor (MerchantCustomerContactSelection, @escaping () -> Bool) -> MerchantCustomerContactFlow?)? {
        get { self[MerchantCustomerContactFactoryKey.self] }
        set { self[MerchantCustomerContactFactoryKey.self] = newValue }
    }
}
@MainActor struct MerchantCustomerContactEntry: View {
    @ObservedObject var owner: MerchantBusinessViewModel
    let record: MerchantBusinessRecord
    @Environment(\.merchantCustomerContactFactory) private var factory
    @Binding var flow: MerchantCustomerContactFlow?
    private func selection(_ purpose: MerchantContactPurpose) -> MerchantCustomerContactSelection? {
        let state = owner.coordinator
        guard state.isCurrent, !state.isBusy, !state.isLocked, state.failureKey == nil else { return nil }
        return .init(scope: state.reader.scope, authorizationGeneration: state.reader.authorizationGeneration,
            snapshot: state.snapshot, record: record, purpose: purpose)
    }
    var body: some View {
        if factory != nil, selection(.call) != nil {
            HStack {
                ForEach(MerchantContactPurpose.allCases, id: \.self) { purpose in
                    Button(LocalizedStringKey("merchant.engagement.contact." + purpose.rawValue)) { open(purpose) }
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("merchant.contactFlow." + purpose.rawValue + "." + record.id)
                }
            }

        }
    }
    private func open(_ purpose: MerchantContactPurpose) {
        guard flow == nil, let selected = selection(purpose), let factory else { return }
        let acceptedOwner = owner
        let current: () -> Bool = {
            let state = acceptedOwner.coordinator
            return state.isCurrent && !state.isBusy && !state.isLocked && state.failureKey == nil &&
                selected.matches(scope: state.reader.scope, authorizationGeneration: state.reader.authorizationGeneration, snapshot: state.snapshot)
        }
        flow = factory(selected, current)
    }
}

/// Retained by MerchantBusinessPage, not a conditional customer row.
@MainActor struct MerchantCustomerContactStablePresentation: ViewModifier {
    @ObservedObject var owner: MerchantBusinessViewModel
    @Binding var flow: MerchantCustomerContactFlow?
    func body(content: Content) -> some View {
        let shownID = flow?.id
        content.background {
            Color.clear.frame(width: 0, height: 0)
                .sheet(item: Binding(get: { flow?.id == shownID ? flow : nil }, set: { next in
                    guard flow?.id == shownID else { return }
                    if next == nil { flow?.invalidate() }; flow = next
                })) { MerchantCustomerContactSheet(flow: $0) }
                .id(flow?.id)
        }
        .onReceive(owner.objectWillChange) { _ in
            // Reconcile the same captured flow; a delayed old callback cannot touch a replacement.
            let captured = flow
            Task { @MainActor in captured?.reconcile() }
        }
        .onDisappear { flow?.invalidate(); flow = nil }
    }
}
