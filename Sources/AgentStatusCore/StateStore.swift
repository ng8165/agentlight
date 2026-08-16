import Foundation
#if canImport(Darwin)
import Darwin
#endif

public final class AgentStateStore: @unchecked Sendable {
    private let lock = NSLock()
    private var sessions: [String: AgentSession] = [:]

    public init() {}

    @discardableResult
    public func apply(_ event: AgentEvent, now: Date = Date()) -> AgentSession {
        let session = AgentSession(
            id: event.sessionID,
            tool: event.tool,
            cwd: event.cwd,
            label: event.label,
            state: event.state,
            lastUpdated: event.timestamp ?? now,
            processID: event.processID
        )
        lock.lock()
        sessions[event.sessionID] = session
        lock.unlock()
        return session
    }

    public func remove(sessionID: String) {
        lock.lock()
        sessions.removeValue(forKey: sessionID)
        lock.unlock()
    }

    public func snapshot(
        now: Date = Date(),
        sessionTimeout: TimeInterval = AgentStatusPolicy.defaultSessionTimeout,
        codexStaleThreshold: TimeInterval = AgentStatusPolicy.defaultCodexStaleThreshold,
        processIsAlive: (Int32) -> Bool = AgentStateStore.defaultProcessIsAlive
    ) -> [AgentSession] {
        lock.lock()
        defer { lock.unlock() }

        sessions = sessions.filter { now.timeIntervalSince($0.value.lastUpdated) <= sessionTimeout }
        return sessions.values.map { session in
            guard session.tool == .codex,
                  session.state != .awaitingInput,
                  now.timeIntervalSince(session.lastUpdated) >= codexStaleThreshold,
                  let processID = session.processID,
                  processIsAlive(processID) else {
                return session
            }

            var stale = session
            stale.state = .awaitingInput
            stale.isStaleHeuristic = true
            return stale
        }.sorted { lhs, rhs in
            if lhs.state == .awaitingInput && rhs.state != .awaitingInput { return true }
            if lhs.state != .awaitingInput && rhs.state == .awaitingInput { return false }
            return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
        }
    }

    private static func defaultProcessIsAlive(_ processID: Int32) -> Bool {
        #if canImport(Darwin)
        return kill(processID, 0) == 0
        #else
        return false
        #endif
    }
}
