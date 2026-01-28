#!/bin/bash
set -uo pipefail

if command -v warp-cli &> /dev/null; then
  # Small delay to ensure logs are flushed before network changes
  sleep 2
  warp-cli --accept-tos disconnect 2>/dev/null || true
  sudo warp-cli --accept-tos registration delete 2>/dev/null || true
  echo "WARP cleanup complete"
else
  echo "WARP CLI not found, skipping cleanup"
fi
