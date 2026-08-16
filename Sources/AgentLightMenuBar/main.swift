import AgentStatusCore
import AppKit
import SwiftUI

@main
struct AgentLightMenuBar: App {
    @NSApplicationDelegateAdaptor(StatusBarAppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class StatusBarAppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let viewModel = StatusBarViewModel()
    private var server: AgentStatusHTTPServer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let port = UInt16(ProcessInfo.processInfo.environment["AGENT_STATUS_PORT"] ?? "43999") ?? 43999
        server = try? AgentStatusHTTPServer(port: port)
        server?.start()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.toolTip = "AgentLight"
        updateIcon()

        popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 370, height: 460)
        popover.contentViewController = NSHostingController(rootView: AgentPopover(viewModel: viewModel))

        viewModel.onChange = { [weak self] in self?.updateIcon() }
        viewModel.startPolling(port: port)
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.becomeKey()
        }
    }

    private func updateIcon() {
        let state = AgentStatusPolicy.aggregate(viewModel.sessions)
        let image = NSImage(systemSymbolName: state.symbolName, accessibilityDescription: "Agent status")
        image?.isTemplate = false
        statusItem.button?.image = image
        statusItem.button?.contentTintColor = state == .needsAttention ? .systemRed : state == .running ? .systemYellow : state == .healthy ? .systemGreen : .secondaryLabelColor
        statusItem.button?.title = viewModel.sessions.contains(where: { $0.state == .awaitingInput }) ? " (viewModel.sessions.filter { $0.state == .awaitingInput }.count)" : ""
    }
}

@MainActor
final class StatusBarViewModel: ObservableObject {
    @Published private(set) var sessions: [AgentSession] = []
    var onChange: (() -> Void)?
    private var timer: Timer?
    private var port: UInt16 = 43999

    func startPolling(port: UInt16) {
        self.port = port
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func refresh() {
        let endpoint = URL(string: "http://127.0.0.1:\(port)/v1/sessions")!
        URLSession.shared.dataTask(with: endpoint) { [weak self] data, _, _ in
            guard let data else { return }
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            guard let sessions = try? decoder.decode([AgentSession].self, from: data) else { return }
            Task { @MainActor [weak self] in
                self?.sessions = sessions
                self?.onChange?()
            }
        }.resume()
    }

    func copyDetails(for session: AgentSession) {
        let details = "(session.tool.displayName)\nSession: (session.id)\nDirectory: (session.cwd)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(details, forType: .string)
    }
}

private struct AgentPopover: View {
    @ObservedObject var viewModel: StatusBarViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("AgentLight").font(.headline)
                Spacer()
                Button("Refresh") { viewModel.refresh() }
                    .buttonStyle(.borderless)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider()

            if viewModel.sessions.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "circle").font(.title2).foregroundStyle(.secondary)
                    Text("No agents connected").font(.headline)
                    Text("Start a Claude Code or Codex session with the hooks configured.")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(24)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.sessions) { session in
                            AgentRow(session: session) {
                                viewModel.copyDetails(for: session)
                            }
                            Divider().padding(.leading, 16)
                        }
                    }
                }
            }

            Divider()
            HStack {
                Text("Click an agent to copy its session details")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }.buttonStyle(.borderless)
            }
            .padding(12)
        }
        .frame(width: 370, height: 460)
    }
}

private struct AgentRow: View {
    let session: AgentSession
    let onClick: () -> Void

    var body: some View {
        Button(action: onClick) {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(color)
                    .frame(width: 9, height: 9)
                    .padding(.top, 5)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(session.label).font(.headline)
                        Spacer()
                        Text(session.tool.displayName).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(session.state.displayName + (session.isStaleHeuristic ? " (possibly waiting)" : ""))
                        .font(.subheadline).foregroundStyle(color)
                    Text(session.cwd).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Text("Updated \(session.lastUpdated, style: .relative) ago")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }

    private var color: Color {
        switch session.state {
        case .awaitingInput: .red
        case .running: .yellow
        case .finished, .idle: .green
        }
    }
}
