// Ported from Vitrin for Mac (apps/VitrinMac/VitrinMac/Views/AscAnalyticsSections.swift).
import SwiftUI

/// `asc insights weekly`: this week against last week, each metric with why it is missing when it is.
struct WeeklyInsights: View {
    var appID: String
    /// Monday of last week.
    private var week: String {
        var c = Calendar(identifier: .iso8601)
        c.timeZone = TimeZone(identifier: "UTC")!
        let monday = c.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        let last = c.date(byAdding: .day, value: -7, to: monday) ?? monday
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = c.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: last)
    }
    var body: some View {
        AscLoad(args: ["insights", "weekly", "--app", appID, "--source", "analytics", "--week", week], errorText: L.t("asc.analytics.noWeekly")) { doc, _ in
            // A metric the key may not read is explained once, by AnalyticsAccess above.
            let shown = (doc.objectValue?["metrics"]?.arrayValue ?? []).compactMap(\.objectValue).filter { $0["status"]?.stringValue != "unavailable" }
            if !shown.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    SectionTitle(L.t("asc.analytics.weekly"), info: "info.asc.analytics.weekly")
                    AscRowList(rows: shown.enumerated().compactMap { AscDataView.row(.object($0.element), index: $0.offset) })
                }
            }
        }
    }
}

/// `asc performance overview`: Xcode's performance categories and trends, or a sentence when Apple has none yet.
struct PerformanceOverview: View {
    var appID: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle(L.t("asc.analytics.performance"), info: "info.asc.analytics.performance")
            AscLoad(args: ["performance", "overview", "--app", appID], errorText: L.t("asc.analytics.noPerformance")) { doc, _ in
                let o = doc.objectValue ?? [:]
                let insights = o["insights"]?.objectValue ?? [:]
                let categories = o["categories"]?.arrayValue ?? []
                let trends = (insights["regressions"]?.arrayValue ?? []) + (insights["trendingUp"]?.arrayValue ?? [])
                if categories.isEmpty && trends.isEmpty {
                    AscDataView(doc: .array([]), empty: L.t("asc.analytics.noPerformance"))
                } else {
                    if !trends.isEmpty { AscDataView(doc: .array(trends)) }
                    if !categories.isEmpty { AscDataView(doc: .array(categories)) }
                }
            }
        }
    }
}

/// The analytics reports: Apple makes them only after someone asks, so this says whether they were asked for, and asks.
/// Reading them needs an Admin, Finance or Sales and Reports key; asking for them needs Admin.
struct AnalyticsAccess: View {
    var appID: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle(L.t("asc.analytics.requests"), info: "info.asc.analytics.requests")
            AscLoad(args: ["analytics", "requests", "--app", appID]) { doc, reload in
                let requests = JSONAPI.items(doc)
                if requests.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L.t("asc.analytics.noRequests")).font(.callout).fixedSize(horizontal: false, vertical: true)
                        AscActionButton(action: AscActions.requestAnalytics(app: appID), done: reload, prominent: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .vitrinCard(padding: 14)
                } else {
                    AscDataView(doc: doc)
                    Text(L.t("asc.analytics.waiting")).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// The dashboards App Store Connect shows on the web, over the Apple Account session: they need no analytics role on
/// the API key, so this works where the reports below are refused. The last 30 days.
struct WebAnalytics: View {
    var appID: String
    @State private var session = AppleWebSession.shared
    @State private var signingIn = false

    private var range: (start: String, end: String) {
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -30, to: end) ?? end
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return (f.string(from: start), f.string(from: end))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle(L.t("web.analytics.title"), info: "info.web.analytics")
            if session.authenticated {
                AscLoad(args: ["web", "analytics", "overview", "--app", appID, "--start", range.start, "--end", range.end], readOnly: false) { doc, _ in AscDataView(doc: doc) }
            } else if signingIn {
                AppleAccountForm { signingIn = false }.vitrinCard(padding: 14)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L.t("web.analytics.detail")).font(.callout).fixedSize(horizontal: false, vertical: true)
                    Button(L.t("web.signInWith")) { signingIn = true }.accessibilityIdentifier("web.analytics.signIn")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .vitrinCard(padding: 14)
            }
        }
        .task { await session.refresh() }
    }
}
