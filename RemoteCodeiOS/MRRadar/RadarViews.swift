import Charts
import SwiftUI

private enum RadarFormat {
    static func money(_ value: Double, _ currency: String) -> String {
        value.formatted(.currency(code: currency).precision(.fractionLength(abs(value) >= 1000 ? 0 : 2)))
    }

    static func change(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(0...1)).sign(strategy: .always(includingZero: false)))
    }

    static func percent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(0...1)))
    }
}

private enum RadarBrand {
    static let accent = Color(red: 0.11, green: 0.72, blue: 0.50)
    static let loss = Color(red: 0.95, green: 0.40, blue: 0.38)
    static let forecast = Color(red: 0.96, green: 0.70, blue: 0.22)
}

struct RadarHomeView: View {
    let store: RadarStore

    var body: some View {
        @Bindable var store = store
        NavigationStack(path: $store.path) {
            List {
                notice
                if let portfolio = store.portfolio {
                    ForEach(portfolio.totals) { total in
                        Section { totalRow(total) }
                    }
                    Section("Apps") {
                        ForEach(portfolio.reports) { report in
                            NavigationLink(value: report.id) { row(report) }
                        }
                    }
                    if !store.alerts.isEmpty {
                        Section("Alerts") {
                            ForEach(store.alerts.prefix(10)) { alert in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(RadarAlertText.title(alert.kind))
                                    Text(alert.projectName).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } else if store.loadError == nil {
                    ProgressView()
                }
            }
            .navigationTitle("MRRadar")
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
            Label("Finish setup in MRRadar on your Mac.", systemImage: "macbook")
        } else if store.state == "signedOut" {
            Label("Sign in again in MRRadar on your Mac.", systemImage: "person.badge.key")
        } else if store.state == "missingCLI" {
            Label("Open MRRadar on your Mac to finish its setup.", systemImage: "terminal")
        }
        if let error = store.loadError {
            Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
        }
    }

    private func totalRow(_ total: RadarTotal) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(RadarFormat.money(total.mrr, total.currency)).font(.largeTitle.bold()).monospacedDigit()
                Text(verbatim: "MRR").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if let change = total.mrrChange30 {
                    Text(RadarFormat.change(change)).foregroundStyle(change >= 0 ? RadarBrand.accent : RadarBrand.loss)
                }
            }
            HStack {
                LabeledContent("Subscribers", value: total.activeSubscriptions.formatted())
                LabeledContent("Trials", value: total.activeTrials.formatted())
            }
            .font(.footnote)
        }
    }

    private func row(_ report: RadarReport) -> some View {
        HStack(spacing: 10) {
            RadarIcon(project: report.project)
            Text(report.project.name).lineLimit(1)
            Spacer()
            RadarSparkline(values: report.mrrDaily.map(\.value)).frame(width: 52, height: 20)
            Text(RadarFormat.money(report.overview.mrr, report.overview.currency)).monospacedDigit()
        }
    }
}

enum RadarAlertText {
    static func title(_ kind: String) -> LocalizedStringKey {
        switch kind {
        case "newSubscribers": "New subscribers"
        case "mrrDrop": "MRR is falling"
        case "mrrMilestone": "MRR milestone"
        case "revenueSpike": "Unusually good day"
        case "revenueDip": "Unusually quiet day"
        case "refundSpike": "Refunds are high"
        case "churnSpike": "Churn is up"
        default: "Alerts"
        }
    }
}

private struct RadarIcon: View {
    let project: RadarProject

    var body: some View {
        AsyncImage(url: project.iconURL.flatMap(URL.init(string:))) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            RadarBrand.accent.overlay { Text(project.name.prefix(1)).font(.caption.bold()).foregroundStyle(.white) }
        }
        .frame(width: 28, height: 28)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .accessibilityHidden(true)
    }
}

private struct RadarSparkline: View {
    let values: [Double]

    var body: some View {
        Chart(Array(values.enumerated()), id: \.offset) { item in
            LineMark(x: .value("Day", item.offset), y: .value("MRR", item.element))
                .foregroundStyle((values.last ?? 0) >= (values.first ?? 0) ? RadarBrand.accent : RadarBrand.loss)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: .automatic(includesZero: false))
        .accessibilityHidden(true)
    }
}

struct RadarProjectView: View {
    let store: RadarStore
    let id: String
    @State private var report: RadarReport?
    @State private var error: String?

    var body: some View {
        List {
            if let report {
                content(report)
            } else if let error {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(report?.project.name ?? "")
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

    @ViewBuilder private func content(_ report: RadarReport) -> some View {
        let insights = report.insights, currency = report.overview.currency
        Section {
            LabeledContent("MRR", value: RadarFormat.money(report.overview.mrr, currency))
            LabeledContent("ARR", value: RadarFormat.money(insights.arr, currency))
            LabeledContent("Subscribers", value: report.overview.activeSubscriptions.formatted())
            LabeledContent("Trials", value: report.overview.activeTrials.formatted())
            if let ratio = insights.quickRatio {
                LabeledContent("Quick ratio", value: "\(ratio.formatted(.number.precision(.fractionLength(1))))×")
            }
            if let ltv = insights.impliedLTV {
                LabeledContent("Implied LTV", value: RadarFormat.money(ltv, currency))
            }
            if let pace = insights.monthEndPace {
                LabeledContent("Month-end pace", value: RadarFormat.money(pace, currency))
            }
            if let churn = insights.monthlyChurn {
                LabeledContent("Monthly churn", value: RadarFormat.percent(churn))
            }
            if let conversion = insights.trialConversion {
                LabeledContent("Trial conversion", value: RadarFormat.percent(conversion))
            }
        }
        if report.chartsUpdatedAt == nil {
            Section { Label("Your Mac is still reading the charts.", systemImage: "clock") }
        } else {
            Section("MRR and where it's heading") {
                Chart {
                    ForEach(report.mrrDaily) { day in
                        LineMark(x: .value("Date", day.date), y: .value("MRR", day.value), series: .value("Series", "MRR"))
                            .foregroundStyle(RadarBrand.accent)
                    }
                    ForEach(insights.forecast) { day in
                        LineMark(x: .value("Date", day.date), y: .value("MRR", day.value), series: .value("Series", "Forecast"))
                            .foregroundStyle(RadarBrand.forecast)
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 190)
            }
            Section("MRR won and lost") {
                Chart(report.movement) { week in
                    BarMark(x: .value("Week", week.date, unit: .weekOfYear), y: .value("Won", week.gained)).foregroundStyle(RadarBrand.accent)
                    BarMark(x: .value("Week", week.date, unit: .weekOfYear), y: .value("Lost", -week.lost)).foregroundStyle(RadarBrand.loss)
                }
                .frame(height: 170)
            }
            Section("Daily revenue") {
                Chart(report.revenueDaily.suffix(60)) { day in
                    BarMark(x: .value("Date", day.date, unit: .day), y: .value("Revenue", day.value)).foregroundStyle(RadarBrand.accent.opacity(0.8))
                }
                .frame(height: 170)
            }
            if !report.retention.isEmpty {
                Section("Retention by month") {
                    ForEach(report.retention.suffix(6)) { row in
                        LabeledContent {
                            Text(row.cells.compactMap { $0 }.last.map(RadarFormat.percent) ?? "—")
                        } label: {
                            Text(row.cohort, format: .dateTime.month(.abbreviated).year(.twoDigits))
                        }
                    }
                }
            }
            if !report.countries.isEmpty {
                Section("Countries") {
                    ForEach(report.countries) { country in
                        LabeledContent(country.name, value: RadarFormat.percent(country.fraction))
                    }
                }
            }
        }
    }
}
