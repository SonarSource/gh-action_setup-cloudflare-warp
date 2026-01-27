#!/usr/bin/env bash
# Runs all ShellSpec tests in spec/ directory using bash shell
set -euo pipefail
shellspec spec "$@" --shell bash
