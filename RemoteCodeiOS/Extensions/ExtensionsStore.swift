import Foundation
import Observation
import RemoteCodeKit

/// Settings → Extensions (D-120): the list of tools from the Mac. Owned by `MacConnection`.
@MainActor
@Observable
final class ExtensionsStore {
    private(set) var items: [ExtensionInfo] = []
    private(set) var isOffered = false
    private(set) var error: String?

    @ObservationIgnored private weak var connection: MacConnection?

    func attach(_ connection: MacConnection) {
        self.connection = connection
    }

    /// A tool's tab shows unless the user turned it off. Unknown tools count as on.
    func isEnabled(_ id: String) -> Bool {
        items.first { $0.id == id }?.enabled ?? true
    }

    func connected(capabilities: Set<String>) async {
        isOffered = capabilities.contains(HostCapability.extensions)
        guard isOffered else {
            items = []
            return
        }
        await refresh()
        if let client = connection?.client {
            _ = try? await client.request(.pluginSubscribe(PluginRef(plugin: PluginID.extensions)))
        }
    }

    func refresh() async {
        do {
            items = try await call("GET", "/v1/list")
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func setEnabled(_ id: String, _ enabled: Bool) async {
        let body = try? JSONSerialization.data(withJSONObject: ["id": id, "enabled": enabled])
        await change("/v1/enabled", body)
    }

    /// Takes a while: the Mac downloads and checks the release.
    func install(_ id: String) async {
        let body = try? JSONSerialization.data(withJSONObject: ["id": id])
        await change("/v1/install", body, timeout: 600)
        await connection?.reconnectPlugins()
    }

    private func change(_ path: String, _ body: Data?, timeout: Int = 60) async {
        do {
            items = try await call("POST", path, body: body.map { String(decoding: $0, as: UTF8.self) }, timeout: timeout)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func handle(_ event: PluginEvent) {
        guard event.plugin == PluginID.extensions else { return }
        Task { await self.refresh() }
    }

    private func call(_ method: String, _ path: String, body: String? = nil, timeout: Int = 60) async throws -> [ExtensionInfo] {
        guard let client = connection?.client else { throw MacClientError.notConnected }
        let request = PluginRequest(plugin: PluginID.extensions, method: method, path: path, body: body, timeout: timeout)
        let response: ServerMessage
        do {
            response = try await client.request(.plugin(request), timeout: TimeInterval(timeout + 10))
        } catch let error as ErrorPayload {
            throw VitrinError.message(error.message)
        }
        guard case .pluginResponse(let result) = response else { throw MacClientError.unexpectedResponse(response.typeName) }
        return try JSONDecoder().decode([ExtensionInfo].self, from: result.body)
    }
}
