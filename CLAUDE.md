# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a GitHub composite action that sets up Cloudflare WARP on macOS runners for secure network access to SonarSource infrastructure. It solves the problem of dynamic GitHub runner IPs by routing traffic through fixed Cloudflare egress ranges.

## Architecture

### Component Flow

1. **Vault Integration** (`action.yml:13-21`)
   - Fetches 4 secrets from Vault: `client-id`, `client-secret`, `device-posture-secret`, `inspection-certificate`
   - Uses `SonarSource/vault-action-wrapper` to retrieve credentials from `development/kv/data/cloudflare/warp-github-runner`

2. **Device Posture Setup** (`action.yml:23-36`)
   - Creates `/private/etc/cloudflare-warp-posture.json` with device secret
   - Used by Cloudflare for device authentication and compliance checks

3. **Certificate Installation** (`action.yml:38-76`)
   - Installs Cloudflare inspection certificate to macOS system keychain
   - Creates combined CA bundle at `/private/etc/ca-bundle.pem` (system certs + Cloudflare cert)
   - Sets environment variables for Node.js, Python, AWS CLI, Git, curl, and other tools
   - Imports certificate to Java trust store

4. **Java IPv4 Configuration** (`action.yml:78-82`)
   - Sets `JAVA_TOOL_OPTIONS=-Djava.net.preferIPv4Stack=true` for WARP compatibility

5. **WARP Connection** (`action.yml:84-91`)
   - Delegates to `Boostport/setup-cloudflare-warp` (beta version)
   - Authenticates using retrieved credentials

6. **Connection Stabilization** (`wait-for-warp-connection.sh`)
   - Polls `https://vault.sonar.build` every 2 seconds for up to 300 seconds
   - Ensures WARP tunnel is fully established before proceeding

### Key Design Decisions

- **Composite Action**: All steps run in the user's workflow context (not a Docker/JavaScript action)
- **Combined CA Bundle**: Most tools don't use macOS keychain, so a combined bundle is created for compatibility
- **Polling Strategy**: Uses regular HTTP polling instead of sleep to verify connection readiness
- **Beta WARP**: Uses beta version for latest features and compatibility improvements

## Development Commands

### Testing Pre-commit Hooks Locally

```bash
pre-commit run --all-files
```

### Running Specific Pre-commit Hooks

```bash
pre-commit run markdownlint --all-files
pre-commit run trailing-whitespace --all-files
```

### Installing Pre-commit Hooks

```bash
pre-commit install
```

## Release Process

This repository uses semantic versioning with moving major version branches.

1. Create a GitHub release at <https://github.com/SonarSource/gh-action_setup-cloudflare-warp/releases>
   - **Patch** version (x.y.Z) for fixes
   - **Minor** version (x.Y.0) for new features
   - **Major** version (X.0.0) for breaking changes

2. Update the major version branch to point to the new tag:

   ```bash
   git fetch --tags
   git update-ref -m "reset: update branch v1 to tag 1.y.z" refs/heads/v1 1.y.z
   git push origin v1
   ```

## File Locations and Conventions

- **Action definition**: `action.yml` (composite action structure)
- **Connection verification script**: `wait-for-warp-connection.sh`
- **Certificate paths**: `/private/etc/cloudflare-inspection.pem`, `/private/etc/ca-bundle.pem`
- **Device posture file**: `/private/etc/cloudflare-warp-posture.json`

## Environment Variables Set by Action

The action automatically configures these environment variables for subsequent workflow steps:

- `NODE_EXTRA_CA_CERTS`: Cloudflare cert only (Node appends to built-in CAs)
- `REQUESTS_CA_BUNDLE`, `AWS_CA_BUNDLE`, `SSL_CERT_FILE`, `CURL_CA_BUNDLE`, `GIT_SSL_CAINFO`: Combined CA bundle
- `JAVA_TOOL_OPTIONS`: IPv4 stack preference flag

## Dependencies

- `SonarSource/vault-action-wrapper@3.1.0`: Vault secret retrieval
- `Boostport/setup-cloudflare-warp@v1.17.0`: WARP client installation
- Pre-commit hooks: trailing-whitespace, end-of-file-fixer, check-added-large-files, markdownlint

## Important Notes

- This action is **macOS-specific** and designed for GitHub-hosted macOS runners
- Must be the **first step** in any workflow requiring access to SonarSource infrastructure
- Requires `id-token: write` permission for OIDC authentication with Vault
- WARP connection verification probes `vault.sonar.build` as it's a representative internal service
