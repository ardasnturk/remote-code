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
    /// The failure shown in the Mac's alert, explained (Promo Studio 1.4.0+)
    var problem: PromoStudioProblem?
    /// The Mac's setup checklist: tools, keys, sessions, disk (Promo Studio 1.4.0+)
    var health: [PromoStudioHealth]?
}

/// A failure explained by Promo Studio: what went wrong, what fixes it and the raw output.
struct PromoStudioProblem: Decodable, Hashable {
    var code: String
    var title: String
    var message: String
    var fix: Fix?
    var details: String?
    /// The post (or project) it belongs to
    var subject: String?

    enum Fix: String, Decodable, Hashable {
        /// Run the failed step again; have Claude fix the video code; produce without voiceover
        case retry, repair, withoutVoiceover
        /// Reconnect the Instagram account; open settings or the setup checklist on the Mac
        case reconnect, settings, setup
    }

    /// A Promo Studio version that doesn't know a fix yet decodes as no fix
    enum CodingKeys: String, CodingKey { case code, title, message, fix, details, subject }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code = try c.decodeIfPresent(String.self, forKey: .code) ?? "unknown"
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        message = try c.decodeIfPresent(String.self, forKey: .message) ?? ""
        fix = (try? c.decodeIfPresent(String.self, forKey: .fix)).flatMap { $0.flatMap(Fix.init(rawValue:)) }
        details = try c.decodeIfPresent(String.self, forKey: .details)
        subject = try c.decodeIfPresent(String.self, forKey: .subject)
    }

    init(title: String, message: String) {
        code = "unknown"
        self.title = title
        self.message = message
    }

    /// Instagram problems are fixed in the accounts screen
    var isInstagram: Bool { code.hasPrefix("instagram") }
}

/// One row of the Mac's setup checklist.
struct PromoStudioHealth: Decodable, Hashable, Identifiable {
    var id: String
    var title: String
    /// ready, missing, notSetUp or warning
    var status: String
    var detail: String
    var required: Bool?

    var needsAttention: Bool { status == "warning" || (status == "missing" && required == true) }
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
    /// Codex can edit people's photos on the Mac (Promo Studio 1.4.0+)
    var editPhotos: Bool?
    /// cloudflared is installed, so pictures can be posted (Promo Studio 1.5.0+)
    var canPostPictures: Bool?
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
    /// Why the last step failed and what fixes it (Promo Studio 1.4.0+)
    var problem: PromoStudioProblem?
    /// "image": a single picture instead of a video (Promo Studio 1.4.0+)
    var format: String?
    /// Images the user added for Claude to use
    var uploads: [String]?
    /// Second of the video the cover comes from (also the Reel's cover on Instagram); missing before Promo Studio 1.2.2
    var coverSec: Double?
    /// Where it goes on Instagram: nil or "feed" (a Reel, photo or carousel), or "story" (Promo Studio 1.5.0+)
    var placement: String?
    /// False for a 9:16 image, which can only be a story
    var canPostToFeed: Bool?

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
        /// Size of an image post: portrait, square or story
        var size: String?
        var muted: Bool?
        var summary: String?
        var notes: String?
    }

    struct Storyboard: Codable, Hashable {
        var concept: String
        var scenes: [Scene]
        /// Real people whose photos the video uses
        var people: [Person]?
    }

    struct Person: Codable, Hashable {
        var name: String
        /// How Codex edits the photo
        var edit: String?
        /// The user chose the downloaded photo over the edit
        var useOriginal: Bool?
        /// Why the last edit failed
        var editError: String?
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
        /// The picture of an image post
        var image: String?
        /// Every picture of an image post in order (a carousel has several; Promo Studio 1.5.0+)
        var slides: [String]?
        /// Photos of the storyboard's people: downloaded and Codex-edited
        var people: [PersonPhotos]?
    }

    struct PersonPhotos: Decodable, Hashable {
        var name: String
        var original: String?
        var edited: String?
    }

    var isImage: Bool { format == "image" }
    /// Pictures of an image post: a carousel's slides, else the one image
    var pictures: [String] { media.slides.flatMap { $0.isEmpty ? nil : $0 } ?? media.image.map { [$0] } ?? [] }
    var isCarousel: Bool { pictures.count > 1 }
    var isStory: Bool { placement == "story" || canPostToFeed == false }

    /// The post's text without Promo Studio's *emphasis* markers.
    static func plain(_ text: String) -> String { text.replacingOccurrences(of: "*", with: "") }

    var hasScript: Bool {
        if let directed { return !directed.storyboard.scenes.isEmpty }
        return !spec.scenes.isEmpty
    }

    var isLocked: Bool { [.scheduled, .publishing, .published].contains(status) }
}
