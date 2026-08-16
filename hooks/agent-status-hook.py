#!/usr/bin/env python3
"""Translate Claude Code/Codex hook JSON into an AgentLight event."""

import json
import os
import sys
import time
import urllib.request


DAEMON_URL = os.environ.get("AGENT_STATUS_URL", "http://127.0.0.1:43999/v1/events")


def first(payload, *keys, default=None):
    for key in keys:
        value = payload.get(key)
        if value not in (None, ""):
            return value
    return default


def main():
    tool = os.environ.get("AGENT_STATUS_TOOL", "claude").lower()
    event_name = (sys.argv[1] if len(sys.argv) > 1 else os.environ.get("AGENT_STATUS_EVENT", "")).lower()
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, OSError):
        payload = {}

    session_id = first(payload, "session_id", "sessionId", default=os.environ.get("AGENT_STATUS_SESSION_ID"))
    cwd = first(payload, "cwd", "working_directory", "workdir", default=os.getcwd())
    if not session_id:
        # Hooks without a session id cannot be safely correlated with another agent.
        return 0

    state_by_event = {
        "notification": "awaiting_input",
        "approval-requested": "awaiting_input",
        "approval_requested": "awaiting_input",
        "stop": "finished",
        "agent-turn-complete": "finished",
        "agent_turn_complete": "finished",
        "turn-ended": "finished",
        "turn_ended": "finished",
        "sessionstart": "running",
        "session_start": "running",
        "pretooluse": "running",
        "pre_tool_use": "running",
        "posttooluse": "running",
        "post_tool_use": "running",
        "sessionend": "finished",
        "session_end": "finished",
    }
    state = state_by_event.get(event_name, "running")
    event = "session_end" if event_name in ("sessionend", "session_end") else event_name
    label = first(payload, "label", "session_name", default=os.path.basename(os.path.normpath(cwd)) or cwd)
    process_id = first(payload, "process_id", "processId", "pid")

    body = {
        "session_id": str(session_id),
        "tool": tool,
        "cwd": cwd,
        "label": label,
        "state": state,
        "timestamp": time.time(),
        "process_id": int(process_id) if str(process_id).isdigit() else None,
        "event": event,
    }
    request = urllib.request.Request(
        DAEMON_URL,
        data=json.dumps(body).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        urllib.request.urlopen(request, timeout=0.75).read()
    except OSError:
        # Hooks must never block or fail the coding agent if AgentLight is closed.
        pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
