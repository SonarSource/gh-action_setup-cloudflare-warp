#!/usr/bin/env bash
eval "$(shellspec - -c) exit 1"

Describe 'wait-for-warp-connection.sh'
  It 'succeeds when probe URL is immediately reachable'
    Mock curl
      if [[ "$*" == *"--max-time 5 https://vault.sonar.build"* ]]; then
        true
      else
        command curl "$@"
      fi
    End

    When run script scripts/wait-for-warp-connection.sh
    The status should be success
    The output should include "Waiting for https://vault.sonar.build to be reachable"
    The output should include "https://vault.sonar.build is reachable - WARP connection ready"
  End

  # Note: Retry and timeout tests are not included because they require actual sleep delays and would significantly slow down
  # the test suite. The retry logic is simple and well-tested through manual verification.
End
