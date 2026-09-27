import Foundation

import TabPetCore

/// "exact" is bit-identical (any NaN equals any NaN); "tolerance" is for a
/// result that passed through Math.sin/cos/atan2/hypot on the TypeScript
/// side, where another math library can round the last bit differently.
/// Decoding an unrecognized raw value throws (Decodable's synthesized init
/// for a String-backed enum does this already) - rejects any compare
/// string other than these two.
enum CompareRule: String, Decodable {
    case exact
    case tolerance
}

/// strict decoding - a malformed fixture is a test failure, never a
/// silent zero, a dropped element, or a crashed process.
enum ConformanceDecodeError: Error, CustomStringConvertible {
    case malformedBits(String)
    case wrongTypeArrayElement(JSONValue)
    case notAnArray(JSONValue)
    case repoRootNotFound(String)
    case missingField(String)

    var description: String {
        switch self {
        case .malformedBits(let hex):
            return "malformed bits string (want 16 lowercase hex digits): \(hex)"
        case .wrongTypeArrayElement(let value):
            return "array element is not numeric: \(value)"
        case .notAnArray(let value):
            return "expected a JSON array, got: \(value)"
        case .repoRootNotFound(let filePath):
            return "Package.swift not found walking up from \(filePath)"
        case .missingField(let label):
            return "missing or mistyped field: \(label)"
        }
    }
}

/// unwraps an optional decoded field, throwing .missingField instead of
/// crashing on a malformed fixture.
private func need<T>(_ value: T?, _ label: String) throws -> T {
    guard let value else {
        throw ConformanceDecodeError.missingField(label)
    }
    return value
}

/// probe-only coding key for detecting whether a decoder's underlying JSON
/// value is object-shaped, without decoding any of its values yet.
private struct AnyCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?
    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }
    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}

/// A generic JSON tree for a fixture case's `args`/`expect`, since their
/// shape varies per function. A wrapped float `{"bits": "...", "value": ...}`
/// is decoded eagerly into `.double`, reconstructed from `bits` (authoritative),
/// never from `value` (which JSON cannot carry -0/NaN/Infinity precisely anyway).
indirect enum JSONValue: Decodable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
            return
        }
        if let b = try? container.decode(Bool.self) {
            self = .bool(b)
            return
        }
        if let i = try? container.decode(Int.self) {
            self = .int(i)
            return
        }
        if let d = try? container.decode(Double.self) {
            self = .double(d)
            return
        }
        if let s = try? container.decode(String.self) {
            self = .string(s)
            return
        }
        // Everything scalar is ruled out above - the value is now known to be
        // either array- or object-shaped. Obtaining a container only inspects
        // the decoder's underlying JSON value; it does not decode any element
        // yet, so probing it with `try?` is safe. Once that shape is known,
        // decode its contents WITHOUT try? - a malformed "bits" nested inside
        // (or any other decode error) must propagate as itself, not get
        // swallowed into the generic "unrecognized value" error below.
        if (try? decoder.unkeyedContainer()) != nil {
            let arr = try container.decode([JSONValue].self)
            self = .array(arr)
            return
        }
        if (try? decoder.container(keyedBy: AnyCodingKey.self)) != nil {
            let dict = try container.decode([String: JSONValue].self)
            if dict.count == 2, case .string(let bits)? = dict["bits"], dict["value"] != nil {
                self = .double(try JSONValue.doubleFromBits(bits))
                return
            }
            self = .object(dict)
            return
        }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "unrecognized conformance JSON value")
    }

    private static let hexDigits = Set("0123456789abcdef")

    /// exactly 16 lowercase hex digits, reconstructed as the authoritative
    /// IEEE 754 bit pattern - a malformed bits string is a decode error,
    /// never a silent zero (`UInt64(hex, radix: 16) ?? 0` would do that).
    private static func doubleFromBits(_ hex: String) throws -> Double {
        guard hex.count == 16, hex.allSatisfy(hexDigits.contains), let bits = UInt64(hex, radix: 16) else {
            throw ConformanceDecodeError.malformedBits(hex)
        }
        return Double(bitPattern: bits)
    }

    var doubleValue: Double? {
        switch self {
        case .double(let d): return d
        case .int(let i): return Double(i)
        default: return nil
        }
    }

    var intValue: Int? {
        if case .int(let i) = self { return i }
        return nil
    }

    var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }

    var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    var isNull: Bool {
        if case .null = self { return true }
        return false
    }

    var arrayValue: [JSONValue]? {
        if case .array(let arr) = self { return arr }
        return nil
    }

    /// nil for both a genuinely-missing key and a JSON `null` - `slotCenters`
    /// on the TypeScript side is `readonly number[] | undefined`, and JSON
    /// null stands for both null and undefined per the fixture format -
    /// throws when the value is present, not null, and not an array (a
    /// genuinely malformed fixture), and throws on a non-numeric element
    /// instead of dropping it (`compactMap` would silently shrink the array).
    func doubleArray() throws -> [Double]? {
        if isNull {
            return nil
        }
        guard let arr = arrayValue else {
            throw ConformanceDecodeError.notAnArray(self)
        }
        return try arr.map { element in
            guard let d = element.doubleValue else {
                throw ConformanceDecodeError.wrongTypeArrayElement(element)
            }
            return d
        }
    }

    subscript(key: String) -> JSONValue? {
        if case .object(let dict) = self { return dict[key] }
        return nil
    }

    private func doubleField(_ key: String, _ label: String) throws -> Double {
        try need(self[key]?.doubleValue, label)
    }

    /// decodes {x,y,width,height} (each a wrapped float), or nil when this
    /// value is JSON null - shouldRouteAround's pill argument is optional.
    func pillFrame() throws -> PillFrame? {
        if isNull { return nil }
        return PillFrame(
            x: try doubleField("x", "pill.x"),
            y: try doubleField("y", "pill.y"),
            width: try doubleField("width", "pill.width"),
            height: try doubleField("height", "pill.height")
        )
    }

    /// decodes a raw (unwrapped) -1/1 JSON int into a Facing
    func facing(_ label: String) throws -> Facing {
        let raw = try need(intValue, label)
        guard let facing = Facing(rawValue: raw) else {
            throw ConformanceDecodeError.missingField("\(label) (unknown raw facing \(raw))")
        }
        return facing
    }

    private func requiredDoubleArray(_ key: String, _ label: String) throws -> [Double] {
        try need(try need(self[key], label).doubleArray(), label)
    }

    /// decodes a nested AroundPath: exitSide/enterSide/facing/spin as raw
    /// ints, arcCum/legs as wrapped-float arrays, everything else a wrapped float.
    func aroundPath() throws -> AroundPath {
        AroundPath(
            exitSide: try need(self["exitSide"], "path.exitSide").facing("path.exitSide"),
            enterSide: try need(self["enterSide"], "path.enterSide").facing("path.enterSide"),
            facing: try need(self["facing"], "path.facing").facing("path.facing"),
            spin: try need(self["spin"], "path.spin").facing("path.spin"),
            pivot: try doubleField("pivot", "path.pivot"),
            seatFeetY: try doubleField("seatFeetY", "path.seatFeetY"),
            underY: try doubleField("underY", "path.underY"),
            cxExit: try doubleField("cxExit", "path.cxExit"),
            cxEnter: try doubleField("cxEnter", "path.cxEnter"),
            cy: try doubleField("cy", "path.cy"),
            a: try doubleField("a", "path.a"),
            b: try doubleField("b", "path.b"),
            feetX0: try doubleField("feetX0", "path.feetX0"),
            targetFeetX: try doubleField("targetFeetX", "path.targetFeetX"),
            arcCum: try requiredDoubleArray("arcCum", "path.arcCum"),
            arcLen: try doubleField("arcLen", "path.arcLen"),
            legs: try requiredDoubleArray("legs", "path.legs"),
            totalLen: try doubleField("totalLen", "path.totalLen"),
            totalMs: try doubleField("totalMs", "path.totalMs")
        )
    }

    /// decodes a nested pose {x, seatY, rotation}, each a wrapped float -
    /// aroundPose's and resumedPose's shared (unnamed on the TypeScript side) return shape.
    func aroundPose() throws -> AroundPose {
        AroundPose(
            x: try doubleField("x", "pose.x"),
            seatY: try doubleField("seatY", "pose.seatY"),
            rotation: try doubleField("rotation", "pose.rotation")
        )
    }

    /// decodes a nested ResumedRoute: `base` is a nested AroundPath, `dir`/
    /// `facing` are raw ints, everything else is a wrapped float.
    func resumedRoute() throws -> ResumedRoute {
        ResumedRoute(
            base: try need(self["base"], "route.base").aroundPath(),
            startS: try doubleField("startS", "route.startS"),
            endS: try doubleField("endS", "route.endS"),
            dir: try need(self["dir"], "route.dir").facing("route.dir"),
            curveLen: try doubleField("curveLen", "route.curveLen"),
            tailFromFeetX: try doubleField("tailFromFeetX", "route.tailFromFeetX"),
            tailToFeetX: try doubleField("tailToFeetX", "route.tailToFeetX"),
            tailLen: try doubleField("tailLen", "route.tailLen"),
            totalLen: try doubleField("totalLen", "route.totalLen"),
            totalMs: try doubleField("totalMs", "route.totalMs"),
            facing: try need(self["facing"], "route.facing").facing("route.facing"),
            endRotation: try doubleField("endRotation", "route.endRotation")
        )
    }
}

struct ConformanceCase: Decodable {
    let fn: String
    let args: JSONValue
    let expect: JSONValue
    let compare: CompareRule
}

struct ConformanceFixture: Decodable {
    let module: String
    let source: String
    let cases: [ConformanceCase]
}

enum ConformanceCompare {
    /// NaN matches only NaN, under either rule. "exact" is otherwise
    /// bit-identical (tells Infinity from -Infinity, +0 from -0). Under
    /// "tolerance", an infinite value now matches only the same infinity -
    /// the old rule's `|a - b| <= 1e-9 * max(1, |a|, |b|)` made Infinity !=
    /// Infinity (both sides of `<=` were NaN) and Infinity == 5
    /// (Infinity <= Infinity happens to be true).
    static func numbersEqual(_ a: Double, _ b: Double, rule: CompareRule) -> Bool {
        if a.isNaN || b.isNaN {
            return a.isNaN && b.isNaN
        }
        switch rule {
        case .exact:
            return a.bitPattern == b.bitPattern
        case .tolerance:
            if !a.isFinite || !b.isFinite {
                return a == b
            }
            let scale = Swift.max(1, abs(a), abs(b))
            return abs(a - b) <= 1e-9 * scale
        }
    }
}

enum ConformanceFixtureLoader {
    /// walks up from a source file's path to the directory containing
    /// Package.swift, i.e. the repository root - fixtures are read by path,
    /// never as an SwiftPM resource, so Package.swift needs no change.
    /// throws (surfaces as a test failure) instead of `precondition`
    /// trapping the whole process when Package.swift can't be found.
    static func repoRoot(from filePath: String = #filePath) throws -> URL {
        var dir = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        while true {
            let candidate = dir.appendingPathComponent("Package.swift")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return dir
            }
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path {
                throw ConformanceDecodeError.repoRootNotFound(filePath)
            }
            dir = parent
        }
    }

    static func load(_ name: String, from filePath: String = #filePath) throws -> ConformanceFixture {
        let root = try repoRoot(from: filePath)
        let url = root.appendingPathComponent("conformance").appendingPathComponent("\(name).json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ConformanceFixture.self, from: data)
    }
}
