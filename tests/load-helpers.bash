#!/bin/bash
#
# Helper script to load bats-support and bats-assert
# BATS_LIB_PATH should be set by the test runner
#

# Try npm location first (BATS_LIB_PATH should point to npm root)
if command -v npm &> /dev/null; then
    NPM_ROOT=$(npm root -g 2>/dev/null)
    if [ -n "$NPM_ROOT" ] && [ -f "${NPM_ROOT}/bats-assert/load.bash" ]; then
        load "${NPM_ROOT}/bats-assert/node_modules/bats-support/load"
        load "${NPM_ROOT}/bats-assert/load"
        return 0
    fi
fi

# Try system-wide locations
if [ -f "/usr/local/libexec/bats-core/bats-support/load.bash" ]; then
    load "/usr/local/libexec/bats-core/bats-support/load"
    load "/usr/local/libexec/bats-core/bats-assert/load"
    return 0
fi

if [ -f "/usr/libexec/bats-core/bats-support/load.bash" ]; then
    load "/usr/libexec/bats-core/bats-support/load"
    load "/usr/libexec/bats-core/bats-assert/load"
    return 0
fi

echo "Error: Could not find bats-support or bats-assert libraries" >&2
exit 1

