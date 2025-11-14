#!/bin/bash

#
# Enhances the output of 'koii validators' command by appending validator names
# and websites from 'koii validator-info get' command. For each validator that
# has registered their information, the script adds [name - website] or [name]
# at the end of the line after the KOII percentage.
#

# Print help message
print_help() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Enhances the output of 'koii validators' command by appending validator names
and websites from 'koii validator-info get' command.

Options:
    -h          Show this help message
    -s SORT     Sort validators by specified criteria. Multiple criteria can be
                comma-separated. Available options:
                  skiprate: Sort by skip rate (ascending)
                  credits:  Sort by credits (descending)
                Example: -s skiprate,credits
    -d          Debug mode: save raw validator output to file

EOF
    exit 0
}

# Default values
sort_order=()
debug=false

# Parse arguments using getopts
while getopts ":s:dh" opt; do
    case ${opt} in
        s )
            IFS=',' read -ra SORT_OPTS <<< "$OPTARG"
            for opt in "${SORT_OPTS[@]}"; do
                case $opt in
                    credits) sort_order+=("credits") ;;
                    skiprate) sort_order+=("skiprate") ;;
                    *)
                        echo "Invalid sort option: $opt" 1>&2
                        print_help
                        ;;
                esac
            done
            ;;
        d )
            debug=true
            ;;
        h )
            print_help
            ;;
        \? )
            echo "Invalid option: -$OPTARG" 1>&2
            print_help
            ;;
        : )
            echo "Option -$OPTARG requires an argument" 1>&2
            print_help
            ;;
    esac
done

# Get the raw validators output and validator info
validators_output=$(koii validators)
[ "$debug" = true ] && echo "$validators_output" > raw_validators_output.txt
validator_info=$(koii validator-info get)

# Process the validators output line by line
process_validator_line() {
    local line="$1"
    
    # Skip header and version statistics lines
    local header_pattern='^[[:space:]]*Identity'
    local version_pattern='^[0-9]+\.[0-9]+\.[0-9]+[[:space:]]+-|^unknown[[:space:]]+-'
    [[ $line =~ $header_pattern || $line =~ $version_pattern ]] && echo "$line" && return
    
    # Extract validator identity
    if [[ $line =~ [1-9A-HJ-NP-Za-km-z]{32,44} ]]; then
        local validator_id="${BASH_REMATCH[0]}"
        
        # Find the corresponding info block
        local info_block
        info_block=$(echo "$validator_info" | awk -v id="$validator_id" '
            $0 == "Validator Identity: "id {
                found = 1
                p = 1
                next
            }
            p && /^Validator Identity:/ {
                p = 0
            }
            p {
                print
            }
        ')
        
        # Extract name and website
        local name website
        name=$(echo "$info_block" | grep "  Name: " | sed 's/  Name: //')
        website=$(echo "$info_block" | grep "  Website: " | sed 's/  Website: //')
        
        # Append info if available
        if [ -n "$name" ] && [[ $line =~ (.*)KOII[[:space:]]*\([0-9.]+%\) ]]; then
            if [ -n "$website" ]; then
                printf "%s    [%s - %s]\n" "$line" "$name" "$website"
            else
                printf "%s    [%s]\n" "$line" "$name"
            fi
            return
        fi
    fi
    echo "$line"
}

# Extract numeric value from skip rate column for sorting
extract_skiprate() {
    local line="$1"
    # Extract skip rate using awk - find the 2nd percentage field
    # First percentage is commission, second is skip rate
    local skiprate=$(echo "$line" | awk '{
        count = 0
        for(i=1;i<=NF;i++) {
            if($i ~ /%$/) {
                count++
                if(count == 2) {
                    print $i
                    exit
                }
            }
        }
    }')
    
    if [[ -z "$skiprate" ]]; then
        # Check for "-" in skip rate position - treat as 0% skip rate
        if echo "$line" | awk '{for(i=1;i<=NF;i++) if($i == "-" && i > 7) {print $i; exit}}' | grep -q "-"; then
            echo "0.00"
        else
            echo "0.00"
        fi
    else
        # Remove % sign and convert to number, ensure it's a valid float
        local num=$(echo "$skiprate" | sed 's/%//' | awk '{printf "%.2f", $1+0}')
        echo "${num:-0.00}"
    fi
}

# Extract numeric value from credits column for sorting
extract_credits() {
    local line="$1"
    # Credits is the integer number that appears after skip rate and before version
    # Version is in format X.Y.Z, so credits is the number just before that pattern
    local credits=$(echo "$line" | awk '{
        for(i=1;i<=NF;i++) {
            # Check if current field matches version pattern X.Y.Z
            if($i ~ /^[0-9]+\.[0-9]+\.[0-9]+$/) {
                # Previous field should be credits
                if(i > 1) print $(i-1)
                exit
            }
        }
    }')
    
    # Convert to number, handle empty as 0, ensure it's a valid integer
    local num=$(echo "${credits:-0}" | awk '{printf "%d", $1+0}')
    echo "${num:-0}"
}

# Custom sort function that handles skip rate and credits properly
custom_sort() {
    local lines=("$@")
    local i
    local temp_file=$(mktemp)
    # Use a control character as delimiter (very unlikely to appear in validator output)
    local DELIM=$'\x01'
    
    # Build sort keys and write to temp file with format: sort_key<DELIM>index<DELIM>line
    for i in "${!lines[@]}"; do
        local line="${lines[$i]}"
        local sort_key=""
        
        # Check if this is a validator line
        if [[ $line =~ [1-9A-HJ-NP-Za-km-z]{32,44} ]]; then
            # Build sort key based on sort_order
            for criterion in "${sort_order[@]}"; do
                case $criterion in
                    skiprate)
                        local skiprate_val=$(extract_skiprate "$line")
                        # Ensure skiprate_val is numeric, default to 0
                        skiprate_val=$(echo "$skiprate_val" | awk '{printf "%.2f", $1+0}')
                        # Format with leading zeros for proper numeric sorting
                        local skiprate_formatted=$(printf "%010.2f" "$skiprate_val" 2>/dev/null || echo "000000.00")
                        sort_key="${sort_key}${skiprate_formatted}|"
                        ;;
                    credits)
                        local credits_val=$(extract_credits "$line")
                        # Ensure credits_val is numeric, default to 0
                        credits_val=$(echo "$credits_val" | awk '{printf "%d", $1+0}')
                        # Invert for descending sort (subtract from large number)
                        local inverted_credits=$((999999999 - credits_val))
                        local credits_formatted=$(printf "%09d" "$inverted_credits" 2>/dev/null || echo "999999999")
                        sort_key="${sort_key}${credits_formatted}|"
                        ;;
                esac
            done
            # Add identity as final tiebreaker
            local identity=$(echo "$line" | awk '{print $1}')
            sort_key="${sort_key}${identity}"
        else
            # Non-validator line - use empty sort key so it appears first
            sort_key=""
        fi
        
        # Write to temp file: sort_key<DELIM>index<DELIM>line
        printf "%s%s%d%s%s\n" "$sort_key" "$DELIM" "$i" "$DELIM" "$line" >> "$temp_file"
    done
    
    # Sort by sort_key and output lines (extract everything after the second delimiter)
    sort -t"$DELIM" -k1,1 "$temp_file" | awk -F'\x01' '{print $3}'
    
    rm -f "$temp_file"
}

# Process output and store in array for easier sorting
mapfile -t output_lines <<< "$validators_output"
processed_lines=()
header=""
footer=""
in_footer=false

for line in "${output_lines[@]}"; do
    if [ -z "$header" ]; then
        header="$line"
        continue
    fi
    
    if [[ $line =~ ^Average || $in_footer == true ]]; then
        in_footer=true
        if [ -z "$footer" ]; then
            footer="$line"
        else
            footer="$footer"$'\n'"$line"
        fi
        continue
    fi
    
    if [[ ! $line =~ ^[[:space:]]*$ && ! $line =~ ^Stake[[:space:]]By[[:space:]]Version: ]]; then
        processed_line=$(process_validator_line "$line")
        processed_lines+=("$processed_line")
    fi
done

# Sort if requested
if [ ${#sort_order[@]} -gt 0 ]; then
    IFS=$'\n' sorted_lines=($(custom_sort "${processed_lines[@]}"))
    processed_lines=("${sorted_lines[@]}")
fi

# Output results
echo "$header"
printf "%s\n" "${processed_lines[@]}"
echo ""  # Add empty line before footer
echo -n "$footer"
