#!/bin/bash
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

# exit when any command fails
set -e

S=$(cd $(dirname "$0"); pwd)
O=$S/out
R=$S/..

rm -rf $O
mkdir -p $O

CC="cc -g"

if [ "$(uname)" == "Linux" ];
then
  # linux path variation and -fPIC for .so output
  CC="${CC} -I $O -I $R -fPIC"
  SUFFIX=dll
else
  # assuming clang elsewhere (e.g. Mac)
  CC="${CC} -I $O -I $R"
  SUFFIX=dll
fi

if [ "${SQLITE_PATH}" != "" ] ;
then
  echo building sqlite amalgam
  CC="${CC} -I${SQLITE_PATH}"
  SQLITE_LINK=sqlite3-all.o
  ${CC} -c -o $O/sqlite3-all.o ${SQLITE_PATH}/sqlite3-all.c
else
  SQLITE_LINK=-lsqlite3
fi

echo "building cql"
(cd $O/../.. ; make)
CQL=$R/out/cql

echo "making directories"

mkdir -p $O/sample

echo "generating stored procs C and JSON"
cp Sample.sql $O
pushd $O >/dev/null
${CQL} --in Sample.sql --cg Sample.h Sample.c
${CQL} --in Sample.sql --rt json_schema --cg Sample.json

echo "generating C# interop class and the C code for it"
../cqlcs.py Sample.json --class SampleInterop >SampleInterop.cs
../cqlcs.py Sample.json --emit_c --class SampleInterop --cql_header Sample.h >SampleInterop.c
popd >/dev/null

echo "compiling native code"
pushd $O >/dev/null

${CC} -o cql_interop.dll -shared $S/cql_interop.c $R/cqlrt.c Sample.c SampleInterop.c ${SQLITE_LINK}

mkdir -p ../bin/Debug/net8.0
mv cql_interop.dll ../bin/Debug/net8.0

popd >/dev/null

dotnet run -f net8.0
