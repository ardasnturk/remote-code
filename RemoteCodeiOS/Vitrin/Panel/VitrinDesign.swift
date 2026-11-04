// Ported from Vitrin for Mac (apps/VitrinMac/VitrinMac/Views/Design/Design.swift and Views/Components.swift).
import RemoteCodeKit
import SwiftUI

/// The Remote Code family look (Remote Code D-104, as Promo Studio carries it): glass cards on blurred colour blobs,
/// gradient icon badges, a gradient header and primary button. Vitrin owns the warm end: amber → coral → pink.
enum VitrinBrand {
    static let teal = Color(red: 0.05, green: 0.66, blue: 0.68)
    static let indigo = Color(red: 0.30, green: 0.36, blue: 0.93)
    static let violet = Color(red: 0.62, green: 0.32, blue: 0.92)
    static let pink = Color(red: 0.93, green: 0.36, blue: 0.62)
    static let mint = Color(red: 0.48, green: 0.91, blue: 0.77)
    static let amber = Color(red: 1.00, green: 0.62, blue: 0.20)
    static let coral = Color(red: 0.98, green: 0.42, blue: 0.38)

    /// Headers and featured cards
    static let gradient = LinearGradient(colors: [amber, coral, pink], startPoint: .topLeading, endPoint: .bottomTrailing)
    /// Primary action buttons
    static let buttonGradient = LinearGradient(colors: [coral, pink], startPoint: .leading, endPoint: .trailing)
}

/// Soft, blurred color blobs behind the window content.
struct BrandBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    var intensity: Double = 1

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
            GeometryReader { proxy in
                let size = proxy.size
                ZStack {
                    blob(VitrinBrand.amber, diameter: size.width * 0.9)
                        .offset(x: -size.width * 0.35, y: -size.height * 0.35)
                    blob(VitrinBrand.coral, diameter: size.width * 0.8)
                        .offset(x: size.width * 0.4, y: -size.height * 0.1)
                    blob(VitrinBrand.pink, diameter: size.width * 0.9)
                        .offset(x: -size.width * 0.1, y: size.height * 0.45)
                }
                .frame(width: size.width, height: size.height)
            }
            .blur(radius: 60)
            .opacity((colorScheme == .dark ? 0.4 : 0.22) * intensity)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private func blob(_ color: Color, diameter: CGFloat) -> some View {
        Circle().fill(color).frame(width: diameter, height: diameter)
    }
}

extension View {
    /// Translucent rounded card that lets the brand background show through.
    func vitrinCard(cornerRadius: CGFloat = 14, padding: CGFloat = 12) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
            )
    }

    /// Screen content: brand background, with list/form backgrounds hidden.
    func brandWindowBackground(intensity: Double = 0.45) -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(BrandBackground(intensity: intensity))
    }
}

/// White SF Symbol on a gradient rounded square (rows, headers).
struct VitrinBadge: View {
    let symbol: String
    var colors: [Color] = [VitrinBrand.coral, VitrinBrand.pink]
    var size: CGFloat = 22

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.52, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }
}

/// Large primary action button: gradient, white text.
struct VitrinGradientButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var fullWidth = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.vertical, 8)
            .padding(.horizontal, 14)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(VitrinBrand.buttonGradient, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

/// Small colored status pill, e.g. "Ready".
struct StatusPill: View {
    let text: Text
    let color: Color
    /// White fill on a gradient header; colored on a regular background
    var onGradient = false

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            text
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(onGradient ? AnyShapeStyle(.white.opacity(0.18)) : AnyShapeStyle(color.opacity(0.16)), in: Capsule())
        .foregroundStyle(onGradient ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
    }
}

/// Small uppercase section title inside a card.
struct SectionTitle: View {
    let title: String
    /// A key for the ⓘ next to the title; nothing shows when the key has no text.
    var info: String?

    init(_ title: String, info: String? = nil) { self.title = title; self.info = info }

    var body: some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            if let info { InfoButton(key: info) }
        }
    }
}

/// Large icon, title and one-line description at the top of a pane.
struct PaneHeader: View {
    let symbol: String
    let colors: [Color]
    let title: Text
    let subtitle: Text

    var body: some View {
        HStack(spacing: 14) {
            VitrinBadge(symbol: symbol, colors: colors, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                title.font(.title2.weight(.bold))
                subtitle
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
        }
    }
}

/// Badge colours per area, so a page and its row match.
enum BadgeColors {
    static let warm = [VitrinBrand.amber, VitrinBrand.coral]
    static let brand = [VitrinBrand.coral, VitrinBrand.pink]
    static let cool = [VitrinBrand.teal, VitrinBrand.indigo]
    static let deep = [VitrinBrand.indigo, VitrinBrand.violet]
    static let magic = [VitrinBrand.violet, VitrinBrand.pink]
    static let fresh = [Color.green, VitrinBrand.teal]
    static let alert = [Color.orange, Color.red]
    static let gray = [Color.gray, Color.gray.opacity(0.65)]
}

// MARK: components

enum Tone: Sendable { case ok, warn, err, info, accent, neutral }

extension Tone {
    var color: Color {
        switch self {
        case .ok: return .green
        case .warn: return .orange
        case .err: return .red
        case .info: return .blue
        case .accent: return .accentColor
        case .neutral: return .secondary
        }
    }
}

struct Pill: View {
    var text: String
    var tone: Tone = .neutral
    init(_ text: String, _ tone: Tone = .neutral) {
        self.text = text
        self.tone = tone
    }
    var body: some View {
        StatusPill(text: Text(text), color: tone == .neutral ? .gray : tone.color)
    }
}

/// Capsule tabs that scroll sideways when they do not fit: the language rows, instead of a segmented control.
struct CapsuleTabs<T: Hashable>: View {
    var items: [T]
    @Binding var selection: T
    var title: (T) -> String
    var mono = false

    var body: some View {
        ScrollViewReader { proxy in
            row
                .onChange(of: selection) { _, new in withAnimation { proxy.scrollTo(new, anchor: .center) } }
                .onAppear { proxy.scrollTo(selection, anchor: .center) }
        }
        // A horizontal ScrollView is flexible in height too; without this it takes the page's whole height.
        .fixedSize(horizontal: false, vertical: true)
        .background(.quaternary.opacity(0.35), in: Capsule())
    }

    private var row: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(items, id: \.self) { item in
                    let on = item == selection
                    Button { selection = item } label: {
                        Text(title(item))
                            .font(mono ? .callout.monospaced() : .callout)
                            .fontWeight(on ? .semibold : .regular)
                            .lineLimit(1)
                            .padding(.horizontal, 11).padding(.vertical, 5)
                            .background(on ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(.clear), in: Capsule())
                            .overlay { if on { Capsule().strokeBorder(.white.opacity(0.15), lineWidth: 0.5) } }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .id(item)
                }
            }
            .padding(2)
        }
    }
}

/// Wraps its children onto as many lines as needed. A child wider than the line is offered the line's width.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = layout(proposal: proposal, subviews: subviews)
        // An unbounded proposal (a parent measuring its maximum) gets the width the rows use, never infinity.
        let w = proposal.width.map { $0.isFinite ? $0 : rows.width } ?? rows.width
        return CGSize(width: w, height: rows.height)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let size = measure(s, width: bounds.width)
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowH = max(rowH, size.height)
        }
    }
    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (width: CGFloat, height: CGFloat) {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, width: CGFloat = 0
        for s in subviews {
            let size = measure(s, width: maxW)
            if x + size.width > maxW, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += size.width + spacing
            rowH = max(rowH, size.height)
            width = max(width, x)
        }
        return (width, y + rowH)
    }
    private func measure(_ s: LayoutSubview, width: CGFloat) -> CGSize {
        let ideal = s.sizeThatFits(.unspecified)
        return ideal.width > width ? s.sizeThatFits(ProposedViewSize(width: width, height: nil)) : ideal
    }
}

/// An App Store Connect app: a badge, the name, the version and its state, a coloured dot, and a link badge when a
/// project on the Mac has this bundle id.
struct AppRow: View {
    var app: ASCApp
    var linked: VitrinProject?
    var body: some View {
        HStack(spacing: 10) {
            AppIcon(app: app, size: 40)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(app.name).lineLimit(1)
                    if linked != nil { Image(systemName: "link").font(.caption2).foregroundStyle(.secondary) }
                }
                if let v = app.current {
                    Text(verbatim: "\(v.version) · \(ASCWords.state(v.state))").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                } else {
                    Text(app.bundleId).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer(minLength: 4)
            if let v = app.current { Circle().fill(ASCWords.tone(v.state).color).frame(width: 8, height: 8).accessibilityHidden(true) }
        }
        .padding(.vertical, 1)
        .accessibilityIdentifier("vitrin.app.\(app.bundleId)")
    }
}

/// An app's icon from its newest build (`AppIconStore`), else a badge with its initial.
struct AppIcon: View {
    /// Loaded icons, kept while the app runs. `AsyncImage` stays on its placeholder for good when the user leaves the
    /// list before an icon arrives: its cancelled load counts as a failure and is never tried again.
    @MainActor private static let loaded = NSCache<NSURL, UIImage>()

    @Environment(VitrinPanelModel.self) private var model
    @State private var image: UIImage?
    var app: ASCApp
    var size: CGFloat

    var body: some View {
        let url = model.icons.url(for: app.id, size: size)
        Group {
            if let image {
                Image(uiImage: image).resizable().interpolation(.high)
            } else {
                AppIconPlaceholder(name: app.name, size: size)
            }
        }
        .task(id: url) {
            guard let url else { return }
            if let hit = Self.loaded.object(forKey: url as NSURL) {
                image = hit
            } else if let (data, _) = try? await URLSession.shared.data(from: url), let icon = UIImage(data: data) {
                Self.loaded.setObject(icon, forKey: url as NSURL)
                image = icon
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
        .accessibilityHidden(true)
    }
}

/// An app without a build has no icon yet: its initial on the team colours.
struct AppIconPlaceholder: View {
    var name = ""
    var size: CGFloat
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
            .fill(LinearGradient(colors: BadgeColors.cool, startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(Text(verbatim: name.first.map { String($0).uppercased() } ?? "").font(.system(size: size * 0.5, weight: .semibold, design: .rounded)).foregroundStyle(.white))
            .frame(width: size, height: size)
    }
}

/// Installs asc on the Mac through the hub, with its progress and any failure under the button.
struct AscInstallButton: View {
    @Environment(VitrinPanelModel.self) private var model
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if model.installingAsc {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(L.t("vitrin.installingAsc")).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityIdentifier("tool.installing.asc")
            } else {
                Button(L.t("asc.install")) { Task { await model.installAsc() } }
                    .buttonStyle(VitrinGradientButtonStyle(fullWidth: false))
                    .accessibilityIdentifier("tool.install.asc")
            }
            if let error = model.installError {
                Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
        }
    }
}

/// Browses the Mac for a path an asc command takes: a file, or a folder when `folders` is true. Like
/// `VitrinFolderPicker`, with the browser the new-chat screen uses.
struct VitrinPathPicker: View {
    let connection: MacConnection
    var folders = false
    let choose: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var path: String?
    @State private var listing: DirectoryListing?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                if let listing {
                    Section {
                        Breadcrumb(listing: listing) { path = $0 }
                            .listRowBackground(Color.clear)
                    }
                    Section {
                        ForEach(listing.entries.filter { $0.isDirectory || !folders }, id: \.path) { entry in
                            FolderRow(entry: entry) {
                                if entry.isDirectory {
                                    path = entry.path
                                } else {
                                    choose(entry.path)
                                    dismiss()
                                }
                            }
                        }
                    }
                } else if let error {
                    Text(error).foregroundStyle(.secondary)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(L.t(folders ? "vitrin.chooseFolder" : "vitrin.chooseFile"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.t("vitrin.cancel")) { dismiss() }
                }
                if folders {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L.t("vitrin.useThisFolder")) {
                            if let listing { choose(listing.path) }
                            dismiss()
                        }
                        .disabled(listing == nil)
                    }
                }
            }
            .task(id: path) {
                do {
                    listing = try await connection.listDirectory(path, showHidden: false)
                    error = nil
                } catch {
                    self.error = error.localizedDescription
                }
            }
        }
    }
}
