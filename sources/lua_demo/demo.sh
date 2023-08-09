#!/bin/bash
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

set -euo pipefail

DIR="$( dirname -- "$0"; )"
cd "${DIR}" || exit

set -e

O="../out"
cp ../cqlrt.lua $O

echo test1
$O/cql --in t1.sql --cg $O/x.l --rt lua
(cd $O ; lua $O/x.l)
echo test2
$O/cql --in t2.sql --cg $O/x.l --rt lua
(cd $O ; lua $O/x.l)
echo test3
$O/cql --in t3.sql --cg $O/x.l --rt lua
(cd $O ; lua $O/x.l)
echo test4
$O/cql --in t4.sql --cg $O/x.l --rt lua
(cd $O ; lua $O/x.l)
echo test5
$O/cql --in t5.sql --cg $O/x.l --rt lua
(cd $O ; lua $O/x.l)
echo test6
$O/cql --in t6.sql --cg $O/x.l --rt lua
(cd $O ; lua $O/x.l)
echo demo
$O/cql --in demo.sql --cg $O/x.l --rt lua
(cd $O ; lua $O/x.l)
echo query plan
$O/cql --in qp.sql --cg $O/qp_gen.sql --rt query_plan
$O/cql --in $O/qp_gen.sql --cg $O/x.l --rt lua --dev
echo "function printf(...) io.write(cql_printf(...)) end" >> $O/x.l
echo "query_plan(sqlite3.open_memory())" >> $O/x.l
(cd $O ; lua $O/x.l)

echo ""
echo "run test"
echo "--------"
echo ""
echo "NOTE: some exception spam is normal, the tests throwing exceptions on purpose;  there are 9."
echo ""

./run_test.sh
