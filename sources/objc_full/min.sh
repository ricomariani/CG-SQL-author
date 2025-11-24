#!/bin/bash
# Copyright (c) Rico Mariani
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

# exit when any command fails
set -e

echo "building cql"
(cd .. ; make)

echo "This script minimally tests the generated code to see if it will at least compile"

echo "building C code"
../out/cql --in Sample.sql --cg Sample.h Sample.c --cqlrt cqlrt_cf.h

echo "building JSON"
../out/cql --in Sample.sql --cg Sample.json --rt json_schema

echo "building OBJC header (.h)"
./cql_objc_full.py Sample.json --header Sample.h --legacy >Sample_objc.h

echo "building OBJC implementation (.m)"
./cql_objc_full.py Sample.json --emit_impl --header Sample_objc.h --legacy >Sample_objc.m

echo "compiling generated code looking for errors"
clang -DCQL_OBJC_MIN_COMPILE -c Sample_objc.m -I/usr/include/GNUstep/ -I/usr/lib/gcc/x86_64-linux-gnu/11/include -I. -I.. -I../cqlrt_cf -Wno-arc-bridge-casts-disallowed-in-nonarc

echo "compiling sample consumer"
clang -DCQL_OBJC_MIN_COMPILE -c my_objc.m -I/usr/include/GNUstep/ -I/usr/lib/gcc/x86_64-linux-gnu/11/include -I. -I.. -I../cqlrt_cf -Wno-arc-bridge-casts-disallowed-in-nonarc

echo "not linking or running -- this is a compile test only"
#./demo

echo ""
echo "Done"
echo ""
echo "to clean the directory run ./clean.sh"
