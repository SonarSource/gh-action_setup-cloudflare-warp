#!/bin/bash
# Sets up prerequisites for Cloudflare WARP: device posture check, inspection certificate, and Java IPv4 preference
set -euo pipefail

# Validate required environment variables
if [[ -z "${CLOUDFLARE_DEVICE_SECRET:-}" || -z "${CLOUDFLARE_INSPECTION_CERTIFICATE:-}" ]]; then
  echo "Error: Missing required environment variables"
  echo "Required: CLOUDFLARE_DEVICE_SECRET, CLOUDFLARE_INSPECTION_CERTIFICATE"
  exit 1
fi

if [[ -z "${GITHUB_ENV:-}" || -z "${GITHUB_OUTPUT:-}" ]]; then
  echo "Error: Missing GitHub environment variables"
  echo "Required: GITHUB_ENV, GITHUB_OUTPUT"
  exit 1
fi

# Setup device posture check file
setup_device_posture() {
  echo "Setting up device posture check..."
  sudo mkdir -p /private/etc
  echo "$CLOUDFLARE_DEVICE_SECRET" | sudo sh -c 'cat > /private/etc/cloudflare-warp-posture.json'
  echo "SHA256 hash of the posture file:"
  shasum -a 256 /private/etc/cloudflare-warp-posture.json
  echo "Device posture check configured"
}

# Install and configure inspection certificate
install_certificate() {
  echo "Installing inspection certificate..."

  # Write certificate file
  echo "$CLOUDFLARE_INSPECTION_CERTIFICATE" | sudo sh -c 'cat > /private/etc/cloudflare-inspection.pem'

  # Add to macOS keychain
  sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain /private/etc/cloudflare-inspection.pem

  # Create combined CA bundle with system certs + Cloudflare cert
  # This is needed for tools that don't use the macOS keychain (like Python/AWS CLI)
  CERTIFI_PATH=$(python3 -c "import certifi; print(certifi.where())")
  sudo sh -c "cat $CERTIFI_PATH /private/etc/cloudflare-inspection.pem > /private/etc/ca-bundle.pem"

  # Set environment variables for various tools
  {
    # Make certificate path available to subsequent steps and platform-specific tools
    echo "CLOUDFLARE_INSPECTION_CERTIFICATE_PATH=/private/etc/cloudflare-inspection.pem"

    # Node.js (adds to built-in CAs, so we only need the Cloudflare cert)
    echo "NODE_EXTRA_CA_CERTS=/private/etc/cloudflare-inspection.pem"

    # Python (requests, urllib3, etc.) - needs full CA bundle
    echo "REQUESTS_CA_BUNDLE=/private/etc/ca-bundle.pem"

    # AWS CLI and boto3 - needs full CA bundle
    echo "AWS_CA_BUNDLE=/private/etc/ca-bundle.pem"

    # General SSL/TLS tools (curl, wget, etc.) - needs full CA bundle
    echo "SSL_CERT_FILE=/private/etc/ca-bundle.pem"
    echo "CURL_CA_BUNDLE=/private/etc/ca-bundle.pem"

    # Git - needs full CA bundle
    echo "GIT_SSL_CAINFO=/private/etc/ca-bundle.pem"
  } >> "$GITHUB_ENV"

  # Import to Java trust store
  echo "Importing certificate to Java trust store..."
  sudo keytool -import -alias cloudflare-warp -cacerts -file /private/etc/cloudflare-inspection.pem -storepass changeit -noprompt || true

  # Set action output for workflows to reference
  echo "certificate_path=/private/etc/cloudflare-inspection.pem" >> "$GITHUB_OUTPUT"

  echo "Inspection certificate installed"
}

# Configure Java to prefer IPv4 for WARP compatibility
configure_java_ipv4() {
  echo "Configuring Java to prefer IPv4..."
  echo "JAVA_TOOL_OPTIONS=-Djava.net.preferIPv4Stack=true" >> "$GITHUB_ENV"
  echo "Java IPv4 preference configured"
}

# Main execution
main() {
  echo "Starting prerequisite setup..."
  setup_device_posture
  install_certificate
  configure_java_ipv4
  echo "Prerequisite setup complete!"
}

main
