import SwiftUI

/// Empty-by-default manual search-center entry. The callback is the only output. The root owns
/// the in-memory selection and decides when its configured reader uses it. No persistence/network.
@MainActor
struct RoamAreaPicker: View {
    let onSelect: (RoamSearchArea) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var latitude = ""
    @State private var longitude = ""
    @State private var name = ""
    private var selectedArea: RoamSearchArea? {
        try? RoamSearchArea.manual(latitude: latitude, longitude: longitude, label: name)
    }
    private var latitudeIsInvalid: Bool {
        guard !latitude.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard let value = Double(latitude.trimmingCharacters(in: .whitespacesAndNewlines)),
              value.isFinite, (-90...90).contains(value) else { return true }
        return false
    }
    private var longitudeIsInvalid: Bool {
        guard !longitude.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard let value = Double(longitude.trimmingCharacters(in: .whitespacesAndNewlines)),
              value.isFinite, (-180...180).contains(value) else { return true }
        return false
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("roam.area.explanation")
                    Text("roam.area.searchDisclosure").foregroundStyle(.secondary)
                }
                Section("roam.area.coordinates") {
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("roam.area.latitude", text: $latitude)
                            .keyboardType(.numbersAndPunctuation)
                            .autocorrectionDisabled().textInputAutocapitalization(.never)
                            .accessibilityIdentifier("roam.area.latitude.input")
                        Text("roam.area.latitudeHint").font(.caption).foregroundStyle(.secondary)
                        if latitudeIsInvalid {
                            Label("roam.area.invalidLatitude", systemImage: "exclamationmark.circle")
                                .font(.caption).foregroundStyle(.red)
                                .accessibilityIdentifier("roam.area.latitude.error")
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("roam.area.longitude", text: $longitude)
                            .keyboardType(.numbersAndPunctuation)
                            .autocorrectionDisabled().textInputAutocapitalization(.never)
                            .accessibilityIdentifier("roam.area.longitude.input")
                        Text("roam.area.longitudeHint").font(.caption).foregroundStyle(.secondary)
                        if longitudeIsInvalid {
                            Label("roam.area.invalidLongitude", systemImage: "exclamationmark.circle")
                                .font(.caption).foregroundStyle(.red)
                                .accessibilityIdentifier("roam.area.longitude.error")
                        }
                    }
                    TextField("roam.area.name", text: $name)
                        .accessibilityIdentifier("roam.area.name.input")
                }
                Section {
                    Text("roam.area.coordinateSystem").font(.footnote).foregroundStyle(.secondary)
                    Text("roam.area.memoryOnly").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("roam.area.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("roam.area.cancel") { dismiss() }
                        .accessibilityIdentifier("roam.area.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("roam.area.select") {
                        guard let area = selectedArea else { return }
                        onSelect(area)
                        dismiss()
                    }
                    .disabled(selectedArea == nil)
                    .accessibilityIdentifier("roam.area.select")
                }
            }
        }
        .accessibilityIdentifier("roam.area.picker")
    }
}
