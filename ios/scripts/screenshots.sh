#!/bin/bash
# Runs the UI test of the scheme "gassipass Screenshots", which walks through
# the main screens with the demo data and saves a screenshot of each one.
#
#   ios/scripts/screenshots.sh           light mode
#   ios/scripts/screenshots.sh --dark    dark mode
#
# The screenshots go to ios/DerivedData/Screenshots/light or …/dark. The
# test runs on its own simulator, "GassiPass UI Tests", which the script
# erases and boots before each run. On a simulator that the unit tests or a
# person used before, the UI test runner timed out with "Timed out waiting
# for AX loaded notification", and an erased one has no app that iOS could
# relaunch into a real store. The runs of all checkouts wait for each other.
#
# The run stops after UI_TEST_TIMEOUT seconds (default 1200). The full log
# is in ios/DerivedData/screenshots.log.

set -uo pipefail
source "$(dirname "$0")/common.sh"

log="$derived/screenshots.log"
bundle="$derived/screenshots.xcresult"
appearance=light
[ "${1:-}" = "--dark" ] && appearance=dark
folder="$derived/Screenshots/$appearance"

# The run under the lock.
if [ "${1:-}" = "--locked" ]; then
    udid=$2
    xcrun simctl shutdown "$udid" > /dev/null 2>&1
    xcrun simctl erase "$udid" || exit 1
    xcrun simctl boot "$udid" || exit 1
    xcrun simctl bootstatus "$udid" -b > /dev/null 2>&1 || { echo "The simulator $udid does not boot."; exit 1; }
    # The whole simulator takes the appearance, so that it holds also for
    # the screens of the system.
    xcrun simctl ui "$udid" appearance "$4" || exit 1
    timeout="${UI_TEST_TIMEOUT:-1200}"
    rm -rf "$bundle"
    TEST_RUNNER_SCREENSHOT_DIR="$3" TEST_RUNNER_APPEARANCE="$4" \
        run_with_limit "$timeout" xcodebuild test \
        -project "$ios/gassipass.xcodeproj" \
        -scheme "gassipass Screenshots" \
        -derivedDataPath "$derived" \
        -skipPackageUpdates \
        -destination "platform=iOS Simulator,id=$udid" \
        -parallel-testing-enabled NO \
        -collect-test-diagnostics never \
        -resultBundlePath "$bundle"
    status=$?
    (( status == 124 )) && echo "The UI test stopped after $timeout s."
    # Nothing keeps running in the background, for example a walk.
    xcrun simctl shutdown "$udid" > /dev/null 2>&1
    exit $status
fi

start=$SECONDS
mkdir -p "$derived"
: > "$log"
rm -rf "$folder"
mkdir -p "$folder"
udid="$(simulator "GassiPass UI Tests")" || exit 1

run_locked "$git_folder/gassipass-ui-tests.lock" "$0" --locked "$udid" "$folder" "$appearance"
status=$?

report --tests "$bundle" --status "$status" --log "$log"
echo "$(ls "$folder" | wc -l | tr -d ' ') screenshots in $folder"
echo "$(( SECONDS - start )) s, log: $log"
exit $status
