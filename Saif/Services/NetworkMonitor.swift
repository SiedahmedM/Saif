import Foundation
import Network

@MainActor
class NetworkMonitor: ObservableObject {
    @Published var isConnected: Bool = true
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "net.monitor")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in self?.isConnected = (path.status == .satisfied) }
        }
        monitor.start(queue: queue)
    }
}

