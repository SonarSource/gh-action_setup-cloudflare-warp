# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a GitHub composite action that sets up Cloudflare WARP on macOS runners to provide secure network access to
SonarSource infrastructure. The action solves the problem of GitHub-hosted runners having dynamic IPs by routing all
traffic through Cloudflare's fixed egress IP ranges.

**Critical constraint:** This action MUST be used as the first step in any workflow job on macOS runners that needs to
access SonarSource internal services or clone private repositories.

## Development Commands

### Testing

```bash
# Run all ShellSpec tests
bash run_shell_tests.sh

# Run specific test file
shellspec spec/setup-warp_spec.sh

# Run with verbose output
shellspec spec --format documentation
```

Tests use ShellSpec mocking framework to simulate `brew`, `warp-cli`, `sudo`, and other system commands without
requiring actual system modifications or sudo privileges.

### Linting

```bash
# Run pre-commit hooks manually
pre-commit run --all-files

# Install pre-commit hooks
pre-commit install
```

Configured hooks:

- `trailing-whitespace`, `end-of-file-fixer`, `check-added-large-files` (standard pre-commit)
- `markdownlint` (validates markdown formatting)

## Architecture

### Action Flow (action.yml)

The composite action executes 6 sequential steps:

1. **Get secrets from Vault** - Retrieves 4 credentials using `vault-action-wrapper`:
   - `client-id` / `client-secret` - Cloudflare WARP authentication
   - `device-posture-secret` - Device posture check JSON
   - `inspection-certificate` - Cloudflare TLS inspection certificate PEM

2. **Setup Device Posture Check** - Writes posture JSON to `/private/etc/cloudflare-warp-posture.json`

3. **Install inspection certificate** - Multi-step certificate setup:
   - Writes cert to `/private/etc/cloudflare-inspection.pem`
   - Adds to macOS system keychain (`security add-trusted-cert`)
   - Creates combined CA bundle at `/private/etc/ca-bundle.pem` (system CAs + Cloudflare cert)
   - Imports to Java trust store (`keytool`)
   - Sets 7 environment variables for different tools (NODE_EXTRA_CA_CERTS, REQUESTS_CA_BUNDLE, AWS_CA_BUNDLE,
     SSL_CERT_FILE, CURL_CA_BUNDLE, GIT_SSL_CAINFO)

4. **Disable IPv6 for Java** - Sets `JAVA_TOOL_OPTIONS=-Djava.net.preferIPv4Stack=true`

5. **Setup Cloudflare WARP** - Calls `scripts/setup-warp.sh` with organization credentials

6. **Wait for WARP connection** - Calls `wait-for-warp-connection.sh` (continues on error)

### Core Script: scripts/setup-warp.sh

**Critical ordering requirement:** The plist configuration MUST be created BEFORE installing WARP so the daemon loads
it on first start.

Main execution flow:

1. Create plist config at `/Library/Managed Preferences/com.cloudflare.warp.plist` (binary plist format)
2. Install WARP CLI via `brew install --cask cloudflare-warp@VERSION`
3. Verify registration with retry logic (checks `warp-cli settings` for organization name)
4. Connect to WARP (`warp-cli connect`)
5. Verify connection with retry logic (checks `warp-cli status` for "Connected")

**Retry logic:** Exponential backoff with 20 max attempts (~60s total), 1s initial delay, 4s max delay.
Rationale: Balance responsiveness vs system load.

**"Registration Missing" error:** Indicates WARP daemon hasn't yet read the plist config file - normal during startup,
resolved by retry logic.

### Connection Verification: wait-for-warp-connection.sh

Polls `https://vault.sonar.build` (internal service) to verify WARP connectivity:

- Max wait: 300 seconds
- Poll interval: 2 seconds
- Uses `curl --max-time 5` with silent mode

This verifies actual connectivity to internal infrastructure, not just WARP connection status.

### Testing Strategy

Tests in `spec/setup-warp_spec.sh` use ShellSpec's mocking system to:

1. **Mock brew** - Returns success without actual installation
2. **Mock warp-cli** - Returns appropriate output for `settings`, `status`, `connect` commands
3. **Mock sudo** - Redirects `/Library` paths to `$GLOBAL_TEST_DIR` using shell parameter expansion `${path#/Library}`
4. **Mock plutil** - Succeeds silently (no actual binary plist conversion)
5. **Mock command** - Simulates `warp-cli` being installed

All tests run in isolated temp directory (`GLOBAL_TEST_DIR`) to avoid touching system files.

## Important Constraints

### WARP Version Parameter

The `--version` parameter in `setup-warp.sh` accepts ONLY:

- `latest` - Latest stable release
- `beta` - Beta version (currently used)

**Do NOT use arbitrary version numbers** (e.g., `2024.6.474.0`). The parameter is passed directly to
`brew install --cask cloudflare-warp@VERSION`.

### macOS Only

This action is designed exclusively for macOS runners. The implementation relies on:

- macOS security keychain (`security add-trusted-cert`)
- macOS plist system (`plutil`, `/Library/Managed Preferences/`)
- Homebrew for WARP installation

### Organization-Specific

Hardcoded for SonarSource:

- Organization: `sonarsource`
- Probe URL: `https://vault.sonar.build`
- Vault path: `development/kv/data/cloudflare/warp-github-runner`

## Release Process

1. Create GitHub release at `https://github.com/SonarSource/gh-action_setup-cloudflare-warp/releases`
   - Patch: Bug fixes
   - Minor: New features
   - Major: Breaking changes

2. Update version branch to point to new tag:
   ```bash
   git fetch --tags
   git update-ref -m "reset: update branch v2 to tag v2.y.z" refs/heads/v2 v2.y.z
   git push origin v2
   ```

This allows users to reference `@v2` in workflows, which automatically gets the latest v2.x.y release.
