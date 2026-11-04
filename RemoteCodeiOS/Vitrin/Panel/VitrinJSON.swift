// Ported from Vitrin for Mac (apps/VitrinMac/VitrinMac/Core/JSONValue.swift).
import Foundation

/// Any JSON value, for the parts of the Studio API that are open-ended: job arguments, blocker fixes, editable files.
enum VitrinJSON: Codable, Hashable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([VitrinJSON])
    case object([String: VitrinJSON])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([VitrinJSON].self) { self = .array(a) }
        else if let o = try? c.decode([String: VitrinJSON].self) { self = .object(o) }
        else { throw DecodingError.dataCorruptedError(in: c, debugDescription: "Not a JSON value") }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .number(let n): try c.encode(n)
        case .bool(let b): try c.encode(b)
        case .null: try c.encodeNil()
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    var stringValue: String? { if case .string(let s) = self { return s }; return nil }
    var boolValue: Bool? { if case .bool(let b) = self { return b }; return nil }
    var numberValue: Double? { if case .number(let n) = self { return n }; return nil }
    var arrayValue: [VitrinJSON]? { if case .array(let a) = self { return a }; return nil }
    var objectValue: [String: VitrinJSON]? { if case .object(let o) = self { return o }; return nil }

    /// Strings and arrays of strings joined, numbers without a trailing `.0`: how a value reads in a sentence.
    var display: String {
        switch self {
        case .string(let s): return s
        case .number(let n): return n == n.rounded() ? String(Int(n)) : String(n)
        case .bool(let b): return b ? "true" : "false"
        case .null: return ""
        case .array(let a): return a.map(\.display).joined(separator: ", ")
        case .object(let o): return o.keys.sorted().joined(separator: ", ")
        }
    }
}

extension VitrinJSON: ExpressibleByStringLiteral, ExpressibleByBooleanLiteral, ExpressibleByIntegerLiteral {
    init(stringLiteral value: String) { self = .string(value) }
    init(booleanLiteral value: Bool) { self = .bool(value) }
    init(integerLiteral value: Int) { self = .number(Double(value)) }
}
