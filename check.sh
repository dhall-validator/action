#!/bin/sh -e
if [ -n "$VERBOSE" ]; then
  set -x
fi

dhall_json="$(eval echo "$DHALL_JSON_BINARY")"
dhall_haskell="$(eval echo "$DHALL_HASKELL_BINARY")"

dhall_json_archive=$(mktemp)
curl -Lsf "$dhall_json" -o "$dhall_json_archive"
dhall_json_extracted=$(mktemp -d)
tar -xjf "$dhall_json_archive" -C "$dhall_json_extracted"
PATH="$dhall_json_extracted/bin:$PATH"

dhall_haskell_archive=$(mktemp)
curl -Lsf "$dhall_haskell" -o "$dhall_haskell_archive"
dhall_haskell_extracted=$(mktemp -d)
tar -xjf "$dhall_haskell_archive" -C "$dhall_haskell_extracted"
PATH="$dhall_haskell_extracted/bin:$PATH"

echo "::add-matcher::$GITHUB_ACTION_PATH/dhall-checker.json"

export DHALL_FAILURES=$(mktemp -d)
if [ -z "$LIST" ]; then
  export LIST=$(mktemp)
fi
if [ -n "$FILES" ]; then
  echo "$FILES" | tr "\n" "\0" >> "$LIST"
fi

if ! grep -q . "$LIST"; then
  echo "::notice::No Dhall files to check."
  exit 0
fi

if [ -z "$PARALLEL_JOBS" ]; then
  PARALLEL_JOBS=2
fi

if [ -n "$LINT" ]; then
  echo "::group::lint"
  if ! cat "$LIST" | xargs -0 "$GITHUB_ACTION_PATH/dhall-linter"; then
    echo '::error::Linting failed. Use `dhall lint` locally to fix the errors.'
    exit 1
  fi
  echo '::notice::Linting passed.'
  echo "::endgroup::"
fi

cat "$LIST" |
  xargs -0 "-P$PARALLEL_JOBS" -r -n1 $GITHUB_ACTION_PATH/dhall-checker 2>/dev/null

if [ -n "$RETRY_FAILED_FILES" ]; then
  files="$(cd $DHALL_FAILURES; find . -type f)"
  if [ -z "$files" ]; then
    exit 0
  fi

  old_failures=$DHALL_FAILURES
  DHALL_FAILURES=$(mktemp -d)
  echo
  echo "Rechecking serially..."
  echo
  for file in $files; do
    dhall_file=$(cat "$old_failures/$file")
    (
      $GITHUB_ACTION_PATH/dhall-checker $dhall_file
    )
  done
fi
cd $DHALL_FAILURES
files="$(find . -type f)"
if [ -z "$files" ]; then
  exit 0
fi
echo
echo "Errors detected in:"
for file in $files; do
  cat $file
done
exit 1
