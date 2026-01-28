#!/usr/bin/env bash
eval "$(shellspec - -c) exit 1"

Mock warp-cli
  echo "warp-cli $*"
End

Mock sudo
  echo "sudo $*"
End

Mock command
  echo "command $*"
End

Describe 'cleanup-warp.sh'
  It 'runs successfully and executes expected commands'
    When run script scripts/cleanup-warp.sh
    The status should be success
    The output should include "warp-cli --accept-tos disconnect"
    The output should include "sudo warp-cli --accept-tos registration delete"
    The output should include "WARP cleanup complete"
  End
End
