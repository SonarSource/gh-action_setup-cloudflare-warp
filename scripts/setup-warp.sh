#!/bin/bash
# Installs and configures Cloudflare WARP CLI with organization authentication
# Usage: ./setup-warp.sh --version latest --organization "Org Name" --auth-client-id "id" --auth-client-secret "secret"
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

  # Create XML plist with organization credentials
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

  echo "Configuration created"
}

# Install WARP CLI
install_warp_cli() {
  # If version is "latest" or "beta", use homebrew
  if [[ "$VERSION" == "latest" || "$VERSION" == "beta" ]]; then
    echo "Installing cloudflare-warp@${VERSION}"
    brew update
    brew install --cask "cloudflare-warp@${VERSION}"
    return 0
  fi

  # For specific versions, download and install pkg directly
  echo "Installing Cloudflare WARP ${VERSION}"

  local pkg_url="https://1111-releases.cloudflareclient.com/mac/Cloudflare_WARP_${VERSION}.pkg"
  local pkg_file="/tmp/Cloudflare_WARP.pkg"

  curl -sSL "$pkg_url" -o "$pkg_file"
  sudo installer -pkg "$pkg_file" -target /
  rm -f "$pkg_file"
}

# Retry with exponential backoff
# Max 20 attempts (~60s total) with 4s max delay to balance responsiveness vs system load
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
    echo "Registration verified"
    return 0
  fi

  return 1
}

# Verify registration with retry
verify_registration() {
  retry_with_backoff check_registration
}

# Check connection
check_connection() {
  local output
  output=$(warp-cli status 2>&1)

  # Check for Registration Missing error (indicates WARP daemon hasn't yet read the plist config)
  if echo "$output" | grep -q "Registration Missing"; then
    return 1
  fi

  # Check for Connected status
  if echo "$output" | grep -q "Status update: Connected"; then
    echo "Connection verified"
    return 0
  fi

  return 1
}

# Verify connection with retry
verify_connection() {
  retry_with_backoff check_connection
}

# Main execution
main() {
  echo "Setting up WARP ${VERSION} for ${ORGANIZATION}"

  # Step 1: Create plist configuration BEFORE installing WARP
  # The plist must exist before WARP installation so the daemon loads it on first start
  create_plist_config

  # Step 2: Install WARP
  install_warp_cli

  # Step 3: Verify registration
  verify_registration

  # Step 4: Connect to WARP
  warp-cli connect

  # Step 5: Verify connection
  verify_connection

  echo "WARP setup complete"
}

main
