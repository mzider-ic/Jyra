#!/bin/bash
# Start the mock Jira server (kills any previous instance first)
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

lsof -ti:3001 | xargs kill -9 2>/dev/null || true

node "$SCRIPT_DIR/server.js" >/tmp/jyra-mock.log 2>&1 &
PID=$!
echo $PID > /tmp/jyra-mock.pid

sleep 0.4
if kill -0 $PID 2>/dev/null; then
  echo "Mock Jira started (pid $PID) — http://localhost:3001"
  echo "Logs: /tmp/jyra-mock.log   Stop: bash mock-jira/stop.sh"
else
  echo "Mock Jira failed to start — check /tmp/jyra-mock.log"
  exit 1
fi
