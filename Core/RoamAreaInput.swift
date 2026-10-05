import Foundation

public enum RoamAreaInputError: Error, Equatable {
    case missingLatitude, missingLongitude, invalidLatitude, invalidLongitude
}

extension RoamSearchArea {
    /// Pure, transient user-input parsing. This does not request a location, transmit, or persist it.
    public static func manual(latitude: String, longitude: String, label: String = "") throws -> RoamSearchArea {
        let latitudeText = latitude.trimmingCharacters(in: .whitespacesAndNewlines)
        let longitudeText = longitude.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !latitudeText.isEmpty else { throw RoamAreaInputError.missingLatitude }
        guard !longitudeText.isEmpty else { throw RoamAreaInputError.missingLongitude }
        guard let lat = Double(latitudeText), lat.isFinite, (-90...90).contains(lat) else {
            throw RoamAreaInputError.invalidLatitude
        }
        guard let lng = Double(longitudeText), lng.isFinite, (-180...180).contains(lng),
              let coordinate = RoamCoordinate(latitude: lat, longitude: lng) else {
            throw RoamAreaInputError.invalidLongitude
        }
        return RoamSearchArea(coordinate: coordinate, label: label)
    }
}
