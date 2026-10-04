import SwiftUI

/// Only the verified result fields are shown; no synthetic answers, scores or tag grants.
struct TemplatePreferencePreviewView: View {
    let raw: String
    var body: some View {
        if let preview = try? TemplatePreferencePreview(raw: raw) {
            Text("templateAuthor.preference.partial").font(.caption).foregroundStyle(.secondary)
            ForEach(preview.dimensions.indices, id: \.self) { index in Text(verbatim: preview.dimensions[index]) }
            ForEach(preview.results) { result in
                VStack(alignment: .leading) {
                    Text(verbatim: result.id).font(.caption)
                    Text(verbatim: result.title).font(.headline)
                    Text(verbatim: result.body)
                    Text(verbatim: result.nextStep)
                    LabeledContent("templateAuthor.preference.days", value: String(result.nextStepDays))
                }
            }
            if let recipient = preview.recipientLabel, let purpose = preview.purpose {
                LabeledContent("templateAuthor.preference.recipient", value: recipient)
                LabeledContent("templateAuthor.preference.purpose", value: purpose)
                Text("templateAuthor.preference.revocable")
            }
        } else { Text("templateAuthor.preference.unsupported") }
    }
}
