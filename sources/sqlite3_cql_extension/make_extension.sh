#!/bin/bash
# Copyright (c) Joris Garonian and Rico Mariani
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

set -o errexit -o nounset -o pipefail

echo "This build is only to create a shared library version of some extension you might need"
echo "On many operating systems this binding can be tricky."
echo "Testing is limited so be prepared to sort out the dynamic loading yourself."
echo

S=$(cd $(dirname "$0"); pwd)
O=$S/out
R=$S/..
T=.

rm -f $O/cqlrt.o

source $S/../common/test_helpers.sh || exit 1

if [ -v SQLITE_PATH ]; then
  echo using external SQLITE ${SQLITE_PATH}
else
  SQLITE_PATH=$R/sqlite
fi

SQLITE_PATH=$(realpath $SQLITE_PATH)

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
  elif [ "$1" == "--non_interactive" ]; then
    # shellcheck disable=SC2034
    NON_INTERACTIVE=1
    export NON_INTERACTIVE
    shift 1
  else
    echo "Usage: make.sh"
    echo "  --use_gcc"
    echo "  --use_clang"
    echo "  --non_interactive"
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

CC="${CC} -g -O0 -DCQL_SQLITE_EXT"

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

CC="${CC} -shared"
echo CFLAGS: ${CC}

echo "Build ./out/cqlextension.$LIB_EXT extension for SQLite ${SQLITE_PATH}/sqlite3ext.h on ${OS}"

${CC} \
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

echo running SQLite test cases with extension
set +e
$SQLITE_PATH/sqlite3 <test_extension.sql > out/test_extension.out 2>&1

echo checking output difference
set -e
on_diff_exit ./test_extension.out

popd >/dev/null

echo "test passed"
exit 0
