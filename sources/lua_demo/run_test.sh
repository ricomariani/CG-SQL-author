#!/bin/bash
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

set -euo pipefail

DIR="$( dirname -- "$0"; )"
cd "${DIR}/.."

lua_demo/prepare_run_test.sh
lua out/run_test.lua | tee out/run_test_lua.out

#-- this number changes all the time, don't check for it
grep -v "tests executed[.]" out/run_test_lua.out >out/run_test_lua.clean

echo "verifying test output"

if ! diff lua_demo/run_test_lua.ref out/run_test_lua.clean
then
  echo diff lua_demo/run_test_lua.ref out/run_test_lua.out
  echo failed
  exit 1
fi

echo "no differences found"

echo ""
echo "schema upgrade test"

schema_upgrade() {
  V=$1
  O=$2
  lua "out/lua_schema_upgrade$V.lua" >out/lua_upgrade.txt "$O"
}

schema_diff() {
  V=$1
  if ! diff "lua_demo/lua_upgrade$V.ref" out/lua_upgrade.txt
  then
    echo diff "lua_demo/lua_upgrade$V.ref" out/lua_upgrade.txt
    echo failed
    exit 1
  fi
}

echo "test will terminate on any unexpected schema difference"

rm -f out/*.db

for i in {0..4}
do
  schema_upgrade "$i" "out/lua_db$i.db"
  schema_diff "$i"
done

rm -f out/*.db

for i in {0..4}
do
  echo "upgrade incrementally to $i"
  schema_upgrade "$i" out/lua_db.db
  schema_diff "$i"
done


for i in {0..4}
do
  for j in {0..4}
  do
    if [ "$j" -le "$i" ]; then

      echo "Upgrade from nothing to v$j, then to v$i -- must match direct update to v$i"
      rm -f out/*.db
      schema_upgrade "$j" out/lua_db.db
      schema_upgrade "$i" out/lua_db.db
      schema_diff "$i"
   fi

  done
done

echo "no differences found"
echo ""
echo "all tests complete"
