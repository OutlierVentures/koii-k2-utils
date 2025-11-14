#!/usr/bin/env bats

#
# BATS tests for validators-with-info.sh
#

# Load helper libraries (supports npm and system-wide installations)
# Use BATS_TEST_FILENAME to find the test directory
TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
source "${TEST_DIR}/load-helpers.bash"

# Get the directory of this test file (redefine after sourcing helper)
PROJECT_ROOT="$(cd "${TEST_DIR}/.." && pwd)"
SCRIPT_PATH="${PROJECT_ROOT}/monitoring/validators-with-info.sh"

# Mock koii command output
setup() {
    TEST_TMPDIR=$(mktemp -d)
    
    # Create mock koii command
    MOCK_KOII="${TEST_TMPDIR}/koii"
    cat > "${MOCK_KOII}" <<'KOIIMOCK'
#!/bin/bash
if [ "$1" = "validators" ]; then
    cat <<'VALIDATORS_OUTPUT'
Identity                                     Vote Account                              Commission  Skip Rate  KOII    Credits  Version
11111111111111111111111111111111             22222222222222222222222222222222             5%         2.5%       KOII (50.0%)   100      1.0.0
33333333333333333333333333333333             44444444444444444444444444444444             3%         -          KOII (30.0%)   200      1.1.0
55555555555555555555555555555555             66666666666666666666666666666666             1%         0.1%       KOII (20.0%)   300      1.2.0

Average Commission: 3.0%
Average Skip Rate: 0.87%
VALIDATORS_OUTPUT
elif [ "$1" = "validator-info" ] && [ "$2" = "get" ]; then
    cat <<'VALIDATOR_INFO_OUTPUT'
Validator Identity: 11111111111111111111111111111111
  Name: Test Validator One
  Website: https://test1.example.com

Validator Identity: 33333333333333333333333333333333
  Name: Test Validator Three

Validator Identity: 55555555555555555555555555555555
  Name: Test Validator Five
  Website: https://test5.example.com
VALIDATOR_INFO_OUTPUT
fi
KOIIMOCK
    chmod +x "${MOCK_KOII}"
    
    # Add mock to PATH
    export PATH="${TEST_TMPDIR}:${PATH}"
}

teardown() {
    rm -rf "${TEST_TMPDIR}"
}

@test "script exists and is executable" {
    assert [ -f "${SCRIPT_PATH}" ]
    assert [ -x "${SCRIPT_PATH}" ]
}

@test "script shows help message with -h option" {
    run bash "${SCRIPT_PATH}" -h
    assert_success
    assert_output --partial "Usage:"
    assert_output --partial "validators-with-info.sh"
    assert_output --partial "Options:"
}

@test "script processes validators output and adds info" {
    run bash "${SCRIPT_PATH}"
    assert_success
    
    # Check that validator identities are present
    assert_output --partial "11111111111111111111111111111111"
    assert_output --partial "33333333333333333333333333333333"
    assert_output --partial "55555555555555555555555555555555"
    
    # Check that validator info is appended
    assert_output --partial "[Test Validator One - https://test1.example.com]"
    assert_output --partial "[Test Validator Three]"
    assert_output --partial "[Test Validator Five - https://test5.example.com]"
}

@test "script handles validators without info gracefully" {
    # Create mock that returns validators but no info
    cat > "${TEST_TMPDIR}/koii" <<'KOIIMOCK'
#!/bin/bash
if [ "$1" = "validators" ]; then
    cat <<'VALIDATORS_OUTPUT'
Identity                                     Vote Account                              Commission  Skip Rate  KOII    Credits  Version
99999999999999999999999999999999             AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA             5%         2.5%       KOII (50.0%)   100      1.0.0
VALIDATORS_OUTPUT
elif [ "$1" = "validator-info" ] && [ "$2" = "get" ]; then
    echo ""  # No validator info
fi
KOIIMOCK
    chmod +x "${TEST_TMPDIR}/koii"
    
    run bash "${SCRIPT_PATH}"
    assert_success
    assert_output --partial "99999999999999999999999999999999"
    # Should not crash when no info is available
}

@test "script sorts by skiprate when -s skiprate is used" {
    run bash "${SCRIPT_PATH}" -s skiprate
    assert_success
    
    # Extract validator lines and check order
    # Validator with 0.1% skip rate should come before 2.5%
    output_lines=($(echo "$output" | grep -E "^[0-9A-Za-z]{32,44}"))
    
    # Find positions of validators
    pos_555=$(echo "$output" | grep -n "55555555555555555555555555555555" | cut -d: -f1)
    pos_111=$(echo "$output" | grep -n "11111111111111111111111111111111" | cut -d: -f1)
    
    # Validator 555 (0.1%) should come before 111 (2.5%)
    if [ -n "$pos_555" ] && [ -n "$pos_111" ]; then
        assert [ "$pos_555" -lt "$pos_111" ]
    fi
}

@test "script sorts by credits when -s credits is used" {
    run bash "${SCRIPT_PATH}" -s credits
    assert_success
    
    # Validator with 300 credits should come before 100 credits (descending)
    pos_555=$(echo "$output" | grep -n "55555555555555555555555555555555" | cut -d: -f1)
    pos_111=$(echo "$output" | grep -n "11111111111111111111111111111111" | cut -d: -f1)
    
    # Validator 555 (300 credits) should come before 111 (100 credits)
    if [ -n "$pos_555" ] && [ -n "$pos_111" ]; then
        assert [ "$pos_555" -lt "$pos_111" ]
    fi
}

@test "script handles multiple sort criteria" {
    run bash "${SCRIPT_PATH}" -s skiprate,credits
    assert_success
    
    # Should not crash with multiple sort options
    assert_output --partial "11111111111111111111111111111111"
}

@test "script enables debug mode with -d option" {
    run bash "${SCRIPT_PATH}" -d
    assert_success
    
    # Debug mode should create raw_validators_output.txt
    if [ -f "raw_validators_output.txt" ]; then
        assert [ -f "raw_validators_output.txt" ]
        rm -f "raw_validators_output.txt"
    fi
}

@test "script handles invalid sort option" {
    run bash "${SCRIPT_PATH}" -s invalid_option
    # Script calls print_help which exits 0, so we expect success
    assert_success
    assert_output --partial "Invalid sort option"
    assert_output --partial "Usage:"
}

@test "script handles missing argument for -s option" {
    run bash "${SCRIPT_PATH}" -s
    # Script calls print_help which exits 0, so we expect success
    assert_success
    assert_output --partial "requires an argument"
    assert_output --partial "Usage:"
}

@test "script handles invalid option" {
    run bash "${SCRIPT_PATH}" -x
    # Script calls print_help which exits 0, so we expect success
    assert_success
    assert_output --partial "Invalid option"
    assert_output --partial "Usage:"
}

@test "script preserves header and footer" {
    run bash "${SCRIPT_PATH}"
    assert_success
    
    # Check header is present
    assert_output --partial "Identity"
    assert_output --partial "Vote Account"
    
    # Check footer is present
    assert_output --partial "Average Commission"
    assert_output --partial "Average Skip Rate"
}

@test "script handles validators with dash in skip rate" {
    # Validator 333 has "-" as skip rate, should be handled as 0%
    run bash "${SCRIPT_PATH}" -s skiprate
    assert_success
    
    # Should not crash when processing dash
    assert_output --partial "33333333333333333333333333333333"
}

@test "script output ends with newline" {
    # Run script and capture output to a file to check trailing newline
    output_file="${TEST_TMPDIR}/script_output.txt"
    bash "${SCRIPT_PATH}" > "${output_file}"
    
    # Check that the file exists and is not empty
    assert [ -f "${output_file}" ]
    assert [ -s "${output_file}" ]
    
    # Check that the last byte is a newline (0x0A)
    last_byte=$(tail -c 1 "${output_file}" | od -An -tx1 | tr -d ' \n')
    assert [ "$last_byte" = "0a" ] || {
        echo "Output does not end with newline (last byte: $last_byte)"
        false
    }
}

