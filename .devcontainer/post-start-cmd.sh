#!/bin/bash

echo "[post-start-cmd.sh] Checking modelrelay..."
if command -v modelrelay &>/dev/null; then
  if pgrep -f modelrelay > /dev/null; then
    echo "[post-start-cmd.sh] modelrelay is already running, skipping"
  else
    echo "[post-start-cmd.sh] Starting modelrelay in the background..."
    setsid /usr/local/bin/modelrelay >> /tmp/modelrelay.log 2>&1 &
  fi
else
  echo "[post-start-cmd.sh] modelrelay not found, skipping start"
fi

# so that the script doesn't exit immediately before modelrelay has a chance to start properly
sleep 60