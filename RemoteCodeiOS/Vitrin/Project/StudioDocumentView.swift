import RemoteCodeKit
import SwiftUI
import WebKit

/// A page Vitrin generated, such as `store-preview.html`: a result to look at, not part of the app. It is the one web
/// view left on the phone, because the page is the product of the design stage and its pictures sit next to it.
struct StudioDocumentView: UIViewRepresentable {
    static let scheme = "vitrin-studio"
    let client: StudioClient
    /// Under the project's root, like `metadata/design/store-preview.html`.
    let path: String
    var bust: String? = nil

    private var url: URL? {
        let encoded = path.split(separator: "/").map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }.joined(separator: "/")
        return URL(string: "\(Self.scheme)://app/files/\(encoded)\(bust.map { "?v=\($0)" } ?? "")")
    }

    func makeCoordinator() -> StudioFiles {
        StudioFiles(project: client.project, store: client.store)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(context.coordinator, forURLScheme: Self.scheme)
        configuration.allowsInlineMediaPlayback = true
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false
        if let url { view.load(URLRequest(url: url)) }
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        if let url, view.url != url { view.load(URLRequest(url: url)) }
    }

    static func dismantleUIView(_ view: WKWebView, coordinator: StudioFiles) {
        coordinator.cancelAll()
    }
}

/// Serves `vitrin-studio://app/<path>` from the project's Studio on the Mac. A response larger than one message
/// arrives in chunks; a range the page asked for itself (a video) is passed through.
@MainActor
final class StudioFiles: NSObject, WKURLSchemeHandler {
    private let project: String
    private let store: VitrinStore
    private var running: [ObjectIdentifier: Task<Void, Never>] = [:]

    init(project: String, store: VitrinStore) {
        self.project = project
        self.store = store
    }

    func cancelAll() {
        running.values.forEach { $0.cancel() }
        running.removeAll()
    }

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        let id = ObjectIdentifier(task)
        running[id] = Task { [weak self] in
            await self?.serve(task)
            self?.running[id] = nil
        }
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {
        running.removeValue(forKey: ObjectIdentifier(task))?.cancel()
    }

    private func serve(_ task: any WKURLSchemeTask) async {
        let request = task.request
        guard let url = request.url else { return task.didFailWithError(URLError(.badURL)) }
        let query = url.query(percentEncoded: true).map { "?\($0)" } ?? ""
        let path = "/v1/projects/\(project)/studio\(url.path(percentEncoded: true))\(query)"
        let method = request.httpMethod ?? "GET"
        let body = request.httpBody.map { String(decoding: $0, as: UTF8.self) }
        let asked = request.value(forHTTPHeaderField: "Range")
        let chunk = PluginRequest.maxChunkBytes
        do {
            var range = asked
            if range == nil, method == "GET" { range = "bytes=0-\(chunk - 1)" }
            var reply = try await store.call(method, path, body: body, range: range, timeout: 120, checked: false)
            try Task.checkCancellation()
            var data = reply.body
            // The whole file, when the page didn't ask for a part of it.
            if asked == nil, reply.status == 206, let total = reply.totalSize {
                while data.count < total {
                    reply = try await store.call("GET", path, range: "bytes=\(data.count)-\(data.count + chunk - 1)", timeout: 120, checked: false)
                    try Task.checkCancellation()
                    guard reply.status == 206, !reply.body.isEmpty else { break }
                    data.append(reply.body)
                }
                reply.status = 200
                reply.contentRange = nil
            }
            var headers = ["Content-Length": String(data.count), "Cache-Control": "no-store"]
            if let type = reply.contentType { headers["Content-Type"] = type }
            if let contentRange = reply.contentRange { headers["Content-Range"] = contentRange }
            guard let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: headers) else {
                return task.didFailWithError(URLError(.badServerResponse))
            }
            task.didReceive(response)
            task.didReceive(data)
            task.didFinish()
        } catch is CancellationError {
            return
        } catch {
            task.didFailWithError(error)
        }
    }
}
