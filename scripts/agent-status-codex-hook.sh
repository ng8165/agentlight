#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export AGENT_STATUS_TOOL=codex
exec "${SCRIPT_DIR}/../hooks/agent-status-hook.py" "${1:-agent-turn-complete}"
