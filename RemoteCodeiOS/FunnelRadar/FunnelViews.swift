import Charts
import SwiftUI

private let gridColumns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
private let utc = TimeZone(identifier: "UTC")!

private func monthName(_ date: Date) -> String {
    date.formatted(Date.FormatStyle(timeZone: utc).month(.wide))
}

private func dayName(_ text: String) -> String {
    let parts = text.prefix(10).split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3 else { return text }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = utc
    guard let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else { return text }
    return date.formatted(Date.FormatStyle(timeZone: utc).month(.abbreviated).day())
}

enum FunnelAlertText {
    static func title(_ alert: FunnelAlertItem) -> String {
        let name = alert.projectName
        return switch alert.kind {
        case "conversionDrop": String(localized: "Conversion fell · \(name)")
        case "eventSpike": String(localized: "Unusually busy day · \(name)")
        case "eventDip": String(localized: "Unusually quiet day · \(name)")
        default: String(localized: "Retention fell · \(name)")
        }
    }

    static func detail(_ alert: FunnelAlertItem) -> String {
        let subject = alert.subject
        switch alert.kind {
        case "conversionDrop":
            let now = PanelFormat.percent(alert.value), before = PanelFormat.percent(alert.baseline)
            return String(localized: "\(subject): \(now) now, \(before) the period before.")
        case "eventSpike", "eventDip":
            let now = PanelFormat.count(alert.value), normal = PanelFormat.count(alert.baseline)
            return String(localized: "\(subject): \(now) users, against about \(normal) on a normal day.")
        default:
            let now = PanelFormat.percent(alert.value), before = PanelFormat.percent(alert.baseline)
            return String(localized: "Day 7 retention is \(now), down from \(before).")
        }
    }

    static func symbol(_ kind: String) -> String {
        switch kind {
        case "conversionDrop": "line.3.horizontal.decrease"
        case "eventSpike": "arrow.up.right"
        case "eventDip": "arrow.down.right"
        default: "person.badge.minus"
        }
    }
}

/// A change as a bar to the left or right of the middle.
private struct ChangeBar: View {
    let change: Double

    var body: some View {
        GeometryReader { proxy in
            let half = proxy.size.width / 2
            let width = max(2, min(1, abs(change)) * half)
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary).frame(height: 2).frame(maxHeight: .infinity)
                Capsule().fill(change >= 0 ? FunnelBrand.mint : FunnelBrand.coral)
                    .frame(width: width, height: 6)
                    .offset(x: change >= 0 ? half : half - width)
                    .frame(maxHeight: .infinity)
            }
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }
}

private struct FunnelFreshness: View {
    let date: Date?

    var body: some View {
        if let date {
            Label {
                HStack(spacing: 4) {
                    Text("Last read")
                    Text(date, format: .relative(presentation: .named))
                }
            } icon: {
                Image(systemName: "clock")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct FunnelHomeView: View {
    let store: FunnelStore

    var body: some View {
        @Bindable var store = store
        NavigationStack(path: $store.path) {
            ScrollView {
                VStack(spacing: 12) {
                    notice
                    if let portfolio = store.portfolio {
                        FunnelFreshness(date: portfolio.updatedAt)
                        trend(portfolio)
                        movers(portfolio)
                        leaks(portfolio)
                        compared(portfolio)
                        if !store.alerts.isEmpty { alerts }
                    } else if store.loadError == nil {
                        ProgressView("Reading your numbers…").padding(.top, 80)
                    }
                }
                .padding(16)
            }
            .funnelScreen()
            .navigationTitle(Text(verbatim: "FunnelRadar"))
            .navigationDestination(for: String.self) { id in
                FunnelProjectView(store: store, id: id)
            }
            .refreshable { await store.refresh() }
            .task { await store.refresh() }
        }
    }

    @ViewBuilder private var notice: some View {
        if store.state == "setup" {
            Label("Finish setup in FunnelRadar on your Mac.", systemImage: "macbook").vitrinCard()
        } else if store.state == "signedOut" {
            Label("Sign in again in FunnelRadar on your Mac.", systemImage: "person.badge.key").vitrinCard()
        } else if store.state == "missingCLI" {
            Label("Open FunnelRadar on your Mac to finish its setup.", systemImage: "terminal").vitrinCard()
        }
        if let error = store.loadError {
            Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).vitrinCard()
        }
    }

    private func trend(_ portfolio: FunnelPortfolio) -> some View {
        let series = portfolio.reports.compactMap { store.reports[$0.id] }.compactMap(FunnelIndexedSeries.make)
        return PanelCard(title: "Active users, side by side", note: "A 7-day average, 100 = each app 90 days ago. Apps count different events and can share people, so they are compared and never added.") {
            if series.isEmpty {
                PanelEmptyNote(text: "This fills in after two weeks of data.")
            } else {
                Chart {
                    ForEach(series) { app in
                        ForEach(app.points) { point in
                            LineMark(x: .value("Date", point.date), y: .value("Index", point.value))
                                .interpolationMethod(.monotone)
                                .foregroundStyle(by: .value("App", app.name))
                        }
                    }
                    RuleMark(y: .value("Start", 100)).foregroundStyle(.secondary.opacity(0.4)).lineStyle(StrokeStyle(dash: [3, 3]))
                }
                .chartForegroundStyleScale(domain: series.map(\.name), range: Array(FunnelBrand.series.prefix(max(1, series.count))))
                .chartYScale(domain: .automatic(includesZero: false))
                .chartLegend(position: .bottom, alignment: .leading)
                .frame(height: 210)
            }
        }
    }

    private func movers(_ portfolio: FunnelPortfolio) -> some View {
        PanelCard(title: "Biggest movers", note: "Top events, this week against last week.") {
            if portfolio.movers.isEmpty {
                PanelEmptyNote(text: "Nothing has moved much yet.")
            } else {
                VStack(spacing: 9) {
                    ForEach(portfolio.movers) { row in
                        NavigationLink(value: row.projectID) {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(verbatim: row.mover.event).lineLimit(1)
                                    Spacer()
                                    Text(verbatim: row.mover.change.map(PanelFormat.change) ?? "—").monospacedDigit()
                                        .foregroundStyle((row.mover.change ?? 0) >= 0 ? FunnelBrand.mint : FunnelBrand.coral)
                                }
                                .font(.callout)
                                Text(verbatim: row.projectName).font(.caption2).foregroundStyle(.secondary)
                                ChangeBar(change: row.mover.change ?? 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder private func leaks(_ portfolio: FunnelPortfolio) -> some View {
        if !portfolio.leaks.isEmpty {
            PanelCard(title: "Where people drop out", note: "The worst step of each saved funnel, worst first.") {
                VStack(spacing: 10) {
                    ForEach(portfolio.leaks) { row in
                        if let leak = row.funnel.leak {
                            NavigationLink(value: row.projectID) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(verbatim: "\(leak.fromEvent) → \(leak.toEvent)").lineLimit(1).font(.callout)
                                    Text(verbatim: "\(row.projectName) · \(row.funnel.name)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    HStack(spacing: 10) {
                                        GeometryReader { proxy in
                                            ZStack(alignment: .leading) {
                                                Capsule().fill(FunnelBrand.coral.opacity(0.28))
                                                Capsule().fill(FunnelBrand.buttonGradient).frame(width: max(4, proxy.size.width * leak.kept))
                                            }
                                        }
                                        .frame(height: 8)
                                        let kept = PanelFormat.percent(leak.kept, digits: 0)
                                        Text("keeps \(kept)").font(.caption).monospacedDigit()
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func compared(_ portfolio: FunnelPortfolio) -> some View {
        PanelCard(title: "Apps compared", note: "Daily users are of each app's key event, a 7-day average. Stickiness is DAU/MAU of the last full month. D7 is the share of a cohort back on day 7.") {
            VStack(spacing: 12) {
                ForEach(Array(portfolio.reports.enumerated()), id: \.element.id) { index, report in
                    if index > 0 { Divider() }
                    NavigationLink(value: report.id) { row(report) }.buttonStyle(.plain)
                }
            }
        }
    }

    private func row(_ report: FunnelProjectReport) -> some View {
        let insights = report.insights
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                FunnelBrand.gradient
                    .overlay { Text(verbatim: String(report.project.name.prefix(1))).font(.caption.bold()).foregroundStyle(.white) }
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: report.project.name).fontWeight(.medium).lineLimit(1)
                    Text(verbatim: report.keyEvent ?? "—").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary).accessibilityHidden(true)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 6) {
                cell("Daily users", insights.activeUsers.map(PanelFormat.count) ?? "—")
                cell("Change", insights.activeChange.map(PanelFormat.change) ?? "—", color: insights.activeChange.map { $0 >= 0 ? FunnelBrand.mint : FunnelBrand.coral })
                cell("Stickiness", insights.stickiness.map { PanelFormat.percent($0) } ?? "—")
                cell("D7", report.retention?.d7.map { PanelFormat.percent($0) } ?? "—", isName: false)
                cell("Best funnel", report.funnels.map(\.conversion).max().map { PanelFormat.percent($0) } ?? "—")
            }
        }
        .contentShape(Rectangle())
    }

    private func cell(_ title: LocalizedStringKey, _ value: String, color: Color? = nil, isName: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
            Text(verbatim: value).font(.caption.weight(.medium)).monospacedDigit().foregroundStyle(color ?? .primary).lineLimit(1)
        }
    }

    private var alerts: some View {
        PanelCard(title: "Alerts") {
            VStack(spacing: 12) {
                ForEach(store.alerts.prefix(20)) { alert in
                    PanelAlertRow(
                        title: FunnelAlertText.title(alert), detail: FunnelAlertText.detail(alert), date: alert.date,
                        symbol: FunnelAlertText.symbol(alert.kind), isGood: alert.kind == "eventSpike",
                        colors: [FunnelBrand.violet, FunnelBrand.blue]
                    )
                }
            }
        }
    }
}

struct FunnelProjectView: View {
    let store: FunnelStore
    let id: String
    @State private var report: FunnelProjectReport?
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if let report {
                    FunnelFreshness(date: report.updatedAt)
                    content(report)
                } else if let error {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).vitrinCard()
                } else {
                    ProgressView().padding(.top, 80)
                }
            }
            .padding(16)
        }
        .funnelScreen()
        .navigationTitle(Text(verbatim: report?.project.name ?? ""))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: store.portfolio) { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        do {
            report = try await store.report(id)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func takeaways(_ report: FunnelProjectReport) -> [String] {
        let insights = report.insights
        var lines: [String] = []
        if let funnel = report.funnels.filter({ $0.leak != nil }).min(by: { $0.leak!.kept < $1.leak!.kept }), let leak = funnel.leak {
            let name = funnel.name, step = leak.toEvent, kept = PanelFormat.percent(leak.kept, digits: 0), from = leak.fromEvent
            lines.append(String(localized: "\(name) loses the most people at \(step): only \(kept) get there from \(from)."))
        }
        if let sticky = insights.stickiness, let month = insights.stickinessMonth {
            let days = (sticky * 30).formatted(.number.precision(.fractionLength(0...1)))
            let name = monthName(month)
            lines.append(String(localized: "In \(name) an active user came back on about \(days) days of 30."))
        }
        if let day = insights.bestWeekday, insights.weekdayIndex.count == 7 {
            let name = Calendar.current.standaloneWeekdaySymbols[(day + 1) % 7]
            let change = PanelFormat.change(insights.weekdayIndex[day] - 1)
            lines.append(String(localized: "\(name) is your busiest day, \(change) against an average day."))
        }
        return lines
    }

    @ViewBuilder private func content(_ report: FunnelProjectReport) -> some View {
        let insights = report.insights
        LazyVGrid(columns: gridColumns, spacing: 10) {
            PanelKPI(
                title: "Daily users", value: insights.activeUsers.map(PanelFormat.count) ?? "—",
                detail: insights.activeChange.map { value in
                    let change = PanelFormat.change(value)
                    return String(localized: "\(change) on last week")
                },
                positive: insights.activeChange.map { $0 >= 0 }, good: FunnelBrand.mint, bad: FunnelBrand.coral
            )
            PanelKPI(title: "Stickiness", value: insights.stickiness.map { PanelFormat.percent($0) } ?? "—", detail: insights.stickinessMonth.map(monthName))
            PanelKPI(title: "D1 retention", value: report.retention?.d1.map { PanelFormat.percent($0) } ?? "—")
            PanelKPI(title: "D7 retention", value: report.retention?.d7.map { PanelFormat.percent($0) } ?? "—")
            PanelKPI(title: "D30 retention", value: report.retention?.d30.map { PanelFormat.percent($0) } ?? "—")
        }
        if report.deepKey == nil {
            Label("Your Mac is still reading the reports.", systemImage: "clock").font(.callout).vitrinCard()
        } else {
            PanelTakeaways(lines: takeaways(report))
            funnels(report)
            users(report)
            movers(report)
            PanelCard(title: "Weekday pattern", note: "Against an average day, last 12 weeks.") {
                if insights.weekdayIndex.isEmpty {
                    PanelEmptyNote(text: "This fills in after a week of data.")
                } else {
                    PanelWeekdays(index: insights.weekdayIndex, high: FunnelBrand.violet, low: FunnelBrand.blue.opacity(0.5))
                }
            }
            today(report)
            retention(report)
            curve(report)
            stickiness(report)
        }
    }

    @ViewBuilder private func funnels(_ report: FunnelProjectReport) -> some View {
        if report.funnels.isEmpty {
            PanelCard(title: "Funnels") {
                PanelEmptyNote(text: "This project has no saved funnels. Save one in Mixpanel and it appears here.", height: 60)
            }
        } else {
            let first = report.funnels.first
            let from = first.map { dayName($0.from) } ?? "", to = first.map { dayName($0.to) } ?? ""
            PanelCard(title: "Funnels", note: "\(from) – \(to), against the 28 days before. The newest 7 days are left out: people who just entered may still convert.") {
                VStack(spacing: 10) {
                    ForEach(report.funnels) { FunnelCard(funnel: $0) }
                }
                if report.funnelCount > report.funnels.count {
                    let shown = String(report.funnels.count), all = String(report.funnelCount)
                    Text("Showing the \(shown) most recently changed of \(all) saved funnels. Each one costs queries.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func users(_ report: FunnelProjectReport) -> some View {
        let event = report.keyEvent ?? "—"
        return PanelCard(title: "Daily users", note: report.keyEventIsGuess
            ? "\(event), the busiest event until you pick one in Settings. Marked days are far from the 28 before them. Dashed: a straight line through the last 60 days, for 30 more. A trend, not a forecast."
            : "\(event). Marked days are far from the 28 before them. Dashed: a straight line through the last 60 days, for 30 more. A trend, not a forecast.") {
            if report.dailyUsers.isEmpty {
                PanelEmptyNote(text: "No data yet.")
            } else {
                Chart {
                    ForEach(report.dailyUsers.suffix(120)) { day in
                        AreaMark(x: .value("Date", day.date), y: .value("Users", day.value))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(LinearGradient(colors: [FunnelBrand.violet.opacity(0.4), FunnelBrand.violet.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                        LineMark(x: .value("Date", day.date), y: .value("Users", day.value), series: .value("Series", "Users"))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(FunnelBrand.violet)
                    }
                    ForEach(report.insights.trend) { day in
                        LineMark(x: .value("Date", day.date), y: .value("Users", day.value), series: .value("Series", "Trend"))
                            .foregroundStyle(FunnelBrand.gold)
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
                    }
                    ForEach(report.anomalies.suffix(12)) { anomaly in
                        PointMark(x: .value("Date", anomaly.date), y: .value("Users", anomaly.value))
                            .foregroundStyle(anomaly.value > anomaly.expected ? FunnelBrand.mint : FunnelBrand.coral)
                            .symbolSize(50)
                    }
                }
                .frame(height: 200)
            }
        }
    }

    private func movers(_ report: FunnelProjectReport) -> some View {
        PanelCard(title: "Movers", note: "This week against last week.") {
            if report.movers.isEmpty {
                PanelEmptyNote(text: "Nothing has moved much yet.")
            } else {
                VStack(spacing: 8) {
                    ForEach(report.movers) { mover in
                        VStack(spacing: 2) {
                            HStack {
                                Text(verbatim: mover.event).lineLimit(1)
                                Spacer()
                                Text(verbatim: mover.change.map(PanelFormat.change) ?? String(localized: "new")).monospacedDigit()
                                    .foregroundStyle((mover.change ?? 1) >= 0 ? FunnelBrand.mint : FunnelBrand.coral)
                            }
                            .font(.callout)
                            ChangeBar(change: mover.change ?? 0)
                        }
                    }
                }
            }
        }
    }

    private func today(_ report: FunnelProjectReport) -> some View {
        PanelCard(title: "Today so far", note: "Busiest events, from the latest check.") {
            if report.topEvents.isEmpty {
                PanelEmptyNote(text: "No events yet today.")
            } else {
                VStack(spacing: 6) {
                    ForEach(report.topEvents.prefix(6)) { event in
                        HStack {
                            Text(verbatim: event.event).lineLimit(1)
                            Spacer()
                            Text(verbatim: PanelFormat.count(event.count)).monospacedDigit().foregroundStyle(.secondary)
                        }
                        .font(.callout)
                    }
                }
            }
        }
    }

    @ViewBuilder private func retention(_ report: FunnelProjectReport) -> some View {
        PanelCard(title: "Retention by week", note: "Weekly cohorts by day. Blank cells are too young to know.") {
            if let retention = report.retention {
                Text(verbatim: "\(retention.born) → \(retention.returning)").font(.caption).foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    Grid(horizontalSpacing: 3, verticalSpacing: 3) {
                        GridRow {
                            Text(verbatim: "").gridColumnAlignment(.leading)
                            Text(verbatim: "")
                            ForEach(retention.days, id: \.self) { day in
                                Text(verbatim: "D\(day)").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        ForEach(retention.rows) { row in
                            GridRow {
                                Text(row.week, format: Date.FormatStyle(timeZone: utc).month(.abbreviated).day())
                                    .font(.caption).foregroundStyle(.secondary)
                                Text(verbatim: PanelFormat.count(row.size)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                                ForEach(Array(row.cells.enumerated()), id: \.offset) { _, value in cell(value) }
                            }
                        }
                    }
                }
            } else {
                PanelEmptyNote(text: "Pick the two events of this project's cohort in FunnelRadar's Settings on your Mac.")
            }
        }
    }

    private func cell(_ value: Double?) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(value.map { FunnelBrand.violet.opacity(0.12 + min(1, $0 * 1.6) * 0.8) } ?? Color.clear)
            .frame(width: 42, height: 26)
            .overlay {
                if let value { Text(verbatim: PanelFormat.percent(value, digits: 0)).font(.caption2).monospacedDigit() }
            }
    }

    private func curve(_ report: FunnelProjectReport) -> some View {
        PanelCard(title: "Retention curve", note: "All cohorts, weighted by size. A curve that flattens means people stay.") {
            if let curve = report.retention?.curve, !curve.isEmpty {
                Chart(curve) { point in
                    LineMark(x: .value("Day", point.day), y: .value("Share", point.value))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(FunnelBrand.blue)
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel { Text(verbatim: value.as(Double.self).map { PanelFormat.percent($0, digits: 0) } ?? "") }
                    }
                }
                .frame(height: 190)
            } else {
                PanelEmptyNote(text: "No cohorts to draw yet.")
            }
        }
    }

    private func stickiness(_ report: FunnelProjectReport) -> some View {
        PanelCard(title: "Stickiness by month", note: "DAU/MAU of the key event, full months only.") {
            if report.insights.stickinessByMonth.isEmpty {
                PanelEmptyNote(text: "This fills in after a full month of data.")
            } else {
                Chart(report.insights.stickinessByMonth) { month in
                    BarMark(x: .value("Month", month.date, unit: .month), y: .value("DAU/MAU", month.value))
                        .foregroundStyle(FunnelBrand.buttonGradient)
                        .annotation(position: .top) {
                            Text(verbatim: PanelFormat.percent(month.value, digits: 0)).font(.caption2).monospacedDigit()
                        }
                }
                .chartYAxis(.hidden)
                .frame(height: 130)
            }
        }
    }
}

/// One funnel as bars that narrow, with the worst step in red.
private struct FunnelCard: View {
    let funnel: FunnelInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: funnel.name).font(.callout.weight(.semibold)).lineLimit(1)
                Spacer()
                Text(verbatim: PanelFormat.percent(funnel.conversion)).font(.system(.title3, design: .rounded).weight(.bold)).monospacedDigit()
            }
            if let change = funnel.change, let before = funnel.previousConversion {
                let delta = PanelFormat.change(change), was = PanelFormat.percent(before)
                Text("\(delta) · was \(was)")
                    .font(.caption.weight(.medium)).foregroundStyle(change >= 0 ? FunnelBrand.mint : FunnelBrand.coral)
            } else {
                Text("Nothing to compare with yet.").font(.caption).foregroundStyle(.secondary)
            }
            if funnel.entered == 0 {
                Text("Nobody entered this funnel in the period.").font(.caption).foregroundStyle(.secondary)
            }
            let first = max(1, funnel.steps.first?.count ?? 1)
            ForEach(Array(funnel.steps.enumerated()), id: \.offset) { index, step in
                let isLeak = funnel.leak?.step == index
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(verbatim: step.event).lineLimit(1).fontWeight(isLeak ? .semibold : .regular)
                        Spacer()
                        Text(verbatim: PanelFormat.count(step.count)).monospacedDigit().foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    GeometryReader { proxy in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(isLeak ? AnyShapeStyle(FunnelBrand.coral) : AnyShapeStyle(FunnelBrand.buttonGradient))
                            .frame(width: max(3, proxy.size.width * step.count / first))
                    }
                    .frame(height: 8)
                }
            }
            if let leak = funnel.leak {
                let lost = PanelFormat.count(leak.lost), step = leak.toEvent
                Label("\(lost) people stop before \(step)", systemImage: "drop.fill")
                    .font(.caption).foregroundStyle(FunnelBrand.coral).lineLimit(2)
            }
        }
        .padding(12)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}
