#!/bin/bash

set -o errexit

source ../common/test_helpers.sh || exit 1

S=$(cd $(dirname "$0"); pwd)

if [ -z "$SQLITE_PATH" ]; then
  echo "Error: SQLITE_PATH environment variable is not set"
  exit 1
fi

OS=$(uname)

if [ "$OS" = "Darwin" ]; then
  LIB_EXT="dylib"
elif [ "$OS" = "Linux" ]; then
  LIB_EXT="so"
elif [ "$OS" = "MINGW64_NT" ] || [ "$OS" = "MSYS_NT" ]; then
  LIB_EXT="dll"
else
  echo "Unsupported platform: $OS"
  exit 1
fi

$SQLITE_PATH/sqlite3 ":memory:" <<EOF 2>&1 \
  | LC_ALL=C awk '
    /^Runtime error/ { getline nextLine; print nextLine "\n" "got ERROR:  " $0; next; }
    /^\[/ { print "got RESULT:  " $0; next }
    { print }' \
  | LC_ALL=C awk '
    /got/ { printf " %s", $0; next }
    { printf "\n%s", $0 }
    END {print ""}' \
  | tee $S/test.out
.load $S/out/cqlextension.$LIB_EXT
.mode json
.echo on
.nullvalue 'NULL'
.read test.sql
EOF

on_diff_exit $S/test.out
