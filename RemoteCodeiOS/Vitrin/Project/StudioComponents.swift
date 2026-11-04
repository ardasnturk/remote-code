// Ported from Vitrin for Mac (apps/VitrinMac/VitrinMac/Views/Components.swift) and reshaped for a phone.
import AVKit
import ImageIO
import SwiftUI
import UIKit

/// The pieces every project page is made of.

struct Card<Content: View>: View {
    var title: String?
    var accent = false
    @ViewBuilder var content: Content
    init(_ title: String? = nil, accent: Bool = false, @ViewBuilder content: () -> Content) {
        self.title = title
        self.accent = accent
        self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title { SectionTitle(title) }
            content
        }
        .vitrinCard(padding: 14)
        .overlay {
            if accent {
                RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(VitrinBrand.gradient, lineWidth: 1.5)
            }
        }
    }
}

extension Tone {
    static func of(_ s: StageStatus) -> Tone {
        switch s {
        case .done: return .ok
        case .needsClaude, .needsUser: return .warn
        case .blocked: return .err
        case .outdated: return .info
        case .notRun, .skipped, .unknown: return .neutral
        }
    }
    static func ofJob(_ status: String) -> Tone {
        switch status {
        case "ok": return .ok
        case "running": return .accent
        case "needs-input": return .warn
        default: return .err
        }
    }
}

/// A numbered circle that turns into a check mark once its step is done.
struct StepNumber: View {
    var n: Int
    var done: Bool
    var tone: Tone = .neutral
    var running = false
    var body: some View {
        ZStack {
            Circle().fill(done ? Color.green.opacity(0.18) : (tone == .neutral ? Color(.quaternaryLabel).opacity(0.3) : tone.color.opacity(0.18)))
            if running { ProgressView().controlSize(.small) }
            else if done { Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.green) }
            else { Text(verbatim: "\(n)").font(.caption.bold()).foregroundStyle(tone == .neutral ? Color.secondary : tone.color) }
        }
        .frame(width: 26, height: 26)
    }
}

/// A command or install line the user copies.
struct CopyCode: View {
    var text: String
    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(verbatim: text).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color(.tertiarySystemFill)))
            Button { UIPasteboard.general.string = text } label: { Image(systemName: "doc.on.doc") }
                .buttonStyle(.borderless).accessibilityLabel(L.t("common.copy"))
        }
    }
}

struct EmptyHint: View {
    var text: String
    var symbol = "tray"
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.largeTitle).foregroundStyle(.tertiary)
            Text(text).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(30)
    }
}

/// The toast strip at the bottom of a project page.
struct ToastStack: View {
    var session: ProjectSession
    var body: some View {
        VStack(spacing: 6) {
            ForEach(session.toasts) { t in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: t.tone == .ok ? "checkmark.circle.fill" : t.tone == .error ? "exclamationmark.triangle.fill" : "info.circle.fill")
                        .foregroundStyle(t.tone == .ok ? .green : t.tone == .error ? .red : .blue)
                    Text(verbatim: t.text).font(.callout).lineLimit(4).frame(maxWidth: .infinity, alignment: .leading)
                    Button { session.dismiss(t) } label: { Image(systemName: "xmark").font(.caption) }.buttonStyle(.borderless)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(.regularMaterial).shadow(radius: 6, y: 2))
            }
        }
        .padding(12)
        .animation(.spring(duration: 0.3), value: session.toasts)
    }
}

/// A label over its value: the phone has no width for two columns.
struct KeyValueRow: View {
    var key: String
    var value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(verbatim: key).font(.caption).foregroundStyle(.secondary)
            Text(verbatim: value).font(.callout).textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// `.borderedProminent` or `.bordered` chosen at runtime.
struct AnyButtonStyle: PrimitiveButtonStyle {
    private let make: (Configuration) -> AnyView
    init<S: PrimitiveButtonStyle>(_ style: S) { make = { AnyView(style.makeBody(configuration: $0)) } }
    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}

/// The name of a tool the Mac is missing, and a button that installs it there.
struct ToolInstallButton: View {
    @Environment(VitrinPanelModel.self) private var model
    var tool: String
    var title: String
    var done: (() -> Void)?
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if model.installingTool == tool {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(L.t("tools.installing")).font(.callout).foregroundStyle(.secondary)
                }
            } else {
                Button(title) { Task { await model.install(tool: tool); done?() } }
                    .buttonStyle(VitrinGradientButtonStyle(fullWidth: false))
                    .disabled(model.installingTool != nil)
                    .accessibilityIdentifier("tool.install.\(tool)")
            }
            if let error = model.installError {
                Text(verbatim: error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
        }
    }
}

extension RenderedFile {
    var isVideo: Bool { [".mp4", ".mov", ".m4v"].contains { name.lowercased().hasSuffix($0) } }
    var size: String { ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file) }
}

// MARK: Media

/// Pictures from the Mac, scaled to what the screen shows: a screenshot is several megabytes and a gallery holds dozens.
@MainActor
final class StudioImages {
    static let shared = StudioImages()
    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.totalCostLimit = 200 * 1024 * 1024
    }

    func image(_ client: StudioClient, path: String, bust: String?, maxPixels: Int?) async throws -> UIImage {
        let key = "\(client.project)|\(path)|\(bust ?? "")|\(maxPixels ?? 0)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let data = try await client.fileData(path, bust: bust)
        let image = await Task.detached(priority: .userInitiated) { () -> UIImage? in Self.decode(data, maxPixels: maxPixels) }.value
        guard let image else { throw URLError(.cannotDecodeContentData) }
        cache.setObject(image, forKey: key, cost: Int(image.size.width * image.size.height * image.scale * image.scale * 4))
        return image
    }

    private nonisolated static func decode(_ data: Data, maxPixels: Int?) -> UIImage? {
        guard let maxPixels, let source = CGImageSourceCreateWithData(data as CFData, nil) else { return UIImage(data: data) }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary).map { UIImage(cgImage: $0) }
    }
}

/// A picture under the project's root, read through the Mac.
struct StudioImage: View {
    var client: StudioClient
    var path: String
    var bust: String? = nil
    /// Longest side in pixels; nil is the full picture.
    var maxPixels: Int? = 700
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: .fit)
            } else if failed {
                Image(systemName: "photo").foregroundStyle(.tertiary)
            } else {
                ProgressView()
            }
        }
        .task(id: "\(path)|\(bust ?? "")") {
            failed = false
            do {
                image = try await StudioImages.shared.image(client, path: path, bust: bust, maxPixels: maxPixels)
            } catch {
                if !ProjectSession.isCancellation(error) { failed = true }
            }
        }
    }
}

/// A screenshot or creative with its file name and size. A video stays a tile until tapped: it has to come from the Mac.
struct MediaThumb: View {
    var client: StudioClient
    var file: RenderedFile
    var bust: String? = nil
    var height: CGFloat = 220

    var body: some View {
        VStack(spacing: 4) {
            Group {
                if file.isVideo {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8).fill(Color(.tertiarySystemFill))
                        Image(systemName: "play.circle.fill").font(.largeTitle).foregroundStyle(.secondary)
                    }
                } else {
                    StudioImage(client: client, path: file.path, bust: bust)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            Text(verbatim: file.name).font(.caption).lineLimit(1).truncationMode(.middle)
            Text(verbatim: file.size).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground).opacity(0.7)))
        .contentShape(Rectangle())
    }
}

/// A picture or a video in full: the video is fetched from the Mac first, with its progress on screen.
struct MediaSheet: View {
    var client: StudioClient
    var file: RenderedFile
    var bust: String? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var progress: Double?
    @State private var failure: String?
    @State private var scale: CGFloat = 1

    var body: some View {
        NavigationStack {
            Group {
                if let failure {
                    EmptyHint(text: failure, symbol: "exclamationmark.triangle")
                } else if file.isVideo {
                    if let player {
                        VideoPlayer(player: player).onAppear { player.play() }.onDisappear { player.pause() }
                    } else {
                        VStack(spacing: 10) {
                            ProgressView(value: progress ?? 0).frame(maxWidth: 240)
                            Text(verbatim: file.size).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } else {
                    ScrollView([.horizontal, .vertical]) {
                        StudioImage(client: client, path: file.path, bust: bust, maxPixels: nil)
                            .scaleEffect(scale)
                            .containerRelativeFrame(.horizontal)
                    }
                    .gesture(MagnifyGesture().onChanged { scale = max(1, min($0.magnification, 5)) })
                }
            }
            .navigationTitle(Text(verbatim: file.name))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.t("common.close")) { dismiss() }.accessibilityIdentifier("media.close")
                }
            }
        }
        .task(id: file.path) {
            guard file.isVideo, player == nil else { return }
            do {
                let url = try await StudioVideos.fetch(client, file: file, bust: bust) { progress = $0 }
                player = AVPlayer(url: url)
            } catch {
                if !ProjectSession.isCancellation(error) { failure = error.localizedDescription }
            }
        }
    }
}

/// App Previews, kept under Caches once fetched: the player needs a whole file, and they run to hundreds of megabytes.
@MainActor
enum StudioVideos {
    static func fetch(_ client: StudioClient, file: RenderedFile, bust: String?, progress: (Double) -> Void) async throws -> URL {
        let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("vitrin-media", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = "\(client.project)-\(file.path)-\(file.bytes)".addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? UUID().uuidString
        let target = folder.appendingPathComponent(String(name.suffix(120))).appendingPathExtension((file.name as NSString).pathExtension)
        if FileManager.default.fileExists(atPath: target.path) { return target }
        let partial = target.appendingPathExtension("part")
        FileManager.default.createFile(atPath: partial.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: partial) }
        let handle = try FileHandle(forWritingTo: partial)
        defer { try? handle.close() }
        var received = 0
        try await client.readFile(file.path, bust: bust) { piece, total in
            try handle.write(contentsOf: piece)
            received += piece.count
            if let total, total > 0 { progress(Double(received) / Double(total)) }
        }
        try FileManager.default.moveItem(at: partial, to: target)
        return target
    }
}
