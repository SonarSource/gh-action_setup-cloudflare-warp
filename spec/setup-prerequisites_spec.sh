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
  if [[ "$1" == "mkdir" ]]; then
    shift
    shift  # Skip -p
    mkdir -p "$GLOBAL_TEST_DIR${1#/private}"
  elif [[ "$1" == "sh" && "$2" == "-c" ]]; then
    # Handle piped writes like: sudo sh -c 'cat > /private/etc/file'
    shift 2
    cmd="$1"
    # Replace /private/etc with test dir in the command
    modified_cmd=$(echo "$cmd" | sed "s|/private/etc|$GLOBAL_TEST_DIR/etc|g")
    sh -c "$modified_cmd"
  elif [[ "$1" == "security" ]]; then
    # Mock security command - just succeed
    echo "security $*"
    true
  elif [[ "$1" == "keytool" ]]; then
    # Mock keytool command - just succeed
    echo "keytool $*"
    true
  else
    "$@"
  fi
End

Mock python3
  if [[ "$1" == "-c" && "$2" == *"certifi"* ]]; then
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
  It 'requires CLOUDFLARE_DEVICE_SECRET'
    unset CLOUDFLARE_DEVICE_SECRET
    When run script scripts/setup-prerequisites.sh
    The status should be failure
    The output should include "Missing required environment variables"
  End

  It 'requires CLOUDFLARE_INSPECTION_CERTIFICATE'
    unset CLOUDFLARE_INSPECTION_CERTIFICATE
    When run script scripts/setup-prerequisites.sh
    The status should be failure
    The output should include "Missing required environment variables"
  End

  It 'requires GITHUB_ENV'
    unset GITHUB_ENV
    When run script scripts/setup-prerequisites.sh
    The status should be failure
    The output should include "Missing GitHub environment variables"
  End

  It 'requires GITHUB_OUTPUT'
    unset GITHUB_OUTPUT
    When run script scripts/setup-prerequisites.sh
    The status should be failure
    The output should include "Missing GitHub environment variables"
  End
End

Describe 'setup-prerequisites.sh main workflow'
  It 'completes successfully with all environment variables'
    When run script scripts/setup-prerequisites.sh
    The status should be success
    The output should include "Starting prerequisite setup"
    The output should include "Prerequisite setup complete"
  End

  It 'sets up device posture check'
    When run script scripts/setup-prerequisites.sh
    The status should be success
    The output should include "Setting up device posture check"
    The output should include "Device posture check configured"
  End

  It 'installs inspection certificate'
    When run script scripts/setup-prerequisites.sh
    The status should be success
    The output should include "Installing inspection certificate"
    The output should include "Inspection certificate installed"
  End

  It 'configures Java IPv4 preference'
    When run script scripts/setup-prerequisites.sh
    The status should be success
    The output should include "Configuring Java to prefer IPv4"
    The output should include "Java IPv4 preference configured"
  End
End

Describe 'setup-prerequisites.sh environment variable output'
  It 'writes certificate environment variables to GITHUB_ENV'
    When run script scripts/setup-prerequisites.sh
    The status should be success
    The contents of file "$GITHUB_ENV" should include "CLOUDFLARE_INSPECTION_CERTIFICATE_PATH=/private/etc/cloudflare-inspection.pem"
    The contents of file "$GITHUB_ENV" should include "NODE_EXTRA_CA_CERTS=/private/etc/cloudflare-inspection.pem"
    The contents of file "$GITHUB_ENV" should include "REQUESTS_CA_BUNDLE=/private/etc/ca-bundle.pem"
    The contents of file "$GITHUB_ENV" should include "AWS_CA_BUNDLE=/private/etc/ca-bundle.pem"
    The contents of file "$GITHUB_ENV" should include "SSL_CERT_FILE=/private/etc/ca-bundle.pem"
    The contents of file "$GITHUB_ENV" should include "CURL_CA_BUNDLE=/private/etc/ca-bundle.pem"
    The contents of file "$GITHUB_ENV" should include "GIT_SSL_CAINFO=/private/etc/ca-bundle.pem"
  End

  It 'writes Java IPv4 option to GITHUB_ENV'
    When run script scripts/setup-prerequisites.sh
    The status should be success
    The contents of file "$GITHUB_ENV" should include "JAVA_TOOL_OPTIONS=-Djava.net.preferIPv4Stack=true"
  End

  It 'writes certificate_path to GITHUB_OUTPUT'
    When run script scripts/setup-prerequisites.sh
    The status should be success
    The contents of file "$GITHUB_OUTPUT" should include "certificate_path=/private/etc/cloudflare-inspection.pem"
  End
End

Describe 'setup-prerequisites.sh file creation'
  It 'creates device posture file'
    When run script scripts/setup-prerequisites.sh
    The status should be success
    The file "$GLOBAL_TEST_DIR/etc/cloudflare-warp-posture.json" should be exist
  End

  It 'creates inspection certificate file'
    When run script scripts/setup-prerequisites.sh
    The status should be success
    The file "$GLOBAL_TEST_DIR/etc/cloudflare-inspection.pem" should be exist
  End

  It 'creates combined CA bundle file'
    When run script scripts/setup-prerequisites.sh
    The status should be success
    The file "$GLOBAL_TEST_DIR/etc/ca-bundle.pem" should be exist
  End
End
