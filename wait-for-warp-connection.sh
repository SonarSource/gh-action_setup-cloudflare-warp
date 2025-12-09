#!/bin/bash
set -euo pipefail

PROBE_URL="https://vault.sonar.build"

echo "Waiting for $PROBE_URL to be reachable..."
MAX_WAIT=300
POLL_INTERVAL=2
START_TIME=$(date +%s)

while true; do
  ELAPSED=$(($(date +%s) - START_TIME))

  if [ $ELAPSED -ge $MAX_WAIT ]; then
    echo "Error: $PROBE_URL did not become reachable within ${MAX_WAIT} seconds"
    exit 1
  fi

  if curl -s --max-time 5 ${PROBE_URL} > /dev/null 2>&1; then
    echo "$PROBE_URL is reachable - WARP connection ready"
    exit 0
  fi
  ELAPSED=$(($(date +%s) - START_TIME))
  echo "$PROBE_URL not reachable yet, waiting ${POLL_INTERVAL}s... (elapsed: ${ELAPSED}s/${MAX_WAIT}s)"
  sleep $POLL_INTERVAL
done
