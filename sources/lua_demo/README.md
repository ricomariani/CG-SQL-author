# Summary

These files illustrate the usage of an the generation of Lua from CQL.  CQL can generate
C or Lua natively.

* `demo.sh` -- test and demo output script
* `demo.sql` -- simple Lua demo
* `lua_upgrade0.ref` -- referendce output for schema upgrade with Lua (baseline)
* `lua_upgrade1.ref` -- referendce output for schema upgrade with Lua (0 to 1)
* `lua_upgrade2.ref` -- referendce output for schema upgrade with Lua (1 to 2)
* `lua_upgrade3.ref` -- referendce output for schema upgrade with Lua (2 to 3)
* `lua_upgrade4.ref` -- referendce output for schema upgrade with Lua (3 to 4)
* `prepare_run_test.sh` -- build the run test and test helpers in lua, concat them to make buildable artifacts
* `qp.sql` -- a simple test for query plan output
* `run_test.sh` -- build and execute the standard run tests for Lua (`test/run_test.sql`)
* `run_test_lua.ref` -- reference output for the run tests
* `t[1-5].sql` -- assorted small test cases for easy debugging of basics
* `test_helpers.lua` -- lua version of test helpers, these are simple runtime function used by test cases
* `upgrade_harness.cql` -- runs the upgrade steps in sequence and verifies as we go along

# Usage

* `demo.sh` can be run from this directory
* `run_test.sh` should be run from the main sources directory

the main test script does not execute lua code because that would require assumptions about
lua install that we are not yet willing to make

# License

This source code is licensed under the MIT license found in the
LICENSE file in the root directory of this source tree.