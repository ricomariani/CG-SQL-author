#!/bin/bash
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

# out directory
O="out"

# test directory
T="test"

CQL="./$O/cql"

xSQLITE_PATH="SQLITE_PATH=$HOME/dev/dadbiz++/third-party/dad/sqlite3-orig"

# shellcheck disable=SC2034
ERROR_DOC="../docs/user_guide/appendices/04_error_codes.md"

# shellcheck disable=SC1091
source common/test_helpers.sh || exit 1

while [ "$1" != "" ]; do
	if [ "$1" == "--use_asan" ]; then
		CGSQL_ASAN=1
		export CGSQL_ASAN
		shift 1
	elif [ "$1" == "--use_gcc" ]; then
		CC=gcc
		export CC
		shift 1
	elif [ "$1" == "--use_clang" ]; then
		CC=clang
		export CC
		shift 1
	elif [ "$1" == "--coverage" ]; then
		MAKE_COVERAGE_ARGS="COVERAGE=1 $xSQLITE_PATH"
		TEST_COVERAGE_ARGS="--coverage"
		shift 1
	elif [ "$1" == "--use_amalgam" ]; then
		CQL=$O/cql_amalgam
		shift 1
	elif [ "$1" == "--non_interactive" ]; then
		# shellcheck disable=SC2034
		NON_INTERACTIVE=1
		shift 1
	else
		echo "Usage: test.sh"
		echo "  --use_asan"
		echo "  --use_gcc"
		echo "  --use_clang"
		echo "  --coverage"
		echo "  --use_amalgam"
		echo "  --non_interactive"
		exit 1
	fi
done

# no extra tests
extra_tests() {
	echo "no extra tests at this time"
}

MAKE_ARGS="${MAKE_COVERAGE_ARGS} $xSQLITE_PATH"

do_make() {
	if [ "${MAKE_ARGS}" == "" ]; then
		# we don't want to send empty strings "" to make, so avoid that
		make "$@"
	else
		make "$@" "${MAKE_ARGS}"
	fi
}

sem_check() {
	${CQL} "$@"
	if [ "$?" -ne "1" ]; then
		echo 'All semantic analysis checks have errors in the test'
		echo 'the normal return code is "1" -- any other return code is bad news'
		echo 'A return code of zero indicates we reported success in the face of errors'
		echo 'A return code other than 1 indicates an unexpected fatal error of some type'
		return 1
	fi
}

cql_verify() {
	if ! "$O/cql-verify" "$1" "$2"; then
		echo failed verification: cql-verify "$1" "$2"
		failed
	fi
}

errors_documented() {
	echo '--------------------------------- VERIFYING ALL ERRORS DOCUMENTED'
	grep '"CQL[0-9][0-9][0-9][0-9]:' sem.c rewrite.c printf.c | sed -e 's/[.]c://' -e 's/:.*//' -e "s/.*CQL/CQL/" | sort -u >"$O/errs_used.txt"
	grep '### CQL[0-9][0-9][0-9][0-9]:' "${ERROR_DOC}" | sed -e 's/:.*//' -e "s/.*CQL/CQL/" | sort -u >"$O/errs_documented.txt"
	echo "missing lines (usually red) need to be added to docs"
	echo "extras lines (usually green) need to be marked as available for re-use"
	echo "when marking lines available (remove the ':' so they don't match)"
	echo "errors are documented in" "${ERROR_DOC}"
	__on_diff_exit "$O/errs_used.txt" "$O/errs_documented.txt"
}

some_lints() {
	echo '--------------------------------- VERIFYING A FEW CODE LINTS'
	if grep ' for(' ./*.c ./*.h; then
		echo "anti pattern 'for(' found, use 'for ('"
		failed
	fi

	if grep ' if(' ./*.c ./*.h; then
		echo "anti pattern 'if(' found, use 'if ('"
		failed
	fi

	if grep ' while(' ./*.c ./*.h; then
		echo "anti pattern 'while(' found, use 'while ('"
		failed
	fi

	if grep ' switch(' ./*.c ./*.h; then
		echo "anti pattern 'switch(' found, use 'switch ('"
		failed
	fi
}

building() {
	echo '--------------------------------- STAGE 1 -- make clean, then make'
	echo building new cql
	do_make clean >/dev/null 2>/dev/null
	if ! do_make all >"$O/build.out" 2>"$O/build.err"; then
		echo build cql failed:
		cat "$O/build.err"
		failed
	fi

	if grep "^State.*conflicts:" "$O/cql.y.output" >"$O/build.err"; then
		echo "conflicts found in grammar, these must be fixed" >>"$O/build.err"
		echo "look at the conflicting states in" "$O/cql.y.output" "to debug" >>"$O/build.err"
		cat "$O/build.err"
		failed
	fi

	echo building cql amalgam
	if ! do_make amalgam >"$O/build.out" 2>"$O/build.err"; then
		echo build cql amalgam failed:
		cat "$O/build.err"
		failed
	fi

	echo building cql amalgam test
	if ! do_make amalgam_test >"$O/build.out" 2>"$O/build.err"; then
		echo build cql amalgam test failed:
		cat "$O/build.err"
		failed
	fi

	echo building cql-verify
	if ! (do_make cql-verify) 2>"$O/build.err"; then
		echo build cql-verify failed:
		cat "$O/build.err"
		failed
	fi

	echo building cql-linetest
	if ! (do_make cql-linetest) 2>"$O/build.err"; then
		echo build cql-linetest failed:
		cat "$O/build.err"
		failed
	fi

	echo building json-test
	if ! (do_make json-test) 2>"$O/build.err"; then
		echo build json-test failed:
		cat "$O/build.err"
		failed
	fi

	errors_documented
	some_lints
}

create_unwritable_file() {
	rm -f "$1"
	echo x >"$1"
	chmod -rw "$1"
}

basic_test() {
	echo '--------------------------------- STAGE 2 -- BASIC PARSING TEST'
	echo running "$T/test.sql"
	# exercising the non --in path (i.e. read from stdin)
	if ! ${CQL} --echo --dev --include_paths "$T" <"$T/test.sql" >"$O/test.out"; then
		echo basic parsing test failed
		failed
	fi
	if ! ${CQL} --echo --dev --in "$O/test.out" >"$O/test.out2"; then
		echo "Echo output does not parse again correctly"
		failed
	fi

	echo "  computing diffs (empty if none)"
	on_diff_exit test.out

	echo "  computing diffs second parsing (empty if none)"
	mv "$O/test.out2" "$O/test.out"
	on_diff_exit test.out

	echo running "$T/test.sql" "with macro expansion"
	if ! ${CQL} --echo --dev --include_paths "$T" --in "$T/test.sql" --exp >"$O/test_exp.out"; then
		echo basic parsing with expansion test failed
		failed
	fi
	echo "  computing diffs (empty if none)"
	on_diff_exit test_exp.out

	echo testing include file not found
	if ${CQL} --in "$T/test_include_file_not_found.sql" 2>"$O/include_not_found.err"; then
		echo "error code should have indicated failure"
		failed
	fi

	echo "  computing diffs (empty if none)"
	on_diff_exit include_not_found.err

	echo testing include files nested too deeply

	if ${CQL} --in "$T/include_files_infinite_nesting.sql" --include_paths test 2>"$O/include_nesting.err"; then
		echo "error code should have indicated failure"
		failed
	fi

	echo "  computing diffs (empty if none)"
	on_diff_exit include_nesting.err

	echo "testing ifdef"
	if ! ${CQL} --in "$T/test_ifdef.sql" --echo --defines foo >"$O/test_ifdef.out" 2>"$O/test_ifdef.err"; then
		echo "basic parsing with ifdefs failed"
		cat "$O/test_ifdef.err"
		failed
	fi

	echo "  computing diffs (empty if none)"
	on_diff_exit test_ifdef.out

	echo "testing empty include file"

	if ! ${CQL} --in "$T/include_empty.sql" --echo --include_paths test >"$O/include_empty.out" 2>"$O/include_empty.err"; then
		echo "empty include file failed"
		cat "$O/include_empty.err"
		failed
	fi

	echo "  computing diffs (empty if none)"
	on_diff_exit include_empty.out
}

macro_test() {
	echo '--------------------------------- STAGE 3 -- MACRO TEST'
	echo running macro expansion test
	if ! ${CQL} --test --exp --ast --hide_builtins --in "$T/macro_test.sql" >"$O/macro_test.out" 2>"$O/macro_test.err"; then
		echo "CQL macro test returned unexpected error code"
		cat "$O/macro_test.err"
		failed
	fi

	echo validating output trees
	cql_verify "$T/macro_test.sql" "$O/macro_test.out"

	echo "  computing diffs (empty if none)"
	on_diff_exit macro_test.out

	echo running macro expansion error cases
	if ${CQL} --exp --in "$T/macro_exp_errors.sql" >"$O/macro_exp_errors.out" 2>"$O/macro_test.err.out"; then
		echo "CQL macro error test returned unexpected error code"
		cat "$O/macro_test.err.out"
		failed
	fi

	echo "  computing diffs (empty if none)"
	on_diff_exit macro_test.err.out

	echo running macro expansion duplicate name
	if ${CQL} --exp --in "$T/macro_test_dup_arg.sql" >"$O/macro_exp_errors.out" 2>"$O/macro_test_dup.err.out"; then
		echo "CQL macro error test returned unexpected error code"
		cat "$O/macro_test_dup.err.out"
		failed
	fi

	echo "  computing diffs (empty if none)"
	on_diff_exit macro_test_dup.err.out
}

semantic_test() {
	echo '--------------------------------- STAGE 4 -- SEMANTIC ANALYSIS TEST'
	echo running semantic analysis test
	if ! sem_check --sem --ast --hide_builtins --dev --in "$T/sem_test.sql" >"$O/sem_test.out" 2>"$O/sem_test.err"; then
		echo "CQL semantic analysis returned unexpected error code"
		cat "$O/sem_test.err"
		failed
	fi

	echo validating output trees
	cql_verify "$T/sem_test.sql" "$O/sem_test.out"

	echo running dev semantic analysis test
	if ! sem_check --sem --ast --in "$T/sem_test_dev.sql" >"$O/sem_test_dev.out" 2>"$O/sem_test_dev.err"; then
		echo "CQL semantic analysis returned unexpected error code"
		cat "$O/sem_test_dev.err"
		failed
	fi

	echo validating output trees
	cql_verify "$T/sem_test_dev.sql" "$O/sem_test_dev.out"

	echo "  computing diffs (empty if none)"
	on_diff_exit sem_test.out
	on_diff_exit sem_test.err
	on_diff_exit sem_test_dev.out
	on_diff_exit sem_test_dev.err
}

code_gen_c_test() {
	echo '--------------------------------- STAGE 5 -- C CODE GEN TEST'
	echo running codegen test
	if ! ${CQL} --dev --test --cg "$O/cg_test_c.h" "$O/cg_test_c.c" "$O/cg_test_exports.out" --in "$T/cg_test.sql" --global_proc cql_startup --generate_exports 2>"$O/cg_test_c.err"; then
		echo "ERROR:"
		cat "$O/cg_test_c.err"
		failed
	fi

	echo validating codegen
	cql_verify "$T/cg_test.sql" "$O/cg_test_c.c"

	echo testing for successful compilation of generated C
	rm -f out/cg_test_c.o
	if ! do_make out/cg_test_c.o; then
		echo "ERROR: failed to compile the C code from the code gen test"
		failed
	fi

	echo verifying globals codegen does not require a global proc
	# this has no --test directive and no --nolines
	if ! ${CQL} --cg "$O/cg_test_c_globals.h" "$O/cg_test_c_globals.c" --in "$T/cg_test_c_globals.sql" 2>"$O/cg_test_c.err"; then
		echo "ERROR:"
		cat "$O/cg_test_c.err"
		failed
	fi

	echo running codegen test for global variables group
	if ! ${CQL} --test --cg "$O/cg_test_c_globals.h" "$O/cg_test_c_globals.c" --in "$T/cg_test_c_globals.sql" 2>"$O/cg_test_c.err"; then
		echo "ERROR:"
		cat "$O/cg_test_c.err"
		failed
	fi

	echo validating codegen for globals
	cql_verify "$T/cg_test_c_globals.sql" "$O/cg_test_c_globals.h"

	echo running codegen test with type getters enabled
	if ! ${CQL} --test --cg "$O/cg_test_c_with_type_getters.h" "$O/cg_test_c_with_type_getters.c" --in "$T/cg_test_c_type_getters.sql" --global_proc cql_startup 2>"$O/cg_test_c.err"; then
		echo "ERROR:"
		cat "$O/cg_test_c.err"
		failed
	fi

	echo validating codegen
	cql_verify "$T/cg_test_c_type_getters.sql" "$O/cg_test_c_with_type_getters.h"

	echo testing for successful compilation of generated C with type getters
	rm -f out/cg_test_c_with_type_getters.o
	if ! do_make out/cg_test_c_with_type_getters.o; then
		echo "ERROR: failed to compile the C code from the type getters code gen test"
		failed
	fi

	echo running codegen test with namespace enabled
	if ! ${CQL} --dev --test --cg "$O/cg_test_c_with_namespace.h" "$O/cg_test_c_with_namespace.c" "$O/cg_test_imports_with_namespace.ref" --in "$T/cg_test.sq"l --global_proc cql_startup --c_include_namespace test_namespace --generate_exports 2>"$O/cg_test_c.err"; then
		echo "ERROR:"
		cat "$O/cg_test_c.err"
		failed
	fi

	echo validating codegen
	cql_verify "$T/cg_test.sql" "$O/cg_test_c_with_namespace.c"

	echo running codegen test with c_include_path specified
	if ! ${CQL} --dev --test --cg "$O/cg_test_c_with_header.h" "$O/cg_test_c_with_header.c" --in "$T/cg_test.sql" --global_proc cql_startup --c_include_path "somewhere/something.h" 2>"$O/cg_test_c.err"; then
		echo "ERROR:"
		cat "$O/cg_test_c.err"
		failed
	fi

	echo validating codegen
	cql_verify "$T/cg_test.sql" "$O/cg_test_c_with_header.c"

	echo "  computing diffs (empty if none)"
	on_diff_exit cg_test_c.c
	on_diff_exit cg_test_c.h
	on_diff_exit cg_test_c_globals.c
	on_diff_exit cg_test_c_globals.h
	on_diff_exit cg_test_c_with_namespace.c
	on_diff_exit cg_test_c_with_namespace.h
	on_diff_exit cg_test_c_with_header.c
	on_diff_exit cg_test_c_with_header.h
	on_diff_exit cg_test_c_with_type_getters.c
	on_diff_exit cg_test_c_with_type_getters.h
	on_diff_exit cg_test_exports.out
	on_diff_exit cg_test_c.err

	echo "  compiling code"

	if ! do_make cg_test; then
		echo CQL generated invalid C code
		failed
	fi
}

code_gen_objc_test() {
	echo '--------------------------------- STAGE 7 -- OBJ-C CODE GEN TEST'
	echo running codegen test
	if ! ${CQL} --dev --test --cg "$O/cg_test_objc.out" --objc_c_include_path Test/TestFile.h --in "$T/cg_test.sql" --rt objc 2>"$O/cg_test_objc.err"; then
		echo "ERROR:"
		cat "$O/cg_test_objc.err"
		failed
	fi

	echo validating codegen
	echo "  check that the objc_c_include_path argument was is used"
	if ! grep "<Test/TestFile.h>" "$O/cg_test_objc.out"; then
		echo "<Test/TestFile.h>" should appear in the output
		echo check "$O/cg_test_objc.out" for this pattern and root cause.
		failed
	fi

	echo validating codegen
	echo "  computing diffs (empty if none)"

	on_diff_exit cg_test_objc.out
	on_diff_exit cg_test_objc.err
}

assorted_errors_test() {
	echo '--------------------------------- STAGE 8 -- FAST FAIL CASES'
	echo running various failure cases that cause no output

	# the output path doesn't exist, should cause an error

	if ${CQL} --in /xx/yy/zz 2>"$O/badpath.err"; then
		echo "reading from non-existant file should have failed, but didn't"
		failed
	fi

	on_diff_exit badpath.err

	# the output file is not writeable, should cause an error

	if ${CQL} --dev --cg /xx/yy/zz /xx/yy/zzz --in "$T/cg_test.sql" --global_proc xx 2>"$O/unwriteable.err"; then
		echo "failed writing to unwriteable file should have failed, but didn't"
		failed
	fi

	on_diff_exit unwriteable.err

	# wrong number of args specified in --cg (for objc)

	if ${CQL} --dev --cg "$O/__temp" "$O/__temp2" --in "$T/cg_test.sql" --rt objc 2>"$O/cg_1_2.err"; then
		echo "objc rt should require 1 files for the cg param but two were passed, should have failed"
		failed
	fi

	# semantic errors should abort output (we'll not try to write)

	on_diff_exit cg_1_2.err

	if ${CQL} --cg "$O/__temp" /xx/yy/zz --in "$T/semantic_error.sql" 2>"$O/sem_abort.err"; then
		echo "simple semantic error to abort output -- failed"
		failed
	fi

	on_diff_exit sem_abort.err

	# no result sets in the input for objc should result in empty output, not errors

	if ! ${CQL} --cg "$O/__temp" --in "$T/noresult.sql" --objc_c_include_path dummy --rt objc 2>"$O/objc_no_results.err"; then
		echo "no result sets in output objc case, should not fail"
		failed
	fi

	on_diff_exit objc_no_results.err

	# bogus arg should report error

	if ${CQL} --garbonzo!! 2>"$O/invalid_arg.err"; then
		echo "invalid arg should report error -- failed"
		failed
	fi

	on_diff_exit invalid_arg.err

	# --cg did not have any following args, should force an error

	if ${CQL} --cg 2>"$O/cg_requires_file.err"; then
		echo "failed to require a file name with --cg"
		failed
	fi

	on_diff_exit cg_requires_file.err

	# --generate_file_type did not specify a file type

	if ${CQL} --generate_file_type 2>"$O/generate_file_type.err"; then
		echo "failed to require a file type with --generate_file_type"
		failed
	fi

	on_diff_exit generate_file_type.err

	# --generate_file_type specified invalid file type (should cause an error)

	if ${CQL} --generate_file_type foo 2>"$O/generate_file_file.err"; then
		echo "failed to require a valid file type with --generate_file_type"
		failed
	fi

	on_diff_exit generate_file_file.err

	# --rt specified with no arg following it

	if ${CQL} --rt 2>"$O/rt_arg_missing.err"; then
		echo "failed to require a runtime with --rt"
		failed
	fi

	on_diff_exit rt_arg_missing.err

	# invalid result type specified with --rt, should force an error

	if ${CQL} --rt foo 2>"$O/rt_arg_bogus.err"; then
		echo "failed to require a valid result type with --rt"
		failed
	fi

	on_diff_exit rt_arg_bogus.err

	# --cqlrt specified but no file name present, should force an error

	if ${CQL} --cqlrt 2>"$O/cqlrt_arg_missing.err"; then
		echo "failed to require a file arg with --cqlrt"
		failed
	fi

	on_diff_exit cqlrt_arg_missing.err

	# --global_proc has no proc name

	if ${CQL} --global_proc 2>"$O/global_proc_missing.err"; then
		echo "failed to require a procedure name with --global_proc"
		failed
	fi

	on_diff_exit global_proc_missing.err

	# objc_c_include_path had no path

	if ${CQL} --objc_c_include_path 2>"$O/objc_include_missing.err"; then
		echo "failed to require an include path with --objc_c_include_path"
		failed
	fi

	on_diff_exit objc_include_missing.err

	# --in arg missing

	if ${CQL} --in 2>"$O/in_arg_missing.err"; then
		echo "failed to require a file name with --in"
		failed
	fi

	on_diff_exit in_arg_missing.err

	# no c_include_namespace arg

	if ${CQL} --c_include_namespace 2>"$O/c_include_namespace_missing.err"; then
		echo "failed to require a C namespace with --c_include_namespace"
		failed
	fi

	on_diff_exit c_include_namespace_missing.err
}

schema_migration_test() {
	echo '--------------------------------- STAGE 9 -- SCHEMA MIGRATION TESTS'
	echo running semantic analysis for migration test
	if ! sem_check --sem --ast --in "$T/sem_test_migrate.sql" >"$O/sem_test_migrate.out" 2>"$O/sem_test_migrate.err"; then
		echo "CQL semantic analysis returned unexpected error code"
		cat "$O/sem_test_migrate.err"
		failed
	fi

	echo validating output trees
	cql_verify "$T/sem_test_migrate.sql" "$O/sem_test_migrate.out"

	echo "  computing diffs (empty if none)"
	on_diff_exit sem_test_migrate.out
	on_diff_exit sem_test_migrate.err

	echo '---------------------------------'
	echo running a schema migrate proc test
	if ! sem_check --sem --in "$T/schema_version_error.sql" --ast >"$O/schema_version_error.out" 2>"$O/schema_version_error.err.out"; then
		echo "CQL semantic analysis returned unexpected error code"
		cat "$O/schema_version_error.err.out"
		failed
	fi

	cql_verify "$T/schema_version_error.sql" "$O/schema_version_error.out"

	echo '---------------------------------'
	echo running semantic analysis for previous schema error checks test
	if ! sem_check --sem --ast --exclude_regions high_numbered_thing --in "$T/sem_test_prev.sql" >"$O/sem_test_prev.out" 2>"$O/sem_test_prev.err"; then
		echo "CQL semantic analysis returned unexpected error code"
		cat "$O/sem_test_prev.err"
		failed
	fi

	echo validating output trees
	cql_verify "$T/sem_test_prev.sql" "$O/sem_test_prev.out"

	echo "  computing diffs (empty if none)"
	on_diff_exit sem_test_prev.out
	on_diff_exit sem_test_prev.err

	echo '---------------------------------'
	echo running code gen for migration test

	if ! ${CQL} --cg "$O/cg_test_schema_upgrade.out" --in "$T/cg_test_schema_upgrade.sql" --global_proc test --rt schema_upgrade 2>"$O/cg_test_schema_upgrade.err"; then
		echo "ERROR:"
		cat "$O/cg_test_schema_upgrade.err"
		failed
	fi

	echo validating output trees
	cql_verify "$T/cg_test_schema_upgrade.sql" "$O/cg_test_schema_upgrade.out"

	echo "  compiling the upgrade script with CQL"
	if ! ${CQL} --cg "$O/cg_test_schema_upgrade.h" "$O/cg_test_schema_upgrade.c" --in "$O/cg_test_schema_upgrade.out"; then
		echo CQL compilation failed
		failed
	fi

	echo "  compiling the upgrade script with C"
	if ! do_make cg_test_schema_upgrade; then
		echo CQL migration script compilation failed.
		failed
	fi

	echo "  computing diffs (empty if none)"

	on_diff_exit cg_test_schema_upgrade.out
	on_diff_exit cg_test_schema_upgrade.err

	echo '---------------------------------'
	echo running code gen to produce previous schema

	if ! ${CQL} --cg "$O/cg_test_schema_prev.out" --in "$T/cg_test_schema_upgrade.sql" --rt schema 2>"$O/cg_test_schema_prev.err"; then
		echo "ERROR:"
		cat "$O/cg_test_schema_prev.err"
		failed
	fi

	echo '---------------------------------'
	echo running code gen to produce raw sqlite schema

	if ! ${CQL} --cg "$O/cg_test_schema_sqlite.out" --in "$T/cg_test_schema_upgrade.sql" --rt schema_sqlite 2>"$O/cg_test_schema_sqlite.err"; then
		echo "ERROR:"
		cat "$O/cg_test_schema_sqlite.err"
		failed
	fi

	echo combining generated previous schema with itself to ensure it self validates

	cat "$O/cg_test_schema_prev.out" >"$O/prev_loop.out"
	echo "@previous_schema;" >>"$O/prev_loop.out"
	cat "$O/cg_test_schema_prev.out" >>"$O/prev_loop.out"

	if ! ${CQL} --cg "$O/prev_twice.out" --in "$O/prev_loop.out" --rt schema 2>"$O/cg_test_schema_prev_twice.err"; then
		echo "ERROR:"
		cat "$O/cg_test_schema_prev_twice.err"
		failed
	fi

	echo comparing the generated previous schema from that combination and it should be identical to the original

	if ! ${CQL} --cg "$O/prev_thrice.out" --in "$O/prev_twice.out" --rt schema 2>"$O/cg_test_schema_prev_thrice.err"; then
		echo "ERROR:"
		cat "$O/cg_test_schema_prev_thrice.err"
		failed
	fi

	echo "  computing diffs after several applications (empty if none)"
	__on_diff_exit "$O/cg_test_schema_prev.out" "$O/prev_twice.out"
	__on_diff_exit "$O/prev_twice.out" "$O/prev_thrice.out"

	echo "  computing previous schema diffs from reference (empty if none)"
	on_diff_exit cg_test_schema_prev.out
	on_diff_exit cg_test_schema_prev.err

	echo "  computing sqlite schema diffs from reference (empty if none)"
	on_diff_exit cg_test_schema_sqlite.out
	on_diff_exit cg_test_schema_sqlite.err

	echo "  running schema migration with include/exclude args"
	if ! ${CQL} --cg "$O/cg_test_schema_partial_upgrade.out" --in "$T/cg_test_schema_upgrade.sql" --global_proc test --rt schema_upgrade --include_regions extra --exclude_regions shared 2>"$O/cg_test_schema_partial_upgrade.err"; then
		echo "ERROR:"
		cat "$O/cg_test_schema_partial_upgrade.err"
		failed
	fi

	echo "  compiling the upgrade script with CQL"
	if ! ${CQL} --cg "$O/cg_test_schema_partial_upgrade.h" "$O/cg_test_schema_partial_upgrade.c" --in "$O/cg_test_schema_partial_upgrade.out"; then
		echo CQL compilation failed
		failed
	fi

	echo "  computing diffs (empty if none)"
	on_diff_exit cg_test_schema_partial_upgrade.out
	on_diff_exit cg_test_schema_partial_upgrade.err

	echo "  running schema migration with min version args"
	if ! ${CQL} --cg "$O/cg_test_schema_min_version_upgrade.out" --in "$T/cg_test_schema_upgrade.sql" --global_proc test --rt schema_upgrade --min_schema_version 3 2>"$O/cg_test_schema_min_version_upgrade.err"; then
		echo "ERROR:"
		cat "$O/cg_test_schema_min_version_upgrade.err"
		failed
	fi

	echo "  computing diffs (empty if none)"
	on_diff_exit cg_test_schema_min_version_upgrade.out
	on_diff_exit cg_test_schema_min_version_upgrade.err
}

misc_cases() {
	echo '--------------------------------- STAGE 10 -- MISC CASES'
	echo running usage test
	if ! ${CQL} >"$O/usage.out" 2>"$O/usage.err"; then
		echo usage test failed
		failed
	fi
	on_diff_exit usage.out

	echo running simple error test
	if ${CQL} --in "$T/error.sql" >"$O/error.out" 2>"$O/simple_error.err"; then
		echo simple error test failed
		failed
	fi

	on_diff_exit simple_error.err

	echo running previous schema and codegen incompatible test
	if ${CQL} --cg "$O/__temp.h" "$O/__temp.c" --in "$T/cg_test_prev_invalid.sql" 2>"$O/prev_and_codegen_incompat.err"; then
		echo previous schema and codegen are supposed to be incompatible
		failed
	fi

	on_diff_exit prev_and_codegen_incompat.err

	echo running big quote test
	if ! ${CQL} --cg "$O/__temp.h" "$O/__temp.c" --in "$T/bigquote.sql" --global_proc x >/dev/null 2>"$O/bigquote.err"; then
		echo big quote test failed
		failed
	fi

	on_diff_exit bigquote.err

	echo running alternate cqlrt.h test
	if ! ${CQL} --dev --cg "$O/__temp.h" "$O/__temp.c" --in "$T/cg_test.sql" --global_proc x --cqlrt alternate_cqlrt.h 2>"$O/alt_cqlrt.err"; then
		echo alternate cqlrt test failed
		failed
	fi

	if ! grep alternate_cqlrt.h "$O/__temp.h" >/dev/null; then
		echo alternate cqlrt did not appear in the output header
		failed
	fi

	on_diff_exit alt_cqlrt.err

	echo running too few -cg arguments with --generate_exports test
	if ${CQL} --dev --cg "$O/__temp.c" "$O/__temp.h" --in "$T/cg_test.sql" --global_proc x --generate_exports 2>"$O/gen_exports_args.err"; then
		echo too few --cg args test failed
		failed
	fi

	on_diff_exit gen_exports_args.err

	echo running invalid include regions test
	if ${CQL} --cg "$O/cg_test_schema_partial_upgrade.out" --in "$T/cg_test_schema_upgrade.sql" --global_proc test --rt schema_upgrade --include_regions bogus --exclude_regions shared 2>"$O/inc_invalid_regions.err"; then
		echo invalid include region test failed
		failed
	fi

	on_diff_exit inc_invalid_regions.err

	echo running invalid exclude regions test
	if ${CQL} --cg "$O/cg_test_schema_partial_upgrade.out" --in "$T/cg_test_schema_upgrade.sql" --global_proc test --rt schema_upgrade --include_regions extra --exclude_regions bogus 2>"$O/excl_invalid_regions.err"; then
		echo invalid exclude region test failed
		failed
	fi

	on_diff_exit excl_invalid_regions.err

	echo running global proc is needed but not present test
	if ${CQL} --cg "$O/__temp.c" "$O/__temp.h" --in "$T/bigquote.sql" 2>"$O/global_proc_needed.err"; then
		echo global proc needed but absent failed
		failed
	fi

	on_diff_exit global_proc_needed.err

	echo running test where output file cannot be written
	create_unwritable_file "$O/unwritable.h.out"
	create_unwritable_file "$O/unwritable.c.out"
	if ${CQL} --dev --cg "$O/unwritable.h".out "$O/unwritable.c".out --in "$T/cg_test.sql" --rt c --global_proc cql_startup 2>"$O/write_fail.err"; then
		echo writing should have failed
		failed
	fi

	on_diff_exit write_fail.err

	echo 'testing the generated from comments in non-test environment.'
	if ! ${CQL} --cg "$O/cg_test_generated_from.h" "$O/cg_test_generated_from.c" "$O/cg_test_generated_from.out" --in "$T/cg_test_generated_from.sql" 2>"$O/cg_test_generated_from.err"; then
		cat "$O/cg_test_generated_from.err"
		echo 'ERROR: Compilation failed.'
		failed
	fi

	echo "  check that the objc_c_include_path argument is provided in arguments"
	if ${CQL} --test --cg "$O/cg_test_objc.out" --in "$T/cg_test.sql" --rt objc 2>"$O/c_include_needed.err"; then
		echo c_include is required for --rt objc
		failed
	fi

	on_diff_exit c_include_needed.err

	if ! grep "Generated from test/cg_test_generated_from.sql:21" "$O/cg_test_generated_from.h" >/dev/null; then
		echo Generated from text did not appear in the header output.
		failed
	fi
	if ! grep "Generated from test/cg_test_generated_from.sql:21" "$O/cg_test_generated_from.c" >/dev/null; then
		echo Generated from text did not appear in the implementation output.
		failed
	fi

	echo 'running parser disallows columns in FETCH FROM CALL test'
	if ${CQL} --in "$T/parse_test_fetch_from_call_columns.sql" 2>"$O/parse_test_fetch_from_call_columns.err"; then
		echo 'failed to disallow cursor columns in FETCH FROM CALL'
		failed
	fi

	on_diff_exit parse_test_fetch_from_call_columns.err

	echo 'running parser disallows cql_inferred_notnull test'
	if ${CQL} --in "$T/parse_test_cql_inferred_notnull.sql" 2>"$O/parse_test_cql_inferred_notnull.err"; then
		echo 'failed to disallow cql_inferred_notnull'
		failed
	fi

	on_diff_exit parse_test_cql_inferred_notnull.err
}

json_validate() {
	sql_file=$1
	echo "checking for valid JSON formatting of ${sql_file} (test mode disabled)"
	if ! ${CQL} --cg "$O/__temp.out" --in "${sql_file}" --rt json_schema 2>"$O/cg_test_json_schema.err"; then
		cat "$O/cg_test_json_schema.err"
		echo "non-test JSON output failed for ${sql_file}"
		failed
	fi

	echo checking for well formed JSON using python
	if ! common/json_check.py <"$O/__temp.out" >/dev/null; then
		echo "json is badly formed for ${sql_file} -- see $O/__temp.out"
		failed
	fi

	echo checking for CQL JSON grammar conformance
	if ! out/json_test <"$O/__temp.out" >"$O/json_errors.txt"; then
		echo "json did not pass grammar check for ${sql_file} (see $O/__temp.out)"
		cat "$O/json_errors.txt"
		failed
	fi
}

json_schema_test() {
	echo '--------------------------------- STAGE 11 -- JSON SCHEMA TEST'
	echo running json schema test
	if ! ${CQL} --test --cg "$O/cg_test_json_schema.out" --in "$T/cg_test_json_schema.sql" --rt json_schema 2>"$O/cg_test_json_schema.err"; then
		echo "ERROR:"
		cat "$O/cg_test_json_schema.err"
		failed
	fi

	echo validating json output
	cql_verify "$T/cg_test_json_schema.sql" "$O/cg_test_json_schema.out"

	json_validate "$T/cg_test_json_schema.sql"

	echo running json codegen test for an empty file
	echo "" >"$O/__temp"
	json_validate "$O/__temp"

	echo validating json codegen
	echo "  computing diffs (empty if none)"
	on_diff_exit cg_test_json_schema.out
}

test_helpers_test() {
	echo '--------------------------------- STAGE 12 -- TEST HELPERS TEST'
	echo running test builders test
	cc -DCQL_TEST -E -x c "$T/cg_test_test_helpers.sql" >"$O/__temp"
	if ! ${CQL} --test --cg "$O/cg_test_test_helpers.out" --in "$O/__temp" --rt test_helpers 2>"$O/cg_test_test_helpers.err"; then
		echo "ERROR:"
		cat "$O/cg_test_test_helpers.err"
		failed
	fi

	echo validating test helpers output
	cql_verify "$T/cg_test_test_helpers.sql" "$O/cg_test_test_helpers.out"

	echo validating test helpers cql codegen
	echo "  computing diffs (empty if none)"
	on_diff_exit cg_test_test_helpers.out

	echo running semantic analysis on test helpers output
	if ! ${CQL} --sem --ast --in "$O/cg_test_test_helpers.out" >/dev/null 2>"$O/cg_test_test_helpers.err"; then
		echo "CQL semantic analysis returned unexpected error code"
		cat "$O/cg_test_test_helpers.err"
		failed
	fi

	echo build test helpers c codegen
	if ! ${CQL} --test --dev --cg "$O/test_helpers.h" "$O/test_helpers.c" --in "$O/cg_test_test_helpers.out" 2>"$O/cg_test_test_helpers.err"; then
		echo "ERROR:"
		cat "$O/cg_test_test_helpers.err"
		failed
	fi

	echo compile test helpers c code
	if ! do_make test_helpers_test; then
		echo build failed
		failed
	fi

	echo run test helpers in c
	if ! "./$O/test_helpers_test" >/dev/null 2>"$O/cg_test_test_helpers.err"; then
		echo "$O/test_helpers_test returned a failure code"
		cat "$O/cg_test_test_helpers.err"
		failed
	fi
}

run_test() {
	echo '--------------------------------- STAGE 13 -- RUN CODE TEST'

	if ! ${CQL} --nolines --cg "$O/run_test.h" "$O/run_test.c" --in "$T/run_test.sql" --global_proc cql_startup --rt c; then
		echo codegen failed.
		failed
	fi

	if ! (
		echo "  compiling code"
		do_make run_test
	); then
		echo build failed
		failed
	fi

	if ! (
		echo "  executing tests"
		"./$O/run_test"
	); then
		echo tests failed
		failed
	fi

	if ! ${CQL} --compress --cg "$O/run_test_compressed.h" "$O/run_test_compressed.c" --in "$T/run_test.sql" --global_proc cql_startup --rt c; then
		echo compressed codegen failed.
		failed
	fi

	if ! (
		echo "  compiling code (compressed version)"
		do_make run_test_compressed
	); then
		echo build failed
		failed
	fi

	if ! (
		echo "  executing tests (compressed version)"
		"./$O/run_test_compressed"
	); then
		echo tests failed
		failed
	fi
}

upgrade_test() {
	echo '--------------------------------- STAGE 14 -- SCHEMA UPGRADE TEST'
	if ! upgrade/upgrade_test.sh "${TEST_COVERAGE_ARGS}"; then
		failed
	fi
}

query_plan_test() {
	echo '--------------------------------- STAGE 15 -- TEST QUERY PLAN'

	echo C preprocessing
	cc -DCQL_TEST -E -x c "$T/cg_test_query_plan.sql" >"$O/cg_test_query_plan2.sql"

	echo semantic analysis
	if ! ${CQL} --sem --ast --dev --in "$O/cg_test_query_plan2.sql" >"$O/__temp" 2>"$O/cg_test_query_plan.err"; then
		echo "CQL semantic analysis returned unexpected error code"
		cat "$O/cg_test_query_plan.err"
		failed
	fi

	echo codegen query plan
	if ! ${CQL} --test --dev --cg "$O/cg_test_query_plan.out" --in "$O/cg_test_query_plan2.sql" --rt query_plan 2>"$O/cg_test_query_plan.err"; then
		echo "ERROR:"
		cat "$O/cg_test_query_plan.err"
		failed
	fi

	echo semantic analysis
	if ! ${CQL} --sem --ast --dev --test --in "$O/cg_test_query_plan.out" >"$O/__temp" 2>"$O/cg_test_query_plan.err"; then
		echo "CQL semantic analysis returned unexpected error code"
		cat "$O/cg_test_query_plan.err"
		failed
	fi

	echo validating test
	cql_verify "$T/cg_test_query_plan.sql" "$O/cg_test_query_plan.out"

	echo validating query plan codegen
	echo "  computing diffs (empty if none)"
	on_diff_exit cg_test_query_plan.out

	echo build query plan c code
	if ! ${CQL} --test --dev --cg "$O/query_plan.h" "$O/query_plan.c" --in "$O/cg_test_query_plan.out" 2>"$O/query_plan_print.err"; then
		echo "ERROR:"
		cat "$O/query_plan_print.err"
		failed
	fi

	echo compile query plan code
	if ! do_make query_plan_test; then
		echo build failed
		failed
	fi

	echo run query plan in c
	if ! "./$O/query_plan_test" >"$O/cg_test_query_plan_view.out" 2>"$O/cg_test_query_plan_view.err"; then
		echo "$O/query_plan_test returned a failure code"
		cat "$O/cg_test_query_plan_view.out"
		cat "$O/cg_test_query_plan_view.err"
		failed
	fi

	echo validate json format of query plan report
	if ! common/json_check.py <"$O/cg_test_query_plan_view.out" >"$O/cg_test_query_plan_js.out" 2>"$O/cg_test_query_plan_js.err"; then
		echo "$O/cg_test_query_plan_view.out has invalid json format"
		cat "$O/cg_test_query_plan_js.err"
		failed
	fi

	echo codegen empty query plan
	if ! ${CQL} --test --dev --cg "$O/cg_test_query_plan_empty.out" --in "$T/cg_test_query_plan_empty.sql" --rt query_plan 2>"$O/cg_test_query_plan_empty.err"; then
		echo "ERROR:"
		cat "$O/cg_test_query_plan_empty.err"
		failed
	fi

	echo semantic analysis emtpy query plan
	if ! ${CQL} --sem --ast --dev --test --in "$O/cg_test_query_plan_empty.out" >"$O/__temp" 2>"$O/cg_test_query_plan_empty.err"; then
		echo "CQL semantic analysis returned unexpected error code"
		cat "$O/cg_test_query_plan_empty.err"
		failed
	fi

	echo validating query plan codegen empty query plan
	echo "  computing diffs (empty if none)"
	on_diff_exit cg_test_query_plan_empty.out

	echo build empty query plan c code
	if ! ${CQL} --test --dev --cg "$O/query_plan.h" "$O/query_plan.c" --in "$O/cg_test_query_plan_empty.out" 2>"$O/query_plan_print.err"; then
		echo "ERROR:"
		cat "$O/query_plan_print.err"
		failed
	fi

	echo compile empty query plan code
	rm $O/query_plan.o # Make doesn't do a clean build automatically for some reason...
	if ! do_make query_plan_test; then
		echo build failed
		failed
	fi

	echo run query plan in c
	if ! "./$O/query_plan_test" >"$O/cg_test_query_plan_view.out" 2>"$O/cg_test_query_plan_view.err"; then
		echo "$O/query_plan_test returned a failure code"
		cat "$O/cg_test_query_plan_view.out"
		cat "$O/cg_test_query_plan_view.err"
		failed
	fi

	echo validate json format of empty query plan report
	if ! common/json_check.py <"$O/cg_test_query_plan_view.out" >"$O/cg_test_query_plan_js.out" 2>"$O/cg_test_query_plan_js.err"; then
		echo "$O/cg_test_query_plan_view.out has invalid json format"
		cat "$O/cg_test_query_plan_js.err"
		failed
	fi

	echo "validating query plan empty result (this is stable)"
	echo "  computing diffs (empty if none)"
	on_diff_exit cg_test_query_plan_view.out
}

line_number_test() {
	echo '--------------------------------- STAGE 16 -- TEST LINE DIRECTIVES'

	echo "Checking for presence any # line directives"
	if ! ${CQL} --cg "$O/cg_test_generated_from.h" "$O/cg_test_generated_from.c" "$O/cg_test_generated_from.out" --in "$T/cg_test_generated_from.sql" 2>"$O/cg_test_generated_from.err"; then
		cat "$O/cg_test_generated_from.err"
		echo 'ERROR: Compilation failed.'
		failed
	fi

	if ! grep "^#line " "$O/cg_test_generated_from.c" >/dev/null; then
		echo "# line directives not emitted. See" "$O/cg_test_generated_from.c"
		failed
	fi

	if ! grep "/\* A comment \*/" "$O/cg_test_generated_from.c" >/dev/null; then
		echo Code generated by @echo did not appear in the implementation output.
		failed
	fi

	echo 'Testing the suppression of # line directives'
	if ! ${CQL} --nolines --cg "$O/cg_test_generated_from.h" "$O/cg_test_generated_from.c" "$O/cg_test_generated_from.out" --in "$T/cg_test_generated_from.sql" 2>"$O/cg_test_generated_from.err"; then
		cat "$O/cg_test_generated_from.err"
		echo 'ERROR: Compilation failed.'
		failed
	fi

	if grep "^#line " "$O/cg_test_generated_from.c" >/dev/null; then
		echo "# line directives were not correctly suppresed. See" "$O/cg_test_generated_from.c" 2>"$O/cg_test_generated_from.err"
		failed
	fi

	if ! ${CQL} --in "$T/linetest.sql" --cg "$O/linetest.h" "$O/linetest.c" 2>"$O/linetest.err"; then
		cat "$O/linetest.err"
		echo 'ERROR: Compilation failed.'
		failed
	fi

	if ! $O/cql-linetest "$T/linetest.expected" "$O/linetest.c"; then
		echo "Line number verification failed"
		failed
	fi
}

stats_test() {
	echo '--------------------------------- STAGE 17 -- STATS OUTPUT TEST'
	echo running status test
	if ! ${CQL} --cg "$O/stats.csv" --in "$T/stats_test.sql" --rt stats 2>"$O/stats_test.err"; then
		echo "ERROR:"
		cat "$O/stats_test.err"
		failed
	fi

	echo "  computing diffs (empty if none)"
	on_diff_exit stats.csv
}

amalgam_test() {
	echo '--------------------------------- STAGE 18 -- TEST AMALGAM'

	if ! ("./$O/amalgam_test" "$T/cql_amalgam_test_success.sql" "$T/cql_amalgam_test_semantic_error.sql" "$T/cql_amalgam_test_syntax_error.sql" >"$O/cql_amalgam_test.out" 2>"$O/cql_amalgam_test.err"); then
		cat "$O/cql_amalgam_test.err"
		echo CQL amalgam tests failed
		failed
	fi

	on_diff_exit cql_amalgam_test.out
	on_diff_exit cql_amalgam_test.err
}

# add other stages before this one

unit_tests() {
	if ! (${CQL} --run_unit_tests); then
		echo CQL unit tests failed
		failed
	fi
}

code_gen_lua_test() {
	echo '--------------------------------- STAGE 19 -- LUA CODE GEN TEST'
	echo running codegen test
	if ! ${CQL} --dev --test --cg "$O/cg_test_lua.lua" --in "$T/cg_test_lua.sql" --global_proc cql_startup --rt lua 2>"$O/cg_test_lua.err"; then
		echo "ERROR:"
		cat "$O/cg_test_lua.err"
		failed
	fi

	echo validating codegen
	cql_verify "$T/cg_test_lua.sql" "$O/cg_test_lua.lua"

	#  echo testing for successful compilation of generated lua
	#  if ! lua out/cg_test_lua.lua
	#  then
	#    echo "ERROR: failed to compile the C code from the code gen test"
	#    failed
	#  fi

	echo testing for successful compilation of lua run test
	echo " cannot run this by default because of runtime requirements"

	if ! lua_demo/prepare_run_test.sh; then
		failed
	fi

	echo "  computing diffs (empty if none)"
	on_diff_exit cg_test_lua.lua
	on_diff_exit cg_test_lua.err
}

dot_test() {
	echo '--------------------------------- STAGE 20 -- .DOT OUTPUT TEST'
	echo running "$T/dottest.sql"
	if ! ${CQL} --dot --hide_builtins --in "$T/dottest.sql" >"$O/dottest.out"; then
		echo DOT syntax test failed
		failed
	fi

	echo "  computing diffs (empty if none)"
	on_diff_exit dottest.out
}

GENERATED_TAG=generated
AT_GENERATED_TAG="@$GENERATED_TAG"

signatures_test() {
	echo checking for signatures in reference files
	# shellcheck disable=SC2086
	if grep "$AT_GENERATED_TAG SignedSource" $T/*.ref; then
		echo "signatures found in reference files, this is never valid."
		echo "change the test logic so that it validates the presence of the signature which then strips it."
		echo "it's likely that one of those validations is missing which caused a signature to be copied into a .ref file."
		failed
	fi
}

if ! building; then
	cat "$O/build.out" "$O/build.err"
	echo "build failed."
fi

# each of these will exit if anything goes wrong
basic_test
unit_tests
macro_test
semantic_test
code_gen_c_test
code_gen_objc_test
assorted_errors_test
schema_migration_test
misc_cases
json_schema_test
test_helpers_test
run_test
upgrade_test
query_plan_test
line_number_test
stats_test
amalgam_test
signatures_test
code_gen_lua_test
dot_test
extra_tests

make_clean_msg
echo '--------------------------------- DONE SUCCESS'
exit 0
