import Foundation

// Read-only mirrors of the Automat app's state (GET /v1/state, see Automat's
// docs/CONTROL_API.md). Every field that Automat may omit is optional so the
// phone keeps working when Automat adds or drops fields.

struct AutomatState: Decodable {
    var revision: Int
    var projects: [AutomatProject]
    var posts: [AutomatPost]
    var accounts: [AutomatAccount]
    var jobs: [String: AutomatJob]
    var settings: AutomatSettings
    var languages: [AutomatOption]
    var themes: [AutomatOption]
    var alert: String?
}

struct AutomatOption: Decodable, Hashable, Identifiable {
    var id: String
    var label: String
}

struct AutomatJob: Decodable, Hashable {
    var message: String
    var progress: Double?
}

struct AutomatSettings: Decodable, Hashable {
    var loginMode: String
    var metaAppId: String
    var hasAppSecret: Bool
    var contentLanguage: String
    var voiceoverEnabled: Bool
    var defaultTheme: String
}

struct AutomatProject: Decodable, Hashable, Identifiable {
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

struct AutomatAccount: Decodable, Hashable, Identifiable {
    var userId: String
    var username: String
    var name: String?
    var profilePictureURL: String?
    var followers: Int?
    var tokenExpiresAt: Date?
    var id: String { userId }
}

struct AutomatPost: Decodable, Hashable, Identifiable {
    var id: String
    var projectId: String
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
        var skill: String?
        var summary: String?
    }

    struct Media: Decodable, Hashable {
        var video: String?
        var cover: String?
    }

    /// The post's text without Automat's *emphasis* markers.
    static func plain(_ text: String) -> String { text.replacingOccurrences(of: "*", with: "") }

    var hasScript: Bool {
        if let directed { return !directed.storyboard.scenes.isEmpty }
        return !spec.scenes.isEmpty
    }

    var isLocked: Bool { [.scheduled, .publishing, .published].contains(status) }
}
