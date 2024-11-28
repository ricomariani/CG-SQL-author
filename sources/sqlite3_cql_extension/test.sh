#!/bin/bash

set -o errexit -o nounset

S=$(cd $(dirname "$0"); pwd)

source $S/../common/test_helpers.sh || exit 1

if [ -z "$SQLITE_PATH" ]; then
  echo "Error: SQLITE_PATH environment variable is not set"
  exit 1
else
  SQLITE_PATH=$(realpath $SQLITE_PATH)
fi

while [ "${1:-}" != "" ]; do
  if [ "$1" == "--non_interactive" ]; then
    # shellcheck disable=SC2034
    NON_INTERACTIVE=1
    shift 1
  else
    echo "Usage: test.sh"
    echo "  --non_interactive"
    exit 1
  fi
done

pushd $S >/dev/null

$SQLITE_PATH/sqlite3 ":memory:" <<EOF 2>&1 \
  | LC_ALL=C awk '
    /^Runtime error/ { getline nextLine; print nextLine "\n" "got ERROR:  " $0; next; }
    /^\[/ { print "got RESULT:  " $0; next }
    { print }' \
  | LC_ALL=C awk '
    /got/ { printf " %s", $0; next }
    { printf "\n%s", $0 }
    END {print ""}' \
  | tee test.out
.load out/cqlextension
.mode json
.echo on
.nullvalue 'NULL'
.read test.sql
EOF

popd >/dev/null

on_diff_exit $S/test.out
