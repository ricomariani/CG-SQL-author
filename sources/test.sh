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
  TEST_OUT="$O/${TEST_NAME}.out"
  TEST_ERR="$O/${TEST_NAME}.err"

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
  TEST_OUT="$O/${TEST_NAME}.out"
  TEST_ERR="$O/${TEST_NAME}.err"

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

  TEST_NAME="check_for_statement"
  TEST_DESC="Checking for 'for(' anti-pattern"
  TEST_CMD="grep ' for(' ./*.c ./*.h"
  TEST_ERROR_MSG="anti pattern 'for(' found, use 'for ('"
  run_test_expect_fail

  TEST_NAME="check_if_statement"
  TEST_DESC="Checking for 'if(' anti-pattern"
  TEST_CMD="grep ' if(' ./*.c ./*.h"
  TEST_ERROR_MSG="anti pattern 'if(' found, use 'if ('"
  run_test_expect_fail

  TEST_NAME="check_while_statement"
  TEST_DESC="Checking for 'while(' anti-pattern"
  TEST_CMD="grep ' while(' ./*.c ./*.h"
  TEST_ERROR_MSG="anti pattern 'while(' found, use 'while ('"
  run_test_expect_fail

  TEST_NAME="check_switch_statement"
  TEST_DESC="Checking for 'switch(' anti-pattern"
  TEST_CMD="grep ' switch(' ./*.c ./*.h"
  TEST_ERROR_MSG="anti pattern 'switch(' found, use 'switch ('"
  run_test_expect_fail
}

building() {
  echo '--------------------------------- STAGE 1 -- make clean, then make'

  do_make clean

  TEST_NAME="build_all"
  TEST_DESC="Build directory"
  TEST_CMD="do_make all"
  run_test_expect_success

  TEST_NAME="check_conflicts"
  TEST_DESC="Checking for parser conflicts"
  TEST_CMD="grep '^State.*conflicts:' $O/cql.y.output"
  TEST_ERROR_MSG="conflicts found in grammar, these must be fixed. Look at the conflicting states in $O/cql.y.output to debug"
  run_test_expect_fail

  TEST_NAME="build_amalgam"
  TEST_DESC="Building CQL amalgam"
  TEST_CMD="do_make amalgam"
  run_test_expect_success

  TEST_NAME="build_amalgam_test"
  TEST_DESC="Building CQL amalgam test"
  TEST_CMD="do_make amalgam_test"
  run_test_expect_success

  TEST_NAME="build_cql_verify"
  TEST_DESC="Building CQL-verify"
  TEST_CMD="do_make cql-verify"
  run_test_expect_success

  TEST_NAME="build_cql_linetest"
  TEST_DESC="Building CQL-linetest"
  TEST_CMD="do_make cql-linetest"
  run_test_expect_success

  TEST_NAME="build_json_test"
  TEST_DESC="Building JSON-test"
  TEST_CMD="do_make json-test"
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
  TEST_DESC="Compiling basic parsing test \"$T/test.sql\""
  TEST_CMD="${CQL} --echo --dev --include_paths \"test\" \"test2\" <\"$T/test.sql\""
  run_test_expect_success

  TEST_NAME="test_out2"
  TEST_DESC="Testing echo output can be parsed correctly"
  TEST_CMD="${CQL} --echo --dev --in \"$O/test.out\""
  run_test_expect_success

  TEST_NAME="test_ast"
  TEST_DESC="Creating basic AST for test.sql"
  TEST_CMD="${CQL} --ast_no_echo --dev --include_paths test2 --in \"$T/test.sql\""
  run_test_expect_success

  echo "  computing diffs (empty if none)"
  on_diff_exit test.out
  on_diff_exit test_ast.out

  echo "  computing diffs second parsing (empty if none)"
  mv "$O/test_out2.out" "$O/test.out"
  on_diff_exit test.out

  echo running "$T/test.sql" "with CRLF line endings"
  sed -e "s/$/\\r/" <$T/test.sql >$O/test.sql
  TEST_NAME="test_crlf"
  TEST_DESC="Testing CRLF line endings for correct parsing"
  TEST_CMD="${CQL} --include_paths test test2 --echo --dev --in \"$O/test.sql\""
  run_test_expect_success

  echo "  computing diffs CRLF parsing (empty if none)"
  mv "$O/test_crlf.out" "$O/test.out"
  on_diff_exit test.out

  TEST_NAME="test_exp"
  TEST_DESC="Running \"$T/test.sql\" with macro expansion"
  TEST_CMD="${CQL} --echo --dev --include_paths test2 --in \"$T/test.sql\" --exp"
  run_test_expect_success

  echo "  computing diffs (empty if none)"
  on_diff_exit test_exp.out

  TEST_NAME="include_not_found"
  TEST_DESC="Testing include file not found"
  TEST_CMD="${CQL} --in \"$T/test_include_file_not_found.sql\""
  run_test_expect_fail

  echo "  computing diffs (empty if none)"
  on_diff_exit include_not_found.err

  TEST_NAME="include_nesting"
  TEST_DESC="Testing include files nested too deeply"
  TEST_CMD="${CQL} --in \"$T/include_files_infinite_nesting.sql\""
  run_test_expect_fail

  echo "  computing diffs (empty if none)"
  on_diff_exit include_nesting.err

  TEST_NAME="test_ifdef"
  TEST_DESC="Basic parsing with ifdefs"
  TEST_CMD="${CQL} --in \"$T/test_ifdef.sql\" --echo --defines foo"
  run_test_expect_success

  echo "  computing diffs (empty if none)"
  on_diff_exit test_ifdef.out

  TEST_NAME="include_empty"
  TEST_DESC="Testing empty include file"
  TEST_CMD="${CQL} --in \"$T/include_empty.sql\" --echo"
  run_test_expect_success

  echo "  computing diffs (empty if none)"
  on_diff_exit include_empty.out
}

macro_test() {
  echo '--------------------------------- STAGE 3 -- MACRO TEST'
  TEST_NAME="macro_test"
  TEST_DESC="Running macro expansion test"
  TEST_CMD="${CQL} --test --exp --ast --hide_builtins --in \"$T/macro_test.sql\""
  run_test_expect_success

  echo validating output trees
  cql_verify "$T/macro_test.sql" "$O/macro_test.out"

  echo "  computing diffs (empty if none)"
  on_diff_exit macro_test.out

  TEST_NAME="macro_exp_errors"
  TEST_DESC="Running macro expansion error cases"
  TEST_CMD="${CQL} --exp --echo --in \"$T/macro_exp_errors.sql\""
  run_test_expect_fail

  echo "  computing diffs (empty if none)"
  on_diff_exit macro_exp_errors.err

  TEST_NAME="macro_test_dup"
  TEST_DESC="Running macro expansion duplicate name"
  TEST_CMD="${CQL} --exp --in \"$T/macro_test_dup_arg.sql\""
  run_test_expect_fail

  echo "  computing diffs (empty if none)"
  on_diff_exit macro_test_dup.err
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
  run_test_expect_success

  echo validating codegen
  cql_verify "$T/cg_test.sql" "$O/cg_test_c.c"

  rm -f out/cg_test_c.o
  TEST_DESC="Testing for successful compilation of generated C"
  TEST_CMD="do_make out/cg_test_c.o"
  run_test_expect_success

  TEST_NAME="cg_test_c_globals_no_global_proc"
  TEST_DESC="Verifying globals codegen does not require a global proc"
  TEST_CMD="${CQL} --cg \"$O/cg_test_c_globals.h\" \"$O/cg_test_c_globals.c\" --in \"$T/cg_test_c_globals.sql\""
  run_test_expect_success

  TEST_NAME="cg_test_c_globals"
  TEST_DESC="Running codegen test for global variables group"
  TEST_CMD="${CQL} --test --cg \"$O/cg_test_c_globals.h\" \"$O/cg_test_c_globals.c\" --in \"$T/cg_test_c_globals.sql\""
  run_test_expect_success

  echo validating codegen for globals
  cql_verify "$T/cg_test_c_globals.sql" "$O/cg_test_c_globals.h"

  TEST_NAME="cg_test_c_type_getters"
  TEST_DESC="Running codegen test with type getters enabled"
  TEST_CMD="${CQL} --test --cg \"$O/cg_test_c_with_type_getters.h\" \"$O/cg_test_c_with_type_getters.c\" --in \"$T/cg_test_c_type_getters.sql\" --global_proc cql_startup"
  run_test_expect_success

  echo validating codegen
  cql_verify "$T/cg_test_c_type_getters.sql" "$O/cg_test_c_with_type_getters.h"

  rm -f out/cg_test_c_with_type_getters.o
  TEST_NAME="cg_test_c_with_type_getters_compile"
  TEST_DESC="Compiling generated C code from type getters codegen test"
  TEST_CMD="do_make $O/cg_test_c_with_type_getters.o"
  run_test_expect_success

  TEST_NAME="cg_test_c_with_namespace"
  TEST_DESC="Running codegen test with namespace enabled"
  TEST_CMD="${CQL} --dev --test --cg \"$O/cg_test_c_with_namespace.h\" \"$O/cg_test_c_with_namespace.c\" \"$O/cg_test_imports_with_namespace.ref\" --in \"$T/cg_test.sq\"l --global_proc cql_startup --c_include_namespace test_namespace --generate_exports"
  run_test_expect_success

  echo validating codegen
  cql_verify "$T/cg_test.sql" "$O/cg_test_c_with_namespace.c"

  TEST_NAME="cg_test_c_with_header"
  TEST_DESC="Running codegen test with c_include_path specified"
  TEST_CMD="${CQL} --dev --test --cg \"$O/cg_test_c_with_header.h\" \"$O/cg_test_c_with_header.c\" --in \"$T/cg_test.sql\" --global_proc cql_startup --c_include_path \"somewhere/something.h\""
  run_test_expect_success

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

  TEST_NAME="cg_compile_generated"
  TEST_DESC="Compiling generated C code from codegen test"
  TEST_CMD="do_make cg_test"
  TEST_ERROR_MSG="Generated C code compilation failed"
}

assorted_errors_test() {
  echo '--------------------------------- STAGE 6 -- FAST FAIL CASES'
  echo running various failure cases that cause no output

  TEST_NAME="badpath"
  TEST_DESC="Testing reading from non-existent file"
  TEST_CMD="${CQL} --in /xx/yy/zz"
  run_test_expect_fail

  on_diff_exit badpath.err

  TEST_NAME="unwriteable"
  TEST_DESC="Testing writing to unwriteable file"
  TEST_CMD="${CQL} --dev --cg /xx/yy/zz /xx/yy/zzz --in \"$T/cg_test.sql\" --global_proc xx"
  run_test_expect_fail

  on_diff_exit unwriteable.err

  TEST_NAME="sem_abort"
  TEST_DESC="Testing simple semantic error to abort output"
  TEST_CMD="${CQL} --cg \"$O/__temp\" /xx/yy/zz --in \"$T/semantic_error.sql\""
  run_test_expect_fail

  on_diff_exit sem_abort.err

  TEST_NAME="invalid_arg"
  TEST_DESC="Testing invalid argument"
  TEST_CMD="${CQL} --garbonzo!!"
  run_test_expect_fail

  on_diff_exit invalid_arg.err

  TEST_NAME="cg_requires_file"
  TEST_DESC="Testing --cg with no file name"
  TEST_CMD="${CQL} --cg"
  run_test_expect_fail

  on_diff_exit cg_requires_file.err

  TEST_NAME="cg_1_2"
  TEST_DESC="Testing wrong number of args specified in --cg (for lua)"
  TEST_CMD="${CQL} --dev --cg \"$O/__temp\" \"$O/__temp2\" --in \"$T/cg_test.sql\" --rt lua"
  run_test_expect_fail

  TEST_NAME="generate_file_type"
  TEST_DESC="Testing --generate_file_type with no file type specified"
  TEST_CMD="${CQL} --generate_file_type"
  run_test_expect_fail

  on_diff_exit generate_file_type.err

  TEST_NAME="generate_file_file"
  TEST_DESC="Testing --generate_file_type with invalid file type"
  TEST_CMD="${CQL} --generate_file_type foo"
  run_test_expect_fail

  on_diff_exit generate_file_file.err

  TEST_NAME="rt_arg_missing"
  TEST_DESC="Testing --rt with no argument"
  TEST_CMD="${CQL} --rt"
  run_test_expect_fail

  on_diff_exit rt_arg_missing.err

  TEST_NAME="rt_arg_bogus"
  TEST_DESC="Testing --rt with invalid result type"
  TEST_CMD="${CQL} --rt foo"
  run_test_expect_fail

  on_diff_exit rt_arg_bogus.err

  TEST_NAME="cqlrt_arg_missing"
  TEST_DESC="Testing --cqlrt with no file name"
  TEST_CMD="${CQL} --cqlrt"
  run_test_expect_fail

  on_diff_exit cqlrt_arg_missing.err

  TEST_NAME="global_proc_missing"
  TEST_DESC="Testing --global_proc with no procedure name"
  TEST_CMD="${CQL} --global_proc"
  run_test_expect_fail

  on_diff_exit global_proc_missing.err

  TEST_NAME="in_arg_missing"
  TEST_DESC="Testing --in with no file name"
  TEST_CMD="${CQL} --in"
  run_test_expect_fail

  on_diff_exit in_arg_missing.err

  TEST_NAME="c_include_namespace_missing"
  TEST_DESC="Testing --c_include_namespace with no namespace"
  TEST_CMD="${CQL} --c_include_namespace"
  run_test_expect_fail

  on_diff_exit c_include_namespace_missing.err
}

schema_migration_test() {
  echo '--------------------------------- STAGE 7 -- SCHEMA MIGRATION TESTS'
  TEST_NAME="sem_test_migrate"
  TEST_DESC="Running semantic analysis for migration test"
  TEST_CMD="sem_check --sem --ast --in \"$T/sem_test_migrate.sql\""
  TEST_ERROR_MSG="Migration semantic analysis failed"
  run_test_expect_success

  echo validating output trees
  cql_verify "$T/sem_test_migrate.sql" "$O/sem_test_migrate.out"

  echo "  computing diffs (empty if none)"
  on_diff_exit sem_test_migrate.out
  on_diff_exit sem_test_migrate.err

  echo '---------------------------------'
  TEST_NAME="schema_version_error"
  TEST_DESC="Running schema migrate proc test"
  TEST_CMD="sem_check --sem --in \"$T/schema_version_error.sql\" --ast"
  TEST_ERROR_MSG="Schema version error test failed"
  run_test_expect_success

  cql_verify "$T/schema_version_error.sql" "$O/schema_version_error.out"

  echo '---------------------------------'
  TEST_NAME="sem_test_prev"
  TEST_DESC="Running semantic analysis for previous schema error checks test"
  TEST_CMD="sem_check --sem --ast --exclude_regions high_numbered_thing --in \"$T/sem_test_prev.sql\""
  TEST_ERROR_MSG="Previous schema error checks test failed"
  run_test_expect_success

  echo validating output trees
  cql_verify "$T/sem_test_prev.sql" "$O/sem_test_prev.out"

  echo "  computing diffs (empty if none)"
  on_diff_exit sem_test_prev.out
  on_diff_exit sem_test_prev.err

  echo '---------------------------------'
  TEST_NAME="cg_test_schema_upgrade"
  TEST_DESC="Running code gen for migration test"
  TEST_CMD="${CQL} --cg \"$O/cg_test_schema_upgrade.out\" --in \"$T/cg_test_schema_upgrade.sql\" --global_proc test --rt schema_upgrade"
  TEST_ERROR_MSG="Schema upgrade code generation failed"
  run_test_expect_success

  echo validating output trees
  cql_verify "$T/cg_test_schema_upgrade.sql" "$O/cg_test_schema_upgrade.out"

  TEST_NAME="cg_test_schema_upgrade_compile_c"
  TEST_DESC="Compiling the upgrade script with CQL"
  TEST_CMD="${CQL} --cg \"$O/cg_test_schema_upgrade.h\" \"$O/cg_test_schema_upgrade.c\" --in \"$O/cg_test_schema_upgrade.out\""
  run_test_expect_success

  TEST_NAME="cg_test_schema_upgrade_compile_cql"
  TEST_DESC="Compiling the upgrade script with CQL"
  TEST_CMD="do_make cg_test_schema_upgrade"
  run_test_expect_success

  echo "  computing diffs (empty if none)"

  on_diff_exit cg_test_schema_upgrade.out
  on_diff_exit cg_test_schema_upgrade.err

  echo '---------------------------------'
  TEST_NAME="cg_test_schema_prev"
  TEST_DESC="Running code gen to produce previous schema"
  TEST_CMD="${CQL} --cg \"$O/cg_test_schema_prev.out\" --in \"$T/cg_test_schema_upgrade.sql\" --rt schema"
  run_test_expect_success

  echo '---------------------------------'
  TEST_NAME="cg_test_schema_sqlite"
  TEST_DESC="Running code gen to produce raw sqlite schema"
  TEST_CMD="${CQL} --cg \"$O/cg_test_schema_sqlite.out\" --in \"$T/cg_test_schema_upgrade.sql\" --rt schema_sqlite"
  run_test_expect_success

  echo "combining generated previous schema with itself to ensure it self validates"

  cat "$O/cg_test_schema_prev.out" >"$O/prev_loop.out"
  echo "@previous_schema;" >>"$O/prev_loop.out"
  cat "$O/cg_test_schema_prev.out" >>"$O/prev_loop.out"

  TEST_NAME="cg_test_schema_prev_twice"
  TEST_DESC="Validating previous schema combined with itself"
  TEST_CMD="${CQL} --cg \"$O/prev_twice.out\" --in \"$O/prev_loop.out\" --rt schema"
  run_test_expect_success

  echo "comparing the generated previous schema from that combination and it should be identical to the original"

  TEST_NAME="cg_test_schema_prev_thrice"
  TEST_DESC="Validating previous schema combined with itself"
  TEST_CMD="${CQL} --cg \"$O/prev_thrice.out\" --in \"$O/prev_twice.out\" --rt schema"
  run_test_expect_success

  echo "  computing diffs after several applications (empty if none)"
  __on_diff_exit "$O/cg_test_schema_prev.out" "$O/prev_twice.out"
  __on_diff_exit "$O/prev_twice.out" "$O/prev_thrice.out"

  echo "  computing previous schema diffs from reference (empty if none)"
  on_diff_exit cg_test_schema_prev.out
  on_diff_exit cg_test_schema_prev.err

  echo "  computing sqlite schema diffs from reference (empty if none)"
  on_diff_exit cg_test_schema_sqlite.out
  on_diff_exit cg_test_schema_sqlite.err

  TEST_NAME="cg_test_schema_partial_upgrade"
  TEST_DESC="Running schema migration with include/exclude args"
  TEST_CMD="${CQL} --cg \"$O/cg_test_schema_partial_upgrade.out\" --in \"$T/cg_test_schema_upgrade.sql\" --global_proc test --rt schema_upgrade --include_regions extra --exclude_regions shared"
  run_test_expect_success

  echo "  compiling the upgrade script with CQL"

  TEST_NAME="cg_test_schema_partial_upgrade_compile_cql"
  TEST_DESC="Compiling the partial upgrade script with CQL"
  TEST_CMD="${CQL} --cg \"$O/cg_test_schema_partial_upgrade.h\" \"$O/cg_test_schema_partial_upgrade.c\" --in \"$O/cg_test_schema_partial_upgrade.out\""
  run_test_expect_success

  echo "  computing diffs (empty if none)"
  on_diff_exit cg_test_schema_partial_upgrade.out
  on_diff_exit cg_test_schema_partial_upgrade.err

  TEST_NAME="cg_test_schema_min_version_upgrade"
  TEST_DESC="Running schema migration with min version args"
  TEST_CMD="${CQL} --cg \"$O/cg_test_schema_min_version_upgrade.out\" --in \"$T/cg_test_schema_upgrade.sql\" --global_proc test --rt schema_upgrade --min_schema_version 3"
  run_test_expect_success

  echo "  computing diffs (empty if none)"
  on_diff_exit cg_test_schema_min_version_upgrade.out
  on_diff_exit cg_test_schema_min_version_upgrade.err
}

misc_cases() {
  echo '--------------------------------- STAGE 8 -- MISC CASES'
  TEST_NAME="usage"
  TEST_DESC="Running usage test"
  TEST_CMD="${CQL}"
  run_test_expect_success
  on_diff_exit usage.out

  TEST_NAME="simple_error"
  TEST_DESC="Running simple error test"
  TEST_CMD="${CQL} --in \"$T/error.sql\""
  run_test_expect_fail

  on_diff_exit simple_error.err

  TEST_NAME="prev_and_codegen_incompat"
  TEST_DESC="Running previous schema and codegen incompatible test"
  TEST_CMD="${CQL} --cg \"$O/__temp.h\" \"$O/__temp.c\" --in \"$T/cg_test_prev_invalid.sql\""
  run_test_expect_fail

  on_diff_exit prev_and_codegen_incompat.err

  TEST_NAME="bigquote"
  TEST_DESC="Running big quote test"
  TEST_CMD="${CQL} --cg \"$O/__temp.h\" \"$O/__temp.c\" --in \"$T/bigquote.sql\" --global_proc x"
  run_test_expect_success

  on_diff_exit bigquote.err

  TEST_NAME="alt_cqlrt"
  TEST_DESC="Running alternate cqlrt.h test"
  TEST_CMD="${CQL} --dev --cg \"$O/__temp.h\" \"$O/__temp.c\" --in \"$T/cg_test.sql\" --global_proc x --cqlrt alternate_cqlrt.h"
  run_test_expect_success

  on_diff_exit alt_cqlrt.err

  TEST_NAME="alt_cqlrt_check"
  TEST_DESC="Checking alternate cqlrt.h inclusion"
  TEST_CMD="grep alternate_cqlrt.h \"$O/__temp.h\""
  run_test_expect_success

  TEST_NAME="gen_exports_args"
  TEST_DESC="Running too few -cg arguments with --generate_exports test"
  TEST_CMD="${CQL} --dev --cg \"$O/__temp.c\" \"$O/__temp.h\" --in \"$T/cg_test.sql\" --global_proc x --generate_exports"
  run_test_expect_fail

  on_diff_exit gen_exports_args.err

  TEST_NAME="inc_invalid_regions"
  TEST_DESC="Running invalid include regions test"
  TEST_CMD="${CQL} --cg \"$O/cg_test_schema_partial_upgrade.out\" --in \"$T/cg_test_schema_upgrade.sql\" --global_proc test --rt schema_upgrade --include_regions bogus --exclude_regions shared"
  run_test_expect_fail

  on_diff_exit inc_invalid_regions.err

  TEST_NAME="excl_invalid_regions"
  TEST_DESC="Running invalid exclude regions test"
  TEST_CMD="${CQL} --cg \"$O/cg_test_schema_partial_upgrade.out\" --in \"$T/cg_test_schema_upgrade.sql\" --global_proc test --rt schema_upgrade --include_regions extra --exclude_regions bogus"
  run_test_expect_fail

  on_diff_exit excl_invalid_regions.err

  TEST_NAME="global_proc_needed"
  TEST_DESC="Running global proc is needed but not present test"
  TEST_CMD="${CQL} --cg \"$O/__temp.c\" \"$O/__temp.h\" --in \"$T/bigquote.sql\""
  run_test_expect_fail

  on_diff_exit global_proc_needed.err

  create_unwritable_file "$O/unwritable.h.out"
  create_unwritable_file "$O/unwritable.c.out"

  TEST_NAME="write_fail"
  TEST_DESC="Running test where output file cannot be written"
  TEST_CMD="${CQL} --dev --cg \"$O/unwritable.h.out\" \"$O/unwritable.c.out\" --in \"$T/cg_test.sql\" --rt c --global_proc cql_startup"
  run_test_expect_fail

  on_diff_exit write_fail.err

  TEST_NAME="cg_test_generated_from_compile"
  TEST_DESC="Testing the generated from comments in non-test environment"
  TEST_CMD="${CQL} --cg \"$O/cg_test_generated_from.h\" \"$O/cg_test_generated_from.c\" --in \"$T/cg_test_generated_from.sql\""
  run_test_expect_success

  TEST_NAME="cg_test_generated_from_test_h_21"
  TEST_DESC="Testing the 'generated from' comments in test environment (line 21)"
  TEST_CMD="grep 'Generated from test/cg_test_generated_from.sql:21' \"$O/cg_test_generated_from.h\""
  run_test_expect_success

  TEST_NAME="cg_test_generated_from_test_c_21"
  TEST_DESC="Testing the 'generated from' comments in test environment (line 21)"
  TEST_CMD="grep 'Generated from test/cg_test_generated_from.sql:21' \"$O/cg_test_generated_from.c\""
  run_test_expect_success

  TEST_NAME="parse_test_fetch_from_call_columns"
  TEST_DESC="Running parser disallows columns in FETCH FROM CALL test"
  TEST_CMD="${CQL} --in \"$T/parse_test_fetch_from_call_columns.sql\""
  TEST_ERROR_MSG="failed to disallow cursor columns in FETCH FROM CALL"
  run_test_expect_fail

  on_diff_exit parse_test_fetch_from_call_columns.err

  TEST_NAME="parse_test_cql_inferred_notnull"
  TEST_DESC="Running parser disallows cql_inferred_notnull test"
  TEST_CMD="${CQL} --in \"$T/parse_test_cql_inferred_notnull.sql\""
  TEST_ERROR_MSG="failed to disallow cql_inferred_notnull"
  run_test_expect_fail

  on_diff_exit parse_test_cql_inferred_notnull.err
}

json_validate() {
  sql_file=$1
  json_file="$O/cql_test.json"

  TEST_NAME="json_validate"
  TEST_DESC="Checking for valid JSON formatting of ${sql_file} (test mode disabled)"
  TEST_CMD="${CQL} --cg \"${json_file}\" --in \"${sql_file}\" --rt json_schema"
  run_test_expect_success

  TEST_NAME="json_validate_using_python"
  TEST_DESC="Checking for well formed JSON using python for ${sql_file} which creatged ${json_file}"
  TEST_CMD="common/json_check.py <\"${json_file}\""
  run_test_expect_success

  TEST_NAME="json_grammar_conformance"
  TEST_DESC="Checking for CQL JSON grammar conformance for ${sql_file} which creatged ${json_file}"
  TEST_CMD="out/json_test <\"${json_file}\""
  run_test_expect_success
}

json_schema_test() {
  echo '--------------------------------- STAGE 9 -- JSON SCHEMA TEST'
  TEST_NAME="cg_test_json_schema"
  TEST_DESC="Running JSON schema test"
  TEST_CMD="${CQL} --test --cg \"$O/cg_test_json_schema.out\" --in \"$T/cg_test_json_schema.sql\" --rt json_schema"
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
  TEST_ERROR_MSG="Test builders test failed"
  run_test_expect_success

  echo validating test helpers output
  cql_verify "$T/cg_test_test_helpers.sql" "$O/cg_test_test_helpers.out"

  echo validating test helpers cql codegen
  echo "  computing diffs (empty if none)"
  on_diff_exit cg_test_test_helpers.out

  TEST_NAME="cg_test_test_helpers_sem_analysis"
  TEST_DESC="Running semantic analysis on test helpers output"
  TEST_CMD="${CQL} --sem --ast --in \"$O/cg_test_test_helpers.out\""
  run_test_expect_success

  TEST_NAME="cg_test_test_helpers_c_codegen"
  TEST_DESC="Generating test helpers c code"
  TEST_CMD="${CQL} --test --dev --cg \"$O/test_helpers.h\" \"$O/test_helpers.c\" --in \"$O/cg_test_test_helpers.out\""
  run_test_expect_success

  TEST_NAME="cg_test_test_helpers_c_compile"
  TEST_DESC="Compiling test helpers c code"
  TEST_CMD="do_make test_helpers_test"
  run_test_expect_success

  TEST_NAME="cg_test_test_helpers_c_run"
  TEST_DESC="Running test helpers in c"
  TEST_CMD="./$O/test_helpers_test"
  run_test_expect_success
}

run_test_compile() {
  echo "  compiling code"
  do_make run_test
  MAKE_ARGS_SAVED=${MAKE_ARGS}
  # echo gives us a free whitespace trim avoiding empty args with ""
  MAKE_ARGS=$(echo SQLITE_PATH=./sqlite ${MAKE_ARGS})
  do_make sqlite
  do_make run_test_modern
  MAKE_ARGS=${MAKE_ARGS_SAVED}
}

run_test() {
  echo '--------------------------------- STAGE 11 -- RUN CODE TEST'

  TEST_NAME="run_test_codegen"
  TEST_DESC="Generating run test code"
  TEST_CMD="${CQL} --nolines --cg \"$O/run_test.h\" \"$O/run_test.c\" --in \"$T/run_test.sql\" --global_proc cql_startup --rt c"
  run_test_expect_success

  TEST_NAME="run_test_modern_codegen"
  TEST_DESC="Generating modern SQLite run test code"
  TEST_CMD="${CQL} --defines modern_test --nolines --cg \"$O/run_test_modern.h\" \"$O/run_test_modern.c\" --in \"$T/run_test.sql\" --global_proc cql_startup --rt c"
  run_test_expect_success

  TEST_NAME="run_test_compile_code"
  TEST_DESC="Compiling run test code"
  TEST_CMD="run_test_compile"
  run_test_expect_success

  TEST_NAME="run_test_run"
  TEST_DESC="Running run test in C"
  TEST_CMD="./$O/run_test"
  run_test_expect_success

  TEST_NAME="run_test_modern_sqlite"
  TEST_DESC="Running run test for modern SQLite"
  TEST_CMD="./$O/run_test_modern"
  run_test_expect_success

  TEST_NAME="run_test_compressed_codegen"
  TEST_DESC="Generating compressed run test code"
  TEST_CMD="${CQL} --compress --cg \"$O/run_test_compressed.h\" \"$O/run_test_compressed.c\" --in \"$T/run_test.sql\" --global_proc cql_startup --rt c"
  run_test_expect_success

  TEST_NAME="run_test_compressed_compile_code"
  TEST_DESC="Compiling compressed run test code"
  TEST_CMD="do_make run_test_compressed"
  run_test_expect_success

  TEST_NAME="run_test_compressed_run"
  TEST_DESC="Running compressed run test in C"
  TEST_CMD="./$O/run_test_compressed"
  run_test_expect_success
}

upgrade_test() {
  echo '--------------------------------- STAGE 12 -- SCHEMA UPGRADE TEST'

  TEST_NAME="upgrade_test"
  TEST_DESC="Running schema upgrade test"
  TEST_CMD="upgrade/upgrade_test.sh \"${TEST_COVERAGE_ARGS}\""
  run_test_expect_success
}

query_plan_test() {
  echo '--------------------------------- STAGE 13 -- TEST QUERY PLAN'

  TEST_NAME="query_plan_sem"
  TEST_DESC="Baseline semantic analysis of query plan test"
  TEST_CMD="${CQL} --sem --ast --dev --in \"$T/cg_test_query_plan.sql\""
  run_test_expect_success

  TEST_NAME="query_plan_codegen"
  TEST_DESC="Generating query plan code"
  TEST_CMD="${CQL} --test --dev --cg \"$O/cg_test_query_plan.out\" --in \"$T/cg_test_query_plan.sql\" --rt query_plan"
  run_test_expect_success

  TEST_NAME="query_plan_sem_analysis"
  TEST_DESC="Running semantic analysis on generated query plan"
  TEST_CMD="${CQL} --sem --ast --dev --test --in \"$O/cg_test_query_plan.out\""
  run_test_expect_success

  echo validating test results
  cql_verify "$T/cg_test_query_plan.sql" "$O/cg_test_query_plan.out"

  echo validating query plan codegen
  echo "  computing diffs (empty if none)"
  on_diff_exit cg_test_query_plan.out

  TEST_NAME="query_plan_c_build"
  TEST_DESC="Building query plan C code"
  TEST_CMD="${CQL} --test --dev --cg \"$O/query_plan.h\" \"$O/query_plan.c\" --in \"$O/cg_test_query_plan.out\""
  run_test_expect_success

  TEST_NAME="query_plan_compile"
  TEST_DESC="Compiling query plan code"
  TEST_CMD="do_make query_plan_test"
  run_test_expect_success

  TEST_NAME="query_plan_run"
  TEST_DESC="Running query plan in C"
  TEST_CMD="./$O/query_plan_test"
  run_test_expect_success

  TEST_NAME="query_plan_json_validate"
  TEST_DESC="Validating JSON format of query plan report"
  TEST_CMD="common/json_check.py <\"$O/query_plan_run.out\""
  run_test_expect_success

  TEST_NAME="query_plan_empty_codegen"
  TEST_DESC="Generating empty query plan code"
  TEST_CMD="${CQL} --test --dev --cg \"$O/cg_test_query_plan_empty.out\" --in \"$T/cg_test_query_plan_empty.sql\" --rt query_plan"
  run_test_expect_success

  TEST_NAME="query_plan_empty_sem"
  TEST_DESC="Running semantic analysis on empty query plan"
  TEST_CMD="${CQL} --sem --ast --dev --test --in \"$O/cg_test_query_plan_empty.out\""
  run_test_expect_success

  echo validating query plan codegen empty query plan
  echo "  computing diffs (empty if none)"
  on_diff_exit cg_test_query_plan_empty.out

  TEST_NAME="query_plan_empty_c_build"
  TEST_DESC="Building empty query plan C code"
  TEST_CMD="${CQL} --test --dev --cg \"$O/query_plan.h\" \"$O/query_plan.c\" --in \"$O/cg_test_query_plan_empty.out\""
  run_test_expect_success

  TEST_NAME="query_plan_empty_compile"
  TEST_DESC="Compiling empty query plan code"
  TEST_CMD="rm $O/query_plan.o && do_make query_plan_test"
  run_test_expect_success

  TEST_NAME="query_plan_empty_run"
  TEST_DESC="Running empty query plan in C"
  TEST_CMD="./$O/query_plan_test"
  run_test_expect_success

  TEST_NAME="query_plan_empty_json_validate"
  TEST_DESC="Validating JSON format of empty query plan report"
  TEST_CMD="common/json_check.py <\"$O/query_plan_empty_run.out\""
  run_test_expect_success

  echo "validating query plan empty result (this is stable)"
  echo "  computing diffs (empty if none)"
  on_diff_exit query_plan_empty_run.out
}

line_number_test() {
  echo '--------------------------------- STAGE 14 -- TEST LINE DIRECTIVES'

  line_file="$O/line_directives"

  TEST_NAME="line_directives_compile"
  TEST_DESC="Building code with line directives in output"
  TEST_CMD="${CQL} --cg \"${line_file}.h\" \"${line_file}.c\" \"$O/${line_file}.out\" --in \"$T/cg_test_generated_from.sql\""
  run_test_expect_success

  TEST_NAME="line_directives_presence_check"
  TEST_DESC="Testing the presence of #line directives"
  TEST_CMD="grep '^#line ' \"${line_file}.c\""
  run_test_expect_success

  TEST_NAME="line_directives_echo_check"
  TEST_DESC="Testing the presence of echo output in generated code"
  TEST_CMD="grep '/\* A comment \*/' \"${line_file}.c\""
  run_test_expect_success

  TEST_NAME="line_directives_suppression_compile"
  TEST_DESC="Building code with suppression of #line directives"
  TEST_CMD="${CQL} --nolines --cg \"${line_file}.h\" \"${line_file}.c\" \"${line_file}.out\" --in \"$T/cg_test_generated_from.sql\""
  run_test_expect_success

  TEST_NAME="line_directives_suppression_check"
  TEST_DESC="Testing the absence of #line directives"
  TEST_CMD="grep '^#line ' \"${line_file}.c\""
  run_test_expect_fail

  TEST_NAME="line_number_test_compile"
  TEST_DESC="Compiling for line number validation"
  TEST_CMD="${CQL} --cg \"${line_file}.h\" \"${line_file}.c\" --in \"$T/linetest.sql\""
  run_test_expect_success

  TEST_NAME="line_number_validation"
  TEST_DESC="Validating line numbers in generated code"
  TEST_CMD="$O/cql-linetest \"$T/linetest.expected\" \"${line_file}.c\""
  run_test_expect_success
}

stats_test() {
  echo '--------------------------------- STAGE 15 -- STATS OUTPUT TEST'
  TEST_NAME="stats_test"
  TEST_DESC="Running stats output test"
  TEST_CMD="${CQL} --cg \"$O/stats.csv\" --in \"$T/stats_test.sql\" --rt stats"
  run_test_expect_success

  echo "  computing diffs (empty if none)"
  on_diff_exit stats.csv
}

amalgam_test() {
  echo '--------------------------------- STAGE 16 -- TEST AMALGAM'

  TEST_NAME="cql_amalgam_test"
  TEST_DESC="Running CQL amalgam tests"
  TEST_CMD="./$O/amalgam_test \"$T/cql_amalgam_test_success.sql\" \"$T/cql_amalgam_test_semantic_error.sql\" \"$T/cql_amalgam_test_syntax_error.sql\""
  run_test_expect_success

  on_diff_exit cql_amalgam_test.out
  on_diff_exit cql_amalgam_test.err
}

# add other stages before this one

unit_tests() {
  TEST_NAME="unit_tests"
  TEST_DESC="Running CQL unit tests"
  TEST_CMD="${CQL} --run_unit_tests"
  run_test_expect_success
}

code_gen_lua_test() {
  echo '--------------------------------- STAGE 17 -- LUA CODE GEN TEST'
  TEST_NAME="cg_test_lua"
  TEST_DESC="Running Lua codegen test"
  TEST_CMD="${CQL} --dev --test --cg \"$O/cg_test_lua.lua\" --in \"$T/cg_test_lua.sql\" --global_proc cql_startup --rt lua"
  run_test_expect_success

  echo validating codegen
  cql_verify "$T/cg_test_lua.sql" "$O/cg_test_lua.lua"

  #  echo testing for successful compilation of generated lua
  #  if ! lua out/cg_test_lua.lua
  #  then
  #    echo "ERROR: failed to compile the C code from the code gen test"
  #    failed
  #  fi

  TEST_NAME="lua_run_test"
  TEST_DESC="Testing successful compilation of Lua run test (cannot run by default due to runtime requirements)"
  TEST_CMD="lua_demo/prepare_run_test.sh"
  run_test_expect_success

  echo "  computing diffs (empty if none)"
  on_diff_exit cg_test_lua.lua
  on_diff_exit cg_test_lua.err
}

dot_test() {
  echo '--------------------------------- STAGE 18 -- .DOT OUTPUT TEST'
  TEST_NAME="dottest"
  TEST_DESC="Running DOT generation test on $T/dottest.sql"
  TEST_CMD="${CQL} --dot --hide_builtins --in \"$T/dottest.sql\""
  run_test_expect_success

  echo "  computing diffs (empty if none)"
  on_diff_exit dottest.out
}

cqlrt_diag() {
  echo '--------------------------------- STAGE 19 -- COMPILING CQLRT WITH HIGH WARNINGS'
  TEST_NAME="cqlrt_diag"
  TEST_DESC="Building $O/cqlrt_diag.o with high warnings enabled"
  TEST_CMD="do_make $O/cqlrt_diag.o"
  TEST_ERROR_MSG="Warnings discovered in cqlrt"
  run_test_expect_success
}

GENERATED_TAG=generated
AT_GENERATED_TAG="@$GENERATED_TAG"

signatures_test() {
  TEST_NAME="signatures_test"
  TEST_DESC="Checking for signatures in reference files"
  TEST_CMD="! grep \"$AT_GENERATED_TAG SignedSource\" $T/*.ref"
  TEST_ERROR_MSG="Signatures found in reference files, this is never valid. Change the test logic so that it validates the presence of the signature which then strips it. It's likely that one of those validations is missing which caused a signature to be copied into a .ref file."
  run_test_expect_success
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
