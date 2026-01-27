#!/usr/bin/env bash
eval "$(shellspec - -c) exit 1"

# Environment setup
export TMPDIR="${TMPDIR:-/tmp}"
# Isolated test directory to safely mock /Library paths without touching system files
export GLOBAL_TEST_DIR=$(mktemp -d)

Mock brew
  echo "brew $*"
End

Mock warp-cli
  if [[ "$*" == "settings" ]]; then
    echo "Organization: sonarsource"
  elif [[ "$*" == "status" ]]; then
    echo "Status update: Connected"
  elif [[ "$*" == "connect" ]]; then
    echo "Connecting..."
  else
    echo "warp-cli $*"
  fi
End

Mock plutil
  # Just succeed silently
  true
End

Mock sudo
  # Redirect /Library paths to test directory to avoid requiring actual sudo
  # Uses shell parameter expansion ${var#prefix} to strip /Library and prepend test dir
  if [[ "$1" == "mkdir" ]]; then
    shift
    shift  # Skip -p
    # Replace /Library with test dir
    mkdir -p "$GLOBAL_TEST_DIR${1#/Library}"
  elif [[ "$1" == "mv" ]]; then
    shift
    source_file="$1"
    shift
    dest_file="$1"
    # Replace /Library with test dir
    dest_file="$GLOBAL_TEST_DIR${dest_file#/Library}"
    mkdir -p "$(dirname "$dest_file")"
    mv "$source_file" "$dest_file"
  else
    "$@"
  fi
End

Mock command
  if [[ "$*" == "-v warp-cli" ]]; then
    # Simulate warp-cli exists
    true
  else
    builtin command "$@"
  fi
End

Describe 'setup-warp.sh basic execution'
  It 'requires all parameters'
    When run script scripts/setup-warp.sh --version beta --organization sonarsource
    The status should be failure
    The output should include "Missing required parameters"
  End

  It 'accepts required parameters'
    When run script scripts/setup-warp.sh --version beta --organization sonarsource --auth-client-id test-id --auth-client-secret test-secret
    The status should be success
    The output should include "Version: beta"
    The output should include "Organization: sonarsource"
  End

  It 'completes main workflow'
    When run script scripts/setup-warp.sh --version beta --organization sonarsource --auth-client-id test-id --auth-client-secret test-secret
    The status should be success
    The output should include "Starting WARP setup"
    The output should include "Plist configuration created"
    The output should include "WARP setup complete"
  End
End
