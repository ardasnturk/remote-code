// Ported from Vitrin for Mac (apps/VitrinMac/VitrinMac/Core/AscCLI.swift).
import Foundation
import Observation

/// The `asc` CLI on the Mac as the panel's App Store Connect client: every read and write of the app pages goes through
/// the hub (`VitrinStore.asc`), so everything asc can do the phone can do. Which credential a run uses is the hub's
/// business: Vitrin's stored key, else asc's own login.
enum AscCLI {
    struct Failure: LocalizedError {
        var message: String
        var errorDescription: String? { message }
    }

    struct Result: Sendable {
        var code: Int32
        var stdout: String
        var stderr: String
        var ok: Bool { code == 0 }
        /// The JSON asc printed (the first `{` or `[` on stdout onwards), or nil.
        var json: VitrinJSON? {
            guard let i = stdout.firstIndex(where: { $0 == "{" || $0 == "[" }) else { return nil }
            return try? JSONDecoder().decode(VitrinJSON.self, from: Data(stdout[i...].utf8))
        }
        /// The first meaningful error line, for a one-line message.
        var errorLine: String {
            let lines = (stderr + "\n" + stdout).split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            return lines.first { $0.lowercased().hasPrefix("error") } ?? lines.first ?? "asc exited with code \(code)"
        }
    }

    /// The Mac these runs go to; `VitrinPanelModel.attach` sets it.
    @MainActor static weak var store: VitrinStore?

    /// Runs `asc <args>` on the Mac. `readOnly` makes asc refuse any POST, PATCH, PUT or DELETE. The Mac's `extraEnv`
    /// has no counterpart: the hub takes no environment, and Apple Account runs go through `AppleWebSession`.
    @MainActor static func run(_ args: [String], readOnly: Bool = true, timeout: TimeInterval = 180) async throws -> Result {
        guard let store else { throw Failure(message: L.t("vitrin.notConnected")) }
        if store.hub?.tools["asc"] == false { throw Failure(message: L.t("asc.missing")) }
        let r = try await store.asc(args, write: !readOnly, timeout: timeout)
        return Result(code: Int32(r.code), stdout: r.stdout, stderr: r.stderr)
    }

    /// `asc <args> --output json`, decoded; throws with asc's own message when it fails.
    @MainActor static func json(_ args: [String], readOnly: Bool = true, timeout: TimeInterval = 180) async throws -> VitrinJSON {
        let r = try await run(args + ["--output", "json"], readOnly: readOnly, timeout: timeout)
        guard r.ok else { throw Failure(message: r.errorLine) }
        guard let j = r.json else { throw Failure(message: r.stdout.isEmpty ? r.errorLine : String(r.stdout.prefix(300))) }
        return j
    }
}

// MARK: connection

/// Who App Store Connect requests run as: Vitrin's stored key, asc's own login, or nobody. The hub knows
/// (`GET /v1/status`); this keeps the Mac's states for the views.
@MainActor @Observable final class AscConnection {
    enum State: Equatable {
        case unknown
        case missingCLI
        case vitrinKey(keyId: String)
        case ascLogin(name: String, keyId: String)
        case none
    }
    private(set) var state: State = .unknown

    var isConnected: Bool {
        switch state {
        case .vitrinKey, .ascLogin: return true
        default: return false
        }
    }

    func apply(_ hub: VitrinHubStatus.Connection?) {
        switch hub?.state {
        case "vitrinKey": state = .vitrinKey(keyId: hub?.keyId ?? "")
        case "ascLogin": state = .ascLogin(name: hub?.name ?? "asc", keyId: hub?.keyId ?? "")
        case "missingCLI": state = .missingCLI
        case "none": state = .none
        default: state = .unknown
        }
    }
}

// MARK: help

/// One asc command's help page, parsed: its description, usage, subcommands (or the root's command groups) and flags.
/// The command palette builds its tree and forms from these, so it covers every command asc has.
struct AscHelp: Equatable, Sendable {
    struct Entry: Equatable, Hashable, Sendable, Identifiable {
        var name: String
        var summary: String
        var id: String { name }
    }
    struct Group: Equatable, Sendable, Identifiable {
        var title: String
        var entries: [Entry]
        var id: String { title }
    }
    struct Flag: Equatable, Hashable, Sendable, Identifiable {
        var name: String
        var summary: String
        /// `(default: false)` / `(default: true)`: a switch.
        var isBool: Bool
        var defaultValue: String?
        var required: Bool
        var id: String { name }
    }

    var description = ""
    var usage = ""
    var details = ""
    var groups: [Group] = []
    var flags: [Flag] = []

    var subcommands: [Entry] { groups.flatMap(\.entries) }

    /// Parses asc's help layout: `DESCRIPTION`, `USAGE`, free text, `… COMMANDS` / `SUBCOMMANDS` lists
    /// (`  name: summary` or `  name   summary`), `FLAGS` (`  --name   summary (default: x)`).
    static func parse(_ text: String) -> AscHelp {
        var h = AscHelp()
        var section = ""
        var detailLines: [String] = []
        for raw in text.components(separatedBy: "\n") {
            let line = raw.replacingOccurrences(of: "\t", with: "    ")
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !line.hasPrefix(" "), !trimmed.isEmpty, trimmed == trimmed.uppercased(), trimmed.rangeOfCharacter(from: .letters) != nil {
                section = trimmed
                if section.hasSuffix("COMMANDS") { h.groups.append(Group(title: section, entries: [])) }
                continue
            }
            guard !trimmed.isEmpty else { if section == "TEXT" || section == "USAGE" { detailLines.append("") }; continue }
            switch section {
            case "DESCRIPTION":
                h.description += (h.description.isEmpty ? "" : " ") + trimmed
            case "USAGE":
                if h.usage.isEmpty, line.hasPrefix("  ") { h.usage = trimmed } else { detailLines.append(trimmed) }
            case "FLAGS":
                guard trimmed.hasPrefix("--") else { continue }
                let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
                let name = String(parts[0].dropFirst(2))
                let summary = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""
                var def: String?
                if let r = summary.range(of: #"\(default: ([^)]*)\)\s*$"#, options: .regularExpression) {
                    def = String(summary[r]).replacingOccurrences(of: "(default: ", with: "").replacingOccurrences(of: ")", with: "").trimmingCharacters(in: .whitespaces)
                }
                h.flags.append(Flag(name: name, summary: summary, isBool: def == "false" || def == "true", defaultValue: def, required: summary.contains("(required)")))
            default:
                if section.hasSuffix("COMMANDS"), line.hasPrefix("  "), let entry = Self.entry(trimmed) {
                    h.groups[h.groups.count - 1].entries.append(entry)
                }
            }
        }
        h.details = detailLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        // "SUBCOMMANDS" reads as one untitled group.
        return h
    }

    /// `name: summary` (root) or `name   summary` (subcommands).
    private static func entry(_ s: String) -> Entry? {
        if let colon = s.firstIndex(of: ":"), !s[..<colon].contains(" ") {
            return Entry(name: String(s[..<colon]), summary: s[s.index(after: colon)...].trimmingCharacters(in: .whitespaces))
        }
        let parts = s.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard let first = parts.first, !first.hasPrefix("-") else { return nil }
        return Entry(name: String(first), summary: parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : "")
    }

    /// Reads `asc <path…> --help` (asc prints help on stdout or stderr depending on the command).
    @MainActor static func load(_ path: [String]) async throws -> AscHelp {
        let r = try await AscCLI.run(path + ["--help"])
        let text = r.stdout.contains("USAGE") ? r.stdout : r.stderr
        guard text.contains("USAGE") else { throw AscCLI.Failure(message: r.errorLine) }
        return parse(text)
    }
}
