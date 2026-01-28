#!/usr/bin/env bash
eval "$(shellspec - -c) exit 1"

# Environment setup
export TMPDIR="${TMPDIR:-/tmp}"
# Isolated test directory to safely mock system paths without touching system files
export GLOBAL_TEST_DIR=$(mktemp -d)

# Mock secrets via environment variables
export CLOUDFLARE_DEVICE_SECRET='{"posture": "test"}'
export CLOUDFLARE_INSPECTION_CERTIFICATE='-----BEGIN CERTIFICATE-----
test-certificate
-----END CERTIFICATE-----'
# GitHub environment variables
export GITHUB_ENV="$GLOBAL_TEST_DIR/github_env"
export GITHUB_OUTPUT="$GLOBAL_TEST_DIR/github_output"

Mock sudo
  # Redirect /private/etc paths to test directory to avoid requiring actual sudo
  if [[ "$1" == "mkdir" && "$2" == "-p" ]]; then
    mkdir -p "$GLOBAL_TEST_DIR${3#/private}"
  elif [[ "$1" == "tee" ]]; then
    # Handle tee command: redirect /private/etc to test dir
    file_path="$2"
    test_path="$GLOBAL_TEST_DIR${file_path#/private}"
    mkdir -p "$(dirname "$test_path")"
    command tee "$test_path"
  elif [[ "$1" == "sh" && "$2" == "-c" ]]; then
    # Handle shell command execution: redirect /private/etc to test dir
    shift 2
    cmd="$1"
    modified_cmd=$(echo "$cmd" | sed "s|/private/etc|$GLOBAL_TEST_DIR/etc|g")
    sh -c "$modified_cmd"
  elif [[ "$1" == "security" ]]; then
    # Mock security command
    echo "security $*"
  elif [[ "$1" == "keytool" ]]; then
    # Mock keytool command
    echo "keytool $*"
  else
    "$@"
  fi
End

Mock python3
  if [[ "$1" == "-m" && "$2" == "certifi" ]]; then
    # Return a mock certifi path
    echo "$GLOBAL_TEST_DIR/certifi/cacert.pem"
  else
    command python3 "$@"
  fi
End

Mock shasum
  # Mock shasum to avoid dependency on actual file content
  echo "mock-sha256-hash  $2"
End

# Setup mock certifi file before tests
setup() {
  mkdir -p "$GLOBAL_TEST_DIR/certifi"
  echo "# Mock system CA bundle" > "$GLOBAL_TEST_DIR/certifi/cacert.pem"
  # Create GITHUB_ENV and GITHUB_OUTPUT files
  touch "$GITHUB_ENV"
  touch "$GITHUB_OUTPUT"
}

cleanup() {
  rm -rf "$GLOBAL_TEST_DIR"
}

BeforeEach 'setup'
AfterAll 'cleanup'

Describe 'setup-prerequisites.sh environment variable validation'
  It 'requires secret environment variables'
    unset CLOUDFLARE_DEVICE_SECRET
    When run script scripts/setup-prerequisites.sh
    The status should be failure
    The error should include "CLOUDFLARE_DEVICE_SECRET"
  End

  It 'requires GitHub environment variables'
    unset GITHUB_ENV
    When run script scripts/setup-prerequisites.sh
    The status should be failure
    The error should include "GITHUB_ENV"
  End
End

Describe 'setup-prerequisites.sh main workflow'
  It 'sets up all prerequisites successfully'
    When run script scripts/setup-prerequisites.sh
    The status should be success
    The output should be present
    The file "$GLOBAL_TEST_DIR/etc/cloudflare-warp-posture.json" should be exist
    The file "$GLOBAL_TEST_DIR/etc/cloudflare-inspection.pem" should be exist
    The file "$GLOBAL_TEST_DIR/etc/ca-bundle.pem" should be exist
    The contents of file "$GITHUB_ENV" should include "NODE_EXTRA_CA_CERTS=/private/etc/cloudflare-inspection.pem"
    The contents of file "$GITHUB_ENV" should include "REQUESTS_CA_BUNDLE=/private/etc/ca-bundle.pem"
    The contents of file "$GITHUB_ENV" should include "JAVA_TOOL_OPTIONS=-Djava.net.preferIPv4Stack=true"
    The contents of file "$GITHUB_OUTPUT" should include "certificate_path=/private/etc/cloudflare-inspection.pem"
  End
End
