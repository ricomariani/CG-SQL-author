#!/bin/bash
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

DIR="$( dirname -- "$0"; )"
INPUT="${DIR}/out/qp_in"

set -euo pipefail

# shellcheck disable=SC1091
source common/test_helpers.sh || exit 1

rm -f "${INPUT}"
cp "$1" "${INPUT}"
cd "${DIR}" || exit

if ! make > "out/make.out"
then
   echo "CQL build failed"
   cat "out/make.out"
   failed
fi

CQL="out/cql"

# echo semantic analysis
if ! ${CQL} --sem --ast --dev --in "out/qp_in" >"out/__temp" 2>"out/cg_test_query_plan.err"
then
    echo "CQL semantic analysis returned error"
    cat "out/cg_test_query_plan.err"
    failed
fi

# echo codegen query plan
if ! ${CQL} --test --dev --cg "out/cg_test_query_plan.out" --in "out/qp_in" --rt query_plan 2>"out/cg_test_query_plan.err"
then
    echo "CQL codegen query plan error"
    cat "out/cg_test_query_plan.err"
    failed
fi

# echo semantic analysis of generated code (pre check)
if ! ${CQL} --sem --ast --dev --test --in "out/cg_test_query_plan.out" >"out/__temp" 2>"out/cg_test_query_plan.err"
then
    echo "CQL query plan semantic analysis returned error"
    cat "out/cg_test_query_plan.err"
    failed
fi

# build query plan c code
if ! ${CQL} --test --dev --cg "out/query_plan.h" "out/query_plan.c" --in "out/cg_test_query_plan.out" 2>"out/query_plan_print.err"
then
    echo "CQL codegen query plan return error"
    cat "out/query_plan_print.err"
    failed
fi

# compile query plan code with Makefile
if ! make query_plan_test >"out/make.out" 2>"out/make.err"
then
    echo "CQL query plan build failed"
    echo "stdout"
    cat "out/make.out"
    echo "stderr"
    cat "out/make.err"
    failed
fi

# Run query plan in c. It will output the query plan.
# Nothing else should be output in this script otherwise it'll break the formatted text
"./out/query_plan_test"
