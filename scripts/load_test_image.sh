#!/bin/bash
# Loads SampleExpensesTest.png into the simulator's Photos app for testing the multi-expense importer.
# Only runs when building for simulator. Never fails the build.

set +e

[ "$EFFECTIVE_PLATFORM_NAME" != "iphonesimulator" ] && exit 0

IMAGE="${PROJECT_DIR}/Resources/SampleExpensesTest.png"
[ ! -f "$IMAGE" ] && exit 0

if [ -n "$TARGET_DEVICE_IDENTIFIER" ]; then
    xcrun simctl addmedia "$TARGET_DEVICE_IDENTIFIER" "$IMAGE" 2>/dev/null || true
else
    for udid in $(xcrun simctl list devices booted 2>/dev/null | sed -n 's/.*(\([A-F0-9-]*\)) (Booted).*/\1/p'); do
        xcrun simctl addmedia "$udid" "$IMAGE" 2>/dev/null || true
    done
fi

exit 0
