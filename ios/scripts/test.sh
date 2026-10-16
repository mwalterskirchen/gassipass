#!/bin/bash
# Builds the app and runs the unit tests on their own simulator, and prints
# only the result, the failures and the build errors.
#
#   ios/scripts/test.sh                        all unit tests
#   ios/scripts/test.sh CurrentWalkTests       one suite
#   ios/scripts/test.sh 'CurrentWalkTests/aWalkRecordsThePointsAndStopStoresTheTrackAndTheEnd()'
#
# The tests run on the simulator "GassiPass Tests", which the script makes
# and boots when it is missing. So a test run never touches the simulator
# that you use by hand. Runs from other checkouts wait for each other,
# because two runs on one simulator stop each other's test host.
#
# A run stops after TEST_TIMEOUT seconds (default 300), and prints the
# tests that had not finished. Xcode does not collect diagnostics after a
# failure, which takes up to 10 minutes.
#
# The full log is in ios/DerivedData/test.log.

set -uo pipefail

ios="$(cd "$(dirname "$0")/.." && pwd)"
derived="$ios/DerivedData"
log="$derived/test.log"
timeout="${TEST_TIMEOUT:-300}"
simulator_name="GassiPass Tests"
app_id="ch.mwalterskirchen.gassipassapp"
# In the git folder that all worktrees share.
lock="$(cd "$ios" && cd "$(git rev-parse --git-common-dir)" && pwd)/gassipass-tests.lock"
mkdir -p "$derived"

# The lock is a folder with the process ID of its owner. A lock whose owner
# has ended is taken over.
while ! mkdir "$lock" 2>/dev/null; do
    owner="$(cat "$lock/pid" 2>/dev/null)"
    if [ -n "$owner" ] && ! kill -0 "$owner" 2>/dev/null; then
        rm -rf "$lock"
        continue
    fi
    [ -z "${waiting:-}" ] && echo "Waiting for the test run of process ${owner:-?} to end…" && waiting=1
    sleep 1
done
echo $$ > "$lock/pid"
build=""
trap 'rm -rf "$lock"' EXIT
# A run that is stopped from outside also stops its build and its tests.
trap '[ -n "$build" ] && kill $build 2>/dev/null; exit 143' TERM INT HUP

udid="$(xcrun simctl list devices available -j | python3 -c '
import json, sys
name = sys.argv[1]
for runtime, devices in json.load(sys.stdin)["devices"].items():
    for device in devices:
        if device["name"] == name and "iOS" in runtime:
            print(device["udid"]); sys.exit()
' "$simulator_name")"
if [ -z "$udid" ]; then
    device_type="$(xcrun simctl list devicetypes | grep -o 'com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro)' | tr -d ')' | head -1)"
    [ -z "$device_type" ] && device_type="$(xcrun simctl list devicetypes | grep -o 'com.apple.CoreSimulator.SimDeviceType.iPhone[^)]*' | tail -1)"
    udid="$(xcrun simctl create "$simulator_name" "$device_type")" || exit 1
    echo "Made the simulator $simulator_name ($udid)."
fi
xcrun simctl bootstatus "$udid" -b > /dev/null 2>&1 || { echo "The simulator $udid does not boot."; exit 1; }
# A test host that is still running from an earlier run would be reused.
xcrun simctl terminate "$udid" "$app_id" > /dev/null 2>&1

only_testing=()
for test in "$@"; do
    only_testing+=("-only-testing:gassipassTests/$test")
done

start=$SECONDS
xcodebuild test \
    -project "$ios/gassipass.xcodeproj" \
    -scheme gassipass \
    -destination "platform=iOS Simulator,id=$udid" \
    -derivedDataPath "$derived" \
    -collect-test-diagnostics never \
    -skipPackageUpdates \
    ${only_testing[@]+"${only_testing[@]}"} \
    > "$log" 2>&1 &
build=$!

while kill -0 $build 2>/dev/null; do
    if (( SECONDS - start >= timeout )); then
        kill $build 2>/dev/null
        wait $build 2>/dev/null
        xcrun simctl terminate "$udid" "$app_id" > /dev/null 2>&1
        pkill -f "simctl diagnose" 2>/dev/null
        echo "The run stopped after $timeout s. Tests that had not finished:"
        # Swift Testing prints "◇ Test name() started." and later "✔"/"✘"
        # with the same name.
        python3 - "$log" <<'EOF'
import re, sys
started, ended = [], set()
for line in open(sys.argv[1], errors="replace"):
    if m := re.match(r"◇ Test (.+\)) started\.", line):
        started.append(m.group(1))
    elif m := re.match(r"[✔✘] Test (.+\)) (passed|failed|skipped)", line):
        ended.add(m.group(1))
unfinished = [t for t in started if t not in ended]
print("\n".join("  " + t for t in unfinished) or "  none; the hang is outside the tests (build, install or launch)")
EOF
        echo "Log: $log"
        exit 124
    fi
    sleep 0.5
done
wait $build
status=$?

# The compiler errors, without the summary lines that repeat them.
grep -E "^/.*: error: " "$log" | sort -u | head -30
# Each failed test and the lines of its issues.
grep -E "^✘ |^↳ " "$log" | grep -vE "^✘ Test run with|^↳ (Testing Library Version|Target Platform):" | head -80
grep -E "^[✔✘] Test run with" "$log"
grep -E "Testing failed:|encountered an error" -A2 "$log" | grep -v "^--$" | head -10
echo "$(( SECONDS - start )) s, log: $log"
exit $status
