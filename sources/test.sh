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
    MAKE_COVERAGE_ARGS="COVERAGE=1"
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

MAKE_ARGS="${MAKE_COVERAGE_ARGS}"

# Helper function for tests expected to succeed
run_test_expect_success() {
  # Generate output file names automatically if not provided
  if [ -z "$TEST_OUT" ]; then
    TEST_OUT="$O/${TEST_NAME}.out"
  fi
  
  if [ -z "$TEST_ERR" ]; then
    TEST_ERR="$O/${TEST_NAME}.err"
  fi
  
  if [ -z "$TEST_ERROR_MSG" ]; then
    TEST_ERROR_MSG="Test $TEST_NAME failed"
  fi

  echo "$TEST_DESC"
  
  if ! eval "$TEST_CMD" >"$TEST_OUT" 2>"$TEST_ERR"; then
    echo "ERROR: $TEST_ERROR_MSG"
    echo "Command: $TEST_CMD"
    echo "Output: $TEST_OUT"
    echo "Errors: $TEST_ERR"
    cat "$TEST_ERR"
    failed
  fi
  
  # Reset variables after use
  TEST_NAME=""
  TEST_DESC=""
  TEST_CMD=""
  TEST_OUT=""
  TEST_ERR=""
  TEST_ERROR_MSG=""
}

# Helper function for tests expected to fail
run_test_expect_fail() {
  # Generate output file names automatically if not provided
  if [ -z "$TEST_OUT" ]; then
    TEST_OUT="$O/${TEST_NAME}.out"
  fi
  
  if [ -z "$TEST_ERR" ]; then
    TEST_ERR="$O/${TEST_NAME}.err"
  fi
  
  if [ -z "$TEST_ERROR_MSG" ]; then
    TEST_ERROR_MSG="Test $TEST_NAME failed"
  fi

  echo "$TEST_DESC"
  
  if eval "$TEST_CMD" >"$TEST_OUT" 2>"$TEST_ERR"; then
    echo "ERROR: Command succeeded but was expected to fail"
    echo "Command: $TEST_CMD"
    echo "Output: $TEST_OUT"
    echo "Errors: $TEST_ERR"
    failed
  fi
  
  # Reset variables after use
  TEST_NAME=""
  TEST_DESC=""
  TEST_CMD=""
  TEST_OUT=""
  TEST_ERR=""
}

do_make() {
  # echo gives us a free whitespace trim avoiding empty args with ""
  make $(echo "$@" "${MAKE_ARGS}")
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
  grep '"CQL[0-9][0-9][0-9][0-9]:' sem.c rewrite.c ast.c printf.c | sed -e 's/[.]c://' -e 's/:.*//' -e "s/.*CQL/CQL/" | sort -u >"$O/errs_used.txt"
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
  TEST_NAME="build"
  TEST_DESC="Building new CQL"
  TEST_CMD="do_make clean >/dev/null 2>/dev/null && do_make all"
  TEST_OUT="$O/build.out"
  TEST_ERR="$O/build.err"
  TEST_ERROR_MSG="Build CQL failed"
  run_test_expect_success

  if grep "^State.*conflicts:" "$O/cql.y.output" >"$O/build.err"; then
    echo "conflicts found in grammar, these must be fixed" >>"$O/build.err"
    echo "look at the conflicting states in" "$O/cql.y.output" "to debug" >>"$O/build.err"
    cat "$O/build.err"
    failed
  fi

  TEST_NAME="build_amalgam"
  TEST_DESC="Building CQL amalgam"
  TEST_CMD="do_make amalgam"
  TEST_OUT="$O/build.out"
  TEST_ERR="$O/build.err"
  TEST_ERROR_MSG="Build CQL amalgam failed"
  run_test_expect_success

  TEST_NAME="build_amalgam_test"
  TEST_DESC="Building CQL amalgam test"
  TEST_CMD="do_make amalgam_test"
  TEST_OUT="$O/build.out"
  TEST_ERR="$O/build.err"
  TEST_ERROR_MSG="Build CQL amalgam test failed"
  run_test_expect_success

  TEST_NAME="build_cql_verify"
  TEST_DESC="Building CQL-verify"
  TEST_CMD="do_make cql-verify"
  TEST_OUT="/dev/null"
  TEST_ERR="$O/build.err"
  TEST_ERROR_MSG="Build CQL-verify failed"
  run_test_expect_success

  TEST_NAME="build_cql_linetest"
  TEST_DESC="Building CQL-linetest"
  TEST_CMD="do_make cql-linetest"
  TEST_OUT="/dev/null"
  TEST_ERR="$O/build.err"
  TEST_ERROR_MSG="Build CQL-linetest failed"
  run_test_expect_success

  TEST_NAME="build_json_test"
  TEST_DESC="Building JSON-test"
  TEST_CMD="do_make json-test"
  TEST_OUT="/dev/null"
  TEST_ERR="$O/build.err"
  TEST_ERROR_MSG="Build JSON-test failed"
  run_test_expect_success

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
  TEST_NAME="test"
  TEST_DESC="Running \"$T/test.sql\""
  TEST_CMD="${CQL} --echo --dev --include_paths \"test\" \"test2\" <\"$T/test.sql\""
  TEST_OUT="$O/test.out"
  TEST_ERROR_MSG="Basic parsing test failed"
  run_test_expect_success

  TEST_NAME="test_out2"
  TEST_DESC="Testing echo output parses correctly"
  TEST_CMD="${CQL} --echo --dev --in \"$O/test.out\""
  TEST_OUT="$O/test.out2"
  TEST_ERROR_MSG="Echo output does not parse again correctly"
  run_test_expect_success

  TEST_NAME="test_ast"
  TEST_DESC="Creating basic AST for test.sql"
  TEST_CMD="${CQL} --ast_no_echo --dev --include_paths test2 --in \"$T/test.sql\""
  TEST_OUT="$O/test_ast.out"
  TEST_ERROR_MSG="Basic AST test failed"
  run_test_expect_success

  echo "  computing diffs (empty if none)"
  on_diff_exit test.out
  on_diff_exit test_ast.out

  echo "  computing diffs second parsing (empty if none)"
  mv "$O/test.out2" "$O/test.out"
  on_diff_exit test.out

  echo running "$T/test.sql" "with CRLF line endings"
  sed -e "s/$/\\r/" <$T/test.sql >$O/test.sql
  TEST_NAME="test_crlf"
  TEST_DESC="Testing CRLF line endings"
  TEST_CMD="${CQL} --include_paths test test2 --echo --dev --in \"$O/test.sql\""
  TEST_OUT="$O/test.out2"
  TEST_ERROR_MSG="Echo CRLF version does not parse correctly"
  run_test_expect_success

  echo "  computing diffs CRLF parsing (empty if none)"
  mv "$O/test.out2" "$O/test.out"
  on_diff_exit test.out

  TEST_NAME="test_exp"
  TEST_DESC="Running \"$T/test.sql\" with macro expansion"
  TEST_CMD="${CQL} --echo --dev --include_paths test2 --in \"$T/test.sql\" --exp"
  TEST_ERROR_MSG="Basic parsing with expansion test failed"
  run_test_expect_success
  echo "  computing diffs (empty if none)"
  on_diff_exit test_exp.out

  TEST_NAME="include_not_found"
  TEST_DESC="Testing include file not found"
  TEST_CMD="${CQL} --in \"$T/test_include_file_not_found.sql\""
  TEST_ERR="$O/include_not_found.err"
  TEST_OUT="/dev/null"
  run_test_expect_fail

  echo "  computing diffs (empty if none)"
  on_diff_exit include_not_found.err

  TEST_NAME="include_nesting"
  TEST_DESC="Testing include files nested too deeply"
  TEST_CMD="${CQL} --in \"$T/include_files_infinite_nesting.sql\""
  TEST_ERR="$O/include_nesting.err"
  TEST_OUT="/dev/null"
  run_test_expect_fail

  echo "  computing diffs (empty if none)"
  on_diff_exit include_nesting.err

  TEST_NAME="test_ifdef"
  TEST_DESC="Testing ifdef"
  TEST_CMD="${CQL} --in \"$T/test_ifdef.sql\" --echo --defines foo"
  TEST_OUT="$O/test_ifdef.out"
  TEST_ERR="$O/test_ifdef.err"
  TEST_ERROR_MSG="Basic parsing with ifdefs failed"
  run_test_expect_success

  echo "  computing diffs (empty if none)"
  on_diff_exit test_ifdef.out

  TEST_NAME="include_empty"
  TEST_DESC="Testing empty include file"
  TEST_CMD="${CQL} --in \"$T/include_empty.sql\" --echo"
  TEST_OUT="$O/include_empty.out"
  TEST_ERR="$O/include_empty.err"
  TEST_ERROR_MSG="Empty include file failed"
  run_test_expect_success

  echo "  computing diffs (empty if none)"
  on_diff_exit include_empty.out
}

macro_test() {
  echo '--------------------------------- STAGE 3 -- MACRO TEST'
  TEST_NAME="macro_test"
  TEST_DESC="Running macro expansion test"
  TEST_CMD="${CQL} --test --exp --ast --hide_builtins --in \"$T/macro_test.sql\""
  TEST_OUT="$O/macro_test.out"
  TEST_ERR="$O/macro_test.err"
  TEST_ERROR_MSG="CQL macro test returned unexpected error code"
  run_test_expect_success

  echo validating output trees
  cql_verify "$T/macro_test.sql" "$O/macro_test.out"

  echo "  computing diffs (empty if none)"
  on_diff_exit macro_test.out

  TEST_NAME="macro_exp_errors"
  TEST_DESC="Running macro expansion error cases"
  TEST_CMD="${CQL} --exp --echo --in \"$T/macro_exp_errors.sql\""
  TEST_OUT="$O/macro_exp_errors.out"
  TEST_ERR="$O/macro_test.err.out"
  run_test_expect_fail

  echo "  computing diffs (empty if none)"
  on_diff_exit macro_test.err.out

  TEST_NAME="macro_test_dup"
  TEST_DESC="Running macro expansion duplicate name"
  TEST_CMD="${CQL} --exp --in \"$T/macro_test_dup_arg.sql\""
  TEST_OUT="$O/macro_exp_errors.out"
  TEST_ERR="$O/macro_test_dup.err.out"
  run_test_expect_fail

  echo "  computing diffs (empty if none)"
  on_diff_exit macro_test_dup.err.out
}

semantic_test() {
  echo '--------------------------------- STAGE 4 -- SEMANTIC ANALYSIS TEST'

  TEST_NAME="sem_test"
  TEST_DESC="Running semantic analysis test"
  TEST_CMD="sem_check --sem --ast --hide_builtins --dev --in \"$T/sem_test.sql\""
  run_test_expect_success

  echo validating output trees
  cql_verify "$T/sem_test.sql" "$O/sem_test.out"

  TEST_NAME="sem_test_dev"
  TEST_DESC="Running dev semantic analysis test"
  TEST_CMD="sem_check --sem --ast --in \"$T/sem_test_dev.sql\""
  run_test_expect_success

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
  TEST_NAME="cg_test_c"
  TEST_DESC="Running codegen test"
  TEST_CMD="${CQL} --dev --test --cg \"$O/cg_test_c.h\" \"$O/cg_test_c.c\" \"$O/cg_test_exports.out\" --in \"$T/cg_test.sql\" --global_proc cql_startup --generate_exports"
  TEST_ERR="$O/cg_test_c.err"
  TEST_ERROR_MSG="Codegen test failed"
  run_test_expect_success

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

assorted_errors_test() {
  echo '--------------------------------- STAGE 6 -- FAST FAIL CASES'
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

  if ${CQL} --cg "$O/__temp" /xx/yy/zz --in "$T/semantic_error.sql" 2>"$O/sem_abort.err"; then
    echo "simple semantic error to abort output -- failed"
    failed
  fi

  on_diff_exit sem_abort.err

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

  # wrong number of args specified in --cg (for lua)
  TEST_NAME="cg_1_2"
  TEST_DESC="Testing wrong number of args specified in --cg (for lua)"
  TEST_CMD="${CQL} --dev --cg \"$O/__temp\" \"$O/__temp2\" --in \"$T/cg_test.sql\" --rt lua"
  TEST_ERR="$O/cg_1_2.err"
  TEST_OUT="/dev/null"
  run_test_expect_fail

  # --generate_file_type did not specify a file type
  TEST_NAME="generate_file_type"
  TEST_DESC="Testing --generate_file_type with no file type specified"
  TEST_CMD="${CQL} --generate_file_type"
  TEST_ERR="$O/generate_file_type.err"
  TEST_OUT="/dev/null"
  run_test_expect_fail

  on_diff_exit generate_file_type.err

  # --generate_file_type specified invalid file type (should cause an error)
  TEST_NAME="generate_file_file"
  TEST_DESC="Testing --generate_file_type with invalid file type"
  TEST_CMD="${CQL} --generate_file_type foo"
  TEST_ERR="$O/generate_file_file.err"
  TEST_OUT="/dev/null"
  run_test_expect_fail

  on_diff_exit generate_file_file.err

  # --rt specified with no arg following it
  TEST_NAME="rt_arg_missing"
  TEST_DESC="Testing --rt with no argument"
  TEST_CMD="${CQL} --rt"
  TEST_ERR="$O/rt_arg_missing.err"
  TEST_OUT="/dev/null"
  run_test_expect_fail

  on_diff_exit rt_arg_missing.err

  # invalid result type specified with --rt, should force an error
  TEST_NAME="rt_arg_bogus"
  TEST_DESC="Testing --rt with invalid result type"
  TEST_CMD="${CQL} --rt foo"
  TEST_ERR="$O/rt_arg_bogus.err"
  TEST_OUT="/dev/null"
  run_test_expect_fail

  on_diff_exit rt_arg_bogus.err

  # --cqlrt specified but no file name present, should force an error
  TEST_NAME="cqlrt_arg_missing"
  TEST_DESC="Testing --cqlrt with no file name"
  TEST_CMD="${CQL} --cqlrt"
  TEST_ERR="$O/cqlrt_arg_missing.err"
  TEST_OUT="/dev/null"
  run_test_expect_fail

  on_diff_exit cqlrt_arg_missing.err

  # --global_proc has no proc name
  TEST_NAME="global_proc_missing"
  TEST_DESC="Testing --global_proc with no procedure name"
  TEST_CMD="${CQL} --global_proc"
  TEST_ERR="$O/global_proc_missing.err"
  TEST_OUT="/dev/null"
  run_test_expect_fail

  on_diff_exit global_proc_missing.err

  # --in arg missing
  TEST_NAME="in_arg_missing"
  TEST_DESC="Testing --in with no file name"
  TEST_CMD="${CQL} --in"
  TEST_ERR="$O/in_arg_missing.err"
  TEST_OUT="/dev/null"
  run_test_expect_fail

  on_diff_exit in_arg_missing.err

  # no c_include_namespace arg
  TEST_NAME="c_include_namespace_missing"
  TEST_DESC="Testing --c_include_namespace with no namespace"
  TEST_CMD="${CQL} --c_include_namespace"
  TEST_ERR="$O/c_include_namespace_missing.err"
  TEST_OUT="/dev/null"
  run_test_expect_fail

  on_diff_exit c_include_namespace_missing.err
}

schema_migration_test() {
  echo '--------------------------------- STAGE 7 -- SCHEMA MIGRATION TESTS'
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
  echo '--------------------------------- STAGE 8 -- MISC CASES'
  TEST_NAME="usage"
  TEST_DESC="Running usage test"
  TEST_CMD="${CQL}"
  TEST_OUT="$O/usage.out"
  TEST_ERR="$O/usage.err"
  TEST_ERROR_MSG="Usage test failed"
  run_test_expect_success
  on_diff_exit usage.out

  TEST_NAME="simple_error"
  TEST_DESC="Running simple error test"
  TEST_CMD="${CQL} --in \"$T/error.sql\""
  TEST_OUT="$O/error.out"
  TEST_ERR="$O/simple_error.err"
  run_test_expect_fail

  on_diff_exit simple_error.err

  TEST_NAME="prev_and_codegen_incompat"
  TEST_DESC="Running previous schema and codegen incompatible test"
  TEST_CMD="${CQL} --cg \"$O/__temp.h\" \"$O/__temp.c\" --in \"$T/cg_test_prev_invalid.sql\""
  TEST_ERR="$O/prev_and_codegen_incompat.err"
  TEST_OUT="/dev/null"
  run_test_expect_fail

  on_diff_exit prev_and_codegen_incompat.err

  TEST_NAME="bigquote"
  TEST_DESC="Running big quote test"
  TEST_CMD="${CQL} --cg \"$O/__temp.h\" \"$O/__temp.c\" --in \"$T/bigquote.sql\" --global_proc x"
  TEST_OUT="/dev/null"
  TEST_ERR="$O/bigquote.err"
  TEST_ERROR_MSG="Big quote test failed"
  run_test_expect_success

  on_diff_exit bigquote.err

  TEST_NAME="alt_cqlrt"
  TEST_DESC="Running alternate cqlrt.h test"
  TEST_CMD="${CQL} --dev --cg \"$O/__temp.h\" \"$O/__temp.c\" --in \"$T/cg_test.sql\" --global_proc x --cqlrt alternate_cqlrt.h"
  TEST_OUT="/dev/null"
  TEST_ERR="$O/alt_cqlrt.err"
  TEST_ERROR_MSG="Alternate cqlrt test failed"
  run_test_expect_success

  if ! grep alternate_cqlrt.h "$O/__temp.h" >/dev/null; then
    echo alternate cqlrt did not appear in the output header
    failed
  fi

  on_diff_exit alt_cqlrt.err

  TEST_NAME="gen_exports_args"
  TEST_DESC="Running too few -cg arguments with --generate_exports test"
  TEST_CMD="${CQL} --dev --cg \"$O/__temp.c\" \"$O/__temp.h\" --in \"$T/cg_test.sql\" --global_proc x --generate_exports"
  TEST_OUT="/dev/null"
  TEST_ERR="$O/gen_exports_args.err"
  run_test_expect_fail

  on_diff_exit gen_exports_args.err

  TEST_NAME="inc_invalid_regions"
  TEST_DESC="Running invalid include regions test"
  TEST_CMD="${CQL} --cg \"$O/cg_test_schema_partial_upgrade.out\" --in \"$T/cg_test_schema_upgrade.sql\" --global_proc test --rt schema_upgrade --include_regions bogus --exclude_regions shared"
  TEST_ERR="$O/inc_invalid_regions.err"
  TEST_OUT="/dev/null"
  run_test_expect_fail

  on_diff_exit inc_invalid_regions.err

  TEST_NAME="excl_invalid_regions"
  TEST_DESC="Running invalid exclude regions test"
  TEST_CMD="${CQL} --cg \"$O/cg_test_schema_partial_upgrade.out\" --in \"$T/cg_test_schema_upgrade.sql\" --global_proc test --rt schema_upgrade --include_regions extra --exclude_regions bogus"
  TEST_ERR="$O/excl_invalid_regions.err"
  TEST_OUT="/dev/null"
  run_test_expect_fail

  on_diff_exit excl_invalid_regions.err

  TEST_NAME="global_proc_needed"
  TEST_DESC="Running global proc is needed but not present test"
  TEST_CMD="${CQL} --cg \"$O/__temp.c\" \"$O/__temp.h\" --in \"$T/bigquote.sql\""
  TEST_ERR="$O/global_proc_needed.err"
  TEST_OUT="/dev/null"
  run_test_expect_fail

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

  on_diff_exit parse_test_cql_inferred_notnull.err
}

json_validate() {
  sql_file=$1
  TEST_NAME="json_validate_${sql_file##*/}"
  TEST_DESC="Checking for valid JSON formatting of ${sql_file} (test mode disabled)"
  TEST_CMD="${CQL} --cg \"$O/__temp.out\" --in \"${sql_file}\" --rt json_schema"
  TEST_OUT="/dev/null"
  TEST_ERR="$O/cg_test_json_schema.err"
  TEST_ERROR_MSG="Non-test JSON output failed for ${sql_file}"
  run_test_expect_success
  
  echo "Checking for well formed JSON using python"
  if ! common/json_check.py <"$O/__temp.out" >/dev/null; then
    echo "JSON is badly formed for ${sql_file} -- see $O/__temp.out"
    failed
  fi
  
  echo "Checking for CQL JSON grammar conformance"
  if ! out/json_test <"$O/__temp.out" >"$O/json_errors.txt"; then
    echo "JSON did not pass grammar check for ${sql_file} (see $O/__temp.out)"
    cat "$O/json_errors.txt"
    failed
  fi
}

json_schema_test() {
  echo '--------------------------------- STAGE 9 -- JSON SCHEMA TEST'
  TEST_NAME="json_schema_test"
  TEST_DESC="Running JSON schema test"
  TEST_CMD="${CQL} --test --cg \"$O/cg_test_json_schema.out\" --in \"$T/cg_test_json_schema.sql\" --rt json_schema"
  TEST_OUT="/dev/null"
  TEST_ERR="$O/cg_test_json_schema.err"
  TEST_ERROR_MSG="JSON schema test failed"
  run_test_expect_success

  echo "Validating JSON output"
  cql_verify "$T/cg_test_json_schema.sql" "$O/cg_test_json_schema.out"

  json_validate "$T/cg_test_json_schema.sql"

  echo "Running JSON codegen test for an empty file"
  echo "" >"$O/__temp"
  json_validate "$O/__temp"

  echo "Validating JSON codegen"
  echo "  computing diffs (empty if none)"
  on_diff_exit cg_test_json_schema.out
}

test_helpers_test() {
  echo '--------------------------------- STAGE 10 -- TEST HELPERS TEST'
  TEST_NAME="cg_test_test_helpers"
  TEST_DESC="Running test builders test"
  TEST_CMD="${CQL} --test --cg \"$O/cg_test_test_helpers.out\" --in \"$T/cg_test_test_helpers.sql\" --rt test_helpers"
  TEST_OUT="/dev/null"
  TEST_ERR="$O/cg_test_test_helpers.err"
  TEST_ERROR_MSG="Test builders test failed"
  run_test_expect_success

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
  echo '--------------------------------- STAGE 11 -- RUN CODE TEST'

  if ! ${CQL} --nolines --cg "$O/run_test.h" "$O/run_test.c" --in "$T/run_test.sql" --global_proc cql_startup --rt c; then
    echo codegen failed.
    failed
  fi

  if ! ${CQL} --defines modern_test --nolines --cg "$O/run_test_modern.h" "$O/run_test_modern.c" --in "$T/run_test.sql" --global_proc cql_startup --rt c; then
    echo codegen failed.
    failed
  fi

  if ! (
    echo "  compiling code"
    do_make run_test
    MAKE_ARGS_SAVED=${MAKE_ARGS}
    # echo gives us a free whitespace trim avoiding empty args with ""
    MAKE_ARGS=$(echo SQLITE_PATH=./sqlite ${MAKE_ARGS})
    do_make sqlite
    do_make run_test_modern
    MAKE_ARGS=${MAKE_ARGS_SAVED}
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

  if ! (
    echo "  executing tests with modern SQLite"
    "./$O/run_test_modern"
  ); then
    echo modern run tests failed
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
  echo '--------------------------------- STAGE 12 -- SCHEMA UPGRADE TEST'
  if ! upgrade/upgrade_test.sh "${TEST_COVERAGE_ARGS}"; then
    failed
  fi
}

query_plan_test() {
  echo '--------------------------------- STAGE 13 -- TEST QUERY PLAN'

  echo semantic analysis
  if ! ${CQL} --sem --ast --dev --in "$T/cg_test_query_plan.sql" >"$O/__temp" 2>"$O/cg_test_query_plan.err"; then
    echo "CQL semantic analysis returned unexpected error code"
    cat "$O/cg_test_query_plan.err"
    failed
  fi

  echo codegen query plan
  if ! ${CQL} --test --dev --cg "$O/cg_test_query_plan.out" --in "$T/cg_test_query_plan.sql" --rt query_plan 2>"$O/cg_test_query_plan.err"; then
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
  echo '--------------------------------- STAGE 14 -- TEST LINE DIRECTIVES'

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
  echo '--------------------------------- STAGE 15 -- STATS OUTPUT TEST'
  TEST_NAME="stats_test"
  TEST_DESC="Running stats output test"
  TEST_CMD="${CQL} --cg \"$O/stats.csv\" --in \"$T/stats_test.sql\" --rt stats"
  TEST_OUT="/dev/null"
  TEST_ERR="$O/stats_test.err"
  TEST_ERROR_MSG="Stats output test failed"
  run_test_expect_success

  echo "  computing diffs (empty if none)"
  on_diff_exit stats.csv
}

amalgam_test() {
  echo '--------------------------------- STAGE 16 -- TEST AMALGAM'

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
  echo '--------------------------------- STAGE 17 -- LUA CODE GEN TEST'
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
  echo '--------------------------------- STAGE 18 -- .DOT OUTPUT TEST'
  echo running "$T/dottest.sql"
  if ! ${CQL} --dot --hide_builtins --in "$T/dottest.sql" >"$O/dottest.out"; then
    echo DOT syntax test failed
    failed
  fi

  echo "  computing diffs (empty if none)"
  on_diff_exit dottest.out
}

cqlrt_diag() {
  echo '--------------------------------- STAGE 19 -- COMPILING CQLRT WITH HIGH WARNINGS'
  echo Building "$O/cqlrt_diag.o -- this is cqlrt with lots of warnings enabled"
  if ! do_make $O/cqlrt_diag.o; then
    echo Warnings discovered in cqlrt
    failed
  fi
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
cqlrt_diag

echo '---------------------------------'
make_clean_msg
echo '--------------------------------- DONE SUCCESS'
exit 0
