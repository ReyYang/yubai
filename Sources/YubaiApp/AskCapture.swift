import Foundation
import Observation
import Network

@MainActor @Observable final class AskConnectivity {
    var connected = true
    private var monitor: NWPathMonitor?
    private var generation = UUID()
    func start() {
        #if DEBUG
        if AskFixture.current != nil { connected = true; return }
        #endif
        #if DEBUG && targetEnvironment(simulator)
        if UITestSupport.script != nil { connected = true; return }
        #endif
        guard monitor == nil else { return }
        let token = UUID(); generation = token
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                self.connected = connected
            }
        }
        self.monitor = monitor
        monitor.start(queue: DispatchQueue(label: "app.yubai.connectivity"))
    }
    func stop() { generation = UUID(); monitor?.cancel(); monitor = nil }
}
