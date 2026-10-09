#!/bin/sh
# Xcode Cloud runs this script before each xcodebuild action.
# It writes the Supabase keys, which are not in git, from the environment variables of the workflow.
set -eu

config="$CI_PRIMARY_REPOSITORY_PATH/ios/Config"

# In an xcconfig file "//" starts a comment, so the URL needs "/$()/".
write_config() {
  url=$(printf '%s' "$2" | sed 's#//#/$()/#')
  printf 'SUPABASE_URL = %s\nSUPABASE_PUBLISHABLE_KEY = %s\n' "$url" "$3" > "$config/Supabase.$1.xcconfig"
}

if [ -n "${SUPABASE_PRODUCTION_URL:-}" ] && [ -n "${SUPABASE_PRODUCTION_PUBLISHABLE_KEY:-}" ]; then
  write_config Production "$SUPABASE_PRODUCTION_URL" "$SUPABASE_PRODUCTION_PUBLISHABLE_KEY"
elif [ "${CI_XCODEBUILD_ACTION:-}" = "archive" ]; then
  echo "error: Set SUPABASE_PRODUCTION_URL and SUPABASE_PRODUCTION_PUBLISHABLE_KEY in the workflow." >&2
  exit 1
fi

if [ -n "${SUPABASE_DEVELOPMENT_URL:-}" ] && [ -n "${SUPABASE_DEVELOPMENT_PUBLISHABLE_KEY:-}" ]; then
  write_config Development "$SUPABASE_DEVELOPMENT_URL" "$SUPABASE_DEVELOPMENT_PUBLISHABLE_KEY"
fi
