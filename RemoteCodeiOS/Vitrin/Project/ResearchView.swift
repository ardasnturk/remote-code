// Ported from Vitrin for Mac (apps/VitrinMac/VitrinMac/Views/ResearchView.swift); the tables became rows for a phone.
import SwiftUI

/// Competitors and keywords from metadata/research/, read through the Studio's file API.
struct ResearchView: View {
    var session: ProjectSession
    var overview: Overview
    @State private var competitors: Competitors?
    @State private var keywords: KeywordPlan?
    @State private var locale = ""

    struct Competitors: Decodable {
        struct App: Decodable, Identifiable {
            var trackId: Int
            var name: String
            var sellerName: String?
            var bundleId: String?
            var storefront: String?
            var averageUserRating: Double?
            var userRatingCount: Int?
            var formattedPrice: String?
            var primaryGenre: String?
            var id: Int { trackId }
        }
        struct Analysis: Decodable {
            struct Term: Decodable { var term: String; var count: Int }
            var nameTerms: [Term]?
            var gaps: [String]?
        }
        var generatedAt: String?
        var storefronts: [String]
        var seeds: [String]
        var apps: [App]
        var analysis: Analysis?
    }

    struct KeywordCandidate: Decodable, Identifiable {
        struct Score: Decodable { var score: Double }
        var term: String
        var relevance: Double?
        var competition: Score
        var popularity: Score
        var total: Double?
        var ownRank: Int?
        var id: String { term }
    }

    struct KeywordPlan: Decodable {
        struct Selected: Decodable { var name: [String]?; var subtitle: [String]?; var keywords: [String]? }
        var locale: String
        var storefront: String
        var generatedAt: String?
        var candidates: [KeywordCandidate]
        var selected: Selected?
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(L.t("research.intro")).font(.callout).foregroundStyle(.secondary)
                FlowLayout(spacing: 8) {
                    Button(L.stage("research")) { Task { await session.run("research") } }
                        .buttonStyle(.borderedProminent).disabled(session.isBusy).accessibilityIdentifier("research.run")
                    Button(L.stage("rank")) { Task { await session.run("rank") } }
                        .buttonStyle(.bordered).disabled(session.isBusy)
                }
                keywordCard
                competitorCard
            }
            .padding(14)
        }
        .refreshable { await load() }
        .task(id: "\(session.changedTick)-\(locale)") { await load() }
        .onAppear { if locale.isEmpty { locale = overview.config?.startLocale ?? "en-US" } }
    }

    private var keywordCard: some View {
        Card {
            HStack {
                Text(L.t("research.keywords")).font(.headline)
                Spacer()
                Picker(selection: $locale) { ForEach(overview.config?.locales ?? [], id: \.self) { Text(verbatim: $0).tag($0) } } label: { EmptyView() }
                    .labelsHidden()
            }
            if let k = keywords {
                Text(verbatim: "\(k.storefront) · \(L.date(k.generatedAt))").font(.caption).foregroundStyle(.secondary)
                if let s = k.selected {
                    FlowLayout(spacing: 4) {
                        ForEach(s.name ?? [], id: \.self) { Pill($0, .accent) }
                        ForEach(s.subtitle ?? [], id: \.self) { Pill($0, .info) }
                        ForEach(s.keywords ?? [], id: \.self) { Pill($0) }
                    }
                }
                ForEach(k.candidates.sorted { ($0.total ?? -1) > ($1.total ?? -1) }) { KeywordRow(candidate: $0) }
            } else {
                Text(L.t("research.noKeywords")).foregroundStyle(.secondary)
            }
        }
    }

    private var competitorCard: some View {
        Card {
            Text(L.t("research.competitors")).font(.headline)
            if let c = competitors {
                Text(verbatim: "\(c.apps.count) · \(c.storefronts.joined(separator: ", ")) · \(L.date(c.generatedAt))").font(.caption).foregroundStyle(.secondary)
                if let terms = c.analysis?.nameTerms, !terms.isEmpty {
                    FlowLayout(spacing: 4) { ForEach(terms.prefix(24), id: \.term) { Pill("\($0.term) ×\($0.count)") } }
                }
                if let gaps = c.analysis?.gaps, !gaps.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L.t("research.gaps")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(gaps, id: \.self) { Text(verbatim: "• \($0)").font(.callout) }
                    }
                }
                ForEach(c.apps) { CompetitorRow(app: $0) }
            } else {
                Text(L.t("research.noCompetitors")).foregroundStyle(.secondary)
            }
        }
    }

    private func load() async {
        if overview.files["competitors"] == true, let f = try? await session.readFile("metadata/research/competitors.json") {
            competitors = try? JSONDecoder().decode(Competitors.self, from: Data(f.text.utf8))
        } else {
            competitors = nil
        }
        if !locale.isEmpty, let f = try? await session.readFile("metadata/research/keywords/\(locale).json"), f.exists {
            keywords = try? JSONDecoder().decode(KeywordPlan.self, from: Data(f.text.utf8))
        } else {
            keywords = nil
        }
    }
}

private struct KeywordRow: View {
    var candidate: ResearchView.KeywordCandidate

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(verbatim: candidate.term).font(.callout.weight(.medium))
                Spacer()
                if let rank = candidate.ownRank { Pill("#\(rank)", .info) }
                Text(verbatim: candidate.total.map { String(format: "%.2f", $0) } ?? "—").font(.callout.monospacedDigit())
            }
            score("research.relevance", candidate.relevance)
            score("research.popularity", candidate.popularity.score)
            score("research.competition", candidate.competition.score, invert: true)
        }
        .padding(.vertical, 4)
    }

    private func score(_ key: String, _ value: Double?, invert: Bool = false) -> some View {
        HStack(spacing: 8) {
            Text(L.t(key)).font(.caption2).foregroundStyle(.secondary).frame(width: 84, alignment: .leading).lineLimit(1)
            ScoreBar(value: value, invert: invert)
        }
    }
}

private struct CompetitorRow: View {
    var app: ResearchView.Competitors.App

    var body: some View {
        Link(destination: URL(string: "https://apps.apple.com/\(app.storefront ?? "us")/app/id\(app.trackId)")!) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: app.name).font(.callout.weight(.medium)).foregroundStyle(.primary).lineLimit(1)
                    Text(verbatim: app.sellerName ?? app.bundleId ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Text(verbatim: details).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Image(systemName: "arrow.up.right.square").foregroundStyle(.secondary)
            }
            .padding(.vertical, 3)
        }
    }

    private var details: String {
        [
            app.averageUserRating.map { String(format: "★ %.2f", $0) },
            app.userRatingCount.map { $0.formatted() },
            app.formattedPrice,
            app.primaryGenre,
            app.storefront,
        ].compactMap { $0 }.joined(separator: " · ")
    }
}

struct ScoreBar: View {
    var value: Double?
    var invert = false
    var body: some View {
        HStack(spacing: 6) {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.quaternaryLabel).opacity(0.4))
                    if let v = value { Capsule().fill(color(v)).frame(width: max(2, g.size.width * v)) }
                }
            }
            .frame(height: 6)
            Text(verbatim: value.map { String(format: "%.2f", $0) } ?? "—").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 34, alignment: .trailing)
        }
    }

    private func color(_ v: Double) -> Color {
        let good = invert ? 1 - v : v
        return good > 0.66 ? .green : good > 0.33 ? .orange : .red
    }
}
