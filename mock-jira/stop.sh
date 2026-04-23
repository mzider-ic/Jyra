#!/bin/bash
# Stop the mock Jira server
if [ -f /tmp/jyra-mock.pid ]; then
  PID=$(cat /tmp/jyra-mock.pid)
  kill "$PID" 2>/dev/null && echo "Stopped mock Jira (pid $PID)" || echo "Already stopped"
  rm -f /tmp/jyra-mock.pid
else
  lsof -ti:3001 | xargs kill -9 2>/dev/null && echo "Stopped mock Jira" || echo "Nothing running on :3001"
fi
