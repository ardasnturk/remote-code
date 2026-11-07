import Charts
import SwiftUI

private let gridColumns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

enum RadarAlertText {
    static func title(_ alert: RadarAlertItem) -> String {
        let name = alert.projectName
        return switch alert.kind {
        case "newSubscribers": String(localized: "New subscribers · \(name)")
        case "mrrDrop": String(localized: "MRR is falling · \(name)")
        case "mrrMilestone": String(localized: "MRR milestone · \(name)")
        case "revenueSpike": String(localized: "Unusually good day · \(name)")
        case "revenueDip": String(localized: "Unusually quiet day · \(name)")
        case "refundSpike": String(localized: "Refunds are high · \(name)")
        case "churnSpike": String(localized: "Churn is up · \(name)")
        default: name
        }
    }

    static func detail(_ alert: RadarAlertItem) -> String {
        let amount = alert.currency.map { PanelFormat.money(alert.value, $0) } ?? PanelFormat.count(alert.value)
        let share = alert.fraction.map { PanelFormat.percent($0) } ?? ""
        return switch alert.kind {
        case "newSubscribers": String(localized: "\(amount) more active subscribers.")
        case "mrrDrop": String(localized: "Down \(share) in 7 days (\(amount)).")
        case "mrrMilestone": String(localized: "MRR passed \(amount).")
        case "refundSpike": String(localized: "\(PanelFormat.percent(alert.value)) of last month's transactions were refunded.")
        case "churnSpike": String(localized: "\(PanelFormat.percent(alert.value)) of subscribers left this week, \(share) above normal.")
        default: String(localized: "\(amount), \(share) away from a normal day.")
        }
    }

    static func symbol(_ kind: String) -> String {
        switch kind {
        case "newSubscribers": "person.badge.plus"
        case "mrrDrop": "chart.line.downtrend.xyaxis"
        case "mrrMilestone": "flag.checkered"
        case "revenueSpike": "arrow.up.right"
        case "revenueDip": "arrow.down.right"
        case "refundSpike": "arrow.uturn.left"
        default: "person.badge.minus"
        }
    }

    static func isGood(_ kind: String) -> Bool {
        ["newSubscribers", "mrrMilestone", "revenueSpike"].contains(kind)
    }
}

struct RadarHomeView: View {
    let store: RadarStore

    var body: some View {
        @Bindable var store = store
        NavigationStack(path: $store.path) {
            ScrollView {
                VStack(spacing: 12) {
                    notice
                    if let portfolio = store.portfolio {
                        if let date = portfolio.updatedAt { RadarFreshness(date: date) }
                        ForEach(portfolio.totals) { summary($0) }
                        if !portfolio.reports.isEmpty { compared(portfolio.reports) }
                        if !store.alerts.isEmpty { alerts }
                    } else if store.loadError == nil {
                        ProgressView("Reading your numbers…").padding(.top, 80)
                    }
                }
                .padding(16)
            }
            .radarScreen()
            .navigationTitle(Text(verbatim: "MRRadar"))
            .navigationDestination(for: String.self) { id in
                RadarProjectView(store: store, id: id)
            }
            .refreshable {
                await store.readAgain()
                await store.refresh()
            }
            .task { await store.refresh() }
        }
    }

    @ViewBuilder private var notice: some View {
        if store.state == "setup" {
            Label("Finish setup in MRRadar on your Mac.", systemImage: "macbook").vitrinCard()
        } else if store.state == "signedOut" {
            Label("Sign in again in MRRadar on your Mac.", systemImage: "person.badge.key").vitrinCard()
        } else if store.state == "missingCLI" {
            Label("Open MRRadar on your Mac to finish its setup.", systemImage: "terminal").vitrinCard()
        }
        if let error = store.loadError {
            Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).vitrinCard()
        }
    }

    @ViewBuilder private func summary(_ total: RadarTotal) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: PanelFormat.money(total.mrr, total.currency)).font(.system(size: 32, weight: .bold, design: .rounded)).monospacedDigit()
                Text(verbatim: "MRR").font(.caption.weight(.medium))
                Spacer()
                if let change = total.mrrChange30 {
                    Text(verbatim: PanelFormat.change(change)).font(.callout.weight(.semibold))
                }
            }
            HStack(spacing: 7) {
                stat(PanelFormat.count(total.activeSubscriptions), "subscribers")
                stat(PanelFormat.count(total.activeTrials), "trials")
                stat(PanelFormat.money(total.revenue28, total.currency), "28 days")
            }
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(RadarBrand.gradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        LazyVGrid(columns: gridColumns, spacing: 10) {
            PanelKPI(title: "ARR", value: PanelFormat.money(total.mrr * 12, total.currency))
            PanelKPI(title: "Active trials", value: PanelFormat.count(total.activeTrials))
        }
        if total.mrr == 0, total.revenue28 == 0 {
            Label("No revenue yet. The charts fill in with your first subscribers.", systemImage: "leaf").font(.callout).vitrinCard()
        }
        PanelCard(title: "Revenue, all apps", note: "Last 90 days") {
            let days = Array(total.revenueDaily.suffix(90))
            if days.isEmpty {
                PanelEmptyNote(text: "Not enough data yet.")
            } else {
                Chart(days) { day in
                    AreaMark(x: .value("Date", day.date), y: .value("Revenue", day.value))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(LinearGradient(colors: [RadarBrand.emerald.opacity(0.45), RadarBrand.emerald.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("Date", day.date), y: .value("Revenue", day.value))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(RadarBrand.emerald)
                }
                .frame(height: 180)
            }
        }
        PanelCard(title: "Where MRR comes from") {
            if total.mrrShare.isEmpty {
                PanelEmptyNote(text: "Not enough data yet.")
            } else {
                Chart(total.mrrShare) { share in
                    SectorMark(angle: .value("MRR", share.value), innerRadius: .ratio(0.62), angularInset: 1.5)
                        .cornerRadius(3)
                        .foregroundStyle(by: .value("App", share.name))
                }
                .chartLegend(position: .bottom, alignment: .center)
                .frame(height: 220)
            }
        }
    }

    private func stat(_ value: String, _ label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: value).font(.subheadline.weight(.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.caption2)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func compared(_ reports: [RadarReport]) -> some View {
        PanelCard(title: "Apps compared", note: "Sorted by MRR. Quick ratio is MRR won per unit lost over 8 weeks; above 4 is strong, below 1 is shrinking.") {
            VStack(spacing: 12) {
                ForEach(Array(reports.enumerated()), id: \.element.id) { index, report in
                    if index > 0 { Divider() }
                    NavigationLink(value: report.id) { row(report) }.buttonStyle(.plain)
                }
            }
        }
    }

    private func row(_ report: RadarReport) -> some View {
        let insights = report.insights, currency = report.overview.currency
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                RadarIcon(project: report.project)
                Text(verbatim: report.project.name).fontWeight(.medium).lineLimit(1)
                Spacer(minLength: 6)
                PanelSparkline(values: report.mrrDaily.map(\.value), up: RadarBrand.emerald, down: RadarBrand.coral).frame(width: 48, height: 20)
                Text(verbatim: PanelFormat.money(report.overview.mrr, currency)).monospacedDigit()
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary).accessibilityHidden(true)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 6) {
                cell("30 days", insights.mrrChange30.map(PanelFormat.change) ?? "—", color: insights.mrrChange30.map { $0 >= 0 ? RadarBrand.emerald : RadarBrand.coral })
                cell("Quick ratio", insights.quickRatio.map(PanelFormat.ratio) ?? "—")
                cell("Churn / mo", insights.monthlyChurn.map { PanelFormat.percent($0) } ?? "—")
                cell("Implied LTV", insights.impliedLTV.map { PanelFormat.money($0, currency) } ?? "—")
                cell("Month-end pace", insights.monthEndPace.map { PanelFormat.money($0, currency) } ?? "—")
                cell("Trials", PanelFormat.count(report.overview.activeTrials))
            }
        }
        .contentShape(Rectangle())
    }

    private func cell(_ title: LocalizedStringKey, _ value: String, color: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
            Text(verbatim: value).font(.caption.weight(.medium)).monospacedDigit().foregroundStyle(color ?? .primary).lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    private var alerts: some View {
        PanelCard(title: "Alerts") {
            VStack(spacing: 12) {
                ForEach(store.alerts.prefix(20)) { alert in
                    PanelAlertRow(
                        title: RadarAlertText.title(alert), detail: RadarAlertText.detail(alert), date: alert.date,
                        symbol: RadarAlertText.symbol(alert.kind), isGood: RadarAlertText.isGood(alert.kind),
                        colors: [RadarBrand.emerald, RadarBrand.teal]
                    )
                }
            }
        }
    }
}

private struct RadarFreshness: View {
    let date: Date

    var body: some View {
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

private struct RadarIcon: View {
    let project: RadarProject

    var body: some View {
        AsyncImage(url: project.iconURL.flatMap(URL.init(string:))) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            RadarBrand.gradient.overlay { Text(verbatim: String(project.name.prefix(1))).font(.caption.bold()).foregroundStyle(.white) }
        }
        .frame(width: 28, height: 28)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .accessibilityHidden(true)
    }
}

struct RadarProjectView: View {
    let store: RadarStore
    let id: String
    @State private var report: RadarReport?
    @State private var error: String?
    @State private var range = 90

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if let report {
                    content(report)
                } else if let error {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).vitrinCard()
                } else {
                    ProgressView().padding(.top, 80)
                }
            }
            .padding(16)
        }
        .radarScreen()
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

    private func takeaways(_ report: RadarReport) -> [String] {
        let insights = report.insights, currency = report.overview.currency
        var lines: [String] = []
        if let pace = insights.monthEndPace, let last = insights.lastMonth, last > 0 {
            let amount = PanelFormat.money(pace, currency)
            let change = PanelFormat.change((pace - last) / last)
            lines.append(String(localized: "At this pace the month ends at \(amount), \(change) against last month."))
        }
        if let pipeline = insights.trialPipelineMRR, pipeline > 0 {
            let amount = PanelFormat.money(pipeline, currency)
            lines.append(String(localized: "Running trials should add about \(amount) of MRR."))
        }
        if let day = insights.bestWeekday, insights.weekdayIndex.count == 7 {
            let name = Calendar.current.standaloneWeekdaySymbols[(day + 1) % 7]
            let change = PanelFormat.change(insights.weekdayIndex[day] - 1)
            lines.append(String(localized: "\(name) is your best day, \(change) against an average day."))
        }
        if let share = insights.topCountryShare, share > 0.5, let country = report.countries.first?.name {
            let text = PanelFormat.percent(share, digits: 0)
            lines.append(String(localized: "\(text) of revenue comes from \(country)."))
        }
        return lines
    }

    @ViewBuilder private func content(_ report: RadarReport) -> some View {
        let insights = report.insights, currency = report.overview.currency
        LazyVGrid(columns: gridColumns, spacing: 10) {
            PanelKPI(title: "MRR", value: PanelFormat.money(report.overview.mrr, currency), detail: insights.mrrChange30.map(PanelFormat.change), positive: insights.mrrChange30.map { $0 >= 0 })
            PanelKPI(title: "ARR", value: PanelFormat.money(insights.arr, currency))
            PanelKPI(title: "Subscribers", value: PanelFormat.count(report.overview.activeSubscriptions), detail: insights.arpu.map { value in
                let amount = PanelFormat.money(value, currency)
                return String(localized: "\(amount) each")
            })
            PanelKPI(title: "Active trials", value: PanelFormat.count(report.overview.activeTrials), detail: insights.trialConversion.map { value in
                let share = PanelFormat.percent(value)
                return String(localized: "\(share) convert")
            })
            PanelKPI(title: "Quick ratio", value: insights.quickRatio.map(PanelFormat.ratio) ?? "—")
            PanelKPI(title: "Implied LTV", value: insights.impliedLTV.map { PanelFormat.money($0, currency) } ?? "—", detail: insights.lifetimeMonths.map { value in
                let months = PanelFormat.months(value)
                return String(localized: "\(months) months")
            })
        }
        if report.chartsUpdatedAt == nil {
            Label("Your Mac is still reading the charts.", systemImage: "clock").font(.callout).vitrinCard()
        } else {
            PanelTakeaways(lines: takeaways(report))
            forecast(report)
            movement(report)
            revenue(report)
            PanelCard(title: "Best days", note: "Against an average day, last 12 weeks.") {
                if insights.weekdayIndex.isEmpty {
                    PanelEmptyNote(text: "Not enough data yet.")
                } else {
                    PanelWeekdays(index: insights.weekdayIndex, high: RadarBrand.emerald, low: RadarBrand.teal.opacity(0.5))
                }
            }
            trials(report)
            churn(report)
            if !report.retention.isEmpty { retention(report) }
            shares("Countries", report.countries)
            shares("Stores", report.stores)
        }
    }

    private func forecast(_ report: RadarReport) -> some View {
        PanelCard(title: "MRR and where it's heading", note: "Dashed: a straight line through the last 60 days, for 90 more. A trend, not a promise.") {
            Chart {
                ForEach(report.mrrDaily) { day in
                    LineMark(x: .value("Date", day.date), y: .value("MRR", day.value), series: .value("Series", "MRR"))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(RadarBrand.emerald)
                }
                ForEach(report.insights.forecast) { day in
                    LineMark(x: .value("Date", day.date), y: .value("MRR", day.value), series: .value("Series", "Forecast"))
                        .foregroundStyle(RadarBrand.gold)
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
                }
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .frame(height: 190)
        }
    }

    private func movement(_ report: RadarReport) -> some View {
        PanelCard(title: "MRR won and lost", note: "Each week: new, returning and upgraded subscribers against those who left.") {
            Chart(report.movement) { week in
                BarMark(x: .value("Week", week.date, unit: .weekOfYear), y: .value("Won", week.gained)).foregroundStyle(RadarBrand.emerald)
                BarMark(x: .value("Week", week.date, unit: .weekOfYear), y: .value("Lost", -week.lost)).foregroundStyle(RadarBrand.coral)
            }
            .frame(height: 190)
        }
    }

    private func revenue(_ report: RadarReport) -> some View {
        let days = Array(report.revenueDaily.suffix(range))
        let first = days.first?.date ?? .distantPast
        return PanelCard(title: "Daily revenue", note: "Marked days are far from the 28 before them.") {
            Picker("Period", selection: $range) {
                Text("30 days").tag(30)
                Text("90 days").tag(90)
                Text("1 year").tag(365)
            }
            .pickerStyle(.segmented)
            Chart {
                ForEach(days) { day in
                    BarMark(x: .value("Date", day.date, unit: .day), y: .value("Revenue", day.value))
                        .foregroundStyle(RadarBrand.teal.opacity(0.8))
                }
                ForEach(report.anomalies.filter { $0.date >= first }) { anomaly in
                    PointMark(x: .value("Date", anomaly.date, unit: .day), y: .value("Revenue", anomaly.value))
                        .foregroundStyle(anomaly.value > anomaly.expected ? RadarBrand.gold : RadarBrand.coral)
                }
            }
            .frame(height: 190)
        }
    }

    private func trials(_ report: RadarReport) -> some View {
        PanelCard(title: "Trials", note: "Started, and converted, each week.") {
            Chart(report.trialsWeekly) { week in
                BarMark(x: .value("Week", week.date, unit: .weekOfYear), y: .value("Started", week.starts), stacking: .unstacked).foregroundStyle(RadarBrand.teal.opacity(0.35))
                BarMark(x: .value("Week", week.date, unit: .weekOfYear), y: .value("Converted", week.conversions), stacking: .unstacked).foregroundStyle(RadarBrand.emerald)
            }
            .frame(height: 160)
        }
    }

    private func churn(_ report: RadarReport) -> some View {
        PanelCard(title: "Weekly churn", note: "Share of subscribers lost.") {
            Chart(report.churnWeekly) { week in
                LineMark(x: .value("Week", week.date), y: .value("Churn", week.value / 100))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(RadarBrand.coral)
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel { Text(verbatim: value.as(Double.self).map { PanelFormat.percent($0) } ?? "") }
                }
            }
            .frame(height: 160)
        }
    }

    private func retention(_ report: RadarReport) -> some View {
        let columns = report.retention.map(\.cells.count).max() ?? 0
        return PanelCard(title: "Retention by month", note: "Share of each month's new subscribers still paying.") {
            ScrollView(.horizontal, showsIndicators: false) {
                Grid(horizontalSpacing: 3, verticalSpacing: 3) {
                    ForEach(report.retention) { row in
                        GridRow {
                            Text(row.cohort, format: .dateTime.month(.abbreviated).year(.twoDigits))
                                .font(.caption).foregroundStyle(.secondary).gridColumnAlignment(.leading)
                            Text(verbatim: PanelFormat.count(row.size)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                            ForEach(0..<columns, id: \.self) { column in
                                cell(column < row.cells.count ? row.cells[column] : nil)
                            }
                        }
                    }
                }
            }
        }
    }

    private func cell(_ value: Double?) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(value.map { RadarBrand.emerald.opacity(0.12 + $0 * 0.8) } ?? Color.clear)
            .frame(width: 44, height: 26)
            .overlay {
                if let value { Text(verbatim: PanelFormat.percent(value, digits: 0)).font(.caption2).monospacedDigit() }
            }
    }

    private func shares(_ title: LocalizedStringKey, _ rows: [RadarShare]) -> some View {
        PanelCard(title: title, note: "Revenue, last 3 months.") {
            if rows.isEmpty {
                Text("Not enough data yet.").font(.callout).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(rows) { PanelShareRow(name: $0.name, fraction: $0.fraction, fill: RadarBrand.buttonGradient) }
                }
            }
        }
    }
}
