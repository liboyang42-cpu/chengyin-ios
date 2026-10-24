import SwiftUI

/// Declared H5 surface. Appearance does not open a container.
/// Open reports the missing original SDK and does not show a successful session.
@MainActor struct H5DeclaredSessionView: View {
    let frozen: H5FrozenCapability
    let host: String
    let capability: String
    let sdkVersion: String
    @State private var entry = H5DeclaredSessionEntry()
    @State private var message = ""

    var body: some View {
        Form {
            Section("h5.surface") {
                Text(verbatim: host)
                Text(verbatim: capability)
                Text(verbatim: sdkVersion)
            }
            Section {
                Button("h5.admit") { admit() }
                Button("h5.open") { message = entry.open().capabilityText }
                    .disabled(entry.gate.phase != .admitted && entry.gate.phase != .waitingSource)
            }
            if !message.isEmpty { Text(verbatim: message).font(.footnote) }
        }
        .navigationTitle(Text("h5.title"))
    }

    private func admit() {
        do {
            try entry.admit(host: host, capability: capability, sdkVersion: sdkVersion, frozen: frozen)
            message = "h5.admitted"
        } catch let error as H5SessionFailure {
            message = error.capabilityText
        } catch {
            message = "h5.invalid"
        }
    }
}

private extension H5SessionFailure {
    var capabilityText: String {
        switch self {
        case .waitingSource(let capability): return capability
        case .unsignedDomain: return "h5.unsignedDomain"
        case .capabilityNotGranted: return "h5.capabilityNotGranted"
        case .versionIncompatible: return "h5.versionIncompatible"
        case .arbitraryH5Forbidden: return "h5.arbitraryForbidden"
        case .notAdmitted: return "h5.notAdmitted"
        case .invalidSurface: return "h5.invalid"
        case .requestMismatch: return "h5.requestMismatch"
        }
    }
}
