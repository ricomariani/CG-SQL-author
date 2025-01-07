#!/bin/bash
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

# exit when any command fails
set -e

echo "building cql"
(cd .. ; make)

CQL=../out/cql

echo "building C code"
${CQL} --in Sample.sql --cg Sample.h Sample.c --cqlrt cqlrt_cf.h

echo "building JSON"
${CQL} --in Sample.sql --cg Sample.json --rt json_schema

echo "building OBJC header (.h)"
./cql_objc_full.py Sample.json --header Sample.h >Sample_objc.h

echo "building OBJC implementation (.m)"
./cql_objc_full.py Sample.json --emit_impl --header Sample_objc.h >Sample_objc.m

echo "compiling sample consumer"
clang -o demo -g Sample.c Sample_objc.m my_objc.m ../cqlrt_cf/cqlholder.m ../cqlrt_cf/cqlrt_cf.c  -I. -I.. -I../cqlrt_cf -fobjc-arc -lsqlite3

echo "running demo"
./demo

echo ""
echo "Done"
echo ""
echo "to clean the directory run ./clean.sh"
echo "building executable"
