// The form parts of Vitrin Studio's editors (packages/studio/src/ui.tsx, store.tsx), one column for a phone.
import Observation
import SwiftUI

/// One editable file, as the Studio's `useFile` keeps it: JSON parsed into an open dictionary, so a save writes back
/// every key the form does not know. What Claude or a stage wrote replaces it, unless the user is mid-edit.
@MainActor @Observable final class StudioFile {
    private(set) var path: String?
    private(set) var loading = true
    private(set) var exists = false
    private(set) var readOnly = false
    private(set) var text = ""
    private(set) var data: [String: Any]?
    private(set) var dirty = false
    private(set) var saving = false
    private(set) var error: String?
    private(set) var issues: [String] = []
    private let json: Bool
    private var loaded = false

    init(json: Bool = true) {
        self.json = json
    }

    /// Loads `path`, or picks up what changed on disk when it is already open.
    func open(_ path: String, session: ProjectSession) async {
        if path != self.path {
            self.path = path
            loaded = false
            loading = true
            exists = false
            readOnly = false
            text = ""
            data = nil
            dirty = false
            error = nil
            issues = []
        }
        if !dirty { await reload(session) }
    }

    func reload(_ session: ProjectSession) async {
        guard let path else { return }
        defer { if path == self.path { loading = false } }
        do {
            let f = try await session.readFile(path)
            // The user may have typed, or moved on to another file, while this was on its way.
            guard path == self.path, !dirty else { return }
            exists = f.exists
            readOnly = f.readOnly
            text = f.text
            data = nil
            error = nil
            if json, !f.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { parse(f.text) }
            issues = []
            loaded = true
        } catch {
            if ProjectSession.isCancellation(error) { return }
            if path == self.path { self.error = error.localizedDescription }
        }
    }

    private func parse(_ text: String) {
        do {
            data = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
            error = nil
        } catch {
            data = nil
            self.error = L.t("studio.invalidJSON").replacingOccurrences(of: "{error}", with: error.localizedDescription)
        }
    }

    func setData(_ next: [String: Any]) {
        let written = Self.pretty(next)
        // A text field writes its value back when it gets the focus: that is no edit.
        if let data, Self.pretty(data) == written { return }
        data = next
        text = written
        dirty = true
    }

    /// The raw editor: the form follows as long as the text parses.
    func setText(_ next: String) {
        text = next
        if json { parse(next) }
        dirty = true
    }

    @discardableResult func save(_ session: ProjectSession) async -> Bool {
        guard let path else { return false }
        saving = true
        defer { saving = false }
        do {
            try await session.client.save(path, text: text)
            dirty = false
            exists = true
            issues = []
            error = nil
            session.toast(L.t("toast.saved"), .ok)
            return true
        } catch {
            if ProjectSession.isCancellation(error) { return false }
            let e = error as? StudioAPIError
            self.error = e?.message ?? error.localizedDescription
            issues = e?.issues ?? []
            session.toast(self.error ?? "", .error)
            return false
        }
    }

    /// Back to what is on disk.
    func revert(_ session: ProjectSession) async {
        dirty = false
        await reload(session)
    }

    static func pretty(_ value: Any) -> String {
        guard JSONSerialization.isValidJSONObject(value), let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) else { return "" }
        return String(decoding: data, as: UTF8.self) + "\n"
    }
}

extension View {
    /// Keeps a `StudioFile` on `path` and current with what changes under metadata/.
    func studioFile(_ file: StudioFile, path: String, session: ProjectSession) -> some View {
        task(id: "\(path)|\(session.changedTick)") {
            guard !path.isEmpty else { return }
            await file.open(path, session: session)
        }
    }
}

/// Reading the open JSON the editors work on.
extension Dictionary where Key == String, Value == Any {
    func str(_ key: String) -> String { self[key] as? String ?? "" }
    func strings(_ key: String) -> [String] { self[key] as? [String] ?? [] }
    func object(_ key: String) -> [String: Any] { self[key] as? [String: Any] ?? [:] }
    func objects(_ key: String) -> [[String: Any]] { self[key] as? [[String: Any]] ?? [] }
    func flag(_ key: String) -> Bool { self[key] as? Bool ?? false }
    func number(_ key: String) -> Double? { (self[key] as? NSNumber)?.doubleValue }
}

/// A sheet's subject: a file to edit or a generated page to look at.
struct StudioSheetFile: Identifiable {
    var path: String
    var json = false
    var id: String { path }
}

/// A label, its control and a hint under it.
struct StudioField<Content: View>: View {
    var label: String
    var hint: String? = nil
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: label).font(.callout.weight(.medium))
            content
            if let hint { Text(verbatim: hint).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One line or several of text, with an App Store Connect counter when the field has a limit.
struct StudioTextField: View {
    var label: String
    @Binding var text: String
    var hint: String? = nil
    var placeholder = ""
    var mono = false
    var multiline = false
    var minHeight: CGFloat = 90
    var max: Int? = nil
    var bytes = false
    var identifier: String? = nil

    private var used: Int { bytes ? text.utf8.count : text.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(verbatim: label).font(.callout.weight(.medium))
                Spacer()
                if let max {
                    Text(verbatim: "\(used) / \(max)\(bytes ? " B" : "")").font(.caption.monospacedDigit())
                        .foregroundStyle(used > max ? .red : used > Int(Double(max) * 0.9) ? .orange : .secondary)
                }
            }
            field
            if let hint { Text(verbatim: hint).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        }
    }

    @ViewBuilder private var field: some View {
        if multiline {
            TextEditor(text: $text)
                .font(mono ? .callout.monospaced() : .body)
                .frame(minHeight: minHeight)
                .scrollContentBackground(.hidden).padding(6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(.tertiarySystemFill)))
                .autocorrectionDisabled(mono)
                .textInputAutocapitalization(mono ? .never : nil)
                .accessibilityIdentifier(identifier ?? label)
        } else {
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .font(mono ? .body.monospaced() : .body)
                .autocorrectionDisabled(mono)
                .textInputAutocapitalization(mono ? .never : nil)
                .accessibilityIdentifier(identifier ?? label)
        }
    }
}

/// A choice from a list, with an empty choice when the field can stay unset. A value the list doesn't know stays shown.
struct StudioPicker: View {
    struct Option: Hashable {
        var value: String
        var label: String
    }
    var label: String
    var value: String
    var options: [Option]
    var empty: String? = nil
    var hint: String? = nil
    var onChange: (String) -> Void

    init(_ label: String, value: String, options: [String], empty: String? = nil, hint: String? = nil, onChange: @escaping (String) -> Void) {
        self.label = label
        self.value = value
        self.options = options.map { Option(value: $0, label: $0) }
        self.empty = empty
        self.hint = hint
        self.onChange = onChange
    }

    init(_ label: String, value: String, labeled options: [Option], empty: String? = nil, hint: String? = nil, onChange: @escaping (String) -> Void) {
        self.label = label
        self.value = value
        self.options = options
        self.empty = empty
        self.hint = hint
        self.onChange = onChange
    }

    private var all: [Option] {
        var list = options
        if let empty { list.insert(Option(value: "", label: empty), at: 0) }
        if !list.contains(where: { $0.value == value }) { list.append(Option(value: value, label: value)) }
        return list
    }

    var body: some View {
        StudioField(label: label, hint: hint) {
            Menu {
                Picker(selection: Binding(get: { value }, set: { onChange($0) })) {
                    ForEach(all, id: \.self) { Text(verbatim: $0.label).tag($0.value) }
                } label: { EmptyView() }
            } label: {
                HStack {
                    Text(verbatim: all.first { $0.value == value }?.label ?? value).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(.secondary)
                }
                .font(.callout)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(.tertiarySystemFill)))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("picker.\(label)")
        }
    }
}

/// A box that ticks; the row is the button.
struct StudioCheckRow<Label: View>: View {
    var on: Bool
    var action: (Bool) -> Void
    @ViewBuilder var label: Label
    var body: some View {
        Button { action(!on) } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: on ? "checkmark.square.fill" : "square").foregroundStyle(on ? Color.accentColor : .secondary)
                label.frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// One choice of several, and under it what the choice means.
struct StudioRadioRow: View {
    var title: String
    var hint: String?
    var on: Bool
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: on ? "largecircle.fill.circle" : "circle").foregroundStyle(on ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: title).font(.callout)
                    if let hint { Text(verbatim: hint).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// A comma-separated list in one field (ids, colors). Each edit counts at once: a phone has no blur to wait for.
struct StudioListField: View {
    var value: [String]
    var placeholder = ""
    var onChange: ([String]) -> Void
    @State private var text = ""

    private func parse(_ s: String) -> [String] {
        s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.roundedBorder)
            .font(.callout)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .onAppear { text = value.joined(separator: ", ") }
            .onChange(of: value) { if parse(text) != value { text = value.joined(separator: ", ") } }
            .onChange(of: text) { if parse(text) != value { onChange(parse(text)) } }
    }
}

/// Seconds, in the decimal mark of the keyboard showing.
struct StudioNumberField: View {
    var label: String
    var value: Double
    var onChange: (Double) -> Void
    @State private var text = ""

    private func parse(_ s: String) -> Double? { Double(s.replacingOccurrences(of: ",", with: ".")) }
    private var shown: String { VitrinJSON.number(value).display }

    var body: some View {
        StudioField(label: label) {
            TextField("", text: $text)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.decimalPad)
                .font(.callout.monospaced())
                .accessibilityIdentifier(label)
                .onAppear { text = shown }
                .onChange(of: value) { if parse(text) != value { text = shown } }
                .onChange(of: text) { if let n = parse(text), n != value { onChange(n) } }
        }
    }
}

/// The form or the raw JSON behind it.
struct StudioModeToggle: View {
    @Binding var json: Bool
    var body: some View {
        CapsuleTabs(items: [false, true], selection: $json, title: { $0 ? "JSON" : L.t("studio.form") }).frame(width: 136)
    }
}

/// The schema issues the server answered a save with, and any other trouble with the file.
struct StudioFileIssues: View {
    var file: StudioFile
    var body: some View {
        if let error = file.error { Text(verbatim: error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true).textSelection(.enabled) }
        ForEach(file.issues, id: \.self) { issue in
            Label { Text(verbatim: issue).textSelection(.enabled) } icon: { Image(systemName: "xmark.octagon.fill").foregroundStyle(.red) }.font(.caption)
        }
    }
}

/// Save, its state and what went wrong.
struct StudioSaveBar: View {
    var file: StudioFile
    var session: ProjectSession
    var identifier: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Button(file.saving ? L.t("common.saving") : L.t("common.save")) { Task { await file.save(session) } }
                    .buttonStyle(.borderedProminent)
                    .disabled(!file.dirty || file.saving || file.readOnly)
                    .accessibilityIdentifier(identifier)
                if file.dirty { Text(L.t("listing.unsaved")).font(.caption).foregroundStyle(.secondary) }
                if file.readOnly { Pill(L.t("studio.readOnly")) }
            }
            StudioFileIssues(file: file)
        }
    }
}

/// A file as text: JSON the server re-indents on save, or HTML as written.
struct StudioCodeEditor: View {
    var file: StudioFile
    var session: ProjectSession
    var identifier: String
    var minHeight: CGFloat = 360
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: Binding(get: { file.text }, set: { file.setText($0) }))
                .font(.caption.monospaced())
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .frame(minHeight: minHeight)
                .scrollContentBackground(.hidden).padding(6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(.tertiarySystemFill)))
                .disabled(file.readOnly)
                .accessibilityIdentifier("\(identifier).text")
            StudioSaveBar(file: file, session: session, identifier: identifier)
        }
    }
}

/// One file in a sheet: an HTML screen, or a language's strings.
struct StudioFileSheet: View {
    var path: String
    var json: Bool
    var session: ProjectSession
    @State private var file: StudioFile
    @Environment(\.dismiss) private var dismiss

    init(path: String, json: Bool, session: ProjectSession) {
        self.path = path
        self.json = json
        self.session = session
        _file = State(initialValue: StudioFile(json: json))
    }

    var body: some View {
        NavigationStack {
            Group {
                if file.loading {
                    ProgressView()
                } else {
                    StudioCodeEditor(file: file, session: session, identifier: "file.save", minHeight: 300).padding(12)
                }
            }
            .navigationTitle(Text(verbatim: (path as NSString).lastPathComponent))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.t("common.close")) { dismiss() }.accessibilityIdentifier("file.close")
                }
            }
        }
        .studioFile(file, path: path, session: session)
        .interactiveDismissDisabled(file.dirty)
    }
}

/// A page Vitrin generated (the store preview, the mockups gallery), behind a button because it is a web view.
struct StudioDocumentSheet: View {
    var client: StudioClient
    var path: String
    var title: String
    var bust: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            StudioDocumentView(client: client, path: path, bust: bust)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(Text(verbatim: title))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L.t("common.close")) { dismiss() }.accessibilityIdentifier("document.close")
                    }
                }
        }
    }
}

/// Pictures and videos in a row that scrolls sideways: a tap opens one in full.
struct MediaStrip: View {
    var client: StudioClient
    var files: [RenderedFile]
    var bust: String?
    var width: CGFloat = 160
    var height: CGFloat = 280
    var open: (RenderedFile) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 10) {
                ForEach(files) { f in
                    Button { open(f) } label: { MediaThumb(client: client, file: f, bust: bust, height: height).frame(width: width) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("media.\(f.name)")
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
