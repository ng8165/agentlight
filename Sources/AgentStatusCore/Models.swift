import Foundation

public enum AgentTool: String, Codable, CaseIterable, Sendable {
    case claude
    case codex

    public var displayName: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        }
    }
}

public enum AgentState: String, Codable, CaseIterable, Sendable {
    case running
    case awaitingInput = "awaiting_input"
    case finished
    case idle

    public var displayName: String {
        switch self {
        case .running: "Running"
        case .awaitingInput: "Awaiting input"
        case .finished: "Finished"
        case .idle: "Idle"
        }
    }
}

public struct AgentSession: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public var tool: AgentTool
    public var cwd: String
    public var label: String
    public var state: AgentState
    public var lastUpdated: Date
    public var processID: Int32?
    public var isStaleHeuristic: Bool

    public init(
        id: String,
        tool: AgentTool,
        cwd: String,
        label: String? = nil,
        state: AgentState,
        lastUpdated: Date = Date(),
        processID: Int32? = nil,
        isStaleHeuristic: Bool = false
    ) {
        self.id = id
        self.tool = tool
        self.cwd = cwd
        self.label = label ?? URL(fileURLWithPath: cwd).lastPathComponent
        self.state = state
        self.lastUpdated = lastUpdated
        self.processID = processID
        self.isStaleHeuristic = isStaleHeuristic
    }
}

public struct AgentEvent: Codable, Sendable {
    public var sessionID: String
    public var tool: AgentTool
    public var cwd: String
    public var state: AgentState
    public var timestamp: Date?
    public var label: String?
    public var processID: Int32?
    public var event: String?

    public init(
        sessionID: String,
        tool: AgentTool,
        cwd: String,
        state: AgentState,
        timestamp: Date? = nil,
        label: String? = nil,
        processID: Int32? = nil,
        event: String? = nil
    ) {
        self.sessionID = sessionID
        self.tool = tool
        self.cwd = cwd
        self.state = state
        self.timestamp = timestamp
        self.label = label
        self.processID = processID
        self.event = event
    }
}

public enum AggregateState: Sendable, Equatable {
    case noAgents
    case healthy
    case running
    case needsAttention

    public var symbolName: String {
        switch self {
        case .noAgents: "circle"
        case .healthy: "circle.fill"
        case .running: "circle.fill"
        case .needsAttention: "circle.fill"
        }
    }
}

public enum AgentStatusPolicy {
    public static let defaultSessionTimeout: TimeInterval = 60 * 60
    public static let defaultCodexStaleThreshold: TimeInterval = 45

    public static func aggregate(_ sessions: [AgentSession]) -> AggregateState {
        guard !sessions.isEmpty else { return .noAgents }
        if sessions.contains(where: { $0.state == .awaitingInput }) { return .needsAttention }
        if sessions.contains(where: { $0.state == .running }) { return .running }
        return .healthy
    }
}
