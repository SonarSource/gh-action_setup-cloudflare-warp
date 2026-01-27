#!/usr/bin/env bash
set -euo pipefail

# Run ShellSpec tests
shellspec spec "$@" --shell bash
