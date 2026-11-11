#!/bin/sh
# Xcode Cloud runs this script before each xcodebuild action.
# It writes the Supabase keys, which are not in git, from the environment variables of the workflow.
set -eu

config="$CI_PRIMARY_REPOSITORY_PATH/ios/Config"

if [ -n "${SUPABASE_PRODUCTION_URL:-}" ] && [ -n "${SUPABASE_PRODUCTION_PUBLISHABLE_KEY:-}" ]; then
  # In an xcconfig file "//" starts a comment, so the URL needs "/$()/".
  url=$(printf '%s' "$SUPABASE_PRODUCTION_URL" | sed 's#//#/$()/#')
  printf 'SUPABASE_URL = %s\nSUPABASE_PUBLISHABLE_KEY = %s\n' "$url" "$SUPABASE_PRODUCTION_PUBLISHABLE_KEY" \
    > "$config/Supabase.Production.xcconfig"
elif [ "${CI_XCODEBUILD_ACTION:-}" = "archive" ]; then
  echo "error: Set SUPABASE_PRODUCTION_URL and SUPABASE_PRODUCTION_PUBLISHABLE_KEY in the workflow." >&2
  exit 1
fi
