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

set -uo pipefail
source "$(dirname "$0")/common.sh"

log="$derived/test.log"
build_bundle="$derived/build.xcresult"
test_bundle="$derived/test.xcresult"

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
echo "$(( SECONDS - start )) s, log: $log"
exit $status
