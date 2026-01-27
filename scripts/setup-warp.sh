#!/bin/bash
set -euo pipefail

# Parse arguments
VERSION=""
ORGANIZATION=""
AUTH_CLIENT_ID=""
AUTH_CLIENT_SECRET=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --version)
      VERSION="$2"
      shift 2
      ;;
    --organization)
      ORGANIZATION="$2"
      shift 2
      ;;
    --auth-client-id)
      AUTH_CLIENT_ID="$2"
      shift 2
      ;;
    --auth-client-secret)
      AUTH_CLIENT_SECRET="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Validate required parameters
if [[ -z "$VERSION" || -z "$ORGANIZATION" || -z "$AUTH_CLIENT_ID" || -z "$AUTH_CLIENT_SECRET" ]]; then
  echo "Error: Missing required parameters"
  exit 1
fi

# Create plist configuration
create_plist_config() {
  local plist_xml="/tmp/com.cloudflare.warp.plist"
  local plist_dest="/Library/Managed Preferences/com.cloudflare.warp.plist"

  # Create XML plist
  cat > "$plist_xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>organization</key>
  <string>${ORGANIZATION}</string>
  <key>auth_client_id</key>
  <string>${AUTH_CLIENT_ID}</string>
  <key>auth_client_secret</key>
  <string>${AUTH_CLIENT_SECRET}</string>
</dict>
</plist>
EOF

  # Convert to binary plist
  plutil -convert binary1 "$plist_xml"

  # Move to managed preferences
  sudo mkdir -p "$(dirname "$plist_dest")"
  sudo mv "$plist_xml" "$plist_dest"

  echo "Plist configuration created at $plist_dest"
}

# Install WARP CLI
install_warp_cli() {
  if command -v warp-cli &> /dev/null; then
    echo "warp-cli already installed, skipping installation"
    return 0
  fi

  echo "Installing cloudflare-warp@${VERSION}..."
  brew update
  brew install --cask "cloudflare-warp@${VERSION}"
  echo "WARP installation complete"
}

# Retry with exponential backoff
retry_with_backoff() {
  local max_attempts=20
  local delay=1
  local max_delay=4
  local attempt=1

  while [ $attempt -le $max_attempts ]; do
    if "$@"; then
      return 0
    fi

    if [ $attempt -eq $max_attempts ]; then
      echo "Failed after $max_attempts attempts"
      return 1
    fi

    echo "Attempt $attempt failed, retrying in ${delay}s..."
    sleep $delay

    # Exponential backoff with max delay
    delay=$((delay * 2))
    if [ $delay -gt $max_delay ]; then
      delay=$max_delay
    fi

    attempt=$((attempt + 1))
  done
}

# Check registration
check_registration() {
  local output
  output=$(warp-cli settings 2>&1)

  if echo "$output" | grep -q "Organization: ${ORGANIZATION}"; then
    echo "Registration verified for organization: ${ORGANIZATION}"
    return 0
  fi

  return 1
}

# Verify registration with retry
verify_registration() {
  echo "Verifying WARP registration..."
  retry_with_backoff check_registration
}

# Check connection
check_connection() {
  local output
  output=$(warp-cli status 2>&1)

  # Check for Registration Missing error
  if echo "$output" | grep -q "Registration Missing"; then
    echo "Registration Missing error detected, retrying..."
    return 1
  fi

  # Check for Connected status
  if echo "$output" | grep -q "Status update: Connected"; then
    echo "WARP connection verified"
    return 0
  fi

  return 1
}

# Verify connection with retry
verify_connection() {
  echo "Verifying WARP connection..."
  retry_with_backoff check_connection
}

# Main execution
main() {
  echo "Starting WARP setup..."
  echo "Version: ${VERSION}"
  echo "Organization: ${ORGANIZATION}"

  # Step 1: Create plist configuration BEFORE installing WARP
  create_plist_config

  # Step 2: Install WARP
  install_warp_cli

  # Step 3: Verify registration
  verify_registration

  # Step 4: Connect to WARP
  echo "Connecting to WARP..."
  warp-cli connect

  # Step 5: Verify connection
  verify_connection

  echo "WARP setup complete!"
}

main
