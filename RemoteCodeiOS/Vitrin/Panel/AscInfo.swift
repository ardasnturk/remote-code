// Ported from Vitrin for Mac (apps/VitrinMac/VitrinMac/Views/AscInfo.swift).
import SwiftUI

/// The small ⓘ next to a title: what this is, in a sentence or two. Nothing when the key has no text.
struct InfoButton: View {
    /// A key in Localizable.xcstrings.
    var key: String
    @State private var open = false

    var body: some View {
        let text = L.t(key)
        if text != key {
            Button { open.toggle() } label: {
                Image(systemName: "info.circle").font(.caption).foregroundStyle(.secondary).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L.t("common.info"))
            .accessibilityLabel(L.t("common.info"))
            .popover(isPresented: $open, arrowEdge: .bottom) {
                Text(text).font(.callout).fixedSize(horizontal: false, vertical: true).frame(width: 300, alignment: .leading).padding(14)
                    .presentationCompactAdaptation(.popover)
            }
        }
    }
}

/// Why a read failed, in the user's terms, with what to do about it.
enum AscProblem: Equatable {
    case keyRole, agreements, appleAds, other

    init(_ message: String) {
        let m = message.lowercased()
        if m.contains("agreement") { self = .agreements }
        else if m.contains("ads:") && m.contains("credentials") { self = .appleAds }
        else if m.contains("does not allow this request") || m.contains("forbidden") || m.contains("not permitted") { self = .keyRole }
        else { self = .other }
    }
}

/// A failed read: the words for it, and the way out when there is one.
struct AscErrorCard: View {
    var message: String
    /// The page's own sentence for an expected failure (no public rating yet).
    var quiet: String? = nil
    var retry: () -> Void = {}
    @State private var help = false

    var body: some View {
        let problem = AscProblem(message)
        Group {
            switch problem {
            case .keyRole:
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "lock.fill").foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L.t("asc.key.denied")).font(.callout)
                        Button(L.t("asc.key.how")) { help = true }.controlSize(.small)
                    }
                    Spacer(minLength: 0)
                }
            case .agreements:
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "doc.text.fill").foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L.t("asc.key.agreements")).font(.callout).fixedSize(horizontal: false, vertical: true)
                        Link(L.t("asc.key.openAgreements"), destination: AscKeyHelp.agreementsURL).font(.callout)
                    }
                    Spacer(minLength: 0)
                }
            case .appleAds:
                Label(L.t("team.ads.needed"), systemImage: "megaphone.fill").font(.callout).foregroundStyle(.secondary)
            case .other:
                Label(quiet ?? message, systemImage: quiet == nil ? "exclamationmark.triangle.fill" : "info.circle")
                    .font(.callout).foregroundStyle(quiet == nil ? .orange : .secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .vitrinCard(padding: 14)
        .sheet(isPresented: $help) { AscKeyHelp { help = false; retry() } }
    }
}

/// How to get a key that may do this, step by step, and the form to add it.
struct AscKeyHelp: View {
    var close: () -> Void
    static let keysURL = URL(string: "https://appstoreconnect.apple.com/access/integrations/api")!
    static let agreementsURL = URL(string: "https://appstoreconnect.apple.com/business")!

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        VitrinBadge(symbol: "key.horizontal.fill", colors: BadgeColors.cool, size: 34)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L.t("asc.key.title")).font(.title3.bold())
                            Text(L.t("asc.key.why")).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    AscKeySetup(done: close)
                }
                .padding(16)
            }
            .brandWindowBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.t("common.close"), action: close)
                }
            }
        }
    }
}

/// The ways to a key: made for you with the Apple Account, or by hand and added with the form.
struct AscKeySetup: View {
    var done: () -> Void = {}

    var body: some View {
        AutoKeyCard(done: done).vitrinCard(padding: 14)
        SectionTitle(L.t("web.key.orManual"))
        VStack(alignment: .leading, spacing: 8) {
            ForEach(1...5, id: \.self) { n in StepLine(number: n, text: L.t("asc.key.step\(n)")) }
            Link(destination: AscKeyHelp.keysURL) { Label(L.t("asc.key.open"), systemImage: "arrow.up.right.square") }.font(.callout)
            Text(L.t("asc.key.note")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .vitrinCard(padding: 14)
        AccountForm().vitrinCard(padding: 14)
    }
}

struct StepLine: View {
    var number: Int
    var text: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(verbatim: "\(number)").font(.caption.bold().monospacedDigit()).foregroundStyle(.white)
                .frame(width: 18, height: 18).background(VitrinBrand.gradient, in: Circle())
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
        }
    }
}
