import AgentStatusCore
import Foundation

@main
struct AgentStatusDaemon {
    static func main() throws {
        let port = UInt16(ProcessInfo.processInfo.environment["AGENT_STATUS_PORT"] ?? "43999") ?? 43999
        let server = try AgentStatusHTTPServer(port: port)
        server.start()
        print("AgentLight daemon listening on http://127.0.0.1:\(port)")
        dispatchMain()
    }
}
