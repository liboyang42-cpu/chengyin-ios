import SwiftUI

/// Keep the field name and exact revision as separate, ordered accessibility
/// elements. LabeledContent can merge its label into the value's element.
struct ProjectRemoteVersionRow: View {
    let revision: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("projectRemote.version")
            Spacer(minLength: 12)
            Text(verbatim: revision)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .accessibilityIdentifier("projectRemote.version.value")
        }
        .accessibilityElement(children: .contain)
    }
}
