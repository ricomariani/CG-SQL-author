#!/bin/bash
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

set -o errexit -o nounset -o pipefail

S=$(cd $(dirname "$0"); pwd)
O=$S/out
R=$S/..

if [ -z "$SQLITE_PATH" ]; then
  cat $S/README.md | awk '/<!-- build_requirements_start/{flag=1; next} /<!-- build_requirements_end/{flag=0;} flag'

  exit 1
else
  SQLITE_PATH=$(realpath $SQLITE_PATH)
fi

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
    echo "Usage: make.sh"
    echo "  --use_gcc"
    echo "  --use_clang"
    exit 1
  fi
done

echo "# Clean up output directory"
rm -rf $O
mkdir -p $O
ls -d $O

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
popd >/dev/null


pushd $S >/dev/null

CC="cc -g -O0"

OS=$(uname)
if [ "$OS" = "Darwin" ]; then
  CC="${CC} -fPIC -undefined dynamic_lookup"
  LIB_EXT="dylib"
elif [ "$OS" = "Linux" ]; then
  LIB_EXT="so"
  CC="${CC} -fPIC"
elif [ "$OS" = "MINGW64_NT" ] || [ "$OS" = "MSYS_NT" ]; then
  LIB_EXT="dll"
  CC="${CC} -Wl,--enable-auto-import -Wl,--export-all-symbols"
else
  echo "Unsupported platform: $OS"
  exit 1
fi

echo "Build ./out/cqlextension.$LIB_EXT extension for SQLite ($SQLITE_PATH/sqlite3ext.h) on $OS"
${CC} -shared \
  -I $SQLITE_PATH \
  -I./out \
  -I./. \
  -I./.. \
  -o ./out/cqlextension.${LIB_EXT} \
  ./out/SampleInterop.c \
  ./cql_sqlite_extension.c \
  ./out/Sample.c \
  ./../cqlrt.c

ls ./out/cqlextension.${LIB_EXT}

popd >/dev/null
