#!/bin/bash
# Loads sample receipts into the target simulator's photo library — only if they haven't been added yet.
# Uses a marker file in the simulator's data directory to avoid duplicate imports.

RESOURCES_DIR="$(cd "$(dirname "$0")/../Resources" && pwd)"

get_device_data_dir() {
    local udid="$1"
    echo "$HOME/Library/Developer/CoreSimulator/Devices/$udid/data"
}

load_if_needed() {
    local udid="$1"
    local data_dir
    data_dir=$(get_device_data_dir "$udid")
    local marker="$data_dir/.tally_receipts_loaded"

    if [ -f "$marker" ]; then
        echo "load_receipts: Receipts already present on $udid — skipping."
        return
    fi

    echo "load_receipts: Adding receipts to $udid"
    xcrun simctl addmedia "$udid" "$RESOURCES_DIR"/Sample_Receipt_*.jpeg 2>/dev/null
    touch "$marker"
}

if [ -n "$TARGET_DEVICE_IDENTIFIER" ]; then
    load_if_needed "$TARGET_DEVICE_IDENTIFIER"
else
    UDIDS=$(xcrun simctl list devices booted 2>/dev/null | grep "(Booted)" | sed 's/.*(\([A-F0-9-]*\)) (Booted).*/\1/')
    if [ -z "$UDIDS" ]; then
        echo "load_receipts: No booted simulators found. Skipping."
        exit 0
    fi
    for UDID in $UDIDS; do
        load_if_needed "$UDID"
    done
fi

echo "load_receipts: Done."
exit 0
