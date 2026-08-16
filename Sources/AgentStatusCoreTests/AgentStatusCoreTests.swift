import Foundation
import Testing
@testable import AgentStatusCore

@Test func aggregateUsesWorstCaseState() {
    let sessions = [
        AgentSession(id: "1", tool: .claude, cwd: "/tmp/one", state: .running),
        AgentSession(id: "2", tool: .codex, cwd: "/tmp/two", state: .awaitingInput),
        AgentSession(id: "3", tool: .claude, cwd: "/tmp/three", state: .finished)
    ]
    #expect(AgentStatusPolicy.aggregate(sessions) == .needsAttention)
}

@Test func staleCodexSessionOnlyBecomesAttentionWhenProcessIsAlive() {
    let store = AgentStateStore()
    let now = Date(timeIntervalSince1970: 1_000)
    _ = store.apply(AgentEvent(sessionID: "codex-1", tool: .codex, cwd: "/tmp/project", state: .running, timestamp: now.addingTimeInterval(-60), processID: 99), now: now)

    let stale = store.snapshot(now: now, codexStaleThreshold: 45, processIsAlive: { $0 == 99 })
    #expect(stale.first?.state == .awaitingInput)
    #expect(stale.first?.isStaleHeuristic == true)

    let dead = store.snapshot(now: now, codexStaleThreshold: 45, processIsAlive: { _ in false })
    #expect(dead.first?.state == .running)
}

@Test func oldSessionsExpire() {
    let store = AgentStateStore()
    let now = Date(timeIntervalSince1970: 1_000)
    _ = store.apply(AgentEvent(sessionID: "old", tool: .claude, cwd: "/tmp/project", state: .finished, timestamp: now.addingTimeInterval(-100)), now: now)
    #expect(store.snapshot(now: now, sessionTimeout: 90).isEmpty)
}
