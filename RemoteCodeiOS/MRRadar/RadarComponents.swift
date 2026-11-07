import Charts
import SwiftUI
import UIKit

/// MRRadar's colors, as on the Mac (MRRadar/Views/Design.swift): emerald into teal, with gold.
enum RadarBrand {
    static let emerald = Color(red: 0.11, green: 0.72, blue: 0.50)
    static let teal = Color(red: 0.05, green: 0.60, blue: 0.62)
    static let gold = Color(red: 0.96, green: 0.70, blue: 0.22)
    static let coral = Color(red: 0.95, green: 0.40, blue: 0.38)
    static let indigo = Color(red: 0.30, green: 0.36, blue: 0.93)

    /// The Mac app's accent color, lighter in dark mode so it stays readable.
    static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.28, green: 0.84, blue: 0.62, alpha: 1)
            : UIColor(red: 0.05, green: 0.56, blue: 0.45, alpha: 1)
    })

    static let gradient = LinearGradient(colors: [emerald, teal, indigo], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let buttonGradient = LinearGradient(colors: [emerald, teal], startPoint: .leading, endPoint: .trailing)
}

/// FunnelRadar's colors, as on the Mac (FunnelRadar/Views/Design.swift): violet into blue.
enum FunnelBrand {
    static let violet = Color(red: 0.49, green: 0.31, blue: 0.95)
    static let blue = Color(red: 0.20, green: 0.48, blue: 0.97)
    static let pink = Color(red: 0.86, green: 0.36, blue: 0.82)
    static let gold = Color(red: 0.96, green: 0.70, blue: 0.22)
    static let coral = Color(red: 0.97, green: 0.42, blue: 0.42)
    static let mint = Color(red: 0.23, green: 0.80, blue: 0.62)

    static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.62, green: 0.52, blue: 0.98, alpha: 1)
            : UIColor(red: 0.42, green: 0.30, blue: 0.92, alpha: 1)
    })

    static let gradient = LinearGradient(colors: [violet, blue], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let buttonGradient = LinearGradient(colors: [violet, blue], startPoint: .leading, endPoint: .trailing)
    /// One color per app in a chart, in a fixed order.
    static let series: [Color] = [violet, blue, mint, gold, pink, coral]
}

extension View {
    /// An MRRadar screen: its color blobs behind the content and its accent on the controls.
    func radarScreen() -> some View {
        brandWindowBackground(intensity: 0.9, blobs: [RadarBrand.emerald, RadarBrand.teal, RadarBrand.gold])
            .tint(RadarBrand.accent)
    }

    /// A FunnelRadar screen.
    func funnelScreen() -> some View {
        brandWindowBackground(intensity: 0.9, blobs: [FunnelBrand.violet, FunnelBrand.blue, FunnelBrand.pink])
            .tint(FunnelBrand.accent)
    }
}

/// Numbers as the Mac apps write them.
enum PanelFormat {
    static func money(_ value: Double, _ currency: String) -> String {
        value.formatted(.currency(code: currency).precision(.fractionLength(abs(value) >= 1000 ? 0 : 2)))
    }

    static func count(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)))
    }

    static func percent(_ value: Double, digits: Int = 1) -> String {
        value.formatted(.percent.precision(.fractionLength(0...digits)))
    }

    static func change(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(0...1)).sign(strategy: .always(includingZero: false)))
    }

    static func ratio(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(1))))×"
    }

    static func months(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }
}

/// One headline number.
struct PanelKPI: View {
    let title: LocalizedStringKey
    let value: String
    var detail: String?
    var positive: Bool?
    var good: Color = RadarBrand.emerald
    var bad: Color = RadarBrand.coral

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary).lineLimit(1)
            Text(verbatim: value).font(.system(.title3, design: .rounded).weight(.bold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(verbatim: detail ?? " ")
                .font(.caption.weight(.medium))
                .foregroundStyle(positive.map { $0 ? good : bad } ?? .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .vitrinCard()
    }
}

struct PanelCard<Content: View>: View {
    let title: LocalizedStringKey
    var note: LocalizedStringKey?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                if let note {
                    Text(note).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            content
        }
        .vitrinCard(padding: 14)
    }
}

/// A list of plain sentences, from the numbers below it.
struct PanelTakeaways: View {
    let lines: [String]

    var body: some View {
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(lines, id: \.self) { line in
                    Label(line, systemImage: "sparkle").font(.callout)
                }
            }
            .vitrinCard(padding: 14)
        }
    }
}

struct PanelEmptyNote: View {
    let text: LocalizedStringKey
    var height: CGFloat = 90

    var body: some View {
        Text(text)
            .font(.callout).foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: height)
    }
}

/// A bar on a track, for a share of something.
struct PanelShareRow: View {
    let name: String
    let fraction: Double
    let fill: LinearGradient

    var body: some View {
        HStack(spacing: 10) {
            Text(verbatim: name).lineLimit(1).frame(width: 110, alignment: .leading)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(fill).frame(width: max(4, proxy.size.width * fraction))
                }
            }
            .frame(height: 6)
            Text(verbatim: PanelFormat.percent(fraction, digits: 0)).monospacedDigit().frame(width: 42, alignment: .trailing)
        }
        .font(.callout)
    }
}

/// A tiny line with no axes.
struct PanelSparkline: View {
    let values: [Double]
    let up: Color
    let down: Color

    var body: some View {
        Chart(Array(values.enumerated()), id: \.offset) { item in
            LineMark(x: .value("Day", item.offset), y: .value("Value", item.element))
                .interpolationMethod(.monotone)
                .foregroundStyle((values.last ?? 0) >= (values.first ?? 0) ? up : down)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: .automatic(includesZero: false))
        .accessibilityHidden(true)
    }
}

/// Bars against an average day, Monday first.
struct PanelWeekdays: View {
    let index: [Double]
    let high: Color
    let low: Color

    var body: some View {
        let names = Calendar.current.veryShortStandaloneWeekdaySymbols
        let rows = index.enumerated().map { (offset: $0.offset, name: names[($0.offset + 1) % 7], value: $0.element) }
        Chart(rows, id: \.offset) { row in
            BarMark(x: .value("Day", "\(row.offset) \(row.name)"), y: .value("Index", row.value))
                .foregroundStyle(row.value >= 1 ? high : low)
        }
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel { Text(verbatim: value.as(String.self)?.split(separator: " ").last.map(String.init) ?? "") }
            }
        }
        .frame(height: 150)
    }
}

struct PanelAlertRow: View {
    let title: String
    let detail: String
    let date: Date
    let symbol: String
    let isGood: Bool
    let colors: [Color]

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(LinearGradient(colors: isGood ? colors : [Color.red.opacity(0.8), Color.orange], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 28, height: 28)
                .overlay { Image(systemName: symbol).font(.caption.weight(.semibold)).foregroundStyle(.white) }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title).font(.callout.weight(.medium))
                Text(verbatim: detail).font(.caption).foregroundStyle(.secondary)
                Text(date, format: .relative(presentation: .named)).font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
    }
}
