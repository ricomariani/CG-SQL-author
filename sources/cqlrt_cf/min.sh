#!/bin/bash
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

# exit when any command fails
set -e

echo "building cql"
(cd .. ; make)

echo "This script minimally tests the generated code to see if it will at least compile"

echo "building C code"
../out/cql --in demo_todo.sql --cg demo_todo.h demo_todo.c --cqlrt cqlrt_cf.h

echo "building JSON"
../out/cql --in demo_todo.sql --cg demo_todo.json --rt json_schema

echo "building OBJC code"
./cqlobjc.py demo_todo.json --objc_c_include_path demo_todo.h >demo_objc.h

echo "compiling generated code looking for errors"
clang -DCQL_OBJC_MIN_COMPILE -c demo_main.m -I/usr/include/GNUstep/ -I/usr/lib/gcc/x86_64-linux-gnu/11/include -I. -I..

echo "not linking or running -- this is a compile test only"
#./demo

echo ""
echo "Done"
echo ""
echo "to clean the directory run ./clean.sh"
