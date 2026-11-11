#!/bin/bash
# Runs the tests of the package ios/GassiPassCore on the Mac, with `swift
# test`, and prints only the failures and the count.
#
#   ios/scripts/test.sh                        all tests
#   ios/scripts/test.sh CurrentWalkTests       one suite
#   ios/scripts/test.sh CurrentWalkTests/aWalkRecordsThePoints
#
# The argument is a regular expression for the names of the tests (`swift
# test --filter`). The tests need no simulator and no app, so several
# checkouts can run them at once.
#
# The tests of the server run against the local Supabase, so the script
# stops before the build when it does not run (`supabase start`), or when
# it misses a migration of supabase/migrations (`supabase migration up
# --local`). The run without an argument also runs the database tests of
# supabase/tests (`supabase test db`). TEST_WITHOUT_SUPABASE=1 skips the
# check and the database tests, and the Swift tests of the server are then
# skipped.

set -uo pipefail
ios="$(cd "$(dirname "$0")/.." && pwd)"
root="$(cd "$ios/.." && pwd)"

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
    local missing
    missing="$(cd "$root" && supabase migration list --local --output-format json 2> /dev/null | python3 -c '
import json, sys
migrations = json.load(sys.stdin)["migrations"]
print(" ".join(m["local"] for m in migrations if m.get("local") and m.get("remote") != m["local"]))
')" || { echo "The migrations of the local Supabase cannot be read. See \`supabase migration list --local\`."; return 1; }
    if [ -n "$missing" ]; then
        echo "The local Supabase misses the migrations $missing. Apply them with \`supabase migration up --local\` in $root."
        return 1
    fi
}

if [ "${TEST_WITHOUT_SUPABASE:-}" != 1 ]; then
    check_supabase || exit 1
fi

cd "$ios/GassiPassCore" || exit 1
swift test --quiet --disable-xctest ${1:+--filter "$1"}
status=$?

if [ "${TEST_WITHOUT_SUPABASE:-}" != 1 ] && (( $# == 0 )); then
    # psql notes for each file that the test extension exists already.
    (cd "$root" && supabase test db 2>&1 | grep -v "NOTICE:") || status=1
fi
exit $status
