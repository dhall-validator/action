#!/bin/sh -e

dhall_haskell="$(eval echo "$DHALL_BINARY")"
archive=$(mktemp)
curl -Lsf "$dhall_haskell" -o "$archive"
tar -xjf "$archive"
PATH="$(pwd)/bin:$PATH"

echo "::add-matcher::$GITHUB_ACTION_PATH/dhall-checker.json"

export DHALL_FAILURES=$(mktemp -d)
if [ -z "$LIST" ]; then
  export LIST=$(mktemp)
fi
if [ -n "$FILES" ]; then
  echo "$FILES" | tr "\n" "\0" >> $LIST
fi
if [ -z "$PARALLEL_JOBS" ]; then
  PARALLEL_JOBS=2
fi

cat $LIST |
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
