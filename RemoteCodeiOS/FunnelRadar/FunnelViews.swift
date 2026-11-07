import Charts
import SwiftUI

private func percent(_ value: Double) -> String {
    value.formatted(.percent.precision(.fractionLength(0...1)))
}

private func change(_ value: Double) -> String {
    value.formatted(.percent.precision(.fractionLength(0...1)).sign(strategy: .always(includingZero: false)))
}

struct FunnelHomeView: View {
    let store: FunnelStore

    var body: some View {
        @Bindable var store = store
        NavigationStack(path: $store.path) {
            List {
                if store.state == "setup" {
                    Label("Finish setup in FunnelRadar on your Mac.", systemImage: "macbook")
                } else if store.state == "signedOut" {
                    Label("Sign in again in FunnelRadar on your Mac.", systemImage: "person.badge.key")
                } else if store.state == "missingCLI" {
                    Label("Open FunnelRadar on your Mac to finish its setup.", systemImage: "terminal")
                }
                if let error = store.loadError {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }
                if let portfolio = store.portfolio {
                    Section("Projects") {
                        ForEach(portfolio.reports) { report in
                            NavigationLink(value: report.id) { row(report) }
                        }
                    }
                } else if store.loadError == nil {
                    ProgressView()
                }
            }
            .navigationTitle(Text(verbatim: "FunnelRadar"))
            .navigationDestination(for: String.self) { id in
                FunnelProjectView(store: store, id: id)
            }
            .refreshable { await store.refresh() }
            .task { await store.refresh() }
        }
    }

    private func row(_ report: FunnelProjectReport) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: report.project.name).lineLimit(1)
                if let leak = report.funnels.first?.leak {
                    Text(verbatim: "\(leak.fromEvent) → \(leak.toEvent)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            if let users = report.insights.activeUsers {
                Text(users.formatted()).monospacedDigit()
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
        List {
            if let report {
                content(report)
            } else if let error {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            } else {
                ProgressView()
            }
        }
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

    @ViewBuilder private func content(_ report: FunnelProjectReport) -> some View {
        Section {
            if let users = report.insights.activeUsers {
                LabeledContent("Active users", value: users.formatted())
            }
            if let value = report.insights.activeChange {
                LabeledContent("Change", value: change(value))
            }
            if let value = report.insights.stickiness {
                LabeledContent {
                    Text(verbatim: percent(value))
                } label: {
                    Text(verbatim: "DAU/MAU")
                }
            }
        }
        if report.dailyUsers.count > 1 {
            Section("Active users") {
                Chart(report.dailyUsers) { day in
                    LineMark(x: .value("Date", day.date), y: .value("Users", day.value)).foregroundStyle(.tint)
                }
                .frame(height: 170)
            }
        }
        ForEach(report.funnels) { funnel in
            Section {
                LabeledContent("Conversion", value: percent(funnel.conversion))
                ForEach(funnel.steps) { step in
                    LabeledContent {
                        Text(verbatim: percent(step.conversion)).monospacedDigit()
                    } label: {
                        Text(verbatim: step.event).lineLimit(1)
                    }
                }
                if let leak = funnel.leak {
                    Label {
                        Text("Biggest leak: \(percent(leak.lost)) lost")
                    } icon: {
                        Image(systemName: "drop.triangle")
                    }
                    .foregroundStyle(.orange)
                }
            } header: {
                Text(verbatim: funnel.name)
            }
        }
        if let retention = report.retention {
            Section {
                ForEach([("D1", retention.d1), ("D7", retention.d7), ("D30", retention.d30)], id: \.0) { row in
                    LabeledContent {
                        Text(verbatim: row.1.map(percent) ?? "—")
                    } label: {
                        Text(verbatim: row.0)
                    }
                }
            } header: {
                Text("Retention")
            } footer: {
                Text(verbatim: "\(retention.born) → \(retention.returning)")
            }
        }
        if !report.movers.isEmpty {
            Section("Biggest movers") {
                ForEach(report.movers) { mover in
                    LabeledContent {
                        Text(verbatim: mover.change.map(change) ?? "—").monospacedDigit()
                    } label: {
                        Text(verbatim: mover.event).lineLimit(1)
                    }
                }
            }
        }
    }
}
