#!/usr/bin/env bats

#
# Integration tests for validators-with-info.sh
# These tests call the real koii RPC and require network connectivity
#

# Load helper libraries (supports npm and system-wide installations)
# Use BATS_TEST_FILENAME to find the test directory
TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
source "${TEST_DIR}/load-helpers.bash"

# Get the directory of this test file (redefine after sourcing helper)
PROJECT_ROOT="$(cd "${TEST_DIR}/.." && pwd)"
SCRIPT_PATH="${PROJECT_ROOT}/monitoring/validators-with-info.sh"

setup() {
    # Integration tests use the real koii command, no mocks needed
    # Just verify koii is available
    if ! command -v koii &> /dev/null; then
        skip "koii command not found - integration tests require koii CLI"
    fi
}

@test "script works with real koii RPC" {
    # Run the script with real RPC
    run bash "${SCRIPT_PATH}"
    assert_success
    
    # Should have some output
    assert [ -n "$output" ]
    
    # Should contain header
    assert_output --partial "Identity"
    assert_output --partial "Vote Account"
}

@test "all validators from raw output are present in enhanced output" {
    # Get raw validators output
    run koii validators
    assert_success
    raw_output="$output"
    
    # Extract validator identities from raw output
    # Identity is typically in field 2 (field 1 may be space or warning symbol)
    # Match validator lines (skip header) and extract the identity field
    raw_identities=$(echo "$raw_output" | awk 'NF > 5 && ($1 ~ /^[1-9A-HJ-NP-Za-km-z]{32,44}$/ || $2 ~ /^[1-9A-HJ-NP-Za-km-z]{32,44}$/) {if ($1 ~ /^[1-9A-HJ-NP-Za-km-z]{32,44}$/) print $1; else if ($2 ~ /^[1-9A-HJ-NP-Za-km-z]{32,44}$/) print $2}' | sort -u)
    
    # Get enhanced output (without mock)
    run bash "${SCRIPT_PATH}"
    assert_success
    enhanced_output="$output"
    
    # Extract validator identities from enhanced output (same approach)
    enhanced_identities=$(echo "$enhanced_output" | awk 'NF > 5 && ($1 ~ /^[1-9A-HJ-NP-Za-km-z]{32,44}$/ || $2 ~ /^[1-9A-HJ-NP-Za-km-z]{32,44}$/) {if ($1 ~ /^[1-9A-HJ-NP-Za-km-z]{32,44}$/) print $1; else if ($2 ~ /^[1-9A-HJ-NP-Za-km-z]{32,44}$/) print $2}' | sort -u)
    
    # Count validators in each output
    raw_count=$(echo "$raw_identities" | grep -c . || echo "0")
    enhanced_count=$(echo "$enhanced_identities" | grep -c . || echo "0")
    
    # Both should have validators
    assert [ "$raw_count" -gt 0 ]
    assert [ "$enhanced_count" -gt 0 ]
    
    # Enhanced output should have the same number of validator identities
    if [ "$raw_count" -ne "$enhanced_count" ]; then
        echo "Validator count mismatch: raw=$raw_count, enhanced=$enhanced_count" >&2
        false
    fi
    
    # Every validator identity from raw output should be in enhanced output
    missing_validators=""
    while IFS= read -r identity; do
        if [ -n "$identity" ]; then
            if ! echo "$enhanced_identities" | grep -q "^${identity}$"; then
                missing_validators="${missing_validators}${identity}\n"
            fi
        fi
    done <<< "$raw_identities"
    
    assert [ -z "$missing_validators" ] || {
        echo "Missing validators in enhanced output:"
        echo -e "$missing_validators"
        echo "Raw identities count: $raw_count"
        echo "Enhanced identities count: $enhanced_count"
        false
    }
}

@test "enhanced output preserves validator data integrity" {
    # Get raw validators output
    run koii validators
    assert_success
    raw_output="$output"
    
    # Get enhanced output
    run bash "${SCRIPT_PATH}"
    assert_success
    enhanced_output="$output"
    
    # Extract first validator identity from raw output
    first_identity=$(echo "$raw_output" | awk 'NF > 5 && ($1 ~ /^[1-9A-HJ-NP-Za-km-z]{32,44}$/ || $2 ~ /^[1-9A-HJ-NP-Za-km-z]{32,44}$/) {if ($1 ~ /^[1-9A-HJ-NP-Za-km-z]{32,44}$/) {print $1; exit} else if ($2 ~ /^[1-9A-HJ-NP-Za-km-z]{32,44}$/) {print $2; exit}}')
    
    if [ -z "$first_identity" ]; then
        skip "No validators found in raw output"
    fi
    
    # Find the corresponding line in raw output
    raw_line=$(echo "$raw_output" | grep -E "(^|[[:space:]])${first_identity}" | head -1)
    
    # Find the corresponding line in enhanced output
    enhanced_line=$(echo "$enhanced_output" | grep -E "(^|[[:space:]])${first_identity}" | head -1)
    
    # Enhanced line should contain the identity
    assert [ -n "$enhanced_line" ]
    
    # Extract key fields from raw line (identity is in field 1 or 2)
    raw_identity=$(echo "$raw_line" | awk '{if ($1 ~ /^[1-9A-HJ-NP-Za-km-z]{32,44}$/) print $1; else if ($2 ~ /^[1-9A-HJ-NP-Za-km-z]{32,44}$/) print $2}')
    enhanced_identity=$(echo "$enhanced_line" | awk '{if ($1 ~ /^[1-9A-HJ-NP-Za-km-z]{32,44}$/) print $1; else if ($2 ~ /^[1-9A-HJ-NP-Za-km-z]{32,44}$/) print $2}')
    
    # Identities should match
    if [ "$raw_identity" != "$enhanced_identity" ]; then
        echo "Identity mismatch: raw=$raw_identity, enhanced=$enhanced_identity" >&2
        false
    fi
}

@test "script handles real RPC with sorting options" {
    # Test with skiprate sorting
    run bash "${SCRIPT_PATH}" -s skiprate
    assert_success
    assert_output --partial "Identity"
    
    # Test with credits sorting
    run bash "${SCRIPT_PATH}" -s credits
    assert_success
    assert_output --partial "Identity"
    
    # Test with multiple sort criteria
    run bash "${SCRIPT_PATH}" -s skiprate,credits
    assert_success
    assert_output --partial "Identity"
}

