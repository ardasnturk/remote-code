// Ported from Vitrin for Mac (apps/VitrinMac/VitrinMac/Views/AscCommandShelf.swift).
import SwiftUI

/// What asc can do in one place, as app features rather than commands: each area (`AscAreas`) is a card that opens in
/// place. What only reads opens and loads by itself, what needs a choice first (a build, a group) asks for it right
/// there, and what changes something is a button with a short form. Nothing here shows a command line or JSON.
struct AscCommandShelf: View {
    var title: String
    var groups: [String]
    var prefill: [String: String] = [:]
    /// Closed by default: the page first shows what matters; the choice is remembered across pages.
    @AppStorage("ascShelfOpen") private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { withAnimation(.easeOut(duration: 0.15)) { open.toggle() } } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(.secondary).rotationEffect(.degrees(open ? 90 : 0))
                    Text(title).font(.callout.weight(.medium))
                    Text(L.t("asc.shelf.count").replacingOccurrences(of: "{n}", with: "\(groups.count)")).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("asc.shelf.toggle")
            if open {
                Text(L.t("asc.shelf.intro")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                ForEach(groups, id: \.self) { g in AscGroupCard(path: g, prefill: prefill) }
            }
        }
    }
}

/// One area, closed until asked for: a page with many areas stays short and asks nothing of App Store Connect.
private struct AscGroupCard: View {
    var path: String
    var prefill: [String: String]
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { withAnimation(.easeOut(duration: 0.15)) { open.toggle() } } label: {
                HStack(spacing: 10) {
                    VitrinBadge(symbol: AscAreas.symbol(path), colors: BadgeColors.gray, size: 26)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 5) { Text(AscAreas.title(path)).font(.headline); InfoButton(key: "info.group.\(path)") }
                        Text(AscCatalog.counts(path)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary).rotationEffect(.degrees(open ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open { AscGroupBody(path: path, prefill: prefill) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .vitrinCard(padding: 12)
    }
}

/// A group's insides: its reads, its buttons, its subgroups.
struct AscGroupBody: View {
    var path: String
    var prefill: [String: String]

    var body: some View {
        // A leaf at the top (`asc status`) is its own only command.
        let children = AscCatalog.children(path)
        let items = children.isEmpty ? [AscCatalog.command(path)].compactMap { $0 } : children
        VStack(alignment: .leading, spacing: 6) {
            ForEach(items.filter { !$0.group && $0.read }) { c in AscReadRow(command: c, prefill: prefill) }
            let writes = items.filter { !$0.group && !$0.read }
            if !writes.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(writes) { c in AscWriteButton(command: c, prefill: prefill) }
                }
                .padding(.vertical, 2)
            }
            ForEach(items.filter(\.group)) { c in AscSubgroupRow(command: c, prefill: prefill) }
        }
    }
}

private struct AscSubgroupRow: View {
    var command: AscCommand
    var prefill: [String: String]
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { withAnimation(.easeOut(duration: 0.15)) { open.toggle() } } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(.tertiary).rotationEffect(.degrees(open ? 90 : 0)).frame(width: 12)
                    Text(command.title).font(.callout.weight(.medium))
                    Spacer()
                }
                .padding(.vertical, 3)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open { AscGroupBody(path: command.path, prefill: prefill).padding(.leading, 18) }
        }
    }
}

/// A read: opening it loads it; if it needs a choice, the choice comes first and loading follows by itself.
private struct AscReadRow: View {
    var command: AscCommand
    var prefill: [String: String]
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { withAnimation(.easeOut(duration: 0.15)) { open.toggle() } } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(.tertiary).rotationEffect(.degrees(open ? 90 : 0)).frame(width: 12)
                    Text(command.title).font(.callout)
                    Spacer()
                }
                .padding(.vertical, 3)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("asc.read.\(command.path)")
            if open { AscReadResult(command: command, prefill: prefill).padding(.leading, 18) }
        }
    }
}

/// The result of a read, with a picker for each thing it needs that the page does not know.
struct AscReadResult: View {
    var command: AscCommand
    var prefill: [String: String]
    @State private var chosen: [String: String] = [:]

    private var missing: [String] { command.needs.filter { (chosen[$0] ?? prefill[$0] ?? "").isEmpty } }

    private var args: [String] {
        var a = command.words
        for f in command.takes { if let v = prefill[f], !v.isEmpty { a += ["--\(f)", v] } }
        for f in command.needs { if let v = chosen[f] ?? prefill[f], !v.isEmpty, !command.takes.contains(f) { a += ["--\(f)", v] } }
        return a
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(command.needs.filter { (prefill[$0] ?? "").isEmpty }, id: \.self) { f in
                AscIDPicker(flag: f, command: command, prefill: prefill, selection: Binding(get: { chosen[f] ?? "" }, set: { chosen[f] = $0 }))
            }
            if missing.isEmpty {
                AscLoad(args: args) { doc, _ in AscDataView(doc: doc) }.id(args.joined(separator: " "))
            }
        }
    }
}

/// Picks the thing a command needs from the list it comes from (a build from the app's builds), by its name; a
/// free field when there is no such list.
struct AscIDPicker: View {
    var flag: String
    var command: AscCommand
    var prefill: [String: String]
    @Binding var selection: String
    @State private var options: [(id: String, label: String)]?

    var body: some View {
        HStack(spacing: 8) {
            if flag != "id" { Text(AscText.flag(flag)).font(.callout).foregroundStyle(.secondary) }
            if let options, !options.isEmpty {
                Picker("", selection: $selection) {
                    Text(L.t("asc.choose")).tag("")
                    ForEach(options, id: \.id) { o in Text(o.label).tag(o.id) }
                }
                .labelsHidden().frame(maxWidth: 380)
            } else if options == nil {
                ProgressView().controlSize(.small)
            } else {
                TextField("", text: $selection).textFieldStyle(.roundedBorder).frame(maxWidth: 380)
            }
            Spacer(minLength: 0)
        }
        .task {
            guard options == nil else { return }
            guard let source = AscCatalog.source(flag: flag, path: command.path) else { options = []; return }
            var a = source.words
            for f in source.takes { if let v = prefill[f], !v.isEmpty { a += ["--\(f)", v] } }
            guard let doc = try? await AscCLI.json(a), case .list(let rows) = AscDataView.shape(doc) else { options = []; return }
            options = rows.map { r in
                let s = AscRowList.summary(r)
                return (r.id, s.detail.isEmpty ? s.title : "\(s.title) · \(s.detail)")
            }
        }
    }
}

/// A change: a button that opens its short form.
struct AscWriteButton: View {
    var command: AscCommand
    var prefill: [String: String]
    var done: () -> Void = {}
    @State private var open = false

    var body: some View {
        Button { open = true } label: { Label(command.title, systemImage: AscCatalog.symbol(command)) }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(AscCatalog.isDestructive(command) ? .red : nil)
            .accessibilityIdentifier("asc.write.\(command.path)")
            .sheet(isPresented: $open) { AscCommandForm(command: command, prefill: prefill) { changed in open = false; if changed { done() } } }
    }
}

/// The form of a change: what its examples use comes first, the rest under "More options"; what the page knows is
/// filled in and hidden. One button applies it (a destructive one asks once more), and the answer shows in words.
struct AscCommandForm: View {
    var command: AscCommand
    var prefill: [String: String]
    var close: (_ changed: Bool) -> Void
    @State private var help: AscHelp?
    @State private var values: [String: String] = [:]
    @State private var switches: [String: Bool] = [:]
    @State private var running = false
    @State private var result: AscCLI.Result?
    @State private var failure: String?
    @State private var confirm = false
    @State private var pathField: PathField?
    @Environment(AppModel.self) private var app

    /// The field a path is being picked for, named by its flag.
    private struct PathField: Identifiable { var id: String }

    private static let hidden: Set<String> = ["output", "pretty", "help", "api-debug", "debug", "report", "report-file", "retry-log", "strict-auth", "profile", "read-only", "confirm", "paginate", "next", "limit", "fields", "include"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        VitrinBadge(symbol: AscCatalog.symbol(command), colors: AscCatalog.isDestructive(command) ? BadgeColors.alert : BadgeColors.brand, size: 34)
                        Text(command.title).font(.headline)
                    }
                }
                if let help {
                    form(help)
                } else if failure == nil {
                    Section { ProgressView() }
                }
                if let failure { Section { Text(failure).foregroundStyle(.red).font(.callout) } }
                if let r = result {
                    Section {
                        if r.ok {
                            Label(L.t("asc.action.done"), systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.callout)
                            if let j = r.json { AscDataView(doc: j) }
                        } else {
                            Label(r.errorLine, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).font(.callout).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                if result?.ok != true {
                    Section {
                        Button { if AscCatalog.isDestructive(command) { confirm = true } else { Task { await run() } } } label: {
                            HStack(spacing: 8) {
                                if running { ProgressView().tint(.white) }
                                Text(command.title)
                            }
                        }
                        .buttonStyle(VitrinGradientButtonStyle())
                        .disabled(running || help == nil)
                        .accessibilityIdentifier("asc.form.run")
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(result?.ok == true ? L.t("common.close") : L.t("common.cancel")) { close(result?.ok == true) }
                }
            }
            .interactiveDismissDisabled(running || result?.ok == true)
            .confirmationDialog(command.title, isPresented: $confirm, titleVisibility: .visible) {
                Button(command.title, role: .destructive) { Task { await run() } }
                Button(L.t("common.cancel"), role: .cancel) {}
            } message: { Text(L.t("asc.action.undoable")) }
            // A path an asc command takes is a path on the Mac, where asc runs.
            .sheet(item: $pathField) { f in
                if let mac = app.connection {
                    VitrinPathPicker(connection: mac, folders: f.id.contains("dir")) { values[f.id] = $0 }
                }
            }
        }
        .task {
            do {
                let h = try await AscHelp.load(command.words)
                help = h
                for f in h.flags { if let v = prefill[f.name], !v.isEmpty { values[f.name] = v } }
            } catch { failure = error.localizedDescription }
        }
    }

    private func flags(_ h: AscHelp) -> [AscHelp.Flag] {
        h.flags.filter { !Self.hidden.contains($0.name) && (prefill[$0.name] ?? "").isEmpty }
    }

    /// The flags the command's examples use: what a person normally fills in.
    private func mainNames(_ h: AscHelp) -> Set<String> {
        var names = Set<String>()
        let examples = h.details.components(separatedBy: "\n").filter { $0.contains("asc ") }
        for line in examples.prefix(2) {
            for m in line.matches(of: /--([a-z][a-z0-9-]*)/) { names.insert(String(m.1)) }
        }
        return names
    }

    @ViewBuilder private func form(_ h: AscHelp) -> some View {
        let all = flags(h)
        let main = mainNames(h)
        let first = all.filter { main.contains($0.name) || $0.required }
        let rest = all.filter { !first.contains($0) }
        Section {
            ForEach(first.isEmpty ? all : first) { f in field(f) }
            if all.isEmpty { Text(L.t("asc.action.ready")).font(.callout).foregroundStyle(.secondary) }
        }
        if !first.isEmpty && !rest.isEmpty {
            Section {
                DisclosureGroup(L.t("asc.moreOptions")) {
                    ForEach(rest) { f in field(f) }
                }
                .font(.callout)
            }
        }
    }

    @ViewBuilder private func field(_ f: AscHelp.Flag) -> some View {
        if f.isBool {
            Toggle(isOn: Binding(get: { switches[f.name] ?? (f.defaultValue == "true") }, set: { switches[f.name] = $0 })) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(AscText.flag(f.name)).font(.callout)
                    Text(hint(f)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        } else if let choices = AscCatalog.choices(f.summary) {
            Picker(selection: Binding(get: { values[f.name] ?? "" }, set: { values[f.name] = $0 })) {
                Text(f.defaultValue.map { AscText.value($0) } ?? L.t("asc.choose")).tag("")
                ForEach(choices, id: \.self) { c in Text(AscText.value(c)).tag(c) }
            } label: { Text(AscText.flag(f.name)).font(.callout) }
        } else if AscCatalog.source(flag: f.name, path: command.path) != nil, AscText.isID(f.name) {
            AscIDPicker(flag: f.name, command: command, prefill: prefill, selection: Binding(get: { values[f.name] ?? "" }, set: { values[f.name] = $0 }))
        } else {
            VStack(alignment: .leading, spacing: 3) {
                Text(AscText.flag(f.name)).font(.callout)
                HStack {
                    TextField("", text: Binding(get: { values[f.name] ?? "" }, set: { values[f.name] = $0 }))
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    if AscCatalog.takesPath(f.name) {
                        Button(L.t("asc.pickFile")) { pathField = PathField(id: f.name) }
                            .buttonStyle(.bordered).controlSize(.small).disabled(app.connection == nil)
                    }
                }
                Text(hint(f)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
    }

    private func hint(_ f: AscHelp.Flag) -> String {
        f.summary.replacingOccurrences(of: #"\s*\(default: [^)]*\)\s*$"#, with: "", options: .regularExpression)
    }

    private func arguments(_ h: AscHelp) -> [String] {
        var a = command.words
        for f in h.flags {
            if f.isBool {
                if let on = switches[f.name], on != (f.defaultValue == "true") { a.append("--\(f.name)=\(on)") }
            } else if let v = values[f.name]?.trimmingCharacters(in: .whitespaces), !v.isEmpty {
                a += ["--\(f.name)", v]
            }
        }
        // asc asks for --confirm on its own destructive commands; the form's button is the user's confirmation.
        if h.flags.contains(where: { $0.name == "confirm" }) { a.append("--confirm") }
        return a
    }

    private func run() async {
        guard let help else { return }
        running = true
        defer { running = false }
        var args = arguments(help)
        if help.flags.contains(where: { $0.name == "output" }) { args += ["--output", "json"] }
        do { result = try await AscCLI.run(args, readOnly: false, timeout: 600) } catch { failure = error.localizedDescription }
    }
}

/// Which asc command groups belong where. Every group asc lists appears in exactly one place, except the local
/// tooling the app does for you or that needs a terminal (`AscAreas.notInApp`).
enum AscAreas {
    // An app's tabs
    static let release = ["versions", "review", "submit", "release", "release-notes", "publish", "validate", "status"]
    static let listing = ["localizations", "metadata", "categories", "age-rating", "accessibility", "encryption", "eula", "app-tags", "app-setup", "apps"]
    static let visuals = ["screenshots", "video-previews", "product-pages", "app-events", "asset-library"]
    static let builds = ["builds", "build-localizations", "build-bundles"]
    static let testflight = ["testflight"]
    static let reviews = ["reviews"]
    static let money = ["pricing", "pre-orders", "iap", "subscriptions", "storekit"]
    static let analytics = ["analytics", "insights", "performance"]
    static let more = ["app-clips", "game-center", "background-assets", "marketplace", "alternative-distribution", "routing-coverage", "android-ios-mapping", "nominations"]
    // Team pages
    static let users = ["users", "actors", "sandbox"]
    static let devices = ["devices"]
    static let signing = ["certificates", "profiles", "bundle-ids", "signing", "merchant-ids", "pass-type-ids", "notarization"]
    static let reports = ["finance", "optimize"]
    static let automation = ["xcode-cloud", "webhooks", "workflow", "notify"]
    static let ads = ["ads"]
    static let account = ["account", "agreements", "system-status"]
    /// Done by the app itself or only meaningful in a terminal: sign-in, docs, local Xcode builds, raw API and
    /// schema access, shell completion, telemetry.
    static let notInApp = ["auth", "doctor", "install-skills", "init", "docs", "web", "xcode", "distribute", "ipa-info", "pkg-info", "migrate", "diff", "capabilities", "search", "snitch", "version", "completion", "schema", "api", "telemetry"]

    @MainActor static func title(_ g: String) -> String {
        let key = "ascgroup.\(g)"
        let t = L.t(key)
        return t == key ? g.replacingOccurrences(of: "-", with: " ").capitalized : t
    }

    static func symbol(_ g: String) -> String {
        switch g {
        case "versions", "release", "publish": return "shippingbox.fill"
        case "review", "submit", "validate": return "checkmark.seal.fill"
        case "localizations", "metadata": return "text.alignleft"
        case "screenshots", "asset-library": return "photo.fill"
        case "video-previews": return "play.rectangle.fill"
        case "product-pages", "app-events": return "rectangle.stack.fill"
        case "builds", "build-localizations", "build-bundles": return "hammer.fill"
        case "testflight", "sandbox": return "airplane"
        case "reviews": return "star.bubble.fill"
        case "pricing", "pre-orders", "iap", "subscriptions", "storekit", "finance": return "creditcard.fill"
        case "analytics", "insights", "performance", "optimize": return "chart.xyaxis.line"
        case "users", "actors": return "person.2.fill"
        case "devices": return "iphone.gen3"
        case "certificates", "profiles", "bundle-ids", "signing", "merchant-ids", "pass-type-ids", "notarization": return "lock.shield.fill"
        case "xcode-cloud", "webhooks", "workflow", "notify": return "gearshape.2.fill"
        case "ads": return "megaphone.fill"
        default: return "square.grid.2x2.fill"
        }
    }

    /// asc's summaries end with a period and start with a verb ("List App Store versions."): shown as they are,
    /// without the period.
    static func sentence(_ summary: String, fallback: String) -> String {
        let s = summary.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return fallback }
        return s.hasSuffix(".") ? String(s.dropLast()) : s
    }
}
