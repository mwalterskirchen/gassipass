# The helpers of test.sh and screenshots.sh. Each script sets `log` before
# it calls run_with_limit.

ios="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
derived="$ios/DerivedData"
app_id="ch.mwalterskirchen.gassipassapp"
# The locks are in the git folder that all worktrees share. The kernel
# releases a lock when its owner ends, also after a crash.
git_folder="$(cd "$ios" && cd "$(git rev-parse --git-common-dir)" && pwd)"

child=""

# Stops the process and every process that it started, the deepest first.
kill_tree() {
    local child_pid
    for child_pid in $(pgrep -P "$1"); do
        kill_tree "$child_pid"
    done
    kill "$1" 2>/dev/null
}

# A run that is stopped from outside also stops its build or its tests.
trap '[ -n "$child" ] && kill_tree "$child"; exit 143' TERM INT HUP

# Runs the command in the background until it ends or the time limit is
# over, and returns its status, or 124 after the time limit. macOS has no
# `timeout` command.
run_with_limit() {
    local limit=$1 start=$SECONDS
    shift
    "$@" >> "$log" 2>&1 &
    child=$!
    while kill -0 "$child" 2>/dev/null; do
        if (( SECONDS - start >= limit )); then
            kill_tree "$child"
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

# Runs the command under the lock, and says so when it has to wait for
# another checkout first.
run_locked() {
    local lock=$1
    shift
    if ! lockf -t 0 "$lock" true 2>/dev/null; then
        echo "Waiting for the run of another checkout to end…"
    fi
    lockf -k "$lock" "$@" &
    child=$!
    wait "$child"
    local status=$?
    child=""
    return $status
}

# Prints the ID of the simulator with the name on the newest iOS runtime,
# and makes an iPhone 18 Pro with the name when there is none.
simulator() {
    local name=$1 udid device_type
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
' "$name")"
    if [ -z "$udid" ]; then
        device_type="$(xcrun simctl list devicetypes | grep -o 'com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro)' | tr -d ')' | head -1)"
        [ -z "$device_type" ] && device_type="$(xcrun simctl list devicetypes | grep -o 'com.apple.CoreSimulator.SimDeviceType.iPhone[^)]*' | tail -1)"
        udid="$(xcrun simctl create "$name" "$device_type" 2>/dev/null)" || return 1
        echo "Made the simulator $name ($udid)." >&2
    fi
    echo "$udid"
}

# Prints the build errors, the test failures and the counts from the result
# bundles (report.py).
report() {
    python3 "$ios/scripts/report.py" "$@"
}
