#!/bin/bash
# =============================================================================
# gatekeeper.sh — ClamAV Quarantine Pipeline
# =============================================================================
# Scans all files in the quarantine directory using ClamAV.
# Clean files are moved to /cleared for Sonarr/Radarr to import.
# Infected files are deleted and logged.
#
# Scheduled via cron to run every 10 minutes.
# Cron entry: */10 * * * * /data/scripts/gatekeeper.sh
# =============================================================================

QUARANTINE="/data/downloads/quarantine"
CLEARED="/data/downloads/cleared"
LOG="/var/log/gatekeeper.log"

echo "$(date) - Starting scan..." >> "$LOG"

# Exit if quarantine is empty
if [ -z "$(ls -A "$QUARANTINE" 2>/dev/null)" ]; then
    echo "$(date) - Quarantine empty, nothing to scan." >> "$LOG"
    exit 0
fi

for file in "$QUARANTINE"/*; do
    [ -f "$file" ] || continue

    filename=$(basename "$file")
    echo "$(date) - Scanning: $filename" >> "$LOG"

    result=$(docker exec clamav clamscan --no-summary "$file" 2>&1)
    exit_code=$?

    if [ $exit_code -eq 0 ]; then
        # Exit code 0 = clean
        echo "$(date) - CLEAN: Moving $filename to cleared" >> "$LOG"
        mv "$file" "$CLEARED/"
    elif [ $exit_code -eq 1 ]; then
        # Exit code 1 = virus found
        echo "$(date) - INFECTED: Deleting $filename" >> "$LOG"
        echo "$(date) - ALERT: Infected file detected and deleted — $filename" >> "$LOG"
        rm -f "$file"
    else
        # Exit code 2 = scan error
        echo "$(date) - ERROR: Could not scan $filename (exit code $exit_code)" >> "$LOG"
    fi
done

echo "$(date) - Scan complete." >> "$LOG"
