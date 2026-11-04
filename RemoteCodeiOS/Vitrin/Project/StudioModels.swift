// Ported from Vitrin for Mac (apps/VitrinMac/VitrinMac/Core/Models.swift).
import Foundation

/// The Studio server's JSON, mirrored by hand (packages/cli/src/studio/overview.ts, jobs.ts, claude.ts, server.ts).
/// Statuses are kept as strings with typed accessors so a newer server never breaks decoding.

/// A value a newer page reads and an older server may lack or shape differently: it decodes to nil rather than failing
/// the whole overview.
@propertyWrapper
struct Lenient<Value: Codable & Sendable>: Codable, Sendable {
    var wrappedValue: Value?
    init(wrappedValue: Value? = nil) { self.wrappedValue = wrappedValue }
    init(from decoder: Decoder) throws { wrappedValue = try? Value(from: decoder) }
    func encode(to encoder: Encoder) throws { try wrappedValue.encode(to: encoder) }
}

extension Lenient: Equatable where Value: Equatable {}
extension Lenient: Hashable where Value: Hashable {}

extension KeyedDecodingContainer {
    func decode<Value>(_ type: Lenient<Value>.Type, forKey key: Key) throws -> Lenient<Value> {
        try decodeIfPresent(type, forKey: key) ?? Lenient()
    }
}

struct RenderedFile: Codable, Hashable, Identifiable, Sendable {
    var path: String
    var name: String
    var bytes: Int
    var id: String { path }
}

struct AppInfo: Codable, Hashable, Sendable {
    var name: String
    var bundleId: String?
    var icon: String?
    var kind: String
    var platforms: [String]
    var version: String?
}

struct CaptureScreen: Codable, Hashable, Sendable {
    var id: String
    var source: [String]?
    var url: String?
}

/// `research.seeds`: one list for every language, or a list per language.
enum SeedList: Codable, Hashable, Sendable {
    case list([String])
    case perLocale([String: [String]])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let list = try? c.decode([String].self) { self = .list(list) }
        else { self = .perLocale(try c.decode([String: [String]].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .list(let l): try c.encode(l)
        case .perLocale(let m): try c.encode(m)
        }
    }
}

struct ProjectConfig: Codable, Hashable, Sendable {
    var locales: [String]
    var primaryLocale: String
    var language: String?
    var uploader: String?
    var capture: String
    var screens: [CaptureScreen]
    var selection: Selection
    var video: VideoConfig
    var urls: Urls
    @Lenient var seeds: SeedList?

    struct Selection: Codable, Hashable, Sendable {
        var platforms: [String]?
        var assets: [String]?
        var targets: [String]?
    }
    struct VideoConfig: Codable, Hashable, Sendable {
        var enabled: Bool
        var loops: Bool
    }
    struct Urls: Codable, Hashable, Sendable {
        var support: String?
        var privacy: String?
        var marketing: String?
    }

    /// The locale a page opens on: the primary one when it is a store locale, else the first store locale.
    var startLocale: String { locales.contains(primaryLocale) ? primaryLocale : (locales.first ?? primaryLocale) }
}

struct StageRecord: Codable, Hashable, Sendable {
    var completedAt: String
    var status: String
    var note: String?
}

struct Brief: Codable, Hashable, Identifiable, Sendable {
    var name: String
    var path: String
    var modifiedAt: String
    var stage: String?
    var id: String { name }
}

struct ValidationIssue: Codable, Hashable, Identifiable, Sendable {
    var severity: String
    var code: String
    var message: String
    var file: String?
    var locale: String?
    var field: String?
    var fix: String?
    var id: String { "\(code)|\(locale ?? "")|\(field ?? "")|\(message)" }
}

struct ValidationSummary: Codable, Hashable, Sendable {
    struct Counts: Codable, Hashable, Sendable {
        var error: Int
        var warning: Int
        var info: Int
    }
    var ok: Bool
    var counts: Counts
    var generatedAt: String?
    var issues: [ValidationIssue]
}

struct ApprovalSummary: Codable, Hashable, Sendable {
    struct Upload: Codable, Hashable, Sendable {
        var uploadedAt: String
        var overallHash: String
        var readBack: String
        var differences: [String]
    }
    struct Finalized: Codable, Hashable, Sendable {
        var at: String
        var mode: String
    }
    var status: String
    var approvedAt: String
    var via: String
    var overallHash: String
    var upload: Upload?
    var finalized: Finalized?
    var rejections: Int
    var valid: Bool
    var problem: String?
}

enum StageStatus: String, Sendable {
    case done, needsClaude = "needs-claude", needsUser = "needs-user", blocked, outdated, notRun = "not-run", skipped, unknown
}

struct StageView: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var status: String
    var optional: Bool?
    var completedAt: String?
    var note: String?
    var brief: String?
    var reason: String?
    var stageStatus: StageStatus { StageStatus(rawValue: status) ?? .unknown }
    var isOptional: Bool { optional ?? false }
}

struct BlockerFix: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var command: String
    var args: [String: VitrinJSON]
}

struct Blocker: Codable, Hashable, Identifiable, Sendable {
    var code: String
    var severity: String
    var stage: String
    var params: [String: VitrinJSON]
    var fixes: [BlockerFix]
    var id: String { code }
    func param(_ key: String) -> String { params[key]?.display ?? "" }
}

struct NextStep: Codable, Hashable, Sendable {
    var stage: String
    var action: String
    var blocker: String?
    var question: String?
}

struct StudioQuestion: Codable, Hashable, Identifiable, Sendable {
    struct Option: Codable, Hashable, Sendable {
        var label: String
        var value: String
    }
    var id: String
    var stage: String?
    var question: String
    var options: [Option]
    var askedAt: String?
}

struct DesignSamples: Codable, Hashable, Sendable {
    struct Option: Codable, Hashable, Identifiable, Sendable {
        var letter: String
        var style: String
        var name: String
        var id: String { style }
    }
    var styles: [String]
    var contactSheet: String?
    var storePreview: String?
    var generatedAt: String?
    var options: [Option]
}

struct Mockups: Codable, Hashable, Sendable {
    var index: String?
    var screens: [RenderedFile]
}

struct Tools: Codable, Hashable, Sendable {
    var asc: String?
    var ascLogin: Bool?
    var brew: String?
    var claude: String?
    var ffmpeg: String?
}

/// What the app can have and what is selected (`vitrin select`'s view), once the project was analyzed.
struct PlatformsReport: Codable, Hashable, Sendable {
    struct Platform: Codable, Hashable, Identifiable, Sendable {
        var platform: String
        var label: String?
        var detected: Bool?
        var selected: Bool
        var id: String { platform }
    }
    struct Asset: Codable, Hashable, Identifiable, Sendable {
        var asset: String
        var label: String?
        var selected: Bool
        var id: String { asset }
    }
    struct Format: Codable, Hashable, Identifiable, Sendable {
        var target: String
        var label: String?
        var platform: String
        var kind: String?
        var size: String?
        var required: Bool?
        var selected: Bool?
        var id: String { target }
    }
    struct LocaleChoice: Codable, Hashable, Sendable {
        var locale: String
    }
    struct Samples: Codable, Hashable, Sendable {
        var locale: String?
        var target: String?
    }
    var platforms: [Platform]
    var assets: [Asset]
    var formats: [Format]
    var locales: [LocaleChoice]
    var samples: Samples?
}

/// The schema enums the editors offer as choices.
struct StudioEnums: Codable, Hashable, Sendable {
    var presets: [String]?
    var emphasis: [String]?
    var archetypes: [String]?
    var framings: [String]?
    var scenes: [String]?
    var videoStyles: [String]?
    var transitions: [String]?
    var badgeTypes: [String]?
}

struct ClaudeState: Codable, Hashable, Sendable {
    var available: Bool
    var running: Bool
    var sessionId: String?
}

struct RemotionState: Codable, Hashable, Sendable {
    var running: Bool
    var url: String?
    var available: Bool?
}

struct JobSummary: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var command: String
    var args: [String: VitrinJSON]
    var status: String
    var startedAt: String
    var endedAt: String?
    var code: Int?
    var message: String?
    var details: [String]?
    var result: VitrinJSON?
    var isRunning: Bool { status == "running" }
    var isDryRun: Bool { command == "upload" && args["dryRun"]?.boolValue == true }
}

struct Job: Codable, Hashable, Sendable {
    var id: String
    var command: String
    var args: [String: VitrinJSON]
    var status: String
    var startedAt: String
    var endedAt: String?
    var code: Int?
    var message: String?
    var details: [String]?
    var result: VitrinJSON?
    var lines: [LogLine]
    var summary: JobSummary { JobSummary(id: id, command: command, args: args, status: status, startedAt: startedAt, endedAt: endedAt, code: code, message: message, details: details, result: result) }
}

struct LogLine: Codable, Hashable, Identifiable, Sendable {
    var jobId: String?
    var level: String
    var text: String
    var seq: Int = 0
    var id: Int { seq }
    private enum CodingKeys: String, CodingKey { case jobId, level, text }
}

struct ClaudeEvent: Codable, Hashable, Sendable {
    var type: String
    var runId: String?
    var sessionId: String?
    var model: String?
    var text: String?
    var name: String?
    var summary: String?
    var ok: Bool?
    var costUsd: Double?
    var durationMs: Double?
    var turns: Int?
    var code: Int?
}

struct ClaudeRun: Codable, Hashable, Identifiable, Sendable {
    struct Label: Codable, Hashable, Sendable {
        var kind: String
        var stage: String?
        var extra: String?
        var question: String?
        var answer: String?
        var text: String?
    }
    var id: String
    var prompt: String
    var label: Label?
    var startedAt: String
    var endedAt: String?
    var status: String
    var events: [ClaudeEvent]
}

struct ClaudeInfo: Codable, Sendable {
    var available: Bool
    var running: String?
    var sessionId: String?
    var runs: [ClaudeRun]
}

struct ReviewItem: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var kind: String
    var platform: String?
    var locale: String?
    var target: String?
    var label: String
    var files: [String]?
    var bytes: Int?
    var durationSec: Double?
    var fields: [Field]?

    struct Field: Codable, Hashable, Sendable {
        var key: String
        var file: String
        var value: String
    }

    /// The upload's picture or video, when this item is one.
    var media: RenderedFile? {
        guard let path = files?.first(where: { !$0.hasSuffix(".json") && !$0.hasSuffix(".txt") }) else { return nil }
        return RenderedFile(path: path, name: (path as NSString).lastPathComponent, bytes: bytes ?? 0)
    }
}

struct ReviewApproval: Codable, Hashable, Sendable {
    var ok: Bool
    var reason: String?
}

struct ReviewState: Codable, Sendable {
    var overallHash: String
    var approval: ReviewApproval
    var summary: [String]
    var items: [ReviewItem]
    var report: String
}

struct EditableFile: Codable, Sendable {
    var path: String
    var kind: String
    var readOnly: Bool
    var exists: Bool
    var text: String
}

struct Overview: Codable, Sendable {
    var version: String
    var root: String
    var initialized: Bool
    var configError: String?
    var app: AppInfo?
    var config: ProjectConfig?
    @Lenient var platforms: PlatformsReport?
    var stages: [String: StageRecord?]
    var files: [String: Bool]
    var listing: [String]
    var briefs: [Brief]
    var validation: ValidationSummary?
    var approval: ApprovalSummary?
    var flow: [StageView]
    var blockers: [Blocker]
    var questions: [StudioQuestion]
    var next: NextStep?
    var raw: [String: [String: [RenderedFile]]]
    var screenshots: [String: [RenderedFile]]
    var previews: [String: [RenderedFile]]
    var creatives: [String: [RenderedFile]]
    var videoStyles: [String: [RenderedFile]]
    /// Custom Product Page screenshots: page, then language.
    @Lenient var cpp: [String: [String: [RenderedFile]]]?
    var samples: DesignSamples?
    var mockups: Mockups?
    var tools: Tools
    var missingKeys: [String]
    @Lenient var enums: StudioEnums?
    var job: JobSummary?
    var claude: ClaudeState
    var remotion: RemotionState?

    func stage(_ id: String) -> StageView? { flow.first { $0.id == id } }
    func blocker(_ code: String) -> Blocker? { blockers.first { $0.code == code } }
    /// Everything that waits for the user: Claude's questions, then blockers (decisions first), then the approve and upload clicks.
    var pendingDecisions: [PendingDecision] {
        let order = ["decision": 0, "error": 1, "warning": 2]
        let blockers = self.blockers.sorted { (order[$0.severity] ?? 3) < (order[$1.severity] ?? 3) }.map { PendingDecision.blocker($0) }
        let stages = flow.filter { s in s.stageStatus == .needsUser && s.reason != "question" && !self.blockers.contains { b in b.code == s.reason } }.map { PendingDecision.stage($0) }
        return questions.map { PendingDecision.question($0) } + blockers + stages
    }
    var pendingCount: Int { pendingDecisions.count }
}

enum PendingDecision: Identifiable, Hashable {
    case question(StudioQuestion)
    case blocker(Blocker)
    case stage(StageView)
    var id: String {
        switch self {
        case .question(let q): return "question-\(q.id)"
        case .blocker(let b): return "blocker-\(b.code)"
        case .stage(let s): return "stage-\(s.id)"
        }
    }
}

/// The stages in the order the Studio walks through them, grouped as its flow page shows them.
enum Pipeline {
    static let order = ["analyze", "research", "write", "capture", "mockups", "design", "video", "validate", "review", "upload", "rank"]
    static let groups: [(key: String, stages: [String])] = [
        ("groupPrepare", ["analyze", "research"]),
        ("groupContent", ["write", "capture", "mockups", "design", "video"]),
        ("groupShip", ["validate", "review", "upload", "rank"]),
    ]
    /// The command each stage runs; the upload is a page, not a button.
    static func command(for stage: String) -> (command: String, args: [String: VitrinJSON])? {
        switch stage {
        case "upload": return nil
        case "mockups": return ("mockups", ["screens": true])
        default: return (stage, [:])
        }
    }
    /// The app page where a stage's input and output live.
    static func page(for stage: String) -> ProjectPage {
        switch stage {
        case "analyze": return .setup
        case "research", "rank": return .research
        case "write": return .listing
        case "capture", "mockups": return .screens
        case "design": return .design
        case "video": return .video
        case "validate", "review": return .review
        case "upload": return .upload
        default: return .flow
        }
    }
}

enum ProjectPage: String, CaseIterable, Identifiable, Codable, Sendable {
    case flow, setup, research, listing, screens, design, video, review, upload, asc
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .flow: return "list.bullet.rectangle"
        case .research: return "magnifyingglass"
        case .setup: return "slider.horizontal.3"
        case .listing: return "text.alignleft"
        case .screens: return "camera"
        case .design: return "paintbrush"
        case .video: return "film"
        case .review: return "checklist"
        case .upload: return "arrow.up.circle"
        case .asc: return "storefront"
        }
    }
    var titleKey: String {
        switch self {
        case .flow: return "page.flow"
        case .research: return "page.research"
        case .setup: return "page.setup"
        case .listing: return "page.listing"
        case .screens: return "page.screens"
        case .design: return "page.design"
        case .video: return "page.video"
        case .review: return "page.review"
        case .upload: return "page.upload"
        case .asc: return "page.asc"
        }
    }
}

extension Date {
    /// Parses the ISO timestamps the CLI writes (with or without fractional seconds).
    static func fromISO(_ s: String?) -> Date? {
        guard let s else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}
