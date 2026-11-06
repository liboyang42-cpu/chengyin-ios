import Foundation

/// The original issuer returns an inline PNG, not a URL to an authenticated API.
/// Decode in memory only; never persist the signed credential or forward a token.
public enum ClubGroupCodeImage {
    public static let maximumBytes = 1_048_576
    public static func inlinePNG(_ text: String) throws -> Data {
        let prefix = "data:image/png;base64,"
        guard text.hasPrefix(prefix), text.utf8.count <= prefix.utf8.count + (maximumBytes + 2) / 3 * 4,
              let bytes = Data(base64Encoded: String(text.dropFirst(prefix.count))) else {
            throw ClubGovernanceFailure.malformed
        }
        try validatePNG(bytes)
        return bytes
    }
    public static func validatePNG(_ bytes: Data) throws {
        let data = [UInt8](bytes)
        guard (57...maximumBytes).contains(data.count), Array(data.prefix(8)) == [137,80,78,71,13,10,26,10] else { throw ClubGovernanceFailure.malformed }
        func uint32(_ p: Int) -> UInt32 {
            data[p..<p + 4].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        }
        var offset = 8, hasHeader = false, hasPixels = false
        while offset + 12 <= data.count {
            let size = Int(uint32(offset))
            guard size <= maximumBytes, offset + 12 + size <= data.count else { throw ClubGovernanceFailure.malformed }
            let type = String(bytes: data[(offset + 4)..<(offset + 8)], encoding: .ascii)
            var crc: UInt32 = 0xffffffff
            for byte in data[(offset + 4)..<(offset + 8 + size)] {
                crc ^= UInt32(byte)
                for _ in 0..<8 { crc = (crc >> 1) ^ (crc & 1 == 0 ? 0 : 0xedb88320) }
            }
            guard (crc ^ 0xffffffff) == uint32(offset + 8 + size) else { throw ClubGovernanceFailure.malformed }
            if !hasHeader {
                guard type == "IHDR", size == 13, (1...1024).contains(uint32(offset + 8)),
                      (1...1024).contains(uint32(offset + 12)) else { throw ClubGovernanceFailure.malformed }
                hasHeader = true
            } else if type == "IHDR" || type == "acTL" { throw ClubGovernanceFailure.malformed }
            if type == "IDAT" { hasPixels = true }
            if type == "IEND" {
                guard size == 0, hasPixels, offset + 12 == data.count else { throw ClubGovernanceFailure.malformed }
                return
            }
            offset += size + 12
        }
        throw ClubGovernanceFailure.malformed
    }
}
