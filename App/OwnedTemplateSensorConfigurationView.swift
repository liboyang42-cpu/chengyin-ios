import SwiftUI

/// Value-only rendering in the existing session-fenced owner host. No retained child state.
@MainActor struct OwnedTemplateSensorConfigurationFields: View {
    let configuration: OwnedTemplateSensorConfiguration
    var body: some View {
        Section("templateOwnerSensor.configuration") {
            Text("templateOwnerSensor.scope").font(.caption).foregroundStyle(.secondary)
            if let kind = configuration.kind {
                Text(LocalizedStringKey("templateOwnerSensor.kind." + kind.rawValue))
                ForEach(configuration.parameters, id: \.self) { parameter in
                    LabeledContent(LocalizedStringKey("templateOwnerSensor.parameter." + parameter.rawValue)) {
                        switch configuration.value(parameter) {
                        case .value(let value): Text(verbatim: String(value))
                        case .missing, .null: Text("templateOwnerConfig.missing")
                        case .invalid: Text("templateOwnerSensor.invalid")
                        }
                    }
                }
            }
            switch configuration.status {
            case .missing, .null: Text("templateOwnerConfig.missing")
            case .invalid: Text("templateOwnerSensor.invalid")
            case .unsupportedType: Text("templateOwnerSensor.unsupportedType")
            case .partial: Text("templateOwnerConfig.partial")
            case .ready: EmptyView()
            }
        }.accessibilityIdentifier("templateOwnerSensor.configuration")
    }
}
