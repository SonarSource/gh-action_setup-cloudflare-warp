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

Mock curl
  echo "curl $*"
End

Mock installer
  echo "installer $*"
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
    The output should include "Setting up WARP beta for sonarsource"
  End

  It 'uses Homebrew for beta version'
    When run script scripts/setup-warp.sh --version beta --organization sonarsource --auth-client-id test-id --auth-client-secret test-secret
    The status should be success
    The output should include "Installing cloudflare-warp@beta"
    The output should include "brew update"
  End

  It 'uses manual installation for semantic version'
    When run script scripts/setup-warp.sh --version 2024.12.474.0 --organization sonarsource --auth-client-id test-id --auth-client-secret test-secret
    The status should be success
    The output should include "Installing Cloudflare WARP 2024.12.474.0"
    The output should include "curl -sSL https://1111-releases.cloudflareclient.com/mac/Cloudflare_WARP_2024.12.474.0.pkg -o /tmp/Cloudflare_WARP.pkg"
    The output should include "installer -pkg /tmp/Cloudflare_WARP.pkg -target /"
  End
End
