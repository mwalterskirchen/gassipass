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
# that you use by hand. The test runs of all checkouts wait for each other,
# because two runs on one simulator stop each other's test host. The builds
# do not wait, because each checkout builds into its own ios/DerivedData.
#
# The tests stop after TEST_TIMEOUT seconds (default 300), and the script
# prints the tests that had not finished. The build has its own limit,
# BUILD_TIMEOUT (default 900), for the first build of a checkout. Xcode does
# not collect diagnostics after a failure, which takes up to 10 minutes.
#
# The full log is in ios/DerivedData/test.log.

set -uo pipefail

ios="$(cd "$(dirname "$0")/.." && pwd)"
derived="$ios/DerivedData"
log="$derived/test.log"
simulator_name="GassiPass Tests"
app_id="ch.mwalterskirchen.gassipassapp"
# In the git folder that all worktrees share. The kernel releases the lock
# when its owner ends, also after a crash.
lock="$(cd "$ios" && cd "$(git rev-parse --git-common-dir)" && pwd)/gassipass-tests.lock"

child=""
# A run that is stopped from outside also stops its build or its tests.
trap '[ -n "$child" ] && { pkill -TERM -P "$child"; kill "$child"; } 2>/dev/null; exit 143' TERM INT HUP

# Runs the command in the background until it ends or the time limit is
# over, and returns its status, or 124 after the time limit.
run_with_limit() {
    local limit=$1 start=$SECONDS
    shift
    "$@" >> "$log" 2>&1 &
    child=$!
    while kill -0 "$child" 2>/dev/null; do
        if (( SECONDS - start >= limit )); then
            kill "$child" 2>/dev/null
            wait "$child" 2>/dev/null
            child=""
            return 124
        fi
        sleep 0.5
    done
    wait "$child"
    local status=$?
    child=""
    return $status
}

xcodebuild_options=(
    -project "$ios/gassipass.xcodeproj"
    -scheme gassipass
    -derivedDataPath "$derived"
    -skipPackageUpdates
)

# The test phase, which the script runs under the lock.
if [ "${1:-}" = "--locked" ]; then
    udid=$2
    shift 2
    xcrun simctl bootstatus "$udid" -b > /dev/null 2>&1 || { echo "The simulator $udid does not boot."; exit 1; }
    # A test host that is still running from an earlier run would be reused.
    xcrun simctl terminate "$udid" "$app_id" > /dev/null 2>&1
    only_testing=()
    for test in "$@"; do
        only_testing+=("-only-testing:gassipassTests/$test")
    done
    timeout="${TEST_TIMEOUT:-300}"
    run_with_limit "$timeout" xcodebuild test-without-building "${xcodebuild_options[@]}" \
        -destination "platform=iOS Simulator,id=$udid" \
        -collect-test-diagnostics never \
        ${only_testing[@]+"${only_testing[@]}"}
    status=$?
    if (( status == 124 )); then
        xcrun simctl terminate "$udid" "$app_id" > /dev/null 2>&1
        echo "The tests stopped after $timeout s. Tests that had not finished:"
        # Swift Testing prints "◇ Test name() started." and later "✔" or
        # "✘" with the same name.
        python3 - "$log" <<'EOF'
import re, sys
started, ended = [], set()
for line in open(sys.argv[1], errors="replace"):
    if m := re.match(r"◇ Test (.+\)) started\.", line):
        started.append(m.group(1))
    elif m := re.match(r"[✔✘] Test (.+\)) (passed|failed|skipped)", line):
        ended.add(m.group(1))
unfinished = [t for t in started if t not in ended]
print("\n".join("  " + t for t in unfinished) or "  none; the install or the launch of the test host hangs")
EOF
    fi
    exit $status
fi

start=$SECONDS
mkdir -p "$derived"
: > "$log"

# The simulator on the newest iOS runtime, if there are several.
udid="$(xcrun simctl list devices available -j | python3 -c '
import json, re, sys
name = sys.argv[1]
def version(runtime):
    return [int(n) for n in re.findall(r"\d+", runtime)]
devices = json.load(sys.stdin)["devices"]
for runtime in sorted((r for r in devices if ".iOS-" in r), key=version, reverse=True):
    for device in devices[runtime]:
        if device["name"] == name:
            print(device["udid"]); sys.exit()
' "$simulator_name")"
if [ -z "$udid" ]; then
    device_type="$(xcrun simctl list devicetypes | grep -o 'com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro)' | tr -d ')' | head -1)"
    [ -z "$device_type" ] && device_type="$(xcrun simctl list devicetypes | grep -o 'com.apple.CoreSimulator.SimDeviceType.iPhone[^)]*' | tail -1)"
    udid="$(xcrun simctl create "$simulator_name" "$device_type" 2>/dev/null)" || exit 1
    echo "Made the simulator $simulator_name ($udid)."
fi

build_timeout="${BUILD_TIMEOUT:-900}"
run_with_limit "$build_timeout" xcodebuild build-for-testing "${xcodebuild_options[@]}" \
    -destination "platform=iOS Simulator,id=$udid"
status=$?
(( status == 124 )) && echo "The build stopped after $build_timeout s."

if (( status == 0 )); then
    if ! lockf -t 0 "$lock" true 2>/dev/null; then
        echo "Waiting for the test run of another checkout to end…"
    fi
    lockf -k "$lock" "$0" --locked "$udid" "$@" &
    child=$!
    wait "$child"
    status=$?
    child=""
fi

# The compiler errors, without the summary lines that repeat them.
grep -E "^/.*: error: " "$log" | sort -u | head -30
# Each failed test and the lines of its issues.
grep -E "^✘ |^↳ " "$log" | grep -vE "^✘ Test run with|^↳ (Testing Library Version|Target Platform):" | head -80
grep -E "^[✔✘] Test run with" "$log"
grep -E "Testing failed:|encountered an error" -A2 "$log" | grep -v "^--$" | head -10
echo "$(( SECONDS - start )) s, log: $log"
exit $status
