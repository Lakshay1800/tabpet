import Foundation

/// conformance/animals.json's shape is simple enough (no nested unions or
/// AroundPath trees) to decode directly with Codable, unlike the general
/// JSONValue tree in TabPetCoreTests/ConformanceFixture.swift - that type is
/// internal to its own module, so this test target (a separate SwiftPM
/// module) cannot reuse it and instead mirrors the same wire format locally.

/// every float leaf in the fixture is {"bits": "<16 hex>", "value": ...} -
/// bits is authoritative, reconstructed as the raw IEEE 754 pattern. Keeps
/// the raw pattern itself (`bitPattern`), not just the decoded `value`, so a
/// comparison against it tells -0.0 from 0.0 apart - `Double`'s own `==`
/// does not.
struct WrappedDouble: Decodable {
    let bitPattern: UInt64
    let value: Double

    enum CodingKeys: String, CodingKey {
        case bits
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let bits = try container.decode(String.self, forKey: .bits)
        guard bits.count == 16, let raw = UInt64(bits, radix: 16) else {
            throw DecodingError.dataCorruptedError(
                forKey: .bits, in: container, debugDescription: "malformed bits string: \(bits)"
            )
        }
        bitPattern = raw
        value = Double(bitPattern: raw)
    }
}

struct SpringFixture: Decodable {
    let duration: WrappedDouble
    let dampingRatio: WrappedDouble
}

struct SheetGeometryFixture: Decodable {
    let cols: Int
    let rows: Int
    let frames: Int
    let fps: WrappedDouble
}

struct AnimalProfileFixture: Decodable {
    let id: String
    let label: String
    let runFps: WrappedDouble
    let commitSpring: SpringFixture
    let trackSpring: SpringFixture
    let catchSpring: SpringFixture
    let hopHeight: WrappedDouble
    let flightLift: WrappedDouble
    let scale: WrappedDouble
    let aroundRoute: Bool
    let headPad: WrappedDouble?
    let footPad: WrappedDouble?
    let seatLift: WrappedDouble?
    let runSpeed: WrappedDouble?
    let sitSheet: SheetGeometryFixture?

    enum CodingKeys: String, CodingKey {
        case id, label, runFps, commitSpring, trackSpring, catchSpring, hopHeight, flightLift,
            scale, aroundRoute, headPad, footPad, seatLift, runSpeed, sitSheet
    }

    /// custom, not synthesized: the generator always writes an optional
    /// field's key with an explicit `null` (encOrNull in gen-conformance.mjs
    /// never omits a key) - an ABSENT key is a fixture bug, and Swift's
    /// synthesized Decodable can't tell "absent" from "present and null" for
    /// an Optional. `contains(_:)` can.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        label = try container.decode(String.self, forKey: .label)
        runFps = try container.decode(WrappedDouble.self, forKey: .runFps)
        commitSpring = try container.decode(SpringFixture.self, forKey: .commitSpring)
        trackSpring = try container.decode(SpringFixture.self, forKey: .trackSpring)
        catchSpring = try container.decode(SpringFixture.self, forKey: .catchSpring)
        hopHeight = try container.decode(WrappedDouble.self, forKey: .hopHeight)
        flightLift = try container.decode(WrappedDouble.self, forKey: .flightLift)
        scale = try container.decode(WrappedDouble.self, forKey: .scale)
        aroundRoute = try container.decode(Bool.self, forKey: .aroundRoute)
        headPad = try Self.requiredOptional(WrappedDouble.self, container, .headPad)
        footPad = try Self.requiredOptional(WrappedDouble.self, container, .footPad)
        seatLift = try Self.requiredOptional(WrappedDouble.self, container, .seatLift)
        runSpeed = try Self.requiredOptional(WrappedDouble.self, container, .runSpeed)
        sitSheet = try Self.requiredOptional(SheetGeometryFixture.self, container, .sitSheet)
    }

    private static func requiredOptional<T: Decodable>(
        _ type: T.Type,
        _ container: KeyedDecodingContainer<CodingKeys>,
        _ key: CodingKeys
    ) throws -> T? {
        guard container.contains(key) else {
            throw DecodingError.keyNotFound(
                key,
                .init(
                    codingPath: container.codingPath,
                    debugDescription:
                        "optional field \"\(key.rawValue)\" is missing its key entirely - the generator always writes null, never omits"
                )
            )
        }
        return try container.decodeIfPresent(type, forKey: key)
    }
}

struct AnimalCaseArgs: Decodable {
    let id: String
}

struct AnimalCase: Decodable {
    let fn: String
    let args: AnimalCaseArgs
    let expect: AnimalProfileFixture
    let compare: String
}

/// SHA-256 hex digests of every bundled sheet and the shared license, as
/// gen-conformance.mjs computed them from packages/tabpet/assets/.
struct AnimalSheetHashesFixture: Decodable {
    let idle: String
    let run: String
    let sit: String
}

struct AnimalAssetHashesFixture: Decodable {
    let license: String
    let sheets: [String: AnimalSheetHashesFixture]
}

enum AnimalsFixtureError: Error {
    case repoRootNotFound(String)
}

struct AnimalsFixture: Decodable {
    let module: String
    let source: String
    let constants: [String: WrappedDouble]
    let cases: [AnimalCase]
    let assetHashes: AnimalAssetHashesFixture

    /// walks up from this source file's path to the directory containing
    /// Package.swift (the repository root) - fixtures are read by path,
    /// never as an SwiftPM resource, so Package.swift needs no change.
    static func repoRoot(from filePath: String = #filePath) throws -> URL {
        var dir = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        while true {
            let candidate = dir.appendingPathComponent("Package.swift")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return dir
            }
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path {
                throw AnimalsFixtureError.repoRootNotFound(filePath)
            }
            dir = parent
        }
    }

    static func load(from filePath: String = #filePath) throws -> AnimalsFixture {
        let url = try repoRoot(from: filePath)
            .appendingPathComponent("conformance")
            .appendingPathComponent("animals.json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(AnimalsFixture.self, from: data)
    }
}
