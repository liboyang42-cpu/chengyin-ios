import Foundation

/// Approved-backend gap for a purchased upgrade. This type does not open a connection.
public enum WorkshopUpgradeProductionPort: String, Equatable, Sendable {
    case compareModVersions = "CompareModVersions"
    case upgradeInstallDraft = "UpgradeInstallDraft"
}

public struct WorkshopUpgradeProductionBoundary: Equatable, Sendable {
    public static let callsNetwork = false
    public static let portsEnabled = false
    public static let blocked: [WorkshopUpgradeProductionPort] = [.compareModVersions, .upgradeInstallDraft]
}
