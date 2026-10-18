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
# Each test has a time limit of TEST_TIME_ALLOWANCE seconds (default 60).
# Xcode rounds it up to whole minutes, and a test that is over the limit
# fails with its name, while the other tests go on. A test can ask for more
# time with the trait .timeLimit, up to TEST_MAXIMUM_TIME_ALLOWANCE seconds
# (default 120). The whole test run stops after TEST_TIMEOUT seconds (default
# 600), for a hang outside the tests, for example in the install or the
# launch of the test host. The build has its own limit, BUILD_TIMEOUT
# (default 900), for the first build of a checkout. Xcode does not collect
# diagnostics after a failure, which takes up to 10 minutes.
#
# The script reads the build errors and the test failures from the result
# bundles ios/DerivedData/build.xcresult and ios/DerivedData/test.xcresult
# (report.py). The full log is in ios/DerivedData/test.log.
#
# The tests of the server run against the local Supabase, so the script
# stops before the build when it does not run (`supabase start`), or when
# it misses a migration of supabase/migrations (`supabase migration up
# --local`). The full run also runs the database tests of supabase/tests
# (`supabase test db`). TEST_WITHOUT_SUPABASE=1 skips the check and the
# database tests, and the Swift tests of the server are then skipped, as in
# Xcode Cloud.

set -uo pipefail
source "$(dirname "$0")/common.sh"

log="$derived/test.log"
build_bundle="$derived/build.xcresult"
test_bundle="$derived/test.xcresult"
root="$(cd "$ios/.." && pwd)"
with_supabase=$([ "${TEST_WITHOUT_SUPABASE:-}" = 1 ] && echo false || echo true)

# Whether the local Supabase runs with every migration of supabase/migrations.
# When it does not, it says what to run.
check_supabase() {
    local skip="or set TEST_WITHOUT_SUPABASE=1 to skip the tests of the server"
    if ! command -v supabase > /dev/null; then
        echo "The Supabase CLI is missing. Install it with \`brew install supabase/tap/supabase\`, $skip."
        return 1
    fi
    if [ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 http://127.0.0.1:54321/auth/v1/health)" != 200 ]; then
        echo "The local Supabase does not run. Start it with \`supabase start\` in $root, $skip."
        return 1
    fi
    local migrations
    migrations="$(cd "$root" && supabase migration list --local --output-format json 2> /dev/null | python3 -c '
import json, sys
try:
    migrations = json.load(sys.stdin)["migrations"]
except Exception:
    sys.exit(1)
missing = [m["local"] for m in migrations if m.get("local") and m.get("remote") != m["local"]]
extra = [m["remote"] for m in migrations if m.get("remote") and not m.get("local")]
print(" ".join(missing) + "|" + " ".join(extra))
')" || { echo "The migrations of the local Supabase cannot be read. See \`supabase migration list --local\`."; return 1; }
    local missing="${migrations%%|*}" extra="${migrations#*|}"
    if [ -n "$missing" ]; then
        echo "The local Supabase misses the migrations $missing. Apply them with \`supabase migration up --local\` in $root."
        return 1
    fi
    # Another checkout can have newer migrations on the same database.
    [ -n "$extra" ] && echo "Note: the local Supabase has migrations that this checkout does not have: $extra."
    return 0
}

# Runs the database tests of supabase/tests, and prints their count or their
# failures.
database_tests() {
    local size result output
    size=$(wc -c < "$log")
    run_with_limit "${DATABASE_TEST_TIMEOUT:-120}" bash -c "cd '$root' && supabase test db"
    result=$?
    output="$(tail -c +$(( size + 1 )) "$log")"
    if (( result == 0 )); then
        echo "Database: $(grep -o 'Tests=[0-9]*' <<< "$output" | cut -d= -f2) tests passed"
    else
        (( result == 124 )) && echo "The database tests stopped after ${DATABASE_TEST_TIMEOUT:-120} s."
        grep -E '^not ok|^#|Failed|Dubious|ERROR' <<< "$output" | head -30
        echo "Database: the tests of supabase/tests failed"
    fi
    return $result
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
    timeout="${TEST_TIMEOUT:-600}"
    # xcodebuild refuses to write a result bundle over an old one.
    rm -rf "$test_bundle"
    run_with_limit "$timeout" xcodebuild test-without-building "${xcodebuild_options[@]}" \
        -destination "platform=iOS Simulator,id=$udid" \
        -collect-test-diagnostics never \
        -test-timeouts-enabled YES \
        -default-test-execution-time-allowance "${TEST_TIME_ALLOWANCE:-60}" \
        -maximum-test-execution-time-allowance "${TEST_MAXIMUM_TIME_ALLOWANCE:-120}" \
        -resultBundlePath "$test_bundle" \
        ${only_testing[@]+"${only_testing[@]}"}
    status=$?
    if (( status == 124 )); then
        xcrun simctl terminate "$udid" "$app_id" > /dev/null 2>&1
        echo "The test run stopped after $timeout s. Each test has a time limit of its own, so" \
            "something outside the tests probably hangs, for example the install or the launch of the test host."
    fi
    exit $status
fi

start=$SECONDS
mkdir -p "$derived"
: > "$log"
if $with_supabase; then
    check_supabase || exit 1
fi
udid="$(simulator "GassiPass Tests")" || exit 1

build_timeout="${BUILD_TIMEOUT:-900}"
rm -rf "$build_bundle" "$test_bundle"
run_with_limit "$build_timeout" xcodebuild build-for-testing "${xcodebuild_options[@]}" \
    -destination "platform=iOS Simulator,id=$udid" \
    -resultBundlePath "$build_bundle"
status=$?
(( status == 124 )) && echo "The build stopped after $build_timeout s."

if (( status == 0 )); then
    run_locked "$git_folder/gassipass-tests.lock" "$0" --locked "$udid" "$@"
    status=$?
fi

report --build "$build_bundle" --tests "$test_bundle" --status "$status" --log "$log"
if $with_supabase && (( $# == 0 )); then
    database_tests || status=1
fi
echo "$(( SECONDS - start )) s, log: $log"
exit $status
