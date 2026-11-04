// Ported from Vitrin for Mac (apps/VitrinMac/VitrinMac/Views/AscActions.swift).
import SwiftUI

/// One asc command offered where it belongs (create a version, submit for review, invite a tester …): a title, one
/// sentence, the fields the user fills, and the arguments the page already knows (the app, the version).
struct AscAction: Identifiable {
    struct Field: Identifiable {
        enum Kind {
            case text(placeholder: String = "")
            case multiline
            case choice([(value: String, label: String)])
            case toggle
        }
        var flag: String
        var label: String
        var kind: Kind = .text()
        var required = false
        var initial = ""
        var hint: String?
        var id: String { flag }
    }
    var title: String
    var detail: String
    var symbol: String
    var colors: [Color] = BadgeColors.brand
    /// `["versions", "create"]`
    var command: [String]
    /// Arguments the page fills in: `["--app", id]`.
    var fixed: [String] = []
    var fields: [Field] = []
    /// asc refuses this command without `--confirm`; the sheet's button is the user's confirmation.
    var confirm = false
    /// Deletes, revokes, removes, releases: the button is red and says so.
    var destructive = false
    /// A read (validation, a report): runs with `--read-only` and needs no confirmation.
    var readOnly = false
    var id: String { command.joined(separator: " ") + title }
}

/// A button that opens an action's sheet.
struct AscActionButton: View {
    var action: AscAction
    var done: () -> Void = {}
    var prominent = false
    @State private var open = false
    var body: some View {
        Group {
            if prominent {
                Button { open = true } label: { Label(action.title, systemImage: action.symbol) }.buttonStyle(VitrinGradientButtonStyle(fullWidth: false))
            } else {
                Button { open = true } label: { Label(action.title, systemImage: action.symbol) }.buttonStyle(.bordered).tint(action.destructive ? .red : nil)
            }
        }
        .sheet(isPresented: $open) { AscActionSheet(action: action) { changed in open = false; if changed { done() } } }
    }
}

/// The sheet: fields, the exact command line, Run, and asc's answer.
struct AscActionSheet: View {
    var action: AscAction
    var close: (_ changed: Bool) -> Void
    @State private var values: [String: String] = [:]
    @State private var toggles: [String: Bool] = [:]
    @State private var running = false
    @State private var result: AscCLI.Result?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(alignment: .top, spacing: 12) {
                        VitrinBadge(symbol: action.symbol, colors: action.destructive ? BadgeColors.alert : action.colors, size: 36)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(action.title).font(.headline)
                            Text(action.detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                if !action.fields.isEmpty {
                    Section {
                        ForEach(action.fields) { f in field(f) }
                    }
                }
                if let r = result {
                    Section {
                        if let report = r.json?.objectValue, report["checks"] != nil { ReadinessReport(report: report) }
                        Label(r.ok ? L.t(action.readOnly ? "asc.action.read" : "asc.action.done") : r.errorLine, systemImage: r.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(r.ok ? .green : .red).font(.callout).fixedSize(horizontal: false, vertical: true)
                        if r.ok, r.json?.objectValue?["checks"] == nil, let j = r.json { AscDataView(doc: j) }
                    }
                }
                if let error { Section { Text(error).foregroundStyle(.red).font(.callout) } }
                if result?.ok != true {
                    Section {
                        Button { Task { await run() } } label: {
                            HStack(spacing: 8) {
                                if running { ProgressView().tint(.white) }
                                Text(action.readOnly ? L.t("asc.cmd.run") : action.title)
                            }
                        }
                        .buttonStyle(VitrinGradientButtonStyle())
                        .disabled(running || missingRequired)
                        .accessibilityIdentifier("asc.action.run")
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(result?.ok == true ? L.t("common.close") : L.t("common.cancel")) { close(result?.ok == true && !action.readOnly) }
                }
            }
            // A swipe would skip `close`, and the page would not read again after a change.
            .interactiveDismissDisabled(running || result?.ok == true)
        }
        .onAppear {
            for f in action.fields {
                switch f.kind {
                case .toggle: toggles[f.flag] = f.initial == "true"
                case .choice(let options) where f.required && f.initial.isEmpty: values[f.flag] = options.first?.value ?? ""
                default: values[f.flag] = f.initial
                }
            }
        }
    }

    private var missingRequired: Bool {
        action.fields.contains { f in
            guard f.required else { return false }
            if case .toggle = f.kind { return false }
            return (values[f.flag] ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    @ViewBuilder private func field(_ f: AscAction.Field) -> some View {
        switch f.kind {
        case .toggle:
            Toggle(isOn: Binding(get: { toggles[f.flag] ?? false }, set: { toggles[f.flag] = $0 })) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(f.label)
                    if let h = f.hint { Text(h).font(.caption).foregroundStyle(.secondary) }
                }
            }
        case .choice(let options):
            Picker(selection: Binding(get: { values[f.flag] ?? "" }, set: { values[f.flag] = $0 })) {
                if !f.required { Text(verbatim: "—").tag("") }
                ForEach(options, id: \.value) { Text($0.label).tag($0.value) }
            } label: { Text(f.label + (f.required ? " *" : "")) }
        case .multiline:
            VStack(alignment: .leading, spacing: 4) {
                Text(f.label + (f.required ? " *" : "")).font(.callout)
                TextEditor(text: Binding(get: { values[f.flag] ?? "" }, set: { values[f.flag] = $0 })).font(.callout).frame(minHeight: 90)
                    .scrollContentBackground(.hidden).padding(6).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                if let h = f.hint { Text(h).font(.caption).foregroundStyle(.secondary) }
            }
        case .text(let placeholder):
            VStack(alignment: .leading, spacing: 4) {
                Text(f.label + (f.required ? " *" : "")).font(.callout)
                TextField(placeholder, text: Binding(get: { values[f.flag] ?? "" }, set: { values[f.flag] = $0 }))
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                if let h = f.hint { Text(h).font(.caption).foregroundStyle(.secondary) }
            }
        }
    }

    private var arguments: [String] {
        var args = action.command + action.fixed
        for f in action.fields {
            if case .toggle = f.kind {
                if toggles[f.flag] == true { args.append("--\(f.flag)") }
            } else if let v = values[f.flag]?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty {
                args += ["--\(f.flag)", v]
            }
        }
        if action.confirm { args.append("--confirm") }
        return args + ["--output", "json"]
    }


    private func run() async {
        running = true
        defer { running = false }
        error = nil
        do { result = try await AscCLI.run(arguments, readOnly: action.readOnly, timeout: 900) } catch { self.error = error.localizedDescription }
    }
}

/// A titled row of action buttons inside a glass card.
struct ActionBar<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(title)
            FlowLayout(spacing: 8) { content }
        }
        .vitrinCard(padding: 14)
    }
}

// MARK: the catalogue of actions, by place

@MainActor enum AscActions {
    static let platforms: [(value: String, label: String)] = [("IOS", "iOS"), ("MAC_OS", "macOS"), ("TV_OS", "tvOS"), ("VISION_OS", "visionOS")]
    static let releaseTypes: [(value: String, label: String)] = [("AFTER_APPROVAL", "After approval"), ("MANUAL", "Manual"), ("SCHEDULED", "Scheduled")]

    static func requestAnalytics(app: String) -> AscAction {
        AscAction(title: L.t("act.requestAnalytics"), detail: L.t("act.requestAnalytics.detail"), symbol: "chart.xyaxis.line", colors: BadgeColors.deep, command: ["analytics", "request"], fixed: ["--app", app, "--access-type", "ONGOING", "--reuse-existing"])
    }

    // Release
    static func reviewDetails(id: String, item: [String: VitrinJSON]) -> AscAction {
        AscAction(title: L.t("act.reviewDetails"), detail: L.t("act.reviewDetails.detail"), symbol: "pencil", command: ["review", "details-update"], fixed: ["--id", id], fields: [
            .init(flag: "contact-first-name", label: AscText.field("contactFirstName"), initial: JSONAPI.text(item, "contactFirstName")),
            .init(flag: "contact-last-name", label: AscText.field("contactLastName"), initial: JSONAPI.text(item, "contactLastName")),
            .init(flag: "contact-email", label: AscText.field("contactEmail"), initial: JSONAPI.text(item, "contactEmail")),
            .init(flag: "contact-phone", label: AscText.field("contactPhone"), initial: JSONAPI.text(item, "contactPhone")),
            .init(flag: "notes", label: AscText.field("notes"), kind: .multiline, initial: JSONAPI.text(item, "notes")),
        ])
    }
    static func createVersion(app: String) -> AscAction {
        AscAction(title: L.t("act.createVersion"), detail: L.t("act.createVersion.detail"), symbol: "plus.square.on.square", command: ["versions", "create"], fixed: ["--app", app], fields: [
            .init(flag: "version", label: L.t("asc.field.version"), kind: .text(placeholder: "1.1.0"), required: true),
            .init(flag: "platform", label: L.t("asc.field.platform"), kind: .choice(platforms), required: true, initial: "IOS"),
            .init(flag: "copy-metadata-from", label: L.t("act.copyFrom"), kind: .text(placeholder: "1.0.0"), hint: L.t("act.copyFrom.hint")),
            .init(flag: "copyright", label: L.t("act.copyright"), kind: .text(placeholder: "2026 JASTech")),
            .init(flag: "release-type", label: L.t("act.releaseType"), kind: .choice(releaseTypes)),
        ])
    }
    static func attachBuild(versionID: String, app: String) -> AscAction {
        AscAction(title: L.t("act.attachBuild"), detail: L.t("act.attachBuild.detail"), symbol: "shippingbox.and.arrow.backward", colors: BadgeColors.deep, command: ["versions", "attach-build"], fixed: ["--version-id", versionID, "--app", app], fields: [
            .init(flag: "build-number", label: L.t("asc.field.buildNumber"), kind: .text(placeholder: "42"), hint: L.t("act.attachBuild.hint")),
            .init(flag: "latest", label: L.t("act.latestBuild"), kind: .toggle, initial: "true"),
        ])
    }
    static func validate(app: String, versionID: String?) -> AscAction {
        AscAction(title: L.t("act.validate"), detail: L.t("act.validate.detail"), symbol: "checklist", colors: BadgeColors.fresh, command: ["validate"], fixed: ["--app", app] + (versionID.map { ["--version-id", $0] } ?? []), fields: [
            .init(flag: "check-urls", label: L.t("act.checkUrls"), kind: .toggle),
        ], readOnly: true)
    }
    static func submit(app: String, versionID: String) -> AscAction {
        AscAction(title: L.t("act.submit"), detail: L.t("act.submit.detail"), symbol: "paperplane.fill", colors: BadgeColors.fresh, command: ["review", "submit"], fixed: ["--app", app, "--version-id", versionID], fields: [
            .init(flag: "latest", label: L.t("act.latestBuild"), kind: .toggle, hint: L.t("act.submit.latestHint")),
            .init(flag: "build-number", label: L.t("asc.field.buildNumber"), kind: .text(placeholder: "42")),
        ], confirm: true)
    }
    static func cancelSubmission(app: String, versionID: String) -> AscAction {
        AscAction(title: L.t("act.cancelSubmission"), detail: L.t("act.cancelSubmission.detail"), symbol: "xmark.circle", command: ["submit", "cancel"], fixed: ["--app", app, "--version-id", versionID], confirm: true, destructive: true)
    }
    static func release(versionID: String) -> AscAction {
        AscAction(title: L.t("act.release"), detail: L.t("act.release.detail"), symbol: "flag.checkered", colors: BadgeColors.fresh, command: ["versions", "release"], fixed: ["--version-id", versionID], confirm: true)
    }
    static func updateVersion(versionID: String) -> AscAction {
        AscAction(title: L.t("act.updateVersion"), detail: L.t("act.updateVersion.detail"), symbol: "slider.horizontal.3", colors: BadgeColors.gray, command: ["versions", "update"], fixed: ["--version-id", versionID], fields: [
            .init(flag: "version", label: L.t("asc.field.version"), kind: .text(placeholder: "1.0.1")),
            .init(flag: "copyright", label: L.t("act.copyright"), kind: .text(placeholder: "2026 JASTech")),
            .init(flag: "release-type", label: L.t("act.releaseType"), kind: .choice(releaseTypes)),
            .init(flag: "earliest-release-date", label: L.t("act.earliestRelease"), kind: .text(placeholder: "2026-12-01T08:00:00+00:00")),
        ])
    }
    static func phasedCreate(versionID: String) -> AscAction {
        AscAction(title: L.t("act.phasedCreate"), detail: L.t("act.phasedCreate.detail"), symbol: "chart.bar.fill", colors: BadgeColors.warm, command: ["versions", "phased-release", "create"], fixed: ["--version-id", versionID], fields: [
            .init(flag: "state", label: L.t("asc.field.state"), kind: .choice([("INACTIVE", "Inactive"), ("ACTIVE", "Active")]), initial: "INACTIVE"),
        ])
    }
    static func phasedUpdate(phasedID: String) -> AscAction {
        AscAction(title: L.t("act.phasedUpdate"), detail: L.t("act.phasedUpdate.detail"), symbol: "playpause.fill", colors: BadgeColors.warm, command: ["versions", "phased-release", "update"], fixed: ["--id", phasedID], fields: [
            .init(flag: "state", label: L.t("asc.field.state"), kind: .choice([("ACTIVE", "Active"), ("PAUSED", "Paused"), ("COMPLETE", "Complete: release to everyone")]), required: true),
        ], confirm: true)
    }

    // Store listing
    static func appInfoText(app: String, locale: String, name: String, subtitle: String) -> AscAction {
        AscAction(title: L.t("act.appInfo"), detail: L.t("act.appInfo.detail").replacingOccurrences(of: "{locale}", with: locale), symbol: "character.cursor.ibeam", colors: BadgeColors.magic, command: ["localizations", "update"], fixed: ["--app", app, "--type", "app-info", "--locale", locale], fields: [
            .init(flag: "name", label: L.t("asc.field.name"), kind: .text(), initial: name, hint: L.t("act.limit30")),
            .init(flag: "subtitle", label: L.t("asc.field.subtitle"), kind: .text(), initial: subtitle, hint: L.t("act.limit30")),
        ])
    }
    static func categories(app: String) -> AscAction {
        AscAction(title: L.t("act.categories"), detail: L.t("act.categories.detail"), symbol: "square.grid.3x3.fill", colors: BadgeColors.deep, command: ["categories", "set"], fixed: ["--app", app], fields: [
            .init(flag: "primary", label: L.t("act.primaryCategory"), kind: .text(placeholder: "HEALTH_AND_FITNESS"), required: true),
            .init(flag: "secondary", label: L.t("act.secondaryCategory"), kind: .text(placeholder: "LIFESTYLE")),
        ])
    }

    // Builds
    static func buildField(_ builds: [(value: String, label: String)]) -> AscAction.Field {
        .init(flag: "build-id", label: L.t("asc.field.build"), kind: .choice(builds), required: true, initial: builds.first?.value ?? "")
    }
    static func expireBuild(builds: [(value: String, label: String)]) -> AscAction {
        AscAction(title: L.t("act.expireBuild"), detail: L.t("act.expireBuild.detail"), symbol: "clock.badge.xmark", command: ["builds", "expire"], fields: [buildField(builds)], confirm: true, destructive: true)
    }
    static func testNotes(builds: [(value: String, label: String)]) -> AscAction {
        AscAction(title: L.t("act.testNotes"), detail: L.t("act.testNotes.detail"), symbol: "text.bubble.fill", colors: BadgeColors.cool, command: ["builds", "test-notes", "create"], fields: [
            buildField(builds),
            .init(flag: "locale", label: L.t("asc.field.locale"), kind: .text(placeholder: "en-US"), required: true, initial: "en-US"),
            .init(flag: "whats-new", label: L.t("act.whatToTest"), kind: .multiline, required: true),
        ])
    }
    static func addBuildToGroups(builds: [(value: String, label: String)], groups: [(value: String, label: String)]) -> AscAction {
        AscAction(title: L.t("act.addGroups"), detail: L.t("act.addGroups.detail"), symbol: "person.3.fill", colors: BadgeColors.cool, command: ["builds", "add-groups"], fields: [
            buildField(builds),
            .init(flag: "group", label: L.t("act.group"), kind: groups.isEmpty ? .text(placeholder: "Beta") : .choice(groups), required: true, initial: groups.first?.value ?? ""),
            .init(flag: "submit", label: L.t("act.betaSubmit"), kind: .toggle, hint: L.t("act.betaSubmit.hint")),
        ], confirm: false)
    }

    // TestFlight
    static func createGroup(app: String) -> AscAction {
        AscAction(title: L.t("act.createGroup"), detail: L.t("act.createGroup.detail"), symbol: "person.3.sequence.fill", colors: BadgeColors.cool, command: ["testflight", "groups", "create"], fixed: ["--app", app], fields: [
            .init(flag: "name", label: L.t("asc.field.name"), kind: .text(placeholder: "Beta"), required: true),
            .init(flag: "internal", label: L.t("act.internalGroup"), kind: .toggle),
            .init(flag: "public-link-enabled", label: L.t("asc.field.publicLinkEnabled"), kind: .toggle),
            .init(flag: "feedback-enabled", label: L.t("act.feedback"), kind: .toggle, initial: "true"),
        ])
    }
    static func deleteGroup(groups: [(value: String, label: String)]) -> AscAction {
        AscAction(title: L.t("act.deleteGroup"), detail: L.t("act.deleteGroup.detail"), symbol: "trash", command: ["testflight", "groups", "delete"], fields: [
            .init(flag: "id", label: L.t("act.group"), kind: .choice(groups), required: true),
        ], confirm: true, destructive: true)
    }
    static func inviteTester(app: String, groups: [(value: String, label: String)]) -> AscAction {
        AscAction(title: L.t("act.inviteTester"), detail: L.t("act.inviteTester.detail"), symbol: "envelope.badge.fill", colors: BadgeColors.cool, command: ["testflight", "testers", "add"], fixed: ["--app", app], fields: [
            .init(flag: "email", label: L.t("asc.field.email"), kind: .text(placeholder: "name@example.com"), required: true),
            .init(flag: "first-name", label: L.t("asc.field.firstName")),
            .init(flag: "last-name", label: L.t("asc.field.lastName")),
            .init(flag: "group", label: L.t("act.group"), kind: groups.isEmpty ? .text(placeholder: "Beta") : .choice(groups)),
        ])
    }
    static func removeTester(app: String) -> AscAction {
        AscAction(title: L.t("act.removeTester"), detail: L.t("act.removeTester.detail"), symbol: "person.badge.minus", command: ["testflight", "testers", "remove"], fixed: ["--app", app], fields: [
            .init(flag: "email", label: L.t("asc.field.email"), kind: .text(placeholder: "name@example.com"), required: true),
        ], confirm: true, destructive: true)
    }

    // Team
    static let roles = ["ADMIN", "APP_MANAGER", "DEVELOPER", "MARKETING", "SALES", "FINANCE", "CUSTOMER_SUPPORT", "ACCESS_TO_REPORTS", "CREATE_APPS"]
    static func inviteUser() -> AscAction {
        AscAction(title: L.t("act.inviteUser"), detail: L.t("act.inviteUser.detail"), symbol: "person.crop.circle.badge.plus", colors: BadgeColors.deep, command: ["users", "invite"], fields: [
            .init(flag: "email", label: L.t("asc.field.email"), kind: .text(placeholder: "name@example.com"), required: true),
            .init(flag: "first-name", label: L.t("asc.field.firstName"), required: true),
            .init(flag: "last-name", label: L.t("asc.field.lastName"), required: true),
            .init(flag: "roles", label: L.t("act.roles"), kind: .text(placeholder: "APP_MANAGER,DEVELOPER"), required: true, hint: roles.joined(separator: ", ")),
            .init(flag: "all-apps", label: L.t("act.allApps"), kind: .toggle, initial: "true"),
        ])
    }
    static func removeUser(users: [(value: String, label: String)]) -> AscAction {
        AscAction(title: L.t("act.removeUser"), detail: L.t("act.removeUser.detail"), symbol: "person.crop.circle.badge.minus", command: ["users", "delete"], fields: [
            .init(flag: "id", label: L.t("act.user"), kind: .choice(users), required: true),
        ], confirm: true, destructive: true)
    }
    static func registerDevice() -> AscAction {
        AscAction(title: L.t("act.registerDevice"), detail: L.t("act.registerDevice.detail"), symbol: "iphone.badge.play", colors: BadgeColors.deep, command: ["devices", "register"], fields: [
            .init(flag: "name", label: L.t("asc.field.name"), kind: .text(placeholder: "Arda's iPhone"), required: true),
            .init(flag: "udid", label: "UDID", kind: .text(placeholder: "00008110-…"), required: true),
            .init(flag: "platform", label: L.t("asc.field.platform"), kind: .choice([("IOS", "iOS"), ("MAC_OS", "macOS"), ("UNIVERSAL", "Universal")]), required: true, initial: "IOS"),
        ], confirm: true)
    }
    static func revokeCertificate(certs: [(value: String, label: String)]) -> AscAction {
        AscAction(title: L.t("act.revokeCert"), detail: L.t("act.revokeCert.detail"), symbol: "xmark.seal", command: ["certificates", "revoke"], fields: [
            .init(flag: "id", label: L.t("act.certificate"), kind: .choice(certs), required: true),
        ], confirm: true, destructive: true)
    }
    static func deleteProfile(profiles: [(value: String, label: String)]) -> AscAction {
        AscAction(title: L.t("act.deleteProfile"), detail: L.t("act.deleteProfile.detail"), symbol: "trash", command: ["profiles", "delete"], fields: [
            .init(flag: "id", label: L.t("act.profile"), kind: .choice(profiles), required: true),
        ], confirm: true, destructive: true)
    }
    static func createBundleID() -> AscAction {
        AscAction(title: L.t("act.createBundle"), detail: L.t("act.createBundle.detail"), symbol: "plus.app.fill", colors: BadgeColors.deep, command: ["bundle-ids", "create"], fields: [
            .init(flag: "identifier", label: "Bundle ID", kind: .text(placeholder: "com.example.app"), required: true),
            .init(flag: "name", label: L.t("asc.field.name"), kind: .text(placeholder: "Example"), required: true),
            .init(flag: "platform", label: L.t("asc.field.platform"), kind: .choice([("IOS", "iOS"), ("MAC_OS", "macOS"), ("UNIVERSAL", "Universal")]), required: true, initial: "IOS"),
        ])
    }

    /// `[(id, label)]` from a JSON:API list, for a choice field.
    static func options(_ doc: VitrinJSON, label: (([String: VitrinJSON]) -> String)) -> [(value: String, label: String)] {
        JSONAPI.items(doc).compactMap { item in item["id"]?.stringValue.map { ($0, label(item)) } }
    }
}

/// `asc validate`: the counts, then each check with its severity, place and what to do; blocking ones first.
struct ReadinessReport: View {
    var report: [String: VitrinJSON]
    var body: some View {
        let summary = report["summary"]?.objectValue ?? [:]
        let checks = (report["checks"]?.arrayValue ?? []).compactMap(\.objectValue)
        let order = ["error": 0, "warning": 1, "info": 2]
        VStack(alignment: .leading, spacing: 8) {
            FlowLayout(spacing: 6) {
                Pill(L.t("act.val.errors", Int(summary["errors"]?.numberValue ?? 0)), (summary["errors"]?.numberValue ?? 0) > 0 ? .err : .ok)
                Pill(L.t("act.val.warnings", Int(summary["warnings"]?.numberValue ?? 0)), (summary["warnings"]?.numberValue ?? 0) > 0 ? .warn : .ok)
                Pill(L.t("act.val.blocking", Int(summary["blocking"]?.numberValue ?? 0)), (summary["blocking"]?.numberValue ?? 0) > 0 ? .err : .ok)
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(checks.sorted { (order[$0["severity"]?.stringValue ?? ""] ?? 3) < (order[$1["severity"]?.stringValue ?? ""] ?? 3) }.enumerated()), id: \.offset) { _, c in
                    let sev = c["severity"]?.stringValue ?? ""
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: sev == "error" ? "xmark.octagon.fill" : sev == "warning" ? "exclamationmark.triangle.fill" : "info.circle.fill")
                            .foregroundStyle(sev == "error" ? .red : sev == "warning" ? .orange : .blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c["message"]?.stringValue ?? "").font(.callout.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                            Text([c["locale"]?.stringValue, c["field"]?.stringValue].compactMap { $0 }.joined(separator: " · ")).font(.caption.monospaced()).foregroundStyle(.secondary)
                            if let fix = c["remediation"]?.stringValue { Text(fix).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .vitrinCard(padding: 12)
    }
}
