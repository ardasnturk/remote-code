// Ported from Vitrin for Mac (apps/VitrinMac/VitrinMac/Views/AscDataView.swift).
import SwiftUI

/// Any asc result as a page, never as JSON: a list of resources as rows that open in place, one resource as a card,
/// a report as sections. Field names, languages, countries, enum values, dates and sizes come through `AscText`;
/// ids, links and relationships stay out of sight.
struct AscDataView: View {
    var doc: VitrinJSON
    var empty: String? = nil

    var body: some View {
        switch Self.shape(doc) {
        case .list(let rows):
            if rows.isEmpty { emptyCard } else { AscRowList(rows: rows) }
        case .one(let row):
            if row.fields.isEmpty || row.id.isEmpty && row.fields.count <= 1 { emptyCard } else { AscFields(fields: row.fields).vitrinCard(padding: 14) }
        case .report(let object):
            AscReport(object: object)
        case .text(let s):
            Text(s).font(.callout).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).vitrinCard(padding: 14)
        case .nothing:
            emptyCard
        }
    }

    private var emptyCard: some View {
        Label(empty ?? L.t("asc.empty"), systemImage: "tray").font(.callout).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading).vitrinCard(padding: 14)
    }

    struct Row: Identifiable {
        var id: String
        var fields: [(key: String, value: VitrinJSON)]
    }

    enum Shape {
        case list([Row])
        case one(Row)
        case report([String: VitrinJSON])
        case text(String)
        case nothing
    }

    private static let hidden: Set<String> = ["links", "relationships", "meta", "included", "type"]

    static func shape(_ doc: VitrinJSON) -> Shape {
        switch doc {
        case .array(let a):
            if a.allSatisfy({ $0.objectValue != nil }) { return .list(a.enumerated().compactMap { row($0.element, index: $0.offset) }) }
            return .text(a.map(\.display).joined(separator: "\n"))
        case .object(let o):
            if let data = o["data"] {
                if let a = data.arrayValue { return shape(.array(a)) }
                if data.objectValue != nil, let r = row(data, index: 0) { return .one(r) }
                if case .null = data { return .nothing }
            }
            return .report(o)
        case .null: return .nothing
        default: return .text(doc.display)
        }
    }

    /// A JSON:API resource (its attributes) or a plain object, in a useful order; no ids unless there is nothing else.
    static func row(_ v: VitrinJSON, index: Int) -> Row? {
        guard let o = v.objectValue else { return nil }
        let attrs = o["attributes"]?.objectValue ?? o.filter { !hidden.contains($0.key) && $0.key != "id" }
        var fields = attrs.map { (key: $0.key, value: $0.value) }.filter { !isBlank($0.value) }
        fields.sort { rank($0.key) != rank($1.key) ? rank($0.key) < rank($1.key) : $0.key < $1.key }
        if fields.isEmpty, let id = o["id"]?.stringValue, !id.isEmpty { fields = [(key: "id", value: .string(id))] }
        return Row(id: o["id"]?.stringValue ?? "\(index)", fields: fields)
    }

    static func isBlank(_ v: VitrinJSON) -> Bool {
        switch v {
        case .null: return true
        case .string(let s): return s.isEmpty
        case .array(let a): return a.isEmpty
        case .object(let o): return o.isEmpty
        default: return false
        }
    }

    private static let titles = ["name", "title", "displayName", "referenceName", "firstName", "versionString", "version", "locale", "productId", "identifier",
                                 "email", "username", "reviewerNickname", "deviceModel", "territory", "fileName", "comment", "description"]
    private static func rank(_ key: String) -> Int { titles.firstIndex(of: key) ?? (AscText.isStateKey(key) ? 100 : 200) }
}

/// The search field of a list long enough to need one. It filters what the page already has, so it needs no request.
struct AscListSearch: View {
    /// Shorter lists are read at a glance.
    static let threshold = 6
    @Binding var text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(L.t("search.list"), text: $text)
                .textInputAutocapitalization(.never).autocorrectionDisabled().submitLabel(.search)
                .accessibilityIdentifier("asc.listSearch")
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// Rows of resources: image, title, two details, state; a row opens to all of its fields.
struct AscRowList: View {
    var rows: [AscDataView.Row]
    @State private var open: String?
    private static let pageSize = 50
    @State private var shown = pageSize
    @State private var query = ""

    var body: some View {
        let rows = self.rows.filter { Self.matches($0, query) }
        VStack(spacing: 0) {
            if self.rows.count > AscListSearch.threshold { AscListSearch(text: $query).padding(6) }
            if rows.isEmpty { Text(L.t("search.noResults")).font(.callout).foregroundStyle(.secondary).padding(10) }
            ForEach(Array(rows.prefix(shown).enumerated()), id: \.element.id) { i, r in
                row(r)
                if i < min(shown, rows.count) - 1 { Divider().opacity(0.4) }
            }
            if rows.count > shown {
                Button(L.t("asc.showMore").replacingOccurrences(of: "{n}", with: "\(rows.count - shown)")) { shown += Self.pageSize }
                    .buttonStyle(.borderless).padding(10)
            }
        }
        .vitrinCard(padding: 4)
    }

    @ViewBuilder private func row(_ r: AscDataView.Row) -> some View {
        let summary = Self.summary(r)
        VStack(alignment: .leading, spacing: 0) {
            Button { withAnimation(.easeOut(duration: 0.15)) { open = open == r.id ? nil : r.id } } label: {
                HStack(spacing: 10) {
                    if let u = summary.image { RemoteThumb(url: u, size: 34) }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(summary.title).font(.callout.weight(.medium)).lineLimit(1)
                        if !summary.detail.isEmpty { Text(summary.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                    }
                    Spacer(minLength: 8)
                    if let s = summary.state { Pill(s.0, s.1).lineLimit(1) }
                    Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary).rotationEffect(.degrees(open == r.id ? 90 : 0))
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open == r.id {
                AscFields(fields: r.fields).padding(.horizontal, 10).padding(.bottom, 10)
            }
        }
    }

    /// Any field of the row, in the words the page shows it.
    @MainActor static func matches(_ r: AscDataView.Row, _ query: String) -> Bool {
        query.isEmpty || r.fields.contains { AscText.plain($0.key, $0.value).matches(search: query) }
    }

    struct Summary {
        var title: String
        var detail: String
        var image: URL?
        var state: (String, Tone)?
    }

    /// The row's face: the first name-like field, the first state, the first image, two more short fields.
    @MainActor static func summary(_ r: AscDataView.Row) -> Summary {
        var title: String?
        var state: (String, Tone)?
        var image: URL?
        var details: [String] = []
        for (k, v) in r.fields {
            let s = AscText.shown(k, v)
            if case .image(let u) = s, image == nil { image = u; continue }
            if case .state(let t, let tone) = s { if state == nil { state = (t, tone) }; continue }
            if case .flag = s { continue }
            let text = AscText.plain(k, v)
            guard !text.isEmpty else { continue }
            if title == nil { title = text; continue }
            if details.count < 2, text.count <= 48 { details.append(text) }
        }
        return Summary(title: title ?? state?.0 ?? r.id, detail: details.joined(separator: " · "), image: image, state: title == nil ? nil : state)
    }
}

/// A resource's fields, label over value in a grid; long text gets a whole line, images show.
struct AscFields: View {
    var fields: [(key: String, value: VitrinJSON)]

    var body: some View {
        let shown = fields.map { (key: $0.key, value: $0.value, show: AscText.shown($0.key, $0.value)) }
        let short = shown.filter { !isLong($0.show) && $0.show != .none }
        let nested = shown.filter { $0.show == .none && !AscDataView.isBlank($0.value) }
        VStack(alignment: .leading, spacing: 10) {
            if !short.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14, alignment: .topLeading)], alignment: .leading, spacing: 10) {
                    ForEach(short, id: \.key) { f in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(AscText.field(f.key)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            AscValue(show: f.show)
                        }
                    }
                }
            }
            ForEach(shown.filter { isLong($0.show) }, id: \.key) { f in
                VStack(alignment: .leading, spacing: 2) {
                    Text(AscText.field(f.key)).font(.caption).foregroundStyle(.secondary)
                    AscValue(show: f.show)
                }
            }
            ForEach(nested, id: \.key) { f in
                VStack(alignment: .leading, spacing: 4) {
                    Text(AscText.field(f.key)).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    AscNested(value: f.value)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func isLong(_ s: AscText.Shown) -> Bool {
        if case .text(let t) = s { return t.count > 60 }
        return false
    }
}

/// One shown value.
struct AscValue: View {
    var show: AscText.Shown
    var body: some View {
        switch show {
        case .none: Text(verbatim: "—").foregroundStyle(.secondary)
        case .text(let t): Text(t).font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        case .state(let t, let tone): Pill(t, tone).lineLimit(1)
        case .flag(let b): Label(L.t(b ? "common.yes" : "common.no"), systemImage: b ? "checkmark.circle.fill" : "circle").font(.callout).foregroundStyle(b ? .green : .secondary)
        case .image(let u): RemoteThumb(url: u, size: 64)
        case .link(let u, let t): Link(t, destination: u).font(.callout).lineLimit(1)
        }
    }
}

/// An object or a list inside a value.
struct AscNested: View {
    var value: VitrinJSON
    var body: some View {
        switch value {
        case .object(let o):
            AscFields(fields: o.sorted { $0.key < $1.key }.filter { !AscDataView.isBlank($0.value) && $0.key != "links" }.map { (key: $0.key, value: $0.value) })
                .padding(10).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
        case .array(let a):
            AscRowList(rows: a.enumerated().compactMap { AscDataView.row($0.element, index: $0.offset) })
        default:
            EmptyView()
        }
    }
}

/// A report (`asc status`, `asc pricing current` …): its plain values on a card, each object or list under its own title.
struct AscReport: View {
    var object: [String: VitrinJSON]

    var body: some View {
        let keys = object.keys.sorted().filter { $0 != "links" && !AscDataView.isBlank(object[$0] ?? .null) }
        let scalars = keys.filter { k in if case .none = AscText.shown(k, object[k]!) { return false }; return true }
        let nested = keys.filter { !scalars.contains($0) }
        VStack(alignment: .leading, spacing: 12) {
            if !scalars.isEmpty { AscFields(fields: scalars.map { (key: $0, value: object[$0]!) }).vitrinCard(padding: 14) }
            ForEach(nested, id: \.self) { k in
                VStack(alignment: .leading, spacing: 6) {
                    SectionTitle(AscText.field(k))
                    AscNested(value: object[k]!)
                }
            }
        }
    }
}

/// An image from Apple's CDN.
struct RemoteThumb: View {
    var url: URL
    var size: CGFloat
    var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image { image.resizable().scaledToFit() } else { RoundedRectangle(cornerRadius: 6).fill(.quaternary) }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}
