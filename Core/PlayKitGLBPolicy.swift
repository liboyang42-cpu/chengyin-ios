import Foundation
import CoreFoundation

/// Deliberately bounded static glTF 2.0 profile. Unsupported features fail into
/// the existing image fallback before any native decoder sees the bytes.
public enum PlayKitGLBPolicy {
    public static let maximumBytes = 20 * 1024 * 1024
    public static let maximumJSONBytes = 1024 * 1024
    public static let timeoutSeconds: TimeInterval = 20
    public struct Manifest: Equatable {
        public let binaryRange: Range<Int>
        public let imageRanges: [Range<Int>]
        public let nodeCount: Int
    }
    public static func approvedURL(_ source: String?, hosts: Set<String>) -> URL? {
        guard let url = PlayKitCameraAssets.approvedURL(source, hosts: hosts),
              url.pathExtension.lowercased() == "glb", url.fragment == nil else { return nil }
        return url
    }
    /// Re-encode the already validated JSON before native parsing, eliminating
    /// duplicate-key/parser-differential ambiguity. Only the local BIN survives.
    public static func sanitizedData(_ data: Data) throws -> Data {
        let manifest = try validate(data)
        let object = try JSONSerialization.jsonObject(with: data.subdata(in: 20..<(manifest.binaryRange.lowerBound - 8)))
        var json = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        while json.count % 4 != 0 { json.append(0x20) }
        guard json.count <= maximumJSONBytes, 28 + json.count + manifest.binaryRange.count <= maximumBytes else { throw PlayKitSpatialError.unsupportedModel }
        var output = Data()
        func append(_ value: UInt32) { for shift in [0, 8, 16, 24] { output.append(UInt8((value >> shift) & 255)) } }
        append(0x46546C67); append(2); append(UInt32(28 + json.count + manifest.binaryRange.count))
        append(UInt32(json.count)); append(0x4E4F534A); output.append(json)
        append(UInt32(manifest.binaryRange.count)); append(0x004E4942); output.append(data.subdata(in: manifest.binaryRange))
        return output
    }
    public static func validate(_ data: Data) throws -> Manifest {
        func fail() throws -> Never { throw PlayKitSpatialError.unsupportedModel }
        func u32(_ offset: Int) -> UInt32 {
            (0..<4).reduce(0) { $0 | UInt32(data[data.startIndex + offset + $1]) << ($1 * 8) }
        }
        guard data.count >= 28, data.count <= maximumBytes, u32(0) == 0x46546C67,
              u32(4) == 2, Int(u32(8)) == data.count else { try fail() }
        let jsonLength = Int(u32(12))
        guard jsonLength > 0, jsonLength <= maximumJSONBytes, jsonLength % 4 == 0,
              u32(16) == 0x4E4F534A, jsonLength <= data.count - 28 else { try fail() }
        let second = 20 + jsonLength
        let binLength = Int(u32(second))
        guard u32(second + 4) == 0x004E4942, binLength > 0, binLength % 4 == 0,
              second + 8 + binLength == data.count else { try fail() }
        let binaryRange = (second + 8)..<data.count
        guard let root = try JSONSerialization.jsonObject(with: data.subdata(in: 20..<second)) as? [String: Any],
              let asset = root["asset"] as? [String: Any], asset["version"] as? String == "2.0",
              asset["minVersion"] == nil || asset["minVersion"] as? String == "2.0" else { try fail() }
        // No external, relative, file:, data:, HTTP or extension-mediated resources.
        // Reject extensions even when declared optional: SceneKit does not faithfully
        // implement every glTF extension, and no Draco/KTX plugin is activated.
        var budget = 100_000
        func inspect(_ value: Any, depth: Int = 0) throws {
            budget -= 1
            guard depth <= 32, budget >= 0 else { try fail() }
            if let object = value as? [String: Any] {
                for (key, child) in object {
                    if key == "uri" { try fail() }
                    if key == "extensions" { guard let values = child as? [String: Any], values.isEmpty else { try fail() } }
                    if ["extensionsUsed", "extensionsRequired"].contains(key) { guard let values = child as? [String], values.isEmpty else { try fail() } }
                    try inspect(child, depth: depth + 1)
                }
            } else if let values = value as? [Any] {
                for child in values { try inspect(child, depth: depth + 1) }
            } else if let number = value as? NSNumber, !number.doubleValue.isFinite { try fail() }
        }
        try inspect(root)
        func objects(_ key: String, cap: Int, required: Bool = false) throws -> [[String: Any]] {
            guard let value = root[key] else { if required { try fail() }; return [] }
            guard let result = value as? [[String: Any]], result.count <= cap, !required || !result.isEmpty else { try fail() }
            return result
        }
        func integer(_ value: Any?, default fallback: Int? = nil) throws -> Int {
            guard let value else { if let fallback { return fallback }; try fail() }
            guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite,
                  n.doubleValue >= 0, n.doubleValue <= Double(maximumBytes), n.doubleValue.rounded() == n.doubleValue else { try fail() }
            return n.intValue
        }
        func index(_ value: Any?, count: Int) throws -> Int {
            let i = try integer(value); guard i < count else { try fail() }; return i
        }
        let buffers = try objects("buffers", cap: 1, required: true)
        let bufferLength = try integer(buffers[0]["byteLength"])
        guard bufferLength > 0, bufferLength <= binLength, binLength - bufferLength <= 3 else { try fail() }
        let views = try objects("bufferViews", cap: 1024, required: true)
        var ranges: [Range<Int>] = [], strides: [Int] = []
        for view in views {
            guard try integer(view["buffer"]) == 0 else { try fail() }
            let start = try integer(view["byteOffset"], default: 0), length = try integer(view["byteLength"])
            let stride = try integer(view["byteStride"], default: 0)
            guard length > 0, start <= bufferLength, length <= bufferLength - start,
                  stride == 0 || (stride >= 4 && stride <= 252 && stride % 4 == 0) else { try fail() }
            ranges.append(start..<(start + length)); strides.append(stride)
        }
        let accessors = try objects("accessors", cap: 1024, required: true)
        var counts: [Int] = [], components: [Int] = [], dimensions: [String] = [], accessorRanges: [(Int, Int, Int)] = []
        var elements = 0
        for accessor in accessors {
            guard accessor["sparse"] == nil else { try fail() }
            let view = try index(accessor["bufferView"], count: views.count)
            let component = try integer(accessor["componentType"])
            let count = try integer(accessor["count"]), start = try integer(accessor["byteOffset"], default: 0)
            guard let dimension = accessor["type"] as? String,
                  let width = [5120:1, 5121:1, 5122:2, 5123:2, 5125:4, 5126:4][component],
                  let lanes = ["SCALAR":1, "VEC2":2, "VEC3":3, "VEC4":4][dimension],
                  count > 0, count <= 250_000, start % width == 0 else { try fail() }
            let size = width * lanes, stride = strides[view] == 0 ? size : strides[view]
            guard stride >= size, stride % width == 0,
                  start <= ranges[view].count, size <= ranges[view].count - start,
                  count - 1 <= (ranges[view].count - start - size) / stride else { try fail() }
            elements += count; guard elements <= 1_000_000 else { try fail() }
            if component == 5126 {
                // Reject NaN/infinite geometry and pathological coordinates before bridge/bounds calculation.
                for element in 0..<count { for lane in 0..<lanes {
                    let value = Float(bitPattern: u32(binaryRange.lowerBound + ranges[view].lowerBound + start + element * stride + lane * 4))
                    guard value.isFinite, abs(value) <= 1_000_000 else { try fail() }
                } }
            }
            counts.append(count); components.append(component); dimensions.append(dimension)
            accessorRanges.append((ranges[view].lowerBound + start, stride, width))
        }
        let materials = try objects("materials", cap: 128)
        let meshes = try objects("meshes", cap: 128, required: true)
        var primitiveCount = 0
        var meshVertices: [Int] = [], meshPrimitives: [Int] = []
        for mesh in meshes {
            guard mesh["weights"] == nil, let primitives = mesh["primitives"] as? [[String: Any]], !primitives.isEmpty else { try fail() }
            var vertices = 0
            for primitive in primitives {
                primitiveCount += 1; guard primitiveCount <= 512, primitive["targets"] == nil,
                    try integer(primitive["mode"], default: 4) == 4,
                    let attributes = primitive["attributes"] as? [String: Any], !attributes.isEmpty else { try fail() }
                let position = try index(attributes["POSITION"], count: accessors.count)
                guard components[position] == 5126, dimensions[position] == "VEC3" else { try fail() }
                vertices += counts[position]
                for (semantic, reference) in attributes {
                    let a = try index(reference, count: accessors.count)
                    guard counts[a] == counts[position], ["POSITION", "NORMAL", "TANGENT", "TEXCOORD_0", "TEXCOORD_1", "COLOR_0"].contains(semantic) else { try fail() }
                    let validDimensions = semantic == "POSITION" || semantic == "NORMAL" ? ["VEC3"] : semantic == "TANGENT" ? ["VEC4"] : semantic == "COLOR_0" ? ["VEC3", "VEC4"] : ["VEC2"]
                    guard validDimensions.contains(dimensions[a]) else { try fail() }
                }
                if let value = primitive["indices"] {
                    let a = try index(value, count: accessors.count)
                    guard [5121,5123,5125].contains(components[a]), dimensions[a] == "SCALAR", counts[a] % 3 == 0 else { try fail() }
                    // Count submitted elements as well as unique vertices: a small
                    // vertex buffer can otherwise amplify work through indices.
                    vertices += max(0, counts[a] - counts[position])
                    let (start, stride, width) = accessorRanges[a]
                    for element in 0..<counts[a] {
                        let offset = binaryRange.lowerBound + start + element * stride
                        let vertex = (0..<width).reduce(UInt32(0)) { $0 | UInt32(data[data.startIndex + offset + $1]) << ($1 * 8) }
                        guard vertex < UInt32(counts[position]) else { try fail() }
                    }
                } else if counts[position] % 3 != 0 { try fail() }
                if let material = primitive["material"] { _ = try index(material, count: materials.count) }
            }
            meshVertices.append(vertices); meshPrimitives.append(primitives.count)
        }
        let nodes = try objects("nodes", cap: 512, required: true)
        var children = [[Int]](), parents = Set<Int>()
        var instancedVertices = 0, instancedPrimitives = 0
        for node in nodes {
            guard node["skin"] == nil, node["weights"] == nil, node["camera"] == nil else { try fail() }
            if let mesh = node["mesh"] {
                let m = try index(mesh, count: meshes.count)
                instancedVertices += meshVertices[m]; instancedPrimitives += meshPrimitives[m]
                guard instancedVertices <= 1_000_000, instancedPrimitives <= 1024 else { try fail() }
            }
            for (key, size) in [("matrix",16), ("translation",3), ("rotation",4), ("scale",3)] {
                if let raw = node[key] {
                    guard let values = raw as? [NSNumber], values.count == size,
                          values.allSatisfy({ CFGetTypeID($0) != CFBooleanGetTypeID() && $0.doubleValue.isFinite && abs($0.doubleValue) <= 10_000 }) else { try fail() }
                }
            }
            guard node["matrix"] == nil || (node["translation"] == nil && node["rotation"] == nil && node["scale"] == nil) else { try fail() }
            let refs = node["children"] as? [Any] ?? []
            guard node["children"] == nil || node["children"] is [Any] else { try fail() }
            var row: [Int] = []
            for ref in refs {
                let child = try index(ref, count: nodes.count)
                guard parents.insert(child).inserted else { try fail() }; row.append(child)
            }
            children.append(row)
        }
        var visited = Set<Int>(), visiting = Set<Int>()
        func visit(_ node: Int, depth: Int = 0) throws {
            guard depth <= 32, !visiting.contains(node) else { try fail() }
            if visited.contains(node) { return }
            visiting.insert(node); for child in children[node] { try visit(child, depth: depth + 1) }
            visiting.remove(node); visited.insert(node)
        }
        for node in nodes.indices { try visit(node) }
        let scenes = try objects("scenes", cap: 16, required: true)
        _ = try index(root["scene"] ?? 0, count: scenes.count)
        for scene in scenes {
            guard let roots = scene["nodes"] as? [Any], !roots.isEmpty else { try fail() }
            var seen = Set<Int>()
            for root in roots { let n = try index(root, count: nodes.count); guard !parents.contains(n), seen.insert(n).inserted else { try fail() } }
        }
        // Animation/skinning/morphs and compressed codecs need separate compatibility acceptance.
        for key in ["animations", "skins", "cameras"] { guard try objects(key, cap: 0).isEmpty else { try fail() } }
        let images = try objects("images", cap: 16)
        var imageRanges: [Range<Int>] = []
        for image in images {
            let mime = (image["mimeType"] as? String) ?? ""
            guard ["image/png", "image/jpeg"].contains(mime) else { try fail() }
            let view = try index(image["bufferView"], count: views.count)
            guard strides[view] == 0 else { try fail() }
            imageRanges.append((binaryRange.lowerBound + ranges[view].lowerBound)..<(binaryRange.lowerBound + ranges[view].upperBound))
        }
        let samplers = try objects("samplers", cap: 32), textures = try objects("textures", cap: 32)
        for texture in textures {
            _ = try index(texture["source"], count: images.count)
            if let sampler = texture["sampler"] { _ = try index(sampler, count: samplers.count) }
        }
        func checkTextures(_ value: Any) throws {
            if let dict = value as? [String: Any] {
                for (key, child) in dict {
                    if key.hasSuffix("Texture") {
                        guard let texture = child as? [String: Any] else { try fail() }
                        _ = try index(texture["index"], count: textures.count)
                        guard try integer(texture["texCoord"], default: 0) <= 1 else { try fail() }
                    } else { try checkTextures(child) }
                }
            }
        }
        for material in materials { try checkTextures(material) }
        return Manifest(binaryRange: binaryRange, imageRanges: imageRanges, nodeCount: nodes.count)
    }
}

/// Source ar-math.js fitModelOf, with MODEL_SIZE = { PLANE: 0.4, MARKER: 0.8 }.
/// Marker's source units are physical image width; never reuse image-card width as model scale.
public struct PlayKitModelFit: Equatable {
    public let scale: Double
    public let x: Double
    public let y: Double
    public let z: Double
    public init(min: (Double, Double, Double), max: (Double, Double, Double), targetMeters: Double) throws {
        let values = [min.0,min.1,min.2,max.0,max.1,max.2,targetMeters]
        let longest = Swift.max(max.0 - min.0, Swift.max(max.1 - min.1, max.2 - min.2))
        guard values.allSatisfy({ $0.isFinite }), max.0 >= min.0, max.1 >= min.1, max.2 >= min.2,
              longest >= 0.000001, longest <= 1_000_000, targetMeters > 0, targetMeters <= 8 else { throw PlayKitSpatialError.unsupportedModel }
        scale = targetMeters / longest
        x = -(min.0 + max.0) * 0.5 * scale; y = -min.1 * scale; z = -(min.2 + max.2) * 0.5 * scale
    }
}
