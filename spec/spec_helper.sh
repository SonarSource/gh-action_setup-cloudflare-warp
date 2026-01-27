#!/usr/bin/env bash

# Spec helper for ShellSpec tests
# This file is sourced by all spec files

# Helper function to create temp directories
create_temp_dir() {
  mktemp -d "${TMPDIR:-/tmp}/shellspec.XXXXXX"
}

# Helper function to clean up temp directories
cleanup_temp_dir() {
  local dir="$1"
  [[ -d "$dir" ]] && rm -rf "$dir"
}
