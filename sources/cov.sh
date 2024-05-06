#!/bin/bash
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

COV_EXTRA_ARGS=""

COV_ARGS="${COV_COVERAGE_ARGS}"

O="out"

GCOVR=gcovr

coverage() {
	rm -f *.gcov

	if ! ./test.sh --coverage $@; then
		echo "you can't run coverage until the tests all pass"
		return 1
	fi

	# super spammy, we only care about the errors
	if ! gcov out/*.gcda >/dev/null; then
		echo "error running gcov"
		return 1
	fi

	echo generating $O/report.html
	if ! "${GCOVR}" \
		-g -k \
		--html \
		--html-details \
		-o $O/report.html \
		${COV_EXTRA_ARGS} \
		-e test \
		-e cql-verify \
		-e linetester \
		-e json_test \
		-e out \
		-e cql.c \
		-e cql.y.c \
		-e cqltest.c \
		-e result_set_extension.c \
		-e run_test_client.c \
		-e query_plan_test.c \
		-e run_test.c \
		-e generated_upgrade \
		-e upgrade; then
		echo "error generating html"
		return 1
	fi

	echo generating $O/report.txt
	if ! "${GCOVR}" \
		-g -k \
		-o $O/report.txt \
		${COV_EXTRA_ARGS} \
		-e test \
		-e cql-verify \
		-e linetester \
		-e json_test \
		-e out \
		-e cql.c \
		-e cql.y.c \
		-e cqltest.c \
		-e result_set_extension.c \
		-e run_test_client.c \
		-e query_plan_test.c \
		-e run_test.c \
		-e generated_upgrade \
		-e upgrade; then
		echo "error generating plain text"
		return 1
	fi

	rm -f *.gcov

	return 0
}

if ! coverage $@; then
	echo "A coverage step failed, aborting"
	exit 1
fi

cat "$O/report.txt"
exit 0
