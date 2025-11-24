#!/bin/bash
# Copyright (c) Joris Garonian and Rico Mariani
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

set -o errexit -o nounset -o pipefail

S=$(cd $(dirname "$0"); pwd)
O=$S/out
R=$S/..

CC=cc
while [ "${1:-}" != "" ]; do
  if [ "$1" == "--use_gcc" ]; then
    CC=gcc
    export CC
    shift 1
  elif [ "$1" == "--use_clang" ]; then
    CC=clang
    export CC
    shift 1
  else
    echo "Usage: demo.sh"
    echo "  --use_gcc"
    echo "  --use_clang"
    exit 1
  fi
done

echo "# Clean up output directory"
rm -rf $O
mkdir -p $O

echo "# Build CQL compiler"
(cd $O/../.. ; make)
CQL=$R/out/cql

pushd $O >/dev/null
echo "# Generate stored procedures C and JSON output"
${CQL} --nolines --in ../Sample.sql --cg Sample.h Sample.c
${CQL} --nolines --in ../Sample.sql --rt json_schema --cg Sample.json
ls Sample.c Sample.json

echo "# Generate SQLite3 extension"
../cqlsqlite3extension.py ./Sample.json --cql_header Sample.h > SampleInterop.c
ls SampleInterop.c

echo "# Compiling Test Cases"
${CQL} --nolines --in ../TestCases.sql --cg TestCases.h TestCases.c

popd >/dev/null

pushd $S >/dev/null

CC="cc -g -O0"

${CC} \
  -I./out \
  -I./. \
  -I./.. \
  -o ./out/demo \
  ./out/SampleInterop.c \
  ./out/TestCases.c \
  ./cql_sqlite_extension.c \
  ./out/Sample.c \
  ./../cqlrt.c \
  -lsqlite3

echo "# Running test cases"

ls ./out/demo
out/demo

popd >/dev/null
