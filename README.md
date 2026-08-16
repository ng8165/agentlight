# AgentLight

AgentLight is a local macOS menu bar traffic light for Claude Code and Codex CLI sessions. It shows the worst-case state across all connected agents and lists each session with its project, tool, state, and last update.

## What is included

- `agent-status-daemon`: a localhost-only HTTP daemon with an in-memory session store.
- `AgentLightMenuBar`: an `NSStatusItem` app that starts the daemon and polls it once per second.
- `hooks/agent-status-hook.py`: a dependency-free Python hook adapter for Claude Code and Codex notification payloads.
- `examples/claude-settings.json`: Claude Code hook configuration for `SessionStart`, `Notification`, `Stop`, and `SessionEnd`.
- `examples/codex-config.toml`: a conservative Codex notification example, marked version-sensitive.

The daemon listens only on `127.0.0.1:43999`. The state store expires sessions after one hour. For Codex, a session that has not reported for 45 seconds is shown as “possibly waiting” only when its event includes a live `process_id`; this avoids silently treating a dead session as a prompt.

## Build and run

Requirements: macOS 13+, Swift 6 toolchain, and Python 3 for the hook adapter.

```sh
swift build
swift test

# Run the daemon by itself:
AGENT_STATUS_PORT=43999 .build/debug/agent-status-daemon

# Build a signed-for-local-use app bundle:
./scripts/build-app.sh
open dist/AgentLight.app
```

The app bundle is signed with an ad-hoc signature for local development. `LSUIElement` is set in `Info.plist`, so the app has no Dock icon.

## Claude Code setup

1. Replace `/absolute/path/to/agentlight` in `examples/claude-settings.json` with this repository's absolute path.
2. Merge the `hooks` object into `.claude/settings.json` for one project or `~/.claude/settings.json` for all projects. Do not overwrite unrelated settings.
3. Ensure the hook is executable:

   ```sh
   chmod +x hooks/agent-status-hook.py
   ```

Claude hook JSON is read from stdin. The adapter extracts `session_id` and `cwd`, sends the event to the daemon, and exits successfully if AgentLight is not running so it never blocks Claude Code.

## Codex CLI setup

Codex's `notify` and experimental hooks have changed across CLI versions, and the currently available official documentation does not define a stable payload/config reference. Confirm the installed version with `codex --version` and inspect its supported configuration before enabling the example.

When supported, copy the `notify` array from `examples/codex-config.toml` into `~/.codex/config.toml`. The included wrapper sets `AGENT_STATUS_TOOL=codex` before invoking the shared adapter. If the CLI emits `approval-requested`, use that event name as the second array value with the same wrapper. The adapter accepts both hyphenated and underscored event names.

If Codex emits a process id, the daemon uses it for the stale-session heuristic. If it does not, AgentLight will not guess that an old session is waiting.

## HTTP API

The daemon exposes three localhost endpoints:

```text
GET  /v1/health
GET  /v1/sessions
POST /v1/events
DELETE /v1/sessions/:session_id
```

Example event:

```json
{
  "session_id": "session-123",
  "tool": "claude",
  "cwd": "/Users/me/src/project",
  "state": "awaiting_input",
  "timestamp": 1760000000,
  "process_id": 12345
}
```

Valid states are `running`, `awaiting_input`, `finished`, and `idle`. `awaiting_input` wins over every other session state; otherwise running is yellow, completed/idle sessions are green, and an empty store is dim gray.

Clicking a row copies the tool, session id, and working directory to the clipboard. This is the v1 fallback for terminal focus switching and gives enough information to find the relevant terminal manually.

## Project commands

- Install: no package install; use the Swift toolchain.
- Build: `swift build`
- Test: `swift test`
- App bundle: `./scripts/build-app.sh`
