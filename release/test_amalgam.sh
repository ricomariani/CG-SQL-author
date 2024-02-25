#!/bin/bash

set -euo pipefail

echo test full amalgam
cc cql_amalgam.c

echo "test minimal combo"
cc -DCQL_AMALGAM_LEAN -DCQL_AMALGAM_GEN_SQL -DCQL_AMALGAM_SEM -DCQL_AMALGAM_CG_COMMON cql_amalgam.c

echo "test with min + SQL schema features"
cc -DCQL_AMALGAM_LEAN -DCQL_AMALGAM_GEN_SQL -DCQL_AMALGAM_SEM -DCQL_AMALGAM_CG_COMMON -DCQL_AMALGAM_SCHEMA cql_amalgam.c

echo "test with min + C code gen"
cc -DCQL_AMALGAM_LEAN -DCQL_AMALGAM_GEN_SQL -DCQL_AMALGAM_SEM -DCQL_AMALGAM_CG_COMMON -DCQL_AMALGAM_CG_C cql_amalgam.c

echo "test with min + Lua code gen"
cc -DCQL_AMALGAM_LEAN -DCQL_AMALGAM_GEN_SQL -DCQL_AMALGAM_SEM -DCQL_AMALGAM_CG_COMMON -DCQL_AMALGAM_CG_LUA cql_amalgam.c

echo "test with min + JSON schema"
cc -DCQL_AMALGAM_LEAN -DCQL_AMALGAM_GEN_SQL -DCQL_AMALGAM_SEM -DCQL_AMALGAM_CG_COMMON -DCQL_AMALGAM_CG_JSON cql_amalgam.c

echo "test with min + ObjC code gen"
cc -DCQL_AMALGAM_LEAN -DCQL_AMALGAM_GEN_SQL -DCQL_AMALGAM_SEM -DCQL_AMALGAM_CG_COMMON -DCQL_AMALGAM_CG_OBJC cql_amalgam.c

echo "test with min + query plan"
cc -DCQL_AMALGAM_LEAN -DCQL_AMALGAM_GEN_SQL -DCQL_AMALGAM_SEM -DCQL_AMALGAM_CG_COMMON -DCQL_AMALGAM_QUERY_PLAN cql_amalgam.c

echo "test with min + test helpers"
cc -DCQL_AMALGAM_LEAN -DCQL_AMALGAM_GEN_SQL -DCQL_AMALGAM_SEM -DCQL_AMALGAM_CG_COMMON -DCQL_AMALGAM_TEST_HELPERS cql_amalgam.c

echo "test with min + statistics"
cc -DCQL_AMALGAM_LEAN -DCQL_AMALGAM_GEN_SQL -DCQL_AMALGAM_SEM -DCQL_AMALGAM_CG_COMMON -DCQL_AMALGAM_STATS cql_amalgam.c

echo "test with min + internal unit tests (tests C codegen paths)"
cc -DCQL_AMALGAM_LEAN -DCQL_AMALGAM_GEN_SQL -DCQL_AMALGAM_SEM -DCQL_AMALGAM_CG_COMMON -DCQL_AMALGAM_CG_C -DCQL_AMALGAM_UNIT_TESTS cql_amalgam.c

rm a.out
