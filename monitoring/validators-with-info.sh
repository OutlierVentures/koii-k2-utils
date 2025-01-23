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
sort_by_credits=false
sort_by_skiprate=false
debug=false

# Parse arguments using getopts
while getopts ":s:dh" opt; do
    case ${opt} in
        s )
            IFS=',' read -ra SORT_OPTS <<< "$OPTARG"
            for opt in "${SORT_OPTS[@]}"; do
                case $opt in
                    credits) sort_by_credits=true ;;
                    skiprate) sort_by_skiprate=true ;;
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

# Get sort command based on options
get_sort_args() {
    local args=()
    args+=("-k1,1")  # Base sort is always included
    
    if [ "$sort_by_skiprate" = true ]; then
        args+=("-k11,11n")
    fi
    if [ "$sort_by_credits" = true ]; then
        args+=("-k12,12nr")
    fi
    
    printf "%s " "${args[@]}"
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
if [ "$sort_by_skiprate" = true ] || [ "$sort_by_credits" = true ]; then
    read -ra sort_args <<< "$(get_sort_args)"
    IFS=$'\n' sorted_lines=($(printf "%s\n" "${processed_lines[@]}" | sort "${sort_args[@]}"))
    processed_lines=("${sorted_lines[@]}")
fi

# Output results
echo "$header"
printf "%s\n" "${processed_lines[@]}"
echo ""  # Add empty line before footer
echo -n "$footer"
