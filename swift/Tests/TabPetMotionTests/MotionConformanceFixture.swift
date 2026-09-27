import Foundation

/// Reads conformance/motion.json - deliberately simpler than TabPetCoreTests'
/// ConformanceFixture.swift (a typed JSONValue tree), since motion.json's
/// shape is far more regular per `fn`: this loader just hands back
/// JSONSerialization's `[String: Any]` per case and a handful of free
/// functions decode the wrapped-float leaves ({bits, value}, bits
/// authoritative - same wire convention as every other conformance file).
enum MotionFixtureError: Error, CustomStringConvertible {
    case malformed(String)
    case repoRootNotFound(String)

    var description: String {
        switch self {
        case .malformed(let where_):
            return "conformance/motion.json is malformed at \(where_)"
        case .repoRootNotFound(let filePath):
            return "Package.swift not found walking up from \(filePath)"
        }
    }
}

struct MotionFixtureCase {
    let fn: String
    let label: String
    let args: [String: Any]
    let expect: [String: Any]
}

struct MotionFixture {
    let module: String
    let reanimatedVersion: String
    let cases: [MotionFixtureCase]

    func cases(fn: String) -> [MotionFixtureCase] {
        cases.filter { $0.fn == fn }
    }

    func caseNamed(_ label: String) -> MotionFixtureCase? {
        cases.first { $0.label == label }
    }
}

enum MotionFixtureLoader {
    static func repoRoot(from filePath: String = #filePath) throws -> URL {
        var dir = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        while true {
            let candidate = dir.appendingPathComponent("Package.swift")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return dir
            }
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path {
                throw MotionFixtureError.repoRootNotFound(filePath)
            }
            dir = parent
        }
    }

    static func load(from filePath: String = #filePath) throws -> MotionFixture {
        let root = try repoRoot(from: filePath)
        let url = root.appendingPathComponent("conformance").appendingPathComponent("motion.json")
        let data = try Data(contentsOf: url)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MotionFixtureError.malformed("root is not an object")
        }
        guard let module = json["module"] as? String, let version = json["reanimatedVersion"] as? String,
              let rawCases = json["cases"] as? [[String: Any]]
        else {
            throw MotionFixtureError.malformed("missing module/reanimatedVersion/cases")
        }
        let cases = try rawCases.map { raw -> MotionFixtureCase in
            guard let fn = raw["fn"] as? String, let label = raw["label"] as? String,
                  let args = raw["args"] as? [String: Any], let expect = raw["expect"] as? [String: Any]
            else {
                throw MotionFixtureError.malformed("case missing fn/label/args/expect")
            }
            return MotionFixtureCase(fn: fn, label: label, args: args, expect: expect)
        }
        return MotionFixture(module: module, reanimatedVersion: version, cases: cases)
    }
}

/// Decodes one wrapped-float leaf `{"bits": "<16 hex>", "value": ...}` - bits
/// is authoritative, reconstructed as the IEEE 754 bit pattern, never from
/// `value` (which JSON cannot carry -0/NaN/Infinity precisely anyway). Also
/// accepts a bare JSON number defensively, though every fixture leaf here is
/// wrapped. Returns nil for JSON null or a missing key - the caller decides
/// whether that's legitimate (an optional spring config field) or a bug.
func wireDouble(_ any: Any?) -> Double? {
    if let dict = any as? [String: Any] {
        guard let hex = dict["bits"] as? String, hex.count == 16, hex.allSatisfy(\.isHexDigit),
              let bits = UInt64(hex, radix: 16)
        else {
            return nil
        }
        return Double(bitPattern: bits)
    }
    if let number = any as? NSNumber {
        return number.doubleValue
    }
    return nil
}

func wireDoubleArray(_ any: Any?) -> [Double] {
    guard let arr = any as? [Any] else {
        return []
    }
    return arr.map { wireDouble($0) ?? .nan }
}
