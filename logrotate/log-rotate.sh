#!/bin/bash
#
# A script to safely rotate the koii-rpc.log file.
# Designed to be run weekly as a root cron job.
#
# It handles being run multiple times a day by creating suffixed
# archive files (e.g., ...-2.log, ...-3.log).
#

# --- Configuration ---
# Load configuration from .env file if it exists
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "${SCRIPT_DIR}/.env" ]; then
    # Source the .env file, ignoring comments and empty lines
    set -a
    source "${SCRIPT_DIR}/.env"
    set +a
fi

# Set default values if not provided by .env
: ${LOG_DIR:="/home/koii"}
: ${LOG_FILE:="koii-rpc.log"}
: ${SERVICE_NAME:="koii-validator"}
: ${LOG_USER:="koii"}
: ${LOG_GROUP:="koii"}
: ${LINES_TO_KEEP:=1000000}
# ---------------------

# 1. Ensure we are running in the correct directory. Exit if it doesn't exist.
cd "$LOG_DIR" || { echo "Error: Cannot change directory to $LOG_DIR. Exiting."; exit 1; }

# 2. Check for root privileges (cron running as root will pass this)
if [ "$EUID" -ne 0 ]; then
  echo "Error: This script must be run as root or with sudo."
  exit 1
fi

# Exit if the log file doesn't exist or is empty
if [ ! -s "$LOG_FILE" ]; then
  # This is not an error for a cron job, just means nothing to do.
  echo "Log file '$LOG_FILE' does not exist or is empty. Nothing to do."
  exit 0
fi

# 3. Determine the unique archive filename
TIMESTAMP=$(date +%Y%m%d)
BASE_ARCHIVE_FILE="koii-rpc.${TIMESTAMP}.log"
TEMP_FILE="${LOG_FILE}.old"

# Check if the base archive file already exists.
if [ ! -e "$BASE_ARCHIVE_FILE" ]; then
    ARCHIVE_FILE="$BASE_ARCHIVE_FILE"
else
    # If it exists, find the next available suffix (-2, -3, etc.)
    COUNTER=2
    while true; do
        TENTATIVE_FILE="koii-rpc.${TIMESTAMP}-${COUNTER}.log"
        if [ ! -e "$TENTATIVE_FILE" ]; then
            ARCHIVE_FILE="$TENTATIVE_FILE"
            break
        fi
        COUNTER=$((COUNTER + 1))
    done
fi
echo "Determined unique archive filename: $ARCHIVE_FILE"

# 4. Safely move the current log file.
echo "Rotating '$LOG_FILE'..."
mv "$LOG_FILE" "$TEMP_FILE"

# 5. Create a new, empty log file.
touch "$LOG_FILE"

# 6. Set the correct ownership and permissions for the new log file.
chown "${LOG_USER}:${LOG_GROUP}" "$LOG_FILE"
chmod 644 "$LOG_FILE"
echo "New log file created and permissions set for user '$LOG_USER'."

# 7. Restart the service to release the old file handle.
echo "Restarting service '$SERVICE_NAME'..."
service "$SERVICE_NAME" restart
RESTART_STATUS=$? # Capture exit code immediately

if [ $RESTART_STATUS -ne 0 ]; then
    echo "Error: Failed to restart '$SERVICE_NAME'. Please check the service status."
    # Attempt to restore the old log file to prevent service issues
    mv "$TEMP_FILE" "${LOG_FILE}.failed-rotation"
    exit 1
fi
echo "Service restarted successfully."

# 8. Trim the old log file into the final archive.
echo "Archiving the last $LINES_TO_KEEP lines to '$ARCHIVE_FILE'..."
tail -n "$LINES_TO_KEEP" "$TEMP_FILE" > "$ARCHIVE_FILE"

# 9. Clean up the large temporary file.
echo "Cleaning up temporary file..."
rm "$TEMP_FILE"

echo "Rotation complete. New archive is '$ARCHIVE_FILE'."
