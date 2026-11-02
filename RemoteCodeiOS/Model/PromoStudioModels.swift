import Foundation

// Read-only mirrors of the Promo Studio app's state (GET /v1/state, see Promo Studio's
// docs/CONTROL_API.md). Every field that Promo Studio may omit is optional so the
// phone keeps working when Promo Studio adds or drops fields.

struct PromoStudioState: Decodable {
    var revision: Int
    var projects: [PromoStudioProject]
    var posts: [PromoStudioPost]
    var accounts: [PromoStudioAccount]
    var jobs: [String: PromoStudioJob]
    var settings: PromoStudioSettings
    var languages: [PromoStudioOption]
    var themes: [PromoStudioOption]
    var libraries: [PromoStudioLibrary]?
    var alert: String?
}

/// A template library on the Mac (e.g. Promo Templates): Claude Code skills that make ready-made videos.
struct PromoStudioLibrary: Decodable, Hashable, Identifiable {
    var id: String
    var name: String
    var compositions: Int?
    var skills: [Skill]
    var ideas: [Idea]?
    var ideaSources: [String]?

    struct Skill: Decodable, Hashable, Identifiable {
        var id: String { name }
        var name: String
        var description: String
        var argumentHint: String?
        var suggestedProjectId: String?
    }

    struct Idea: Decodable, Hashable, Identifiable {
        var id: String { title }
        var title: String
        var hook: String
        var flow: String
        var why: String
        var skill: String
        var difficulty: String
        var request: String
    }
}

struct PromoStudioOption: Decodable, Hashable, Identifiable {
    var id: String
    var label: String
}

struct PromoStudioJob: Decodable, Hashable {
    var message: String
    var progress: Double?
    /// When Promo Studio expects the job to finish (from the render progress or earlier jobs).
    var estimatedEnd: Date?

    /// "About 3 min left", "About 40 s left", "Almost done…"; nil without an estimate.
    func remainingText(now: Date = .now) -> String? {
        guard let estimatedEnd else { return nil }
        let seconds = estimatedEnd.timeIntervalSince(now)
        if seconds < 5 { return String(localized: "Almost done…") }
        if seconds < 60 {
            let rounded = max(5, Int((seconds / 5).rounded()) * 5)
            return String(localized: "About \(rounded) s left")
        }
        let minutes = Int((seconds / 60).rounded())
        return String(localized: "About \(minutes) min left")
    }
}

struct PromoStudioSettings: Decodable, Hashable {
    var loginMode: String
    var metaAppId: String
    var hasAppSecret: Bool
    var contentLanguage: String
    var voiceoverEnabled: Bool
    var defaultTheme: String
}

struct PromoStudioProject: Decodable, Hashable, Identifiable {
    var id: String
    var name: String
    var accountId: String?
    var logo: String?
    var analysis: Analysis?
    var assets: [Asset]?

    struct Analysis: Decodable, Hashable {
        var appName: String
        var tagline: String
        var summary: String
        var features: [Feature]
        var suggestions: [Suggestion]
    }

    struct Feature: Decodable, Hashable, Identifiable {
        var id: String
        var name: String
        var emoji: String
        var summary: String
    }

    struct Suggestion: Decodable, Hashable, Identifiable {
        var id: String
        var title: String
        var featureId: String?
        var angle: String
        var hook: String
        var theme: String
    }

    struct Asset: Decodable, Hashable {
        var fileName: String
        var label: String
    }
}

struct PromoStudioAccount: Decodable, Hashable, Identifiable {
    var userId: String
    var username: String
    var name: String?
    var profilePictureURL: String?
    var followers: Int?
    var tokenExpiresAt: Date?
    var id: String { userId }
}

struct PromoStudioPost: Decodable, Hashable, Identifiable {
    var id: String
    /// nil: a standalone video that belongs to no project
    var projectId: String?
    /// Instagram account chosen for this post (overrides the project's); once published, the account it went to
    var accountId: String?
    var title: String
    var language: String?
    var status: Status
    var caption: String
    var hashtags: [String]
    var altText: String?
    var postingTip: String?
    var scheduledAt: Date?
    var publishedAt: Date?
    var permalink: String?
    var lastError: String?
    var metrics: Metrics?
    var createdAt: Date
    var brief: Brief?
    var revisions: [Revision]?
    var directed: Directed?
    var spec: Spec
    var external: External?
    var media: Media
    /// Second of the video the cover comes from (also the Reel's cover on Instagram); missing before Promo Studio 1.2.2
    var coverSec: Double?

    enum Status: String, Decodable, Hashable {
        case draft, rendering, ready, scheduled, publishing, published, failed
    }

    struct Metrics: Decodable, Hashable {
        var views: Int?
        var reach: Int?
        var likes: Int?
        var comments: Int?
        var shares: Int?
        var saved: Int?
    }

    struct Brief: Decodable, Hashable {
        var prompt: String
        var research: Bool?
        var findings: String?
        var sources: [String]?
    }

    struct Revision: Decodable, Hashable, Identifiable {
        var id: String
        var createdAt: Date
        var instruction: String
        var title: String
        var code: String?
    }

    struct Directed: Decodable, Hashable {
        var storyboard: Storyboard
        var produced: Bool
        var muted: Bool?
        var summary: String?
        var notes: String?
    }

    struct Storyboard: Codable, Hashable {
        var concept: String
        var scenes: [Scene]
    }

    struct Scene: Codable, Hashable {
        var visual: String
        var text: String
        var voiceover: String?
        var assets: [String]?
        var sfx: String?
        var durationSec: Double
    }

    struct Spec: Decodable, Hashable {
        var scenes: [SpecScene]
        var theme: String?
    }

    struct SpecScene: Decodable, Hashable {
        var kind: String
        var title: String
        var subtitle: String?
        var voiceover: String?
        var durationSec: Double?
    }

    struct External: Decodable, Hashable {
        var libraryId: String?
        var skill: String?
        var summary: String?
    }

    struct Media: Decodable, Hashable {
        var video: String?
        var cover: String?
    }

    /// The post's text without Promo Studio's *emphasis* markers.
    static func plain(_ text: String) -> String { text.replacingOccurrences(of: "*", with: "") }

    var hasScript: Bool {
        if let directed { return !directed.storyboard.scenes.isEmpty }
        return !spec.scenes.isEmpty
    }

    var isLocked: Bool { [.scheduled, .publishing, .published].contains(status) }
}
