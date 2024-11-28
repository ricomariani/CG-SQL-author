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
  echo "Error: SQLITE_PATH environment variable is not set"
  echo "$ git clone https://github.com/sqlite/sqlite.git && cd sqlite"
  echo "$ ./configure && make sqlite3-all.c"
  echo "$ gcc -g -O0 -DSQLITE_ENABLE_LOAD_EXTENSION -o sqlite3 sqlite3-all.c shell.c"
  exit 1
fi

rm -rf $O
mkdir -p $O

echo "building cql"
(cd $O/../.. ; make)
CQL=$R/out/cql

pushd $O >/dev/null
echo "Generate stored procs C and JSON"
${CQL} --nolines --in ../Sample.sql --cg Sample.h Sample.c
${CQL} --nolines --in ../Sample.sql --rt json_schema --cg Sample.json
echo "Generate SQLite3 extension"
../cqlsqlite3extension.py ./Sample.json --cql_header Sample.h > SampleInterop.c
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
  CC="${CC} -Wl,--enable-auto-import"
else
  echo "Unsupported platform: $OS"
  exit 1
fi

echo "Build extension for SQLite ($SQLITE_PATH) on $OS"
${CC} -shared \
  -I ./. \
  -I ./out \
  -I ./.. \
  -I $SQLITE_PATH/sqlite3ext.h \
  -o ./out/cqlextension.${LIB_EXT} \
  ./out/SampleInterop.c \
  ./cql_sqlite_extension.c \
  ./out/Sample.c \
  ./../cqlrt.c

popd >/dev/null
