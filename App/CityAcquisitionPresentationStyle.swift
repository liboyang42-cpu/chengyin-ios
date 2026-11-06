import SwiftUI

// G06 acquisition-only extraction of the original presentation helpers. No authority or request state.
struct CityAcquisitionPageStyle: ViewModifier {
    @Environment(\.themeDomain) private var domain
    func body(content: Content) -> some View {
        content
            .font(Theme.Font.body)
            .foregroundStyle(Theme.Color.textPrimary(in: domain))
            .tint(Theme.Color.accent(in: domain))
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.Color.bgPage(in: domain))
    }
}

struct CityAcquisitionMetadataRow: View {
    let label: Text
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s1) {
            label.font(Theme.Font.label).foregroundStyle(.secondary)
            Text(verbatim: value).font(Theme.Font.body).monospacedDigit()
                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct CityAcquisitionPrimaryAction: ViewModifier {
    var destructive = false
    @Environment(\.themeDomain) private var domain
    func body(content: Content) -> some View {
        content.buttonStyle(.borderedProminent).controlSize(.large).frame(minHeight: 44)
            .tint(destructive ? .red : Theme.Color.accent(in: domain))
    }
}

struct CityAcquisitionSecondaryAction: ViewModifier {
    func body(content: Content) -> some View {
        content.buttonStyle(.bordered).controlSize(.regular).frame(minHeight: 44)
    }
}

struct CityAcquisitionCard<Content: View>: View {
    @Environment(\.themeDomain) private var domain
    private let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s3) { content }
            .padding(Theme.Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Color.bgSurface(in: domain), in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
    }
}
