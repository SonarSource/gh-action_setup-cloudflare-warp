# Setup Cloudflare WARP

GitHub Action to setup Cloudflare WARP with device posture check and inspection certificate for secure network access on GitHub MacOS runners.

## Features

- **Device Posture Check**: Automatically configures
  [device posture check](https://developers.cloudflare.com/cloudflare-one/identity/devices/) file for Cloudflare Zero Trust
- **Certificate Installation**: Installs Cloudflare inspection certificate to system keychain
- **Fixed Egress CIDR**: All traffic is routed through Cloudflare Egress ranges assigned to SonarSource, allowing us to
  configure Firewalls with IP Allowlist

## When to use this action?

Use this action as the **first step** in any workflow job running on GitHub macOS runners that needs secure access to
SonarSource infrastructure.

### Required for

- **Accessing internal services**: Vault, Develocity, SonarQube instances, and other firewall-protected services
- **Cloning private repositories**: Any repositories within the `SonarSource` or `Sonar-Private` GitHub organizations

### Why is this needed?

GitHub-hosted macOS runners use dynamic IP addresses that change with each run, making it impossible to allowlist them in
firewalls. This action establishes a secure tunnel through Cloudflare WARP, routing all traffic through SonarSource's fixed
egress IP ranges. This allows our infrastructure to recognize and trust the runner connections.

> **Note**: This action is specifically designed for macOS runners. Linux and Windows runners have different networking
> configurations and may not require WARP.

## Requirements

### Required GitHub Permissions

- `id-token: write`

### Required Vault Permissions

- `development/kv/data/cloudflare/warp-github-runner`: Cloudflare WARP credentials including:
  - `client-id`: Cloudflare authentication client ID
  - `client-secret`: Cloudflare authentication client secret
  - `device-posture-secret`: Device posture check secret JSON
  - `inspection-certificate`: Cloudflare inspection certificate PEM

## Usage

```yaml
jobs:
  build:
    runs-on: macos-latest-xlarge
    permissions:
      id-token: write
      contents: read
    steps:
      - name: Setup Cloudflare WARP
        uses: SonarSource/gh-action_setup-cloudflare-warp@v1

      # WARP connection is now ready - proceed with your workflow steps
      - name: Your build steps
        run: |
          # Network requests will now go through Cloudflare WARP
          curl -s https://ifconfig.me
```

## Inputs

This action requires no inputs

## Outputs

| Output | Description |
|--------|-------------|
| `certificate_path` | Path to the Cloudflare inspection certificate (`/private/etc/cloudflare-inspection.pem`) |

## Environment Variables

This action automatically sets the following environment variables for subsequent steps,
enabling various tools and platforms to use the Cloudflare inspection certificate:

| Variable | Description | Used By |
|----------|-------------|---------|
| `CLOUDFLARE_INSPECTION_CERTIFICATE_PATH` | Path to the Cloudflare certificate only | General reference |
| `NODE_EXTRA_CA_CERTS` | Path to Cloudflare certificate (adds to Node's built-in CAs) | Node.js, npm, yarn |
| `REQUESTS_CA_BUNDLE` | Path to combined CA bundle (system CAs + Cloudflare cert) | Python (requests, urllib3) |
| `AWS_CA_BUNDLE` | Path to combined CA bundle (system CAs + Cloudflare cert) | AWS CLI, boto3, botocore |
| `SSL_CERT_FILE` | Path to combined CA bundle (system CAs + Cloudflare cert) | curl, wget, OpenSSL-based tools, C/C++ apps |
| `CURL_CA_BUNDLE` | Path to combined CA bundle (system CAs + Cloudflare cert) | curl and curl-based tools |
| `GIT_SSL_CAINFO` | Path to combined CA bundle (system CAs + Cloudflare cert) | Git operations |

**Note:** The action creates a combined CA bundle at `/private/etc/ca-bundle.pem` that includes both the system's trusted certificates
and the Cloudflare inspection certificate. This ensures that tools can verify both standard SSL certificates
and connections inspected by Cloudflare WARP.

## How It Works

1. **Fetches Secrets**: Retrieves all necessary credentials from Vault
2. **Device Posture Setup**: Creates the device posture check file at `/private/etc/cloudflare-warp-posture.json`
3. **Certificate Installation**:
   - Adds Cloudflare inspection certificate to macOS system keychain
   - Creates a combined CA bundle (`/private/etc/ca-bundle.pem`) with system certificates + Cloudflare certificate
   - Imports certificate to Java trust store
   - Sets environment variables for various tools
4. **WARP Setup**: Calls the Boostport/setup-cloudflare-warp action with authentication
5. **Stabilization**: Waits for the connection to stabilize

## Release

1. Create a new GitHub release on <https://github.com/SonarSource/gh-action_setup-cloudflare-warp/releases>

    Increase the **patch** number for **fixes**, the **minor** number for **new features**, and the **major** number for **breaking changes**.

    Edit the generated release notes to curate the highlights and key fixes, add notes, provide samples of new usage if applicable...

   Make sure to include any **breaking changes** in the notes.

2. After release, the `v*` branch must be updated for pointing to the new tag.

    ```shell
    git fetch --tags
    git update-ref -m "reset: update branch v1 to tag 1.y.z" refs/heads/v1 1.y.z
    git push origin v1
    ```
