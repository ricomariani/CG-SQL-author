#!/bin/bash
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

set -euo pipefail

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
echo "schema upgrade test"
$O/cql --in upgrade_test.sql --cg $O/x.l --rt lua
(cd $O ; lua $O/x.l >$O/lua_upgrade.txt)
diff lua_upgrade.ref $O/lua_upgrade.txt 
echo no diffs means success

echo ""
echo "run test (NOTE: some exception spam is normal, the tests throwing exceptions on purpose)"
echo ""

(cd ..; lua_demo/run_test.sh)