#!/usr/bin/env bash
# Runs the tests against real Reminders.
#
# A test process can't get Reminders access itself (its responsible app is
# whatever launched it), so the tests drive the MCP server instead, installed
# as "Reminders MCP Tests": a copy of its own, so macOS asks for access once
# for it, separately from the server Claude uses.
#
# Every test works inside one existing list, "Sync Test" unless
# REMINDERS_MCP_TEST_LIST names another; tests only touch reminders they
# create there, and delete them afterwards.
set -euo pipefail
cd "$(dirname "$0")/.."

scripts/install.sh "Reminders MCP Tests"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" REMINDERS_MCP_TEST_SERVER="$HOME/Library/Application Support/apple-reminders-mcp/Reminders MCP Tests" swift test "$@"
