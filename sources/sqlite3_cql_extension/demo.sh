#!/bin/bash
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

set -o errexit -o nounset -o pipefail

S=$(cd $(dirname "$0"); pwd)
O=$S/out
R=$S/..

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
${CQL} --nolines --in ../Demo.sql --cg Demo.h Demo.c
ls Sample.c Sample.json

echo "# Generate SQLite3 extension"
../cqlsqlite3extension.py ./Sample.json --cql_header Sample.h > SampleInterop.c
ls SampleInterop.c
popd >/dev/null


pushd $S >/dev/null

CC="cc -g -O0 -DNO_SQLITE_EXT"

${CC} \
  -I./out \
  -I./. \
  -I./.. \
  -o ./out/demo \
  ./out/SampleInterop.c \
  ./out/Demo.c \
  ./cql_sqlite_extension.c \
  ./out/Sample.c \
  ./../cqlrt.c \
  -lsqlite3

ls ./out/demo
out/demo

popd >/dev/null
