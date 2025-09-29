/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#include "cql-verify.h"

#ifndef _MSC_VER
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunknown-warning-option"
#pragma clang diagnostic ignored "-Wbitwise-op-parentheses"
#pragma clang diagnostic ignored "-Wshift-op-parentheses"
#pragma clang diagnostic ignored "-Wlogical-not-parentheses"
#pragma clang diagnostic ignored "-Wlogical-op-parentheses"
#pragma clang diagnostic ignored "-Wliteral-conversion"
#pragma clang diagnostic ignored "-Wunused-but-set-variable"
#pragma clang diagnostic ignored "-Wunused-function"
#endif
extern cql_object_ref _Nonnull cql_partition_create(void);
extern cql_bool cql_partition_cursor(cql_object_ref _Nonnull p, cql_dynamic_cursor *_Nonnull key, cql_dynamic_cursor *_Nonnull value);
extern cql_object_ref _Nonnull cql_extract_partition(cql_object_ref _Nonnull p, cql_dynamic_cursor *_Nonnull key);
extern cql_object_ref _Nonnull cql_string_dictionary_create(void);
extern cql_bool cql_string_dictionary_add(cql_object_ref _Nonnull dict, cql_string_ref _Nonnull key, cql_string_ref _Nonnull value);
extern cql_string_ref _Nullable cql_string_dictionary_find(cql_object_ref _Nonnull dict, cql_string_ref _Nullable key);
extern cql_object_ref _Nonnull cql_long_dictionary_create(void);
extern cql_bool cql_long_dictionary_add(cql_object_ref _Nonnull dict, cql_string_ref _Nonnull key, cql_int64 value);
extern cql_nullable_int64 cql_long_dictionary_find(cql_object_ref _Nonnull dict, cql_string_ref _Nullable key);
extern cql_object_ref _Nonnull cql_real_dictionary_create(void);
extern cql_bool cql_real_dictionary_add(cql_object_ref _Nonnull dict, cql_string_ref _Nonnull key, cql_double value);
extern cql_nullable_double cql_real_dictionary_find(cql_object_ref _Nonnull dict, cql_string_ref _Nullable key);
extern cql_object_ref _Nonnull cql_object_dictionary_create(void);
extern cql_bool cql_object_dictionary_add(cql_object_ref _Nonnull dict, cql_string_ref _Nonnull key, cql_object_ref _Nonnull value);
extern cql_object_ref _Nullable cql_object_dictionary_find(cql_object_ref _Nonnull dict, cql_string_ref _Nullable key);
extern cql_object_ref _Nonnull cql_blob_dictionary_create(void);
extern cql_bool cql_blob_dictionary_add(cql_object_ref _Nonnull dict, cql_string_ref _Nonnull key, cql_blob_ref _Nonnull value);
extern cql_blob_ref _Nullable cql_blob_dictionary_find(cql_object_ref _Nonnull dict, cql_string_ref _Nullable key);
extern cql_string_ref _Nonnull cql_cursor_format(cql_dynamic_cursor *_Nonnull C);
extern cql_int64 cql_cursor_hash(cql_dynamic_cursor *_Nonnull C);
extern cql_bool cql_cursors_equal(cql_dynamic_cursor *_Nonnull l, cql_dynamic_cursor *_Nonnull r);
extern cql_int32 cql_cursor_diff_index(cql_dynamic_cursor *_Nonnull l, cql_dynamic_cursor *_Nonnull r);
extern cql_string_ref _Nullable cql_cursor_diff_col(cql_dynamic_cursor *_Nonnull l, cql_dynamic_cursor *_Nonnull r);
extern cql_string_ref _Nullable cql_cursor_diff_val(cql_dynamic_cursor *_Nonnull l, cql_dynamic_cursor *_Nonnull r);
extern cql_object_ref _Nonnull cql_box_int(cql_nullable_int32 x);
extern cql_nullable_int32 cql_unbox_int(cql_object_ref _Nullable box);
extern cql_object_ref _Nonnull cql_box_real(cql_nullable_double x);
extern cql_nullable_double cql_unbox_real(cql_object_ref _Nullable box);
extern cql_object_ref _Nonnull cql_box_bool(cql_nullable_bool x);
extern cql_nullable_bool cql_unbox_bool(cql_object_ref _Nullable box);
extern cql_object_ref _Nonnull cql_box_long(cql_nullable_int64 x);
extern cql_nullable_int64 cql_unbox_long(cql_object_ref _Nullable box);
extern cql_object_ref _Nonnull cql_box_text(cql_string_ref _Nullable x);
extern cql_string_ref _Nullable cql_unbox_text(cql_object_ref _Nullable box);
extern cql_object_ref _Nonnull cql_box_blob(cql_blob_ref _Nullable x);
extern cql_blob_ref _Nullable cql_unbox_blob(cql_object_ref _Nullable box);
extern cql_object_ref _Nonnull cql_box_object(cql_object_ref _Nullable x);
extern cql_object_ref _Nullable cql_unbox_object(cql_object_ref _Nullable box);
extern cql_int32 cql_box_get_type(cql_object_ref _Nullable box);
extern cql_object_ref _Nonnull cql_string_list_create(void);
extern cql_object_ref _Nonnull cql_string_list_set_at(cql_object_ref _Nonnull list, cql_int32 index_, cql_string_ref _Nonnull value_);
extern cql_string_ref _Nullable cql_string_list_get_at(cql_object_ref _Nonnull list, cql_int32 index_);
extern cql_int32 cql_string_list_count(cql_object_ref _Nonnull list);
extern cql_object_ref _Nonnull cql_string_list_add(cql_object_ref _Nonnull list, cql_string_ref _Nonnull string);
extern cql_object_ref _Nonnull cql_blob_list_create(void);
extern cql_object_ref _Nonnull cql_blob_list_set_at(cql_object_ref _Nonnull list, cql_int32 index_, cql_blob_ref _Nonnull value_);
extern cql_blob_ref _Nullable cql_blob_list_get_at(cql_object_ref _Nonnull list, cql_int32 index_);
extern cql_int32 cql_blob_list_count(cql_object_ref _Nonnull list);
extern cql_object_ref _Nonnull cql_blob_list_add(cql_object_ref _Nonnull list, cql_blob_ref _Nonnull value);
extern cql_object_ref _Nonnull cql_object_list_create(void);
extern cql_object_ref _Nonnull cql_object_list_set_at(cql_object_ref _Nonnull list, cql_int32 index_, cql_object_ref _Nonnull value_);
extern cql_object_ref _Nullable cql_object_list_get_at(cql_object_ref _Nonnull list, cql_int32 index_);
extern cql_int32 cql_object_list_count(cql_object_ref _Nonnull list);
extern cql_object_ref _Nonnull cql_object_list_add(cql_object_ref _Nonnull list, cql_object_ref _Nonnull value);
extern cql_object_ref _Nonnull cql_long_list_create(void);
extern cql_object_ref _Nonnull cql_long_list_set_at(cql_object_ref _Nonnull list, cql_int32 index_, cql_int64 value_);
extern cql_int64 cql_long_list_get_at(cql_object_ref _Nonnull list, cql_int32 index_);
extern cql_int32 cql_long_list_count(cql_object_ref _Nonnull list);
extern cql_object_ref _Nonnull cql_long_list_add(cql_object_ref _Nonnull list, cql_int64 value_);
extern cql_object_ref _Nonnull cql_real_list_create(void);
extern cql_object_ref _Nonnull cql_real_list_set_at(cql_object_ref _Nonnull list, cql_int32 index_, cql_double value_);
extern cql_double cql_real_list_get_at(cql_object_ref _Nonnull list, cql_int32 index_);
extern cql_int32 cql_real_list_count(cql_object_ref _Nonnull list);
extern cql_object_ref _Nonnull cql_real_list_add(cql_object_ref _Nonnull list, cql_double value_);
extern cql_int32 cql_cursor_column_count(cql_dynamic_cursor *_Nonnull C);
extern cql_int32 cql_cursor_column_type(cql_dynamic_cursor *_Nonnull C, cql_int32 icol);
extern cql_string_ref _Nullable cql_cursor_column_name(cql_dynamic_cursor *_Nonnull C, cql_int32 icol);
extern cql_nullable_bool cql_cursor_get_bool(cql_dynamic_cursor *_Nonnull C, cql_int32 icol);
extern cql_nullable_int32 cql_cursor_get_int(cql_dynamic_cursor *_Nonnull C, cql_int32 icol);
extern cql_nullable_int64 cql_cursor_get_long(cql_dynamic_cursor *_Nonnull C, cql_int32 icol);
extern cql_nullable_double cql_cursor_get_real(cql_dynamic_cursor *_Nonnull C, cql_int32 icol);
extern cql_string_ref _Nullable cql_cursor_get_text(cql_dynamic_cursor *_Nonnull C, cql_int32 icol);
extern cql_blob_ref _Nullable cql_cursor_get_blob(cql_dynamic_cursor *_Nonnull C, cql_int32 icol);
extern cql_object_ref _Nullable cql_cursor_get_object(cql_dynamic_cursor *_Nonnull C, cql_int32 icol);
extern cql_string_ref _Nonnull cql_cursor_format_column(cql_dynamic_cursor *_Nonnull C, cql_int32 icol);
extern CQL_WARN_UNUSED cql_code cql_throw(sqlite3 *_Nonnull _db_, cql_int32 code);

extern CQL_WARN_UNUSED cql_code cql_cursor_to_blob(sqlite3 *_Nonnull _db_, cql_dynamic_cursor *_Nonnull C, cql_blob_ref _Nullable *_Nonnull result);

extern CQL_WARN_UNUSED cql_code cql_cursor_from_blob(sqlite3 *_Nonnull _db_, cql_dynamic_cursor *_Nonnull C, cql_blob_ref _Nullable b);

extern cql_blob_ref _Nonnull cql_blob_from_int(cql_string_ref _Nullable prefix, cql_int32 val);
extern cql_string_ref _Nonnull cql_format_bool(cql_nullable_bool val);
extern cql_string_ref _Nonnull cql_format_int(cql_nullable_int32 val);
extern cql_string_ref _Nonnull cql_format_long(cql_nullable_int64 val);
extern cql_string_ref _Nonnull cql_format_double(cql_nullable_double val);
extern cql_string_ref _Nonnull cql_format_string(cql_string_ref _Nullable val);
extern cql_string_ref _Nonnull cql_format_blob(cql_blob_ref _Nullable val);
extern cql_string_ref _Nonnull cql_format_object(cql_object_ref _Nullable val);
extern cql_string_ref _Nonnull cql_format_null(cql_nullable_bool ignored);
extern cql_blob_ref _Nonnull cql_make_blob_stream(cql_object_ref _Nonnull list);
extern CQL_WARN_UNUSED cql_code cql_cursor_from_blob_stream(sqlite3 *_Nonnull _db_, cql_dynamic_cursor *_Nonnull C, cql_blob_ref _Nullable b, cql_int32 i);

extern cql_int32 cql_blob_stream_count(cql_blob_ref _Nonnull b);
extern cql_object_ref _Nullable cql_fopen(cql_string_ref _Nonnull name, cql_string_ref _Nonnull mode);
extern cql_string_ref _Nullable readline_object_file(cql_object_ref _Nonnull f);
extern cql_int32 atoi_at_text(cql_string_ref _Nullable str, cql_int32 offset);
extern cql_int32 len_text(cql_string_ref _Nullable self);
extern cql_int32 octet_text(cql_string_ref _Nullable self, cql_int32 offset);
extern cql_string_ref _Nullable after_text(cql_string_ref _Nullable self, cql_int32 offset);
extern cql_bool starts_with_text(cql_string_ref _Nonnull haystack, cql_string_ref _Nonnull needle);
extern cql_int32 index_of_text(cql_string_ref _Nonnull haystack, cql_string_ref _Nonnull needle);
extern cql_bool contains_at_text(cql_string_ref _Nonnull haystack, cql_string_ref _Nonnull needle, cql_int32 offset);
extern cql_string_ref _Nullable str_mid(cql_string_ref _Nonnull self, cql_int32 offset, cql_int32 len);
extern cql_string_ref _Nullable str_right(cql_string_ref _Nonnull self, cql_int32 len);
extern cql_string_ref _Nullable str_left(cql_string_ref _Nonnull self, cql_int32 len);
cql_string_literal(_literal_1_FAIL_dump_source, "FAIL");
cql_string_literal(_literal_2_dump_source, "");
cql_string_literal(_literal_3_dump_output, ">  ");
cql_string_literal(_literal_4_dump_output, "!  ");
cql_string_literal(_literal_5_pattern_found_but_not_on_the_saprint_fail_details, "pattern found but not on the same line (see lines marked with !)");
cql_string_literal(_literal_6_pattern_exists_nowhere_in_test_print_fail_details, "pattern exists nowhere in test output");
cql_string_literal(_literal_7_pattern_exists_but_only_earlierprint_fail_details, "pattern exists but only earlier in the results where + doesn't match it");
cql_string_literal(_literal_8_match_multiline, "-- +");
cql_string_literal(_literal_9_match_actual, "-- ");
cql_string_literal(_literal_10_TEST_match_actual, "-- TEST:");
cql_string_literal(_literal_11_match_actual, "-- - ");
cql_string_literal(_literal_12_match_actual, "-- * ");
cql_string_literal(_literal_13_match_actual, "-- + ");
cql_string_literal(_literal_14_match_actual, "-- = ");
cql_string_literal(_literal_15_r_read_test_results, "r");
cql_string_literal(_literal_16_The_statement_ending_at_line_read_test_results, "The statement ending at line ");

// Generated from cql-verify.sql:1

/*
[[builtin]]
DECLARE PROC cql_throw (code INT!) USING TRANSACTION;
*/

// Generated from cql-verify.sql:1

/*
[[builtin]]
DECLARE PROC cql_cursor_to_blob (C CURSOR, OUT result BLOB!) USING TRANSACTION;
*/

// Generated from cql-verify.sql:1

/*
[[builtin]]
DECLARE PROC cql_cursor_from_blob (C CURSOR, b BLOB) USING TRANSACTION;
*/

// Generated from cql-verify.sql:1

/*
[[builtin]]
DECLARE PROC cql_cursor_from_blob_stream (C CURSOR, b BLOB, i INT!) USING TRANSACTION;
*/

//
// This file is auto-generated by cql-verify.sql, it is checked in just
// in case CQL is broken by a change.  The Last Known Good Verifier
// can be used to verify the tests pass again, or report failures
// while things are still otherwise broken.  Rebuild with regen.sh
//

// enable detailed error tracing
#undef cql_error_trace
#define cql_error_trace() fprintf(stderr, "SQL Failure %d %s: %s %d\n", _rc_, sqlite3_errmsg(_db_), __FILE__, __LINE__)

// Generated from cql-verify.sql:56

/*
DECLARE sql_file_name TEXT;
*/
cql_string_ref sql_file_name = NULL;

// Generated from cql-verify.sql:57

/*
DECLARE result_file_name TEXT;
*/
cql_string_ref result_file_name = NULL;

// Generated from cql-verify.sql:58

/*
DECLARE attempts INT!;
*/
cql_int32 attempts = 0;

// Generated from cql-verify.sql:59

/*
DECLARE errors INT!;
*/
cql_int32 errors = 0;

// Generated from cql-verify.sql:60

/*
DECLARE tests INT!;
*/
cql_int32 tests = 0;

// Generated from cql-verify.sql:61

/*
DECLARE last_rowid LONG!;
*/
cql_int64 last_rowid = 0;

// Generated from cql-verify.sql:82

/*
[[private]]
PROC setup ()
BEGIN
  CREATE TABLE test_results(
    line INT!,
    data TEXT!
  );
  CREATE INDEX __idx__test_results ON test_results (line);
  CREATE TABLE test_input(
    line INT!,
    data TEXT!
  );
  CREATE INDEX __idx__test_input ON test_input (line);
END;
*/

#define _PROC_ "setup"
static CQL_WARN_UNUSED cql_code setup(sqlite3 *_Nonnull _db_) {
  cql_code _rc_ = SQLITE_OK;
  cql_error_prepare();

  _rc_ = cql_exec(_db_,
    "CREATE TABLE test_results( "
      "line INTEGER NOT NULL, "
      "data TEXT NOT NULL "
    ")");
  if (_rc_ != SQLITE_OK) { cql_error_trace(); goto cql_cleanup; }
  _rc_ = cql_exec(_db_,
    "CREATE INDEX __idx__test_results ON test_results (line)");
  if (_rc_ != SQLITE_OK) { cql_error_trace(); goto cql_cleanup; }
  _rc_ = cql_exec(_db_,
    "CREATE TABLE test_input( "
      "line INTEGER NOT NULL, "
      "data TEXT NOT NULL "
    ")");
  if (_rc_ != SQLITE_OK) { cql_error_trace(); goto cql_cleanup; }
  _rc_ = cql_exec(_db_,
    "CREATE INDEX __idx__test_input ON test_input (line)");
  if (_rc_ != SQLITE_OK) { cql_error_trace(); goto cql_cleanup; }
  _rc_ = SQLITE_OK;

cql_cleanup:
  cql_error_report();
  return _rc_;
}
#undef _PROC_

// Generated from cql-verify.sql:110

/*
[[private]]
PROC find_test_output_line (expectation_line INT!, OUT test_output_line INT!)
BEGIN
  TRY
    SET test_output_line := ( SELECT line
      FROM test_results
      WHERE line >= expectation_line
      LIMIT 1 );
  CATCH
    LET max_line := ( SELECT max(line)
      FROM test_results );
    CALL printf("no lines come after %d\n", expectation_line);
    CALL printf("available test output lines: %d\n", ( SELECT count(*)
      FROM test_results ));
    CALL printf("max line number: %d\n", max_line);
    CALL printf("\nThis type of failure usually indicates that:\n");
    CALL printf(" * The semantic validation crashed before the output was complete, or,\n");
    CALL printf(" * An earlier phase of the compiler had errors, such as macro expansion\n\n");
    THROW;
  END;
END;
*/

#define _PROC_ "find_test_output_line"
static CQL_WARN_UNUSED cql_code find_test_output_line(sqlite3 *_Nonnull _db_, cql_int32 expectation_line, cql_int32 *_Nonnull test_output_line) {
  cql_code _rc_ = SQLITE_OK;
  cql_error_prepare();
  cql_int32 _tmp_int_0 = 0;
  sqlite3_stmt *_temp_stmt = NULL;
  cql_nullable_int32 max_line = { .is_null = 1 };

  *test_output_line = 0; // set out arg to non-garbage
  // try
  {
    _rc_ = cql_prepare(_db_, &_temp_stmt,
      "SELECT line "
        "FROM test_results "
        "WHERE line >= ? "
        "LIMIT 1");
    cql_multibind(&_rc_, _db_, &_temp_stmt, 1,
                  CQL_DATA_TYPE_NOT_NULL | CQL_DATA_TYPE_INT32, expectation_line);
    if (_rc_ != SQLITE_OK) { cql_error_trace(); goto catch_start_1; }
    _rc_ = sqlite3_step(_temp_stmt);
    if (_rc_ != SQLITE_ROW) { cql_error_trace(); goto catch_start_1; }
      *test_output_line = sqlite3_column_int(_temp_stmt, 0);
    cql_finalize_stmt(&_temp_stmt);
    goto catch_end_1;
  }
  catch_start_1: {
    int32_t _rc_thrown_1 = _rc_;
    _rc_ = cql_prepare(_db_, &_temp_stmt,
      "SELECT max(line) "
        "FROM test_results");
    if (_rc_ != SQLITE_OK) { cql_error_trace(); goto cql_cleanup; }
    _rc_ = sqlite3_step(_temp_stmt);
    if (_rc_ != SQLITE_ROW) { cql_error_trace(); goto cql_cleanup; }
      cql_column_nullable_int32(_temp_stmt, 0, &max_line);
    cql_finalize_stmt(&_temp_stmt);
    printf("no lines come after %d\n", expectation_line);
    _rc_ = cql_prepare(_db_, &_temp_stmt,
      "SELECT count(*) "
        "FROM test_results");
    if (_rc_ != SQLITE_OK) { cql_error_trace(); goto cql_cleanup; }
    _rc_ = sqlite3_step(_temp_stmt);
    if (_rc_ != SQLITE_ROW) { cql_error_trace(); goto cql_cleanup; }
      _tmp_int_0 = sqlite3_column_int(_temp_stmt, 0);
    cql_finalize_stmt(&_temp_stmt);
    printf("available test output lines: %d\n", _tmp_int_0);
    printf("max line number: %d\n", max_line.value);
    printf("\nThis type of failure usually indicates that:\n");
    printf(" * The semantic validation crashed before the output was complete, or,\n");
    printf(" * An earlier phase of the compiler had errors, such as macro expansion\n\n");
    _rc_ = cql_best_error(_rc_thrown_1);
    cql_error_trace();
    goto cql_cleanup;
  }
  catch_end_1:;
  _rc_ = SQLITE_OK;

cql_cleanup:
  cql_error_report();
  cql_finalize_stmt(&_temp_stmt);
  return _rc_;
}
#undef _PROC_

// Generated from cql-verify.sql:129

/*
[[private]]
PROC find_next (pattern TEXT!, test_output_line INT!, OUT found INT!)
BEGIN
  CURSOR C FOR
    SELECT rowid
      FROM test_results
      WHERE line = test_output_line AND data LIKE "%" || pattern || "%" AND rowid > last_rowid;
  FETCH C;
  IF C THEN
    SET last_rowid := C.rowid;
    SET found := 1;
  ELSE
    SET found := 0;
  END;
END;
*/

#define _PROC_ "find_next"

typedef struct find_next_C_row {
  cql_bool _has_row_;
  cql_uint16 _refs_count_;
  cql_uint16 _refs_offset_;
  cql_int64 rowid;
} find_next_C_row;
static CQL_WARN_UNUSED cql_code find_next(sqlite3 *_Nonnull _db_, cql_string_ref _Nonnull pattern, cql_int32 test_output_line, cql_int32 *_Nonnull found) {
  cql_code _rc_ = SQLITE_OK;
  cql_error_prepare();
  sqlite3_stmt *C_stmt = NULL;
  find_next_C_row C = { 0 };

  *found = 0; // set out arg to non-garbage
  _rc_ = cql_prepare(_db_, &C_stmt,
    "SELECT rowid "
      "FROM test_results "
      "WHERE line = ? AND data LIKE '%' || ? || '%' AND rowid > ?");
  cql_multibind(&_rc_, _db_, &C_stmt, 3,
                CQL_DATA_TYPE_NOT_NULL | CQL_DATA_TYPE_INT32, test_output_line,
                CQL_DATA_TYPE_NOT_NULL | CQL_DATA_TYPE_STRING, pattern,
                CQL_DATA_TYPE_NOT_NULL | CQL_DATA_TYPE_INT64, last_rowid);
  if (_rc_ != SQLITE_OK) { cql_error_trace(); goto cql_cleanup; }
  _rc_ = sqlite3_step(C_stmt);
  C._has_row_ = _rc_ == SQLITE_ROW;
  cql_multifetch(_rc_, C_stmt, 1,
                 CQL_DATA_TYPE_NOT_NULL | CQL_DATA_TYPE_INT64, &C.rowid);
  if (_rc_ != SQLITE_ROW && _rc_ != SQLITE_DONE) { cql_error_trace(); goto cql_cleanup; }
  if (C._has_row_) {
    last_rowid = C.rowid;
    *found = 1;
  }
  else {
    *found = 0;
  }
  _rc_ = SQLITE_OK;

cql_cleanup:
  cql_error_report();
  cql_finalize_stmt(&C_stmt);
  return _rc_;
}
#undef _PROC_

// Generated from cql-verify.sql:140

/*
[[private]]
PROC find_same (pattern TEXT!, OUT found INT!)
BEGIN
  SET found := ( SELECT data LIKE "%" || pattern || "%"
    FROM test_results
    WHERE rowid = last_rowid IF NOTHING THEN FALSE );
END;
*/

#define _PROC_ "find_same"
static CQL_WARN_UNUSED cql_code find_same(sqlite3 *_Nonnull _db_, cql_string_ref _Nonnull pattern, cql_int32 *_Nonnull found) {
  cql_code _rc_ = SQLITE_OK;
  cql_error_prepare();
  cql_bool _tmp_bool_0 = 0;
  cql_bool _tmp_bool_1 = 0;
  sqlite3_stmt *_temp_stmt = NULL;

  *found = 0; // set out arg to non-garbage
  _rc_ = cql_prepare(_db_, &_temp_stmt,
    "SELECT data LIKE '%' || ? || '%' "
      "FROM test_results "
      "WHERE rowid = ?");
  cql_multibind(&_rc_, _db_, &_temp_stmt, 2,
                CQL_DATA_TYPE_NOT_NULL | CQL_DATA_TYPE_STRING, pattern,
                CQL_DATA_TYPE_NOT_NULL | CQL_DATA_TYPE_INT64, last_rowid);
  if (_rc_ != SQLITE_OK) { cql_error_trace(); goto cql_cleanup; }
  _rc_ = sqlite3_step(_temp_stmt);
  if (_rc_ != SQLITE_ROW && _rc_ != SQLITE_DONE) { cql_error_trace(); goto cql_cleanup; }
  if (_rc_ == SQLITE_ROW) {
    _tmp_bool_1 = sqlite3_column_int(_temp_stmt, 0) != 0;
    _tmp_bool_0 = _tmp_bool_1;
  }
  else {
    _tmp_bool_0 = 0;
  }
  cql_finalize_stmt(&_temp_stmt);
  *found = _tmp_bool_0;
  _rc_ = SQLITE_OK;

cql_cleanup:
  cql_error_report();
  cql_finalize_stmt(&_temp_stmt);
  return _rc_;
}
#undef _PROC_

// Generated from cql-verify.sql:154

/*
[[private]]
PROC find_count (pattern TEXT!, test_output_line INT!, OUT found INT!)
BEGIN
  SET found := ( SELECT count(*)
    FROM test_results
    WHERE line = test_output_line AND data LIKE "%" || pattern || "%" );
END;
*/

#define _PROC_ "find_count"
static CQL_WARN_UNUSED cql_code find_count(sqlite3 *_Nonnull _db_, cql_string_ref _Nonnull pattern, cql_int32 test_output_line, cql_int32 *_Nonnull found) {
  cql_code _rc_ = SQLITE_OK;
  cql_error_prepare();
  sqlite3_stmt *_temp_stmt = NULL;

  *found = 0; // set out arg to non-garbage
  _rc_ = cql_prepare(_db_, &_temp_stmt,
    "SELECT count(*) "
      "FROM test_results "
      "WHERE line = ? AND data LIKE '%' || ? || '%'");
  cql_multibind(&_rc_, _db_, &_temp_stmt, 2,
                CQL_DATA_TYPE_NOT_NULL | CQL_DATA_TYPE_INT32, test_output_line,
                CQL_DATA_TYPE_NOT_NULL | CQL_DATA_TYPE_STRING, pattern);
  if (_rc_ != SQLITE_OK) { cql_error_trace(); goto cql_cleanup; }
  _rc_ = sqlite3_step(_temp_stmt);
  if (_rc_ != SQLITE_ROW) { cql_error_trace(); goto cql_cleanup; }
    *found = sqlite3_column_int(_temp_stmt, 0);
  cql_finalize_stmt(&_temp_stmt);
  _rc_ = SQLITE_OK;

cql_cleanup:
  cql_error_report();
  cql_finalize_stmt(&_temp_stmt);
  return _rc_;
}
#undef _PROC_

// Generated from cql-verify.sql:171

/*
[[private]]
PROC prev_line (test_output_line INT!, OUT prev INT!)
BEGIN
  SET prev := ( SELECT line
    FROM test_results
    WHERE line < test_output_line
    ORDER BY line DESC
    LIMIT 1 IF NOTHING THEN 0 );
END;
*/

#define _PROC_ "prev_line"
static CQL_WARN_UNUSED cql_code prev_line(sqlite3 *_Nonnull _db_, cql_int32 test_output_line, cql_int32 *_Nonnull prev) {
  cql_code _rc_ = SQLITE_OK;
  cql_error_prepare();
  cql_int32 _tmp_int_1 = 0;
  sqlite3_stmt *_temp_stmt = NULL;

  *prev = 0; // set out arg to non-garbage
  _rc_ = cql_prepare(_db_, &_temp_stmt,
    "SELECT line "
      "FROM test_results "
      "WHERE line < ? "
      "ORDER BY line DESC "
      "LIMIT 1");
  cql_multibind(&_rc_, _db_, &_temp_stmt, 1,
                CQL_DATA_TYPE_NOT_NULL | CQL_DATA_TYPE_INT32, test_output_line);
  if (_rc_ != SQLITE_OK) { cql_error_trace(); goto cql_cleanup; }
  _rc_ = sqlite3_step(_temp_stmt);
  if (_rc_ != SQLITE_ROW && _rc_ != SQLITE_DONE) { cql_error_trace(); goto cql_cleanup; }
  if (_rc_ == SQLITE_ROW) {
    _tmp_int_1 = sqlite3_column_int(_temp_stmt, 0);
    *prev = _tmp_int_1;
  }
  else {
    *prev = 0;
  }
  cql_finalize_stmt(&_temp_stmt);
  _rc_ = SQLITE_OK;

cql_cleanup:
  cql_error_report();
  cql_finalize_stmt(&_temp_stmt);
  return _rc_;
}
#undef _PROC_

// Generated from cql-verify.sql:189

/*
[[private]]
PROC dump_source (line1 INT!, line2 INT!, current_line INT!)
BEGIN
  CURSOR C FOR
    SELECT line, data
      FROM test_input
      WHERE line > line1 AND line <= line2;
  LOOP FETCH C
  BEGIN
    CALL printf("%5s %05d: %s\n", CASE
      WHEN C.line = current_line THEN "FAIL"
      ELSE ""
    END, C.line, C.data);
  END;
END;
*/

#define _PROC_ "dump_source"

typedef struct dump_source_C_row {
  cql_bool _has_row_;
  cql_uint16 _refs_count_;
  cql_uint16 _refs_offset_;
  cql_int32 line;
  cql_string_ref _Nonnull data;
} dump_source_C_row;

#define dump_source_C_refs_offset cql_offsetof(dump_source_C_row, data) // count = 1
static CQL_WARN_UNUSED cql_code dump_source(sqlite3 *_Nonnull _db_, cql_int32 line1, cql_int32 line2, cql_int32 current_line) {
  cql_code _rc_ = SQLITE_OK;
  cql_error_prepare();
  sqlite3_stmt *C_stmt = NULL;
  dump_source_C_row C = { ._refs_count_ = 1, ._refs_offset_ = dump_source_C_refs_offset };
  cql_string_ref _tmp_text_0 = NULL;

  _rc_ = cql_prepare(_db_, &C_stmt,
    "SELECT line, data "
      "FROM test_input "
      "WHERE line > ? AND line <= ?");
  cql_multibind(&_rc_, _db_, &C_stmt, 2,
                CQL_DATA_TYPE_NOT_NULL | CQL_DATA_TYPE_INT32, line1,
                CQL_DATA_TYPE_NOT_NULL | CQL_DATA_TYPE_INT32, line2);
  if (_rc_ != SQLITE_OK) { cql_error_trace(); goto cql_cleanup; }
  for (;;) {
    _rc_ = sqlite3_step(C_stmt);
    C._has_row_ = _rc_ == SQLITE_ROW;
    cql_multifetch(_rc_, C_stmt, 2,
                   CQL_DATA_TYPE_NOT_NULL | CQL_DATA_TYPE_INT32, &C.line,
                   CQL_DATA_TYPE_NOT_NULL | CQL_DATA_TYPE_STRING, &C.data);
    if (_rc_ != SQLITE_ROW && _rc_ != SQLITE_DONE) { cql_error_trace(); goto cql_cleanup; }
    if (!C._has_row_) break;
    do {
      if (C.line == current_line) {
        cql_set_string_ref(&_tmp_text_0, _literal_1_FAIL_dump_source);
        break;
      }
      cql_set_string_ref(&_tmp_text_0, _literal_2_dump_source);
    } while (0);
    cql_alloc_cstr(_cstr_1, _tmp_text_0);
    cql_alloc_cstr(_cstr_2, C.data);
    printf("%5s %05d: %s\n", _cstr_1, C.line, _cstr_2);
    cql_free_cstr(_cstr_1, _tmp_text_0);
    cql_free_cstr(_cstr_2, C.data);
  }
  _rc_ = SQLITE_OK;

cql_cleanup:
  cql_error_report();
  cql_finalize_stmt(&C_stmt);
  cql_teardown_row(C);
  cql_string_release(_tmp_text_0);
  return _rc_;
}
#undef _PROC_

// Generated from cql-verify.sql:213

/*
[[private]]
PROC dump_output (test_output_line INT!, pat TEXT!)
BEGIN
  LET p := ( SELECT "%" || pat || "%" );
  CURSOR C FOR
    SELECT rowid, line, data
      FROM test_results
      WHERE line = test_output_line;
  LOOP FETCH C
  BEGIN
    CALL printf("%3s%s\n", CASE
      WHEN last_rowid = C.rowid THEN ">  "
      WHEN C.data LIKE p THEN "!  "
      ELSE ""
    END, C.data);
  END;
END;
*/

#define _PROC_ "dump_output"

typedef struct dump_output_C_row {
  cql_bool _has_row_;
  cql_uint16 _refs_count_;
  cql_uint16 _refs_offset_;
  cql_int64 rowid;
  cql_int32 line;
  cql_string_ref _Nonnull data;
} dump_output_C_row;

#define dump_output_C_refs_offset cql_offsetof(dump_output_C_row, data) // count = 1
static CQL_WARN_UNUSED cql_code dump_output(sqlite3 *_Nonnull _db_, cql_int32 test_output_line, cql_string_ref _Nonnull pat) {
  cql_code _rc_ = SQLITE_OK;
  cql_error_prepare();
  cql_string_ref p = NULL;
  sqlite3_stmt *_temp_stmt = NULL;
  sqlite3_stmt *C_stmt = NULL;
  dump_output_C_row C = { ._refs_count_ = 1, ._refs_offset_ = dump_output_C_refs_offset };
  cql_string_ref _tmp_text_0 = NULL;

  _rc_ = cql_prepare(_db_, &_temp_stmt,
    "SELECT '%' || ? || '%'");
  cql_multibind(&_rc_, _db_, &_temp_stmt, 1,
                CQL_DATA_TYPE_NOT_NULL | CQL_DATA_TYPE_STRING, pat);
  if (_rc_ != SQLITE_OK) { cql_error_trace(); goto cql_cleanup; }
  _rc_ = sqlite3_step(_temp_stmt);
  if (_rc_ != SQLITE_ROW) { cql_error_trace(); goto cql_cleanup; }
    cql_column_string_ref(_temp_stmt, 0, &p);
  cql_finalize_stmt(&_temp_stmt);
  _rc_ = cql_prepare(_db_, &C_stmt,
    "SELECT rowid, line, data "
      "FROM test_results "
      "WHERE line = ?");
  cql_multibind(&_rc_, _db_, &C_stmt, 1,
                CQL_DATA_TYPE_NOT_NULL | CQL_DATA_TYPE_INT32, test_output_line);
  if (_rc_ != SQLITE_OK) { cql_error_trace(); goto cql_cleanup; }
  for (;;) {
    _rc_ = sqlite3_step(C_stmt);
    C._has_row_ = _rc_ == SQLITE_ROW;
    cql_multifetch(_rc_, C_stmt, 3,
                   CQL_DATA_TYPE_NOT_NULL | CQL_DATA_TYPE_INT64, &C.rowid,
                   CQL_DATA_TYPE_NOT_NULL | CQL_DATA_TYPE_INT32, &C.line,
                   CQL_DATA_TYPE_NOT_NULL | CQL_DATA_TYPE_STRING, &C.data);
    if (_rc_ != SQLITE_ROW && _rc_ != SQLITE_DONE) { cql_error_trace(); goto cql_cleanup; }
    if (!C._has_row_) break;
    do {
      if (last_rowid == C.rowid) {
        cql_set_string_ref(&_tmp_text_0, _literal_3_dump_output);
        break;
      }
      if (cql_string_like(C.data, p) == 0) {
        cql_set_string_ref(&_tmp_text_0, _literal_4_dump_output);
        break;
      }
      cql_set_string_ref(&_tmp_text_0, _literal_2_dump_source);
    } while (0);
    cql_alloc_cstr(_cstr_3, _tmp_text_0);
    cql_alloc_cstr(_cstr_4, C.data);
    printf("%3s%s\n", _cstr_3, _cstr_4);
    cql_free_cstr(_cstr_3, _tmp_text_0);
    cql_free_cstr(_cstr_4, C.data);
  }
  _rc_ = SQLITE_OK;

cql_cleanup:
  cql_error_report();
  cql_string_release(p);
  cql_finalize_stmt(&_temp_stmt);
  cql_finalize_stmt(&C_stmt);
  cql_teardown_row(C);
  cql_string_release(_tmp_text_0);
  return _rc_;
}
#undef _PROC_

// Generated from cql-verify.sql:242

/*
[[private]]
PROC print_fail_details (pat TEXT!, test_output_line INT!, expected INT!)
BEGIN
  LET found := find_count(pat, test_output_line);
  LET details := CASE
    WHEN expected = -2 THEN CASE
      WHEN found > 0 THEN "pattern found but not on the same line (see lines marked with !)"
      ELSE "pattern exists nowhere in test output"
    END
    WHEN expected = -1 THEN CASE
      WHEN found > 0 THEN "pattern exists but only earlier in the results where + doesn't match it"
      ELSE "pattern exists nowhere in test output"
    END
    ELSE printf("pattern occurrences found: %d, expecting: %d (see lines marked with !)", found, expected)
  END;
  CALL printf("\n%s\n\n", details);
END;
*/

#define _PROC_ "print_fail_details"
static CQL_WARN_UNUSED cql_code print_fail_details(sqlite3 *_Nonnull _db_, cql_string_ref _Nonnull pat, cql_int32 test_output_line, cql_int32 expected) {
  cql_code _rc_ = SQLITE_OK;
  cql_error_prepare();
  cql_int32 found = 0;
  cql_string_ref _tmp_text_1 = NULL;
  cql_string_ref details = NULL;

  _rc_ = find_count(_db_, pat, test_output_line, &found);
  if (_rc_ != SQLITE_OK) { cql_error_trace(); goto cql_cleanup; }
  do {
    if (expected == - 2) {
      do {
        if (found > 0) {
          cql_set_string_ref(&_tmp_text_1, _literal_5_pattern_found_but_not_on_the_saprint_fail_details);
          break;
        }
        cql_set_string_ref(&_tmp_text_1, _literal_6_pattern_exists_nowhere_in_test_print_fail_details);
      } while (0);
      cql_set_string_ref(&details, _tmp_text_1);
      break;
    }
    if (expected == - 1) {
      do {
        if (found > 0) {
          cql_set_string_ref(&_tmp_text_1, _literal_7_pattern_exists_but_only_earlierprint_fail_details);
          break;
        }
        cql_set_string_ref(&_tmp_text_1, _literal_6_pattern_exists_nowhere_in_test_print_fail_details);
      } while (0);
      cql_set_string_ref(&details, _tmp_text_1);
      break;
    }
    {
      char *_printf_result = sqlite3_mprintf("pattern occurrences found: %d, expecting: %d (see lines marked with !)", found, expected);
      cql_string_release(_tmp_text_1);
      _tmp_text_1 = cql_string_ref_new(_printf_result);
      sqlite3_free(_printf_result);
    }
    cql_set_string_ref(&details, _tmp_text_1);
  } while (0);
  cql_alloc_cstr(_cstr_5, details);
  printf("\n%s\n\n", _cstr_5);
  cql_free_cstr(_cstr_5, details);
  _rc_ = SQLITE_OK;

cql_cleanup:
  cql_error_report();
  cql_string_release(details);
  cql_string_release(_tmp_text_1);
  return _rc_;
}
#undef _PROC_

// Generated from cql-verify.sql:271

/*
[[private]]
PROC print_error_block (test_output_line INT!, pat TEXT!, expectation_line INT!, expected INT!)
BEGIN
  CALL printf("test results:\n");
  CALL dump_output(test_output_line, pat);
  CALL printf("Line Markings:\n");
  CALL printf("> : the location of the last successful + match.\n");
  CALL printf("! : any lines that match the pattern; count or location is wrong.\n\n");
  LET prev := prev_line(test_output_line);
  CALL printf("\nThe corresponding test case is:\n");
  CALL dump_source(prev, test_output_line, expectation_line);
  CALL print_fail_details(pat, expectation_line, expected);
END;
*/

#define _PROC_ "print_error_block"
static CQL_WARN_UNUSED cql_code print_error_block(sqlite3 *_Nonnull _db_, cql_int32 test_output_line, cql_string_ref _Nonnull pat, cql_int32 expectation_line, cql_int32 expected) {
  cql_code _rc_ = SQLITE_OK;
  cql_error_prepare();
  cql_int32 prev = 0;

  printf("test results:\n");
  _rc_ = dump_output(_db_, test_output_line, pat);
  if (_rc_ != SQLITE_OK) { cql_error_trace(); goto cql_cleanup; }
  printf("Line Markings:\n");
  printf("> : the location of the last successful + match.\n");
  printf("! : any lines that match the pattern; count or location is wrong.\n\n");
  _rc_ = prev_line(_db_, test_output_line, &prev);
  if (_rc_ != SQLITE_OK) { cql_error_trace(); goto cql_cleanup; }
  printf("\nThe corresponding test case is:\n");
  _rc_ = dump_source(_db_, prev, test_output_line, expectation_line);
  if (_rc_ != SQLITE_OK) { cql_error_trace(); goto cql_cleanup; }
  _rc_ = print_fail_details(_db_, pat, expectation_line, expected);
  if (_rc_ != SQLITE_OK) { cql_error_trace(); goto cql_cleanup; }
  _rc_ = SQLITE_OK;

cql_cleanup:
  cql_error_report();
  return _rc_;
}
#undef _PROC_

// Generated from cql-verify.sql:287

/*
[[private]]
PROC match_multiline (buffer TEXT!, OUT result BOOL!)
BEGIN
  SET result := FALSE;
  IF len_text(buffer) < 7 THEN
    RETURN;
  END;
  IF NOT starts_with_text(buffer, "-- +") THEN
    RETURN;
  END;
  LET digit := octet_text(buffer, 4);
  LET space := octet_text(buffer, 5);
  IF space <> 32 THEN
    RETURN;
  END;
  IF digit < 48 OR digit > 48 + 9 THEN
    RETURN;
  END;
  SET result := TRUE;
END;
*/

#define _PROC_ "match_multiline"
static void match_multiline(cql_string_ref _Nonnull buffer, cql_bool *_Nonnull result) {
  cql_int32 _tmp_int_1 = 0;
  cql_bool _tmp_bool_1 = 0;
  cql_int32 digit = 0;
  cql_int32 space = 0;

  *result = 0; // set out arg to non-garbage
  *result = 0;
  _tmp_int_1 = len_text(buffer);
  if (_tmp_int_1 < 7) {
    goto cql_cleanup; // return
  }
  _tmp_bool_1 = starts_with_text(buffer, _literal_8_match_multiline);
  if (! _tmp_bool_1) {
    goto cql_cleanup; // return
  }
  digit = octet_text(buffer, 4);
  space = octet_text(buffer, 5);
  if (space != 32) {
    goto cql_cleanup; // return
  }
  if (digit < 48 || digit > 48 + 9) {
    goto cql_cleanup; // return
  }
  *result = 1;

cql_cleanup:
  ; // label requires some statement
}
#undef _PROC_

// Generated from cql-verify.sql:370

/*
PROC match_actual (buffer TEXT!, expectation_line INT!)
BEGIN
  DECLARE found INT!;
  DECLARE expected INT!;
  DECLARE pattern TEXT;
  IF NOT starts_with_text(buffer, "-- ") THEN
    SET last_rowid := 0;
    RETURN;
  END;
  IF starts_with_text(buffer, "-- TEST:") THEN
    SET tests := tests + 1;
  END;
  IF starts_with_text(buffer, "-- - ") THEN
    SET pattern := after_text(buffer, 5);
    SET expected := 0;
  ELSE IF starts_with_text(buffer, "-- * ") THEN
    SET pattern := after_text(buffer, 5);
    SET expected := 1;
  ELSE IF starts_with_text(buffer, "-- + ") THEN
    SET pattern := after_text(buffer, 5);
    SET expected := -1;
  ELSE IF starts_with_text(buffer, "-- = ") THEN
    SET pattern := after_text(buffer, 5);
    SET expected := -2;
  ELSE IF match_multiline(buffer) THEN
    SET pattern := after_text(buffer, 6);
    SET expected := octet_text(buffer, 4) - 48;
  ELSE
    RETURN;
  END;
  SET attempts := attempts + 1;
  LET pat := ifnull_throw(pattern);
  LET test_output_line := find_test_output_line(expectation_line);
  IF expected = -1 THEN
    SET found := find_next(pat, test_output_line);
    IF found = 1 THEN
      RETURN;
    END;
  ELSE IF expected = -2 THEN
    SET found := find_same(pat);
    IF found = 1 THEN
      RETURN;
    END;
  ELSE
    SET found := find_count(pat, test_output_line);
    IF expected = found THEN
      RETURN;
    END;
  END;
  SET errors := errors + 1;
  CALL print_error_block(test_output_line, pat, expectation_line, expected);
  CALL printf("test file %s:%d\n", sql_file_name, expectation_line);
  CALL printf("result file: %s\n", result_file_name);
  CALL printf("\n");
END;
*/

#define _PROC_ "match_actual"
CQL_WARN_UNUSED cql_code match_actual(sqlite3 *_Nonnull _db_, cql_string_ref _Nonnull buffer, cql_int32 expectation_line) {
  cql_contract_argument_notnull((void *)buffer, 1);

  cql_code _rc_ = SQLITE_OK;
  cql_error_prepare();
  cql_int32 found = 0;
  cql_int32 expected = 0;
  cql_string_ref pattern = NULL;
  cql_bool _tmp_bool_1 = 0;
  cql_bool _tmp_bool_0 = 0;
  cql_int32 _tmp_int_1 = 0;
  cql_string_ref pat = NULL;
  cql_int32 test_output_line = 0;

  _tmp_bool_1 = starts_with_text(buffer, _literal_9_match_actual);
  if (! _tmp_bool_1) {
    last_rowid = 0;
    _rc_ = SQLITE_OK; // clean up any SQLITE_ROW value or other non-error
    goto cql_cleanup; // return
  }
  _tmp_bool_0 = starts_with_text(buffer, _literal_10_TEST_match_actual);
  if (_tmp_bool_0) {
    tests = tests + 1;
  }
  _tmp_bool_0 = starts_with_text(buffer, _literal_11_match_actual);
  if (_tmp_bool_0) {
    cql_set_created_string_ref(&pattern, after_text(buffer, 5));
    expected = 0;
  }
  else {
    _tmp_bool_0 = starts_with_text(buffer, _literal_12_match_actual);
    if (_tmp_bool_0) {
      cql_set_created_string_ref(&pattern, after_text(buffer, 5));
      expected = 1;
    }
    else {
      _tmp_bool_0 = starts_with_text(buffer, _literal_13_match_actual);
      if (_tmp_bool_0) {
        cql_set_created_string_ref(&pattern, after_text(buffer, 5));
        expected = - 1;
      }
      else {
        _tmp_bool_1 = starts_with_text(buffer, _literal_14_match_actual);
        if (_tmp_bool_1) {
          cql_set_created_string_ref(&pattern, after_text(buffer, 5));
          expected = - 2;
        }
        else {
          match_multiline(buffer, &_tmp_bool_1);
          if (_tmp_bool_1) {
            cql_set_created_string_ref(&pattern, after_text(buffer, 6));
            _tmp_int_1 = octet_text(buffer, 4);
            expected = _tmp_int_1 - 48;
          }
          else {
            _rc_ = SQLITE_OK; // clean up any SQLITE_ROW value or other non-error
            goto cql_cleanup; // return
          }
        }
      }
    }
  }
  attempts = attempts + 1;
  if (!pattern) {
    _rc_ = SQLITE_ERROR;
    cql_error_trace();
    goto cql_cleanup;
  }
  cql_set_string_ref(&pat, pattern);
  _rc_ = find_test_output_line(_db_, expectation_line, &test_output_line);
  if (_rc_ != SQLITE_OK) { cql_error_trace(); goto cql_cleanup; }
  if (expected == - 1) {
    _rc_ = find_next(_db_, pat, test_output_line, &found);
    if (_rc_ != SQLITE_OK) { cql_error_trace(); goto cql_cleanup; }
    if (found == 1) {
      _rc_ = SQLITE_OK; // clean up any SQLITE_ROW value or other non-error
      goto cql_cleanup; // return
    }
  }
  else {
    if (expected == - 2) {
      _rc_ = find_same(_db_, pat, &found);
      if (_rc_ != SQLITE_OK) { cql_error_trace(); goto cql_cleanup; }
      if (found == 1) {
        _rc_ = SQLITE_OK; // clean up any SQLITE_ROW value or other non-error
        goto cql_cleanup; // return
      }
    }
    else {
      _rc_ = find_count(_db_, pat, test_output_line, &found);
      if (_rc_ != SQLITE_OK) { cql_error_trace(); goto cql_cleanup; }
      if (expected == found) {
        _rc_ = SQLITE_OK; // clean up any SQLITE_ROW value or other non-error
        goto cql_cleanup; // return
      }
    }
  }
  errors = errors + 1;
  _rc_ = print_error_block(_db_, test_output_line, pat, expectation_line, expected);
  if (_rc_ != SQLITE_OK) { cql_error_trace(); goto cql_cleanup; }
  cql_alloc_cstr(_cstr_6, sql_file_name);
  printf("test file %s:%d\n", _cstr_6, expectation_line);
  cql_free_cstr(_cstr_6, sql_file_name);
  cql_alloc_cstr(_cstr_7, result_file_name);
  printf("result file: %s\n", _cstr_7);
  cql_free_cstr(_cstr_7, result_file_name);
  printf("\n");
  _rc_ = SQLITE_OK;

cql_cleanup:
  cql_error_report();
  cql_string_release(pattern);
  cql_string_release(pat);
  return _rc_;
}
#undef _PROC_

// Generated from cql-verify.sql:381

/*
[[private]]
PROC do_match (buffer TEXT!, expectation_line INT!)
BEGIN
  TRY
    CALL match_actual(buffer, expectation_line);
  CATCH
    CALL printf("unexpected sqlite error\n");
    THROW;
  END;
END;
*/

#define _PROC_ "do_match"
static CQL_WARN_UNUSED cql_code do_match(sqlite3 *_Nonnull _db_, cql_string_ref _Nonnull buffer, cql_int32 expectation_line) {
  cql_code _rc_ = SQLITE_OK;
  cql_error_prepare();

  // try
  {
    _rc_ = match_actual(_db_, buffer, expectation_line);
    if (_rc_ != SQLITE_OK) { cql_error_trace(); goto catch_start_2; }
    goto catch_end_2;
  }
  catch_start_2: {
    int32_t _rc_thrown_1 = _rc_;
    printf("unexpected sqlite error\n");
    _rc_ = cql_best_error(_rc_thrown_1);
    cql_error_trace();
    goto cql_cleanup;
  }
  catch_end_2:;
  _rc_ = SQLITE_OK;

cql_cleanup:
  cql_error_report();
  return _rc_;
}
#undef _PROC_

// Generated from cql-verify.sql:397

/*
[[private]]
PROC process ()
BEGIN
  CURSOR C FOR
    SELECT test_input.line, test_input.data
      FROM test_input;
  LOOP FETCH C
  BEGIN
    CALL do_match(C.data, C.line);
  END;
  CALL printf("Verification results: %d tests matched %d patterns of which %d were errors.\n", tests, attempts, errors);
END;
*/

#define _PROC_ "process"

typedef struct process_C_row {
  cql_bool _has_row_;
  cql_uint16 _refs_count_;
  cql_uint16 _refs_offset_;
  cql_int32 line;
  cql_string_ref _Nonnull data;
} process_C_row;

#define process_C_refs_offset cql_offsetof(process_C_row, data) // count = 1
static CQL_WARN_UNUSED cql_code process(sqlite3 *_Nonnull _db_) {
  cql_code _rc_ = SQLITE_OK;
  cql_error_prepare();
  sqlite3_stmt *C_stmt = NULL;
  process_C_row C = { ._refs_count_ = 1, ._refs_offset_ = process_C_refs_offset };

  _rc_ = cql_prepare(_db_, &C_stmt,
    "SELECT test_input.line, test_input.data "
      "FROM test_input");
  if (_rc_ != SQLITE_OK) { cql_error_trace(); goto cql_cleanup; }
  for (;;) {
    _rc_ = sqlite3_step(C_stmt);
    C._has_row_ = _rc_ == SQLITE_ROW;
    cql_multifetch(_rc_, C_stmt, 2,
                   CQL_DATA_TYPE_NOT_NULL | CQL_DATA_TYPE_INT32, &C.line,
                   CQL_DATA_TYPE_NOT_NULL | CQL_DATA_TYPE_STRING, &C.data);
    if (_rc_ != SQLITE_ROW && _rc_ != SQLITE_DONE) { cql_error_trace(); goto cql_cleanup; }
    if (!C._has_row_) break;
    _rc_ = do_match(_db_, C.data, C.line);
    if (_rc_ != SQLITE_OK) { cql_error_trace(); goto cql_cleanup; }
  }
  printf("Verification results: %d tests matched %d patterns of which %d were errors.\n", tests, attempts, errors);
  _rc_ = SQLITE_OK;

cql_cleanup:
  cql_error_report();
  cql_finalize_stmt(&C_stmt);
  cql_teardown_row(C);
  return _rc_;
}
#undef _PROC_

// Generated from cql-verify.sql:433

/*
[[private]]
PROC read_test_results (result_name TEXT!)
BEGIN
  LET result_file := cql_fopen(result_name, "r");
  IF result_file IS NULL THEN
    CALL printf("unable to open file '%s'\n", result_name);
    THROW;
  END;
  LET line := 0;
  LET key_string := "The statement ending at line ";
  LET len := len_text(key_string);
  WHILE TRUE
  BEGIN
    LET data := readline_object_file(result_file);
    IF data IS NULL THEN
      LEAVE;
    END;
    LET loc := index_of_text(data, key_string);
    IF loc >= 0 THEN
      SET line := atoi_at_text(data, loc + len);
    END;
    INSERT INTO test_results(line, data)
      VALUES (line, data);
  END;
END;
*/

#define _PROC_ "read_test_results"
static CQL_WARN_UNUSED cql_code read_test_results(sqlite3 *_Nonnull _db_, cql_string_ref _Nonnull result_name) {
  cql_code _rc_ = SQLITE_OK;
  cql_error_prepare();
  cql_object_ref result_file = NULL;
  cql_int32 line = 0;
  cql_string_ref key_string = NULL;
  cql_int32 len = 0;
  cql_string_ref data = NULL;
  cql_int32 loc = 0;
  sqlite3_stmt *_temp1_stmt = NULL;

  cql_set_created_object_ref(&result_file, cql_fopen(result_name, _literal_15_r_read_test_results));
  if (!result_file) {
    cql_alloc_cstr(_cstr_8, result_name);
    printf("unable to open file '%s'\n", _cstr_8);
    cql_free_cstr(_cstr_8, result_name);
    _rc_ = cql_best_error(SQLITE_OK);
    cql_error_trace();
    goto cql_cleanup;
  }
  line = 0;
  cql_set_string_ref(&key_string, _literal_16_The_statement_ending_at_line_read_test_results);
  len = len_text(key_string);
  for (;;) {
    if (!(1)) break;
    cql_set_created_string_ref(&data, readline_object_file(result_file));
    if (!data) {
      break;
    }
    loc = index_of_text(data, key_string);
    if (loc >= 0) {
      line = atoi_at_text(data, loc + len);
    }
    if (!_temp1_stmt) {
      _rc_ = cql_prepare(_db_, &_temp1_stmt,
      "INSERT INTO test_results(line, data) "
        "VALUES (?, ?)");
    }
    else {
      _rc_ = SQLITE_OK;
    }
    cql_multibind(&_rc_, _db_, &_temp1_stmt, 2,
                  CQL_DATA_TYPE_NOT_NULL | CQL_DATA_TYPE_INT32, line,
                  CQL_DATA_TYPE_STRING, data);
    if (_rc_ != SQLITE_OK) { cql_error_trace(); goto cql_cleanup; }
    _rc_ = sqlite3_step(_temp1_stmt);
    if (_rc_ != SQLITE_DONE) { cql_error_trace(); goto cql_cleanup; }
    sqlite3_reset(_temp1_stmt);
  }
  _rc_ = SQLITE_OK;

cql_cleanup:
  cql_error_report();
  cql_object_release(result_file);
  cql_string_release(key_string);
  cql_string_release(data);
  cql_finalize_stmt(&_temp1_stmt);
  return _rc_;
}
#undef _PROC_

// Generated from cql-verify.sql:458

/*
[[private]]
PROC read_test_file (sql_name TEXT!)
BEGIN
  LET sql_file := cql_fopen(sql_name, "r");
  IF sql_file IS NULL THEN
    CALL printf("unable to open file '%s'\n", sql_name);
    THROW;
  END;
  LET line := 1;
  WHILE TRUE
  BEGIN
    LET data := readline_object_file(sql_file);
    IF data IS NULL THEN
      LEAVE;
    END;
    INSERT INTO test_input(line, data)
      VALUES (line, data);
    SET line := line + 1;
  END;
END;
*/

#define _PROC_ "read_test_file"
static CQL_WARN_UNUSED cql_code read_test_file(sqlite3 *_Nonnull _db_, cql_string_ref _Nonnull sql_name) {
  cql_code _rc_ = SQLITE_OK;
  cql_error_prepare();
  cql_object_ref sql_file = NULL;
  cql_int32 line = 0;
  cql_string_ref data = NULL;
  sqlite3_stmt *_temp1_stmt = NULL;

  cql_set_created_object_ref(&sql_file, cql_fopen(sql_name, _literal_15_r_read_test_results));
  if (!sql_file) {
    cql_alloc_cstr(_cstr_9, sql_name);
    printf("unable to open file '%s'\n", _cstr_9);
    cql_free_cstr(_cstr_9, sql_name);
    _rc_ = cql_best_error(SQLITE_OK);
    cql_error_trace();
    goto cql_cleanup;
  }
  line = 1;
  for (;;) {
    if (!(1)) break;
    cql_set_created_string_ref(&data, readline_object_file(sql_file));
    if (!data) {
      break;
    }
    if (!_temp1_stmt) {
      _rc_ = cql_prepare(_db_, &_temp1_stmt,
      "INSERT INTO test_input(line, data) "
        "VALUES (?, ?)");
    }
    else {
      _rc_ = SQLITE_OK;
    }
    cql_multibind(&_rc_, _db_, &_temp1_stmt, 2,
                  CQL_DATA_TYPE_NOT_NULL | CQL_DATA_TYPE_INT32, line,
                  CQL_DATA_TYPE_STRING, data);
    if (_rc_ != SQLITE_OK) { cql_error_trace(); goto cql_cleanup; }
    _rc_ = sqlite3_step(_temp1_stmt);
    if (_rc_ != SQLITE_DONE) { cql_error_trace(); goto cql_cleanup; }
    sqlite3_reset(_temp1_stmt);
    line = line + 1;
  }
  _rc_ = SQLITE_OK;

cql_cleanup:
  cql_error_report();
  cql_object_release(sql_file);
  cql_string_release(data);
  cql_finalize_stmt(&_temp1_stmt);
  return _rc_;
}
#undef _PROC_

// Generated from cql-verify.sql:465

/*
[[private]]
PROC load_data (sql_name TEXT!, result_name TEXT!)
BEGIN
  CALL read_test_results(result_name);
  CALL read_test_file(sql_name);
END;
*/

#define _PROC_ "load_data"
static CQL_WARN_UNUSED cql_code load_data(sqlite3 *_Nonnull _db_, cql_string_ref _Nonnull sql_name, cql_string_ref _Nonnull result_name) {
  cql_code _rc_ = SQLITE_OK;
  cql_error_prepare();

  _rc_ = read_test_results(_db_, result_name);
  if (_rc_ != SQLITE_OK) { cql_error_trace(); goto cql_cleanup; }
  _rc_ = read_test_file(_db_, sql_name);
  if (_rc_ != SQLITE_OK) { cql_error_trace(); goto cql_cleanup; }
  _rc_ = SQLITE_OK;

cql_cleanup:
  cql_error_report();
  return _rc_;
}
#undef _PROC_

// Generated from cql-verify.sql:482

/*
[[private]]
PROC parse_args (args OBJECT<cql_string_list>!)
BEGIN
  LET argc := cql_string_list_count(args);
  IF argc <> 3 THEN
    CALL printf("usage cql-verify foo.sql foo.out\n");
    CALL printf("cql-verify is a test tool.  It processes the input foo.sql\n");
    CALL printf("looking for patterns to match in the CQL output foo.out\n");
    RETURN;
  END;
  SET sql_file_name := ifnull_throw(cql_string_list_get_at(args, 1));
  SET result_file_name := ifnull_throw(cql_string_list_get_at(args, 2));
END;
*/

#define _PROC_ "parse_args"
static CQL_WARN_UNUSED cql_code parse_args(sqlite3 *_Nonnull _db_, cql_object_ref _Nonnull args) {
  cql_code _rc_ = SQLITE_OK;
  cql_error_prepare();
  cql_int32 argc = 0;
  cql_string_ref _tmp_n_text_0 = NULL;

  argc = cql_string_list_count(args);
  if (argc != 3) {
    printf("usage cql-verify foo.sql foo.out\n");
    printf("cql-verify is a test tool.  It processes the input foo.sql\n");
    printf("looking for patterns to match in the CQL output foo.out\n");
    _rc_ = SQLITE_OK; // clean up any SQLITE_ROW value or other non-error
    goto cql_cleanup; // return
  }
  cql_set_string_ref(&_tmp_n_text_0, cql_string_list_get_at(args, 1));
  if (!_tmp_n_text_0) {
    _rc_ = SQLITE_ERROR;
    cql_error_trace();
    goto cql_cleanup;
  }
  cql_set_string_ref(&sql_file_name, _tmp_n_text_0);
  cql_set_string_ref(&_tmp_n_text_0, cql_string_list_get_at(args, 2));
  if (!_tmp_n_text_0) {
    _rc_ = SQLITE_ERROR;
    cql_error_trace();
    goto cql_cleanup;
  }
  cql_set_string_ref(&result_file_name, _tmp_n_text_0);
  _rc_ = SQLITE_OK;

cql_cleanup:
  cql_error_report();
  cql_string_release(_tmp_n_text_0);
  return _rc_;
}
#undef _PROC_

// Generated from cql-verify.sql:494

/*
PROC dbhelp_main (args OBJECT<cql_string_list>!)
BEGIN
  CALL setup();
  CALL parse_args(args);
  IF sql_file_name IS NOT NULL AND result_file_name IS NOT NULL THEN
    CALL load_data(sql_file_name, result_file_name);
    CALL process();
  END;
END;
*/

#define _PROC_ "dbhelp_main"
CQL_WARN_UNUSED cql_code dbhelp_main(sqlite3 *_Nonnull _db_, cql_object_ref _Nonnull args) {
  cql_contract_argument_notnull((void *)args, 1);

  cql_code _rc_ = SQLITE_OK;
  cql_error_prepare();

  _rc_ = setup(_db_);
  if (_rc_ != SQLITE_OK) { cql_error_trace(); goto cql_cleanup; }
  _rc_ = parse_args(_db_, args);
  if (_rc_ != SQLITE_OK) { cql_error_trace(); goto cql_cleanup; }
  if (!!sql_file_name && !!result_file_name) {
    _rc_ = load_data(_db_, sql_file_name, result_file_name);
    if (_rc_ != SQLITE_OK) { cql_error_trace(); goto cql_cleanup; }
    _rc_ = process(_db_);
    if (_rc_ != SQLITE_OK) { cql_error_trace(); goto cql_cleanup; }
  }
  _rc_ = SQLITE_OK;

cql_cleanup:
  cql_error_report();
  return _rc_;
}
#undef _PROC_

#include "cqlhelp.h"

// super cheesy error handling

#define E(x) \
  if (SQLITE_OK != (x)) { \
   fprintf(stderr, "error encountered at: %s (%s:%d)\n", #x, __FILE__, __LINE__); \
   fprintf(stderr, "sqlite3_errmsg: %s\n", sqlite3_errmsg(db)); \
   errors = -1; \
   goto error; \
  }

int main(int argc, char **argv) {
  cql_object_ref args = create_arglist(argc, argv);

  sqlite3 *db = NULL;
  E(sqlite3_open(":memory:", &db));
  E(dbhelp_main(db, args));

error:
  if (db) sqlite3_close(db);
  cql_object_release(args);
  exit(errors ? 1 : 0);
}
#pragma clang diagnostic pop
