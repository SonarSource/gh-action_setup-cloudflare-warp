#!/bin/bash
# Sets up prerequisites for Cloudflare WARP: device posture check, inspection certificate, and Java IPv4 preference
set -euo pipefail

readonly CERT_PATH="/private/etc/cloudflare-inspection.pem"
readonly POSTURE_PATH="/private/etc/cloudflare-warp-posture.json"
readonly CA_BUNDLE_PATH="/private/etc/ca-bundle.pem"

: "${CLOUDFLARE_DEVICE_SECRET:?}" "${CLOUDFLARE_INSPECTION_CERTIFICATE:?}"
: "${GITHUB_ENV:?}" "${GITHUB_OUTPUT:?}"

# Setup device posture check as per
# https://developers.cloudflare.com/cloudflare-one/reusable-components/posture-checks/warp-client-checks/file-check/
setup_device_posture() {
  sudo mkdir -p /private/etc
  echo "$CLOUDFLARE_DEVICE_SECRET" | sudo tee "$POSTURE_PATH" > /dev/null
  shasum -a 256 "$POSTURE_PATH"
}

install_certificate() {
  echo "$CLOUDFLARE_INSPECTION_CERTIFICATE" | sudo tee "$CERT_PATH" > /dev/null
  sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain "$CERT_PATH"

  # Create combined CA bundle with system certs + Cloudflare cert
  # This is needed for tools that don't use the macOS keychain (like Python/AWS CLI)
  CERTIFI_PATH=$(python3 -m certifi)
  sudo sh -c "cat '$CERTIFI_PATH' '$CERT_PATH' > '$CA_BUNDLE_PATH'"

  {
    echo "CLOUDFLARE_INSPECTION_CERTIFICATE_PATH=$CERT_PATH"
    # Node.js adds to built-in CAs, so only needs the Cloudflare cert
    echo "NODE_EXTRA_CA_CERTS=$CERT_PATH"
    # Other tools replace the CA bundle, so need the full bundle
    echo "REQUESTS_CA_BUNDLE=$CA_BUNDLE_PATH"
    echo "AWS_CA_BUNDLE=$CA_BUNDLE_PATH"
    echo "SSL_CERT_FILE=$CA_BUNDLE_PATH"
    echo "CURL_CA_BUNDLE=$CA_BUNDLE_PATH"
    echo "GIT_SSL_CAINFO=$CA_BUNDLE_PATH"
  } >> "$GITHUB_ENV"

  sudo keytool -import -alias cloudflare-warp -cacerts -file "$CERT_PATH" -storepass changeit -noprompt || true
  echo "certificate_path=$CERT_PATH" >> "$GITHUB_OUTPUT"
}

# Java IPv6 networking causes issues with WARP
configure_java_ipv4() {
  echo "JAVA_TOOL_OPTIONS=-Djava.net.preferIPv4Stack=true" >> "$GITHUB_ENV"
}

main() {
  setup_device_posture
  install_certificate
  configure_java_ipv4
}

main
