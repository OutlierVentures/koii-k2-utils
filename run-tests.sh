#!/bin/bash

#
# Test runner script for BATS tests
#

set -e

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DIR="${SCRIPT_DIR}/tests"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if bats is installed
check_bats() {
    if ! command -v bats &> /dev/null; then
        print_error "BATS is not installed. Please install it first."
        echo "Installation instructions: https://bats-core.readthedocs.io/en/stable/installation.html"
        exit 1
    fi
    print_success "BATS version: $(bats --version)"
}

# Function to check if bats-support and bats-assert are available
check_bats_helpers() {
    local npm_root=""
    
    # Try to get npm global root if npm is available
    if command -v npm &> /dev/null; then
        npm_root=$(npm root -g 2>/dev/null)
    fi
    
    # Check npm location first (most common when BATS is installed via npm)
    if [ -n "$npm_root" ] && [ -f "${npm_root}/bats-assert/load.bash" ] && [ -f "${npm_root}/bats-assert/node_modules/bats-support/load.bash" ]; then
        export BATS_LIB_PATH="${npm_root}:${BATS_LIB_PATH:-}"
        return 0
    fi
    
    # Check system-wide locations
    if [ -f "/usr/local/libexec/bats-core/bats-support/load.bash" ] && [ -f "/usr/local/libexec/bats-core/bats-assert/load.bash" ]; then
        export BATS_LIB_PATH="/usr/local/libexec/bats-core:${BATS_LIB_PATH:-}"
        return 0
    fi
    
    if [ -f "/usr/libexec/bats-core/bats-support/load.bash" ] && [ -f "/usr/libexec/bats-core/bats-assert/load.bash" ]; then
        export BATS_LIB_PATH="/usr/libexec/bats-core:${BATS_LIB_PATH:-}"
        return 0
    fi
    
    # Not found
    print_error "bats-support or bats-assert not found."
    echo ""
    echo "Please install bats-support and bats-assert. They can be installed via npm or system-wide."
    echo "See README.md for more information."
    exit 1
}

# Parse command line arguments
TEST_FILE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            cat << EOF
Usage: $0 [OPTIONS] [TEST_FILE]

Run BATS tests for koii-k2-utils scripts.

Options:
    -h, --help       Show this help message

Arguments:
    TEST_FILE        Run specific test file (default: run all tests)

Examples:
    $0                          # Run all tests
    $0 tests/log-rotate.bats    # Run only log-rotate tests
    $0 tests/validators-with-info.bats  # Run only validators-with-info tests

EOF
            exit 0
            ;;
        *)
            if [ -z "$TEST_FILE" ]; then
                TEST_FILE="$1"
            else
                print_error "Unknown option or multiple test files specified: $1"
                exit 1
            fi
            shift
            ;;
    esac
done

# Check if BATS is installed
check_bats

# Check if bats-support and bats-assert are available
check_bats_helpers

# Determine which tests to run
if [ -n "$TEST_FILE" ]; then
    if [ ! -f "$TEST_FILE" ]; then
        print_error "Test file not found: $TEST_FILE"
        exit 1
    fi
    TESTS_TO_RUN="$TEST_FILE"
    print_status "Running test file: $TEST_FILE"
else
    # Find all .bats files in tests directory, excluding test_helper
    TESTS_TO_RUN=$(find "${TEST_DIR}" -name "*.bats" -type f -not -path "*/test_helper/*" | sort)
    
    if [ -z "$TESTS_TO_RUN" ]; then
        print_warning "No test files found in ${TEST_DIR}"
        exit 0
    fi
    print_status "Running all tests..."
fi

# Count tests
TEST_COUNT=$(echo "$TESTS_TO_RUN" | wc -l)
print_status "Found ${TEST_COUNT} test file(s)"
echo ""

# Function to format and run a single test file with streaming output
run_test_file_formatted() {
    local test_file="$1"
    local failure_file=$(mktemp)
    
    # Print test file path in blue
    echo -e "${BLUE}${test_file}${NC}"
    
    # Run the test file and process output line-by-line in real-time
    # Use stdbuf if available to ensure line buffering for real-time output
    local bats_cmd="env BATS_LIB_PATH=\"${BATS_LIB_PATH}\" bats \"$test_file\" 2>&1"
    if command -v stdbuf &> /dev/null; then
        bats_cmd="stdbuf -oL -eL $bats_cmd"
    fi
    
    # Run bats and capture exit code, while processing output
    (eval "$bats_cmd"; echo $? > "${failure_file}.exit") | while IFS= read -r line; do
        # Skip TAP plan line (1..N)
        if [[ $line =~ ^1\.\. ]]; then
            continue
        fi
        
        # Parse test result lines (ok/not ok)
        if [[ $line =~ ^(ok|not ok)[[:space:]]+[0-9]+[[:space:]]+(.*) ]]; then
            local status="${BASH_REMATCH[1]}"
            local test_line="${BASH_REMATCH[2]}"
            
            # Check if test is skipped
            if [[ $test_line =~ ^(.*)[[:space:]]+#[[:space:]]+skip ]]; then
                # Skip showing skipped tests (they're expected in some cases)
                continue
            else
                local test_name="$test_line"
                test_name=$(echo "$test_name" | sed 's/[[:space:]]*$//')
                
                if [ "$status" = "ok" ]; then
                    # Show checkmark for passing tests
                    echo -e " ${GREEN}✓${NC} ${test_name}"
                elif [ "$status" = "not ok" ]; then
                    # Show X for failing tests
                    echo -e " ${RED}✗${NC} ${test_name}"
                    echo "1" > "$failure_file"
                fi
            fi
        elif [[ $line =~ ^# ]]; then
            # Skip comment lines (they're usually part of error details)
            continue
        fi
    done
    
    # Read exit code and failure status
    local test_exit=$(cat "${failure_file}.exit" 2>/dev/null || echo "0")
    local has_failure=$(cat "$failure_file" 2>/dev/null || echo "0")
    
    rm -f "$failure_file" "${failure_file}.exit"
    
    echo ""
    
    # Return failure if either bats failed or we detected a failed test
    test_exit=${test_exit:-0}
    has_failure=${has_failure:-0}
    if [ "$test_exit" -ne 0 ] || [ "$has_failure" = "1" ]; then
        return 1
    fi
    return 0
}

# Run bats with BATS_LIB_PATH set
if echo "$TESTS_TO_RUN" | head -1 | grep -q .; then
    # Export BATS_LIB_PATH so bats can find the libraries
    export BATS_LIB_PATH
    
    # Run each test file separately to show formatted output
    OVERALL_EXIT=0
    while IFS= read -r test_file; do
        if [ -n "$test_file" ]; then
            run_test_file_formatted "$test_file" || OVERALL_EXIT=$?
        fi
    done <<< "$TESTS_TO_RUN"
    
    EXIT_CODE=$OVERALL_EXIT
else
    print_warning "No tests to run."
    EXIT_CODE=0
fi

if [ $EXIT_CODE -eq 0 ]; then
    print_success "All tests passed!"
else
    print_error "Some tests failed."
fi

exit $EXIT_CODE

