// Ported from Vitrin for Mac (apps/VitrinMac/VitrinMac/Views/AscMoneySections.swift).
import SwiftUI

/// `iap pricing summary` / `subscriptions pricing summary`: each product with its price and what you keep.
struct PriceList: View {
    var title: String
    var args: [String]
    var key: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle(title, info: "info." + args.prefix(3).joined(separator: "."))
            AscLoad(args: args) { doc, _ in
                let items = (doc.objectValue?[key]?.arrayValue ?? []).compactMap(\.objectValue)
                if items.isEmpty {
                    AscDataView(doc: .array([]))
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.offset) { i, p in
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(p["name"]?.stringValue ?? p["productId"]?.stringValue ?? "").font(.callout.weight(.medium)).lineLimit(1)
                                    Text([p["type"]?.stringValue.map { AscText.value($0) }, p["subscriptionPeriod"]?.stringValue.map { AscText.value($0) }, p["productId"]?.stringValue].compactMap { $0 }.joined(separator: " · "))
                                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 1) {
                                    Text(Self.money(p["currentPrice"])).font(.callout.weight(.semibold).monospacedDigit())
                                    Text(L.t("asc.money.keep").replacingOccurrences(of: "{amount}", with: Self.money(p["estimatedProceeds"] ?? p["proceeds"]))).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            if i < items.count - 1 { Divider().opacity(0.4) }
                        }
                    }
                    .vitrinCard(padding: 4)
                }
            }
        }
    }

    static func money(_ v: VitrinJSON?) -> String {
        guard let o = v?.objectValue, let a = o["amount"]?.display, !a.isEmpty else { return "—" }
        return "\(a) \(o["currency"]?.display ?? "")"
    }
}
