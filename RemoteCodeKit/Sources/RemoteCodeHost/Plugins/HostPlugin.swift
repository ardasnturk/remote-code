import Foundation
import RemoteCodeKit

/// A tool on the Mac that the phone drives through a local API (D-117). Register one
/// in `MacHostService.plugins`: the host announces it as `plugin.<id>` and forwards
/// its requests and events, and the protocol stays as it is.
public protocol HostPlugin: Sendable {
    func send(_ request: PluginRequest) async throws -> PluginResponse
    /// Runs until the returned stream is cancelled.
    func events() -> AsyncStream<PluginEvent>
}
