/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#include "linetest.h"

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
cql_string_literal(_literal_1_exp_dump, "exp");
cql_string_literal(_literal_2_act_dump, "act");
cql_string_literal(_literal_3_define_PROC_read_file, "#define _PROC_ ");
cql_string_literal(_literal_4_undef_PROC_read_file, "#undef _PROC_");
cql_string_literal(_literal_5_line_read_file, "#line ");
cql_string_literal(_literal_6_read_file, "# ");
cql_string_literal(_literal_7_r_read_file, "r");

// Generated from linetest.sql:1

/*
[[builtin]]
DECLARE PROC cql_throw (code INT!) USING TRANSACTION;
*/

// Generated from linetest.sql:1

/*
[[builtin]]
DECLARE PROC cql_cursor_to_blob (C CURSOR, OUT result BLOB!) USING TRANSACTION;
*/

// Generated from linetest.sql:1

/*
[[builtin]]
DECLARE PROC cql_cursor_from_blob (C CURSOR, b BLOB) USING TRANSACTION;
*/

// Generated from linetest.sql:1

/*
[[builtin]]
DECLARE PROC cql_cursor_from_blob_stream (C CURSOR, b BLOB, i INT!) USING TRANSACTION;
*/

//
// This file is auto-generated by linetest.sql, it is checked in just
// in case CQL is broken by a change.  The Last Known Good Verifier
// can be used to verify the tests pass again, or report failures
// while things are still otherwise broken.  Rebuild with regen.sh
//

// enable detailed error tracing
#undef cql_error_trace
#define cql_error_trace() fprintf(stderr, "SQL Failure %d %s: %s %d\n", _rc_, sqlite3_errmsg(_db_), __FILE__, __LINE__)

// Generated from linetest.sql:53

/*
DECLARE proc_count INT!;
*/
cql_int32 proc_count = 0;

// Generated from linetest.sql:54

/*
DECLARE compares INT!;
*/
cql_int32 compares = 0;

// Generated from linetest.sql:55

/*
DECLARE errors INT!;
*/
cql_int32 errors = 0;

// Generated from linetest.sql:56

/*
DECLARE expected_name TEXT;
*/
cql_string_ref expected_name = NULL;

// Generated from linetest.sql:57

/*
DECLARE actual_name TEXT;
*/
cql_string_ref actual_name = NULL;

// Generated from linetest.sql:76

/*
[[private]]
PROC setup ()
BEGIN
  CREATE TABLE linedata(
    source TEXT!,
    procname TEXT!,
    line INT!,
    data TEXT!,
    physical_line INT!
  );
  CREATE TABLE procs(
    procname TEXT! PRIMARY KEY
  );
  CREATE INDEX __idx__test_lines ON linedata (source, procname);
END;
*/

#define _PROC_ "setup"
static CQL_WARN_UNUSED cql_code setup(sqlite3 *_Nonnull _db_) {
  cql_code _rc_ = SQLITE_OK;
  cql_error_prepare();

  _rc_ = cql_exec(_db_,
    "CREATE TABLE linedata( "
      "source TEXT NOT NULL, "
      "procname TEXT NOT NULL, "
      "line INTEGER NOT NULL, "
      "data TEXT NOT NULL, "
      "physical_line INTEGER NOT NULL "
    ")");
  if (_rc_ != SQLITE_OK) { cql_error_trace(); goto cql_cleanup; }
  _rc_ = cql_exec(_db_,
    "CREATE TABLE procs( "
      "procname TEXT NOT NULL PRIMARY KEY "
    ")");
  if (_rc_ != SQLITE_OK) { cql_error_trace(); goto cql_cleanup; }
  _rc_ = cql_exec(_db_,
    "CREATE INDEX __idx__test_lines ON linedata (source, procname)");
  if (_rc_ != SQLITE_OK) { cql_error_trace(); goto cql_cleanup; }
  _rc_ = SQLITE_OK;

cql_cleanup:
  cql_error_report();
  return _rc_;
}
#undef _PROC_

// Generated from linetest.sql:85

/*
[[private]]
PROC add_linedata (source_ TEXT!, procname_ TEXT!, line_ INT!, data_ TEXT!, physical_line_ INT!)
BEGIN
  INSERT INTO linedata(source, procname, line, data, physical_line) VALUES (source_, procname_, line_, data_, physical_line_);
  INSERT OR IGNORE INTO procs(procname) VALUES (procname_);
END;
*/

#define _PROC_ "add_linedata"
static CQL_WARN_UNUSED cql_code add_linedata(sqlite3 *_Nonnull _db_, cql_string_ref _Nonnull source_, cql_string_ref _Nonnull procname_, cql_int32 line_, cql_string_ref _Nonnull data_, cql_int32 physical_line_) {
  cql_code _rc_ = SQLITE_OK;
  cql_error_prepare();
  sqlite3_stmt *_temp_stmt = NULL;

  _rc_ = cql_prepare(_db_, &_temp_stmt,
    "INSERT INTO linedata(source, procname, line, data, physical_line) VALUES (?, ?, ?, ?, ?)");
  cql_multibind(&_rc_, _db_, &_temp_stmt, 5,
                CQL_DATA_TYPE_NOT_NULL | CQL_DATA_TYPE_STRING, source_,
                CQL_DATA_TYPE_NOT_NULL | CQL_DATA_TYPE_STRING, procname_,
                CQL_DATA_TYPE_NOT_NULL | CQL_DATA_TYPE_INT32, line_,
                CQL_DATA_TYPE_NOT_NULL | CQL_DATA_TYPE_STRING, data_,
                CQL_DATA_TYPE_NOT_NULL | CQL_DATA_TYPE_INT32, physical_line_);
  if (_rc_ != SQLITE_OK) { cql_error_trace(); goto cql_cleanup; }
  _rc_ = sqlite3_step(_temp_stmt);
  if (_rc_ != SQLITE_DONE) { cql_error_trace(); goto cql_cleanup; }
  cql_finalize_stmt(&_temp_stmt);
  _rc_ = cql_prepare(_db_, &_temp_stmt,
    "INSERT OR IGNORE INTO procs(procname) VALUES (?)");
  cql_multibind(&_rc_, _db_, &_temp_stmt, 1,
                CQL_DATA_TYPE_NOT_NULL | CQL_DATA_TYPE_STRING, procname_);
  if (_rc_ != SQLITE_OK) { cql_error_trace(); goto cql_cleanup; }
  _rc_ = sqlite3_step(_temp_stmt);
  if (_rc_ != SQLITE_DONE) { cql_error_trace(); goto cql_cleanup; }
  cql_finalize_stmt(&_temp_stmt);
  _rc_ = SQLITE_OK;

cql_cleanup:
  cql_error_report();
  cql_finalize_stmt(&_temp_stmt);
  return _rc_;
}
#undef _PROC_

// Generated from linetest.sql:96

/*
[[private]]
PROC dump_proc_records (source_ TEXT!, procname_ TEXT!)
BEGIN
  CURSOR C FOR
    SELECT
        linedata.source,
        linedata.procname,
        linedata.line,
        linedata.data,
        linedata.physical_line
      FROM linedata
      WHERE procname = procname_ AND source = source_;
  LOOP FETCH C
  BEGIN
    CALL printf("%5d %s\n", C.line, C.data);
  END;
END;
*/

#define _PROC_ "dump_proc_records"

typedef struct dump_proc_records_C_row {
  cql_bool _has_row_;
  cql_uint16 _refs_count_;
  cql_uint16 _refs_offset_;
  cql_int32 line;
  cql_int32 physical_line;
  cql_string_ref _Nonnull source;
  cql_string_ref _Nonnull procname;
  cql_string_ref _Nonnull data;
} dump_proc_records_C_row;

#define dump_proc_records_C_refs_offset cql_offsetof(dump_proc_records_C_row, source) // count = 3
static CQL_WARN_UNUSED cql_code dump_proc_records(sqlite3 *_Nonnull _db_, cql_string_ref _Nonnull source_, cql_string_ref _Nonnull procname_) {
  cql_code _rc_ = SQLITE_OK;
  cql_error_prepare();
  sqlite3_stmt *C_stmt = NULL;
  dump_proc_records_C_row C = { ._refs_count_ = 3, ._refs_offset_ = dump_proc_records_C_refs_offset };

  _rc_ = cql_prepare(_db_, &C_stmt,
    "SELECT "
        "linedata.source, "
        "linedata.procname, "
        "linedata.line, "
        "linedata.data, "
        "linedata.physical_line "
      "FROM linedata "
      "WHERE procname = ? AND source = ?");
  cql_multibind(&_rc_, _db_, &C_stmt, 2,
                CQL_DATA_TYPE_NOT_NULL | CQL_DATA_TYPE_STRING, procname_,
                CQL_DATA_TYPE_NOT_NULL | CQL_DATA_TYPE_STRING, source_);
  if (_rc_ != SQLITE_OK) { cql_error_trace(); goto cql_cleanup; }
  for (;;) {
    _rc_ = sqlite3_step(C_stmt);
    C._has_row_ = _rc_ == SQLITE_ROW;
    cql_multifetch(_rc_, C_stmt, 5,
                   CQL_DATA_TYPE_NOT_NULL | CQL_DATA_TYPE_STRING, &C.source,
                   CQL_DATA_TYPE_NOT_NULL | CQL_DATA_TYPE_STRING, &C.procname,
                   CQL_DATA_TYPE_NOT_NULL | CQL_DATA_TYPE_INT32, &C.line,
                   CQL_DATA_TYPE_NOT_NULL | CQL_DATA_TYPE_STRING, &C.data,
                   CQL_DATA_TYPE_NOT_NULL | CQL_DATA_TYPE_INT32, &C.physical_line);
    if (_rc_ != SQLITE_ROW && _rc_ != SQLITE_DONE) { cql_error_trace(); goto cql_cleanup; }
    if (!C._has_row_) break;
    cql_alloc_cstr(_cstr_1, C.data);
    printf("%5d %s\n", C.line, _cstr_1);
    cql_free_cstr(_cstr_1, C.data);
  }
  _rc_ = SQLITE_OK;

cql_cleanup:
  cql_error_report();
  cql_finalize_stmt(&C_stmt);
  cql_teardown_row(C);
  return _rc_;
}
#undef _PROC_

// Generated from linetest.sql:107

/*
[[private]]
PROC dump (procname TEXT!)
BEGIN
  CALL printf("%s: difference encountered\n", procname);
  CALL printf("<<<< EXPECTED\n");
  CALL dump_proc_records("exp", procname);
  CALL printf(">>>> ACTUAL\n");
  CALL dump_proc_records("act", procname);
END;
*/

#define _PROC_ "dump"
static CQL_WARN_UNUSED cql_code dump(sqlite3 *_Nonnull _db_, cql_string_ref _Nonnull procname) {
  cql_code _rc_ = SQLITE_OK;
  cql_error_prepare();

  cql_alloc_cstr(_cstr_2, procname);
  printf("%s: difference encountered\n", _cstr_2);
  cql_free_cstr(_cstr_2, procname);
  printf("<<<< EXPECTED\n");
  _rc_ = dump_proc_records(_db_, _literal_1_exp_dump, procname);
  if (_rc_ != SQLITE_OK) { cql_error_trace(); goto cql_cleanup; }
  printf(">>>> ACTUAL\n");
  _rc_ = dump_proc_records(_db_, _literal_2_act_dump, procname);
  if (_rc_ != SQLITE_OK) { cql_error_trace(); goto cql_cleanup; }
  _rc_ = SQLITE_OK;

cql_cleanup:
  cql_error_report();
  return _rc_;
}
#undef _PROC_

// Generated from linetest.sql:166

/*
[[private]]
PROC compare_lines ()
BEGIN
  CURSOR p FOR
    SELECT procs.procname
      FROM procs;
  LOOP FETCH p
  BEGIN
    SET proc_count := proc_count + 1;
    CURSOR actual FOR
      SELECT
          linedata.source,
          linedata.procname,
          linedata.line,
          linedata.data,
          linedata.physical_line
        FROM linedata
        WHERE source = 'act' AND procname = p.procname;
    CURSOR expected FOR
      SELECT
          linedata.source,
          linedata.procname,
          linedata.line,
          linedata.data,
          linedata.physical_line
        FROM linedata
        WHERE source = 'exp' AND procname = p.procname;
    FETCH actual;
    FETCH expected;
    WHILE actual AND expected
    BEGIN
      SET compares := compares + 1;
      IF actual.line <> expected.line OR actual.data <> expected.data THEN
        CALL dump(p.procname);
        CALL printf("\nFirst difference:\n");
        CALL printf("expected: %5d %s\n", expected.line, expected.data);
        CALL printf("  actual: %5d %s\n", actual.line, actual.data);
        CALL printf("\nDifferences at:\n line %d in expected\n line %d in actual", expected.physical_line, actual.physical_line);
        CALL printf("\n");
        SET errors := errors + 1;
        LEAVE;
      END;
      FETCH actual;
      FETCH expected;
    END;
    IF actual <> expected THEN
      IF NOT actual THEN
        CALL dump(p.procname);
        CALL printf("\nRan out of lines in actual:\n");
        CALL printf("\nDifferences at:\n line %d in expected\n", expected.physical_line);
        CALL printf("\n");
        SET errors := errors + 1;
      END;
      IF NOT expected THEN
        CALL dump(p.procname);
        CALL printf("\nRan out of lines in expected:\n");
        CALL printf("\nDifferences at:\n line %d in actual\n", actual.physical_line);
        CALL printf("\n");
        SET errors := errors + 1;
      END;
    END;
  END;
END;
*/

#define _PROC_ "compare_lines"

typedef struct compare_lines_p_row {
  cql_bool _has_row_;
  cql_uint16 _refs_count_;
  cql_uint16 _refs_offset_;
  cql_string_ref _Nonnull procname;
} compare_lines_p_row;

#define compare_lines_p_refs_offset cql_offsetof(compare_lines_p_row, procname) // count = 1

typedef struct compare_lines_actual_row {
  cql_bool _has_row_;
  cql_uint16 _refs_count_;
  cql_uint16 _refs_offset_;
  cql_int32 line;
  cql_int32 physical_line;
  cql_string_ref _Nonnull source;
  cql_string_ref _Nonnull procname;
  cql_string_ref _Nonnull data;
} compare_lines_actual_row;

#define compare_lines_actual_refs_offset cql_offsetof(compare_lines_actual_row, source) // count = 3

typedef struct compare_lines_expected_row {
  cql_bool _has_row_;
  cql_uint16 _refs_count_;
  cql_uint16 _refs_offset_;
  cql_int32 line;
  cql_int32 physical_line;
  cql_string_ref _Nonnull source;
  cql_string_ref _Nonnull procname;
  cql_string_ref _Nonnull data;
} compare_lines_expected_row;

#define compare_lines_expected_refs_offset cql_offsetof(compare_lines_expected_row, source) // count = 3
static CQL_WARN_UNUSED cql_code compare_lines(sqlite3 *_Nonnull _db_) {
  cql_code _rc_ = SQLITE_OK;
  cql_error_prepare();
  sqlite3_stmt *p_stmt = NULL;
  compare_lines_p_row p = { ._refs_count_ = 1, ._refs_offset_ = compare_lines_p_refs_offset };
  sqlite3_stmt *actual_stmt = NULL;
  compare_lines_actual_row actual = { ._refs_count_ = 3, ._refs_offset_ = compare_lines_actual_refs_offset };
  sqlite3_stmt *expected_stmt = NULL;
  compare_lines_expected_row expected = { ._refs_count_ = 3, ._refs_offset_ = compare_lines_expected_refs_offset };

  _rc_ = cql_prepare(_db_, &p_stmt,
    "SELECT procs.procname "
      "FROM procs");
  if (_rc_ != SQLITE_OK) { cql_error_trace(); goto cql_cleanup; }
  for (;;) {
    _rc_ = sqlite3_step(p_stmt);
    p._has_row_ = _rc_ == SQLITE_ROW;
    cql_multifetch(_rc_, p_stmt, 1,
                   CQL_DATA_TYPE_NOT_NULL | CQL_DATA_TYPE_STRING, &p.procname);
    if (_rc_ != SQLITE_ROW && _rc_ != SQLITE_DONE) { cql_error_trace(); goto cql_cleanup; }
    if (!p._has_row_) break;
    proc_count = proc_count + 1;
    cql_finalize_stmt(&actual_stmt);
    _rc_ = cql_prepare(_db_, &actual_stmt,
      "SELECT "
          "linedata.source, "
          "linedata.procname, "
          "linedata.line, "
          "linedata.data, "
          "linedata.physical_line "
        "FROM linedata "
        "WHERE source = 'act' AND procname = ?");
    cql_multibind(&_rc_, _db_, &actual_stmt, 1,
                  CQL_DATA_TYPE_NOT_NULL | CQL_DATA_TYPE_STRING, p.procname);
    if (_rc_ != SQLITE_OK) { cql_error_trace(); goto cql_cleanup; }
    cql_finalize_stmt(&expected_stmt);
    _rc_ = cql_prepare(_db_, &expected_stmt,
      "SELECT "
          "linedata.source, "
          "linedata.procname, "
          "linedata.line, "
          "linedata.data, "
          "linedata.physical_line "
        "FROM linedata "
        "WHERE source = 'exp' AND procname = ?");
    cql_multibind(&_rc_, _db_, &expected_stmt, 1,
                  CQL_DATA_TYPE_NOT_NULL | CQL_DATA_TYPE_STRING, p.procname);
    if (_rc_ != SQLITE_OK) { cql_error_trace(); goto cql_cleanup; }
    _rc_ = sqlite3_step(actual_stmt);
    actual._has_row_ = _rc_ == SQLITE_ROW;
    cql_multifetch(_rc_, actual_stmt, 5,
                   CQL_DATA_TYPE_NOT_NULL | CQL_DATA_TYPE_STRING, &actual.source,
                   CQL_DATA_TYPE_NOT_NULL | CQL_DATA_TYPE_STRING, &actual.procname,
                   CQL_DATA_TYPE_NOT_NULL | CQL_DATA_TYPE_INT32, &actual.line,
                   CQL_DATA_TYPE_NOT_NULL | CQL_DATA_TYPE_STRING, &actual.data,
                   CQL_DATA_TYPE_NOT_NULL | CQL_DATA_TYPE_INT32, &actual.physical_line);
    if (_rc_ != SQLITE_ROW && _rc_ != SQLITE_DONE) { cql_error_trace(); goto cql_cleanup; }
    _rc_ = sqlite3_step(expected_stmt);
    expected._has_row_ = _rc_ == SQLITE_ROW;
    cql_multifetch(_rc_, expected_stmt, 5,
                   CQL_DATA_TYPE_NOT_NULL | CQL_DATA_TYPE_STRING, &expected.source,
                   CQL_DATA_TYPE_NOT_NULL | CQL_DATA_TYPE_STRING, &expected.procname,
                   CQL_DATA_TYPE_NOT_NULL | CQL_DATA_TYPE_INT32, &expected.line,
                   CQL_DATA_TYPE_NOT_NULL | CQL_DATA_TYPE_STRING, &expected.data,
                   CQL_DATA_TYPE_NOT_NULL | CQL_DATA_TYPE_INT32, &expected.physical_line);
    if (_rc_ != SQLITE_ROW && _rc_ != SQLITE_DONE) { cql_error_trace(); goto cql_cleanup; }
    for (;;) {
      if (!(actual._has_row_ && expected._has_row_)) break;
      compares = compares + 1;
      if (actual.line != expected.line || cql_string_compare(actual.data, expected.data) != 0) {
        _rc_ = dump(_db_, p.procname);
        if (_rc_ != SQLITE_OK) { cql_error_trace(); goto cql_cleanup; }
        printf("\nFirst difference:\n");
        cql_alloc_cstr(_cstr_3, expected.data);
        printf("expected: %5d %s\n", expected.line, _cstr_3);
        cql_free_cstr(_cstr_3, expected.data);
        cql_alloc_cstr(_cstr_4, actual.data);
        printf("  actual: %5d %s\n", actual.line, _cstr_4);
        cql_free_cstr(_cstr_4, actual.data);
        printf("\nDifferences at:\n line %d in expected\n line %d in actual", expected.physical_line, actual.physical_line);
        printf("\n");
        errors = errors + 1;
        break;
      }
      _rc_ = sqlite3_step(actual_stmt);
      actual._has_row_ = _rc_ == SQLITE_ROW;
      cql_multifetch(_rc_, actual_stmt, 5,
                     CQL_DATA_TYPE_NOT_NULL | CQL_DATA_TYPE_STRING, &actual.source,
                     CQL_DATA_TYPE_NOT_NULL | CQL_DATA_TYPE_STRING, &actual.procname,
                     CQL_DATA_TYPE_NOT_NULL | CQL_DATA_TYPE_INT32, &actual.line,
                     CQL_DATA_TYPE_NOT_NULL | CQL_DATA_TYPE_STRING, &actual.data,
                     CQL_DATA_TYPE_NOT_NULL | CQL_DATA_TYPE_INT32, &actual.physical_line);
      if (_rc_ != SQLITE_ROW && _rc_ != SQLITE_DONE) { cql_error_trace(); goto cql_cleanup; }
      _rc_ = sqlite3_step(expected_stmt);
      expected._has_row_ = _rc_ == SQLITE_ROW;
      cql_multifetch(_rc_, expected_stmt, 5,
                     CQL_DATA_TYPE_NOT_NULL | CQL_DATA_TYPE_STRING, &expected.source,
                     CQL_DATA_TYPE_NOT_NULL | CQL_DATA_TYPE_STRING, &expected.procname,
                     CQL_DATA_TYPE_NOT_NULL | CQL_DATA_TYPE_INT32, &expected.line,
                     CQL_DATA_TYPE_NOT_NULL | CQL_DATA_TYPE_STRING, &expected.data,
                     CQL_DATA_TYPE_NOT_NULL | CQL_DATA_TYPE_INT32, &expected.physical_line);
      if (_rc_ != SQLITE_ROW && _rc_ != SQLITE_DONE) { cql_error_trace(); goto cql_cleanup; }
    }
    if (actual._has_row_ != expected._has_row_) {
      if (! actual._has_row_) {
        _rc_ = dump(_db_, p.procname);
        if (_rc_ != SQLITE_OK) { cql_error_trace(); goto cql_cleanup; }
        printf("\nRan out of lines in actual:\n");
        printf("\nDifferences at:\n line %d in expected\n", expected.physical_line);
        printf("\n");
        errors = errors + 1;
      }
      if (! expected._has_row_) {
        _rc_ = dump(_db_, p.procname);
        if (_rc_ != SQLITE_OK) { cql_error_trace(); goto cql_cleanup; }
        printf("\nRan out of lines in expected:\n");
        printf("\nDifferences at:\n line %d in actual\n", actual.physical_line);
        printf("\n");
        errors = errors + 1;
      }
    }
  }
  _rc_ = SQLITE_OK;

cql_cleanup:
  cql_error_report();
  cql_finalize_stmt(&p_stmt);
  cql_teardown_row(p);
  cql_finalize_stmt(&actual_stmt);
  cql_teardown_row(actual);
  cql_finalize_stmt(&expected_stmt);
  cql_teardown_row(expected);
  return _rc_;
}
#undef _PROC_

// Generated from linetest.sql:269

/*
[[private]]
PROC read_file (input_name TEXT!, source TEXT!)
BEGIN
  LET proc_start_prefix := '#define _PROC_ ';
  LET proc_undef_prefix := '#undef _PROC_';
  LET line_directive_prefix := '#line ';
  LET short_line_directive_prefix := '# ';
  LET proc_start_prefix_len := len_text(proc_start_prefix);
  LET proc_undef_prefix_len := len_text(proc_undef_prefix);
  LET line_directive_prefix_len := len_text(line_directive_prefix);
  LET short_line_directive_prefix_len := len_text(short_line_directive_prefix);
  LET input_file := cql_fopen(input_name, "r");
  IF input_file IS NULL THEN
    CALL printf("unable to open file '%s'\n", input_name);
    THROW;
  END;
  LET base_at_next_line := FALSE;
  LET line := 0;
  LET line_base := 0;
  LET physical_line := 0;
  DECLARE procname TEXT;
  WHILE TRUE
  BEGIN
    LET data := readline_object_file(input_file);
    IF data IS NULL THEN
      LEAVE;
    END;
    SET physical_line := physical_line + 1;
    IF starts_with_text(data, proc_start_prefix) THEN
      SET procname := after_text(data, proc_start_prefix_len);
      SET base_at_next_line := TRUE;
      SET line := 0;
    END;
    IF starts_with_text(data, proc_undef_prefix) THEN
      SET procname := NULL;
      SET line := 0;
      SET line_base := 0;
    END;
    LET line_start := -1;
    LET line_directive_position := index_of_text(data, line_directive_prefix);
    IF line_directive_position >= 0 THEN
      SET line_start := line_directive_position + line_directive_prefix_len;
    END;
    LET short_line_directive_position := index_of_text(data, short_line_directive_prefix);
    IF short_line_directive_position >= 0 THEN
      SET line_start := short_line_directive_position + short_line_directive_prefix_len;
    END;
    IF line_start >= 0 THEN
      SET line := atoi_at_text(data, line_start);
      IF base_at_next_line THEN
        SET line_base := line - 1;
        SET base_at_next_line := FALSE;
      END;
      SET line := line - line_base;
      CONTINUE;
    END;
    IF procname IS NULL THEN
      CONTINUE;
    END;
    CALL add_linedata(source, procname, line, data, physical_line);
  END;
END;
*/

#define _PROC_ "read_file"
static CQL_WARN_UNUSED cql_code read_file(sqlite3 *_Nonnull _db_, cql_string_ref _Nonnull input_name, cql_string_ref _Nonnull source) {
  cql_code _rc_ = SQLITE_OK;
  cql_error_prepare();
  cql_string_ref proc_start_prefix = NULL;
  cql_string_ref proc_undef_prefix = NULL;
  cql_string_ref line_directive_prefix = NULL;
  cql_string_ref short_line_directive_prefix = NULL;
  cql_int32 proc_start_prefix_len = 0;
  cql_int32 proc_undef_prefix_len = 0;
  cql_int32 line_directive_prefix_len = 0;
  cql_int32 short_line_directive_prefix_len = 0;
  cql_object_ref input_file = NULL;
  cql_bool base_at_next_line = 0;
  cql_int32 line = 0;
  cql_int32 line_base = 0;
  cql_int32 physical_line = 0;
  cql_string_ref procname = NULL;
  cql_bool _tmp_bool_0 = 0;
  cql_string_ref data = NULL;
  cql_int32 line_start = 0;
  cql_int32 line_directive_position = 0;
  cql_int32 short_line_directive_position = 0;

  cql_set_string_ref(&proc_start_prefix, _literal_3_define_PROC_read_file);
  cql_set_string_ref(&proc_undef_prefix, _literal_4_undef_PROC_read_file);
  cql_set_string_ref(&line_directive_prefix, _literal_5_line_read_file);
  cql_set_string_ref(&short_line_directive_prefix, _literal_6_read_file);
  proc_start_prefix_len = len_text(proc_start_prefix);
  proc_undef_prefix_len = len_text(proc_undef_prefix);
  line_directive_prefix_len = len_text(line_directive_prefix);
  short_line_directive_prefix_len = len_text(short_line_directive_prefix);
  cql_set_created_object_ref(&input_file, cql_fopen(input_name, _literal_7_r_read_file));
  if (!input_file) {
    cql_alloc_cstr(_cstr_5, input_name);
    printf("unable to open file '%s'\n", _cstr_5);
    cql_free_cstr(_cstr_5, input_name);
    _rc_ = cql_best_error(SQLITE_OK);
    cql_error_trace();
    goto cql_cleanup;
  }
  base_at_next_line = 0;
  line = 0;
  line_base = 0;
  physical_line = 0;
  for (;;) {
    if (!(1)) break;
    cql_set_created_string_ref(&data, readline_object_file(input_file));
    if (!data) {
      break;
    }
    physical_line = physical_line + 1;
    _tmp_bool_0 = starts_with_text(data, proc_start_prefix);
    if (_tmp_bool_0) {
      cql_set_created_string_ref(&procname, after_text(data, proc_start_prefix_len));
      base_at_next_line = 1;
      line = 0;
    }
    _tmp_bool_0 = starts_with_text(data, proc_undef_prefix);
    if (_tmp_bool_0) {
      cql_set_string_ref(&procname, NULL);
      line = 0;
      line_base = 0;
    }
    line_start = - 1;
    line_directive_position = index_of_text(data, line_directive_prefix);
    if (line_directive_position >= 0) {
      line_start = line_directive_position + line_directive_prefix_len;
    }
    short_line_directive_position = index_of_text(data, short_line_directive_prefix);
    if (short_line_directive_position >= 0) {
      line_start = short_line_directive_position + short_line_directive_prefix_len;
    }
    if (line_start >= 0) {
      line = atoi_at_text(data, line_start);
      if (base_at_next_line) {
        line_base = line - 1;
        base_at_next_line = 0;
      }
      line = line - line_base;
      continue;
    }
    if (!procname) {
      continue;
    }
    _rc_ = add_linedata(_db_, source, procname, line, data, physical_line);
    if (_rc_ != SQLITE_OK) { cql_error_trace(); goto cql_cleanup; }
  }
  _rc_ = SQLITE_OK;

cql_cleanup:
  cql_error_report();
  cql_string_release(proc_start_prefix);
  cql_string_release(proc_undef_prefix);
  cql_string_release(line_directive_prefix);
  cql_string_release(short_line_directive_prefix);
  cql_object_release(input_file);
  cql_string_release(procname);
  cql_string_release(data);
  return _rc_;
}
#undef _PROC_

// Generated from linetest.sql:287

/*
[[private]]
PROC parse_args (args OBJECT<cql_string_list>!)
BEGIN
  LET argc := cql_string_list_count(args);
  IF argc <> 3 THEN
    CALL printf("usage cql-linetest expected actual\n");
    CALL printf("cql-linetest is a test tool.  It processes the input files\n");
    CALL printf("normalizing the lines to the start of each procedure\n");
    CALL printf("and verifies that the line numbers are as expected\n");
    RETURN;
  END;
  SET expected_name := ifnull_throw(cql_string_list_get_at(args, 1));
  SET actual_name := ifnull_throw(cql_string_list_get_at(args, 2));
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
    printf("usage cql-linetest expected actual\n");
    printf("cql-linetest is a test tool.  It processes the input files\n");
    printf("normalizing the lines to the start of each procedure\n");
    printf("and verifies that the line numbers are as expected\n");
    _rc_ = SQLITE_OK; // clean up any SQLITE_ROW value or other non-error
    goto cql_cleanup; // return
  }
  cql_set_string_ref(&_tmp_n_text_0, cql_string_list_get_at(args, 1));
  if (!_tmp_n_text_0) {
    _rc_ = SQLITE_ERROR;
    cql_error_trace();
    goto cql_cleanup;
  }
  cql_set_string_ref(&expected_name, _tmp_n_text_0);
  cql_set_string_ref(&_tmp_n_text_0, cql_string_list_get_at(args, 2));
  if (!_tmp_n_text_0) {
    _rc_ = SQLITE_ERROR;
    cql_error_trace();
    goto cql_cleanup;
  }
  cql_set_string_ref(&actual_name, _tmp_n_text_0);
  _rc_ = SQLITE_OK;

cql_cleanup:
  cql_error_report();
  cql_string_release(_tmp_n_text_0);
  return _rc_;
}
#undef _PROC_

// Generated from linetest.sql:312

/*
PROC linetest_main (args OBJECT<cql_string_list>!)
BEGIN
  CALL setup();
  CALL parse_args(args);
  IF expected_name IS NULL THEN
    RETURN;
  END;
  CALL read_file(expected_name, "exp");
  IF actual_name IS NULL THEN
    RETURN;
  END;
  CALL read_file(actual_name, "act");
  CALL compare_lines();
  CALL printf("\n");
  IF errors THEN
    CALL printf("EXPECTED INPUT FILE: %s\n", expected_name);
    CALL printf("  ACTUAL INPUT FILE: %s\n", actual_name);
  END;
  CALL printf("Verification results: %d procedures matched %d patterns of which %d were errors.\n", proc_count, compares, errors);
END;
*/

#define _PROC_ "linetest_main"
CQL_WARN_UNUSED cql_code linetest_main(sqlite3 *_Nonnull _db_, cql_object_ref _Nonnull args) {
  cql_contract_argument_notnull((void *)args, 1);

  cql_code _rc_ = SQLITE_OK;
  cql_error_prepare();

  _rc_ = setup(_db_);
  if (_rc_ != SQLITE_OK) { cql_error_trace(); goto cql_cleanup; }
  _rc_ = parse_args(_db_, args);
  if (_rc_ != SQLITE_OK) { cql_error_trace(); goto cql_cleanup; }
  if (!expected_name) {
    _rc_ = SQLITE_OK; // clean up any SQLITE_ROW value or other non-error
    goto cql_cleanup; // return
  }
  _rc_ = read_file(_db_, expected_name, _literal_1_exp_dump);
  if (_rc_ != SQLITE_OK) { cql_error_trace(); goto cql_cleanup; }
  if (!actual_name) {
    _rc_ = SQLITE_OK; // clean up any SQLITE_ROW value or other non-error
    goto cql_cleanup; // return
  }
  _rc_ = read_file(_db_, actual_name, _literal_2_act_dump);
  if (_rc_ != SQLITE_OK) { cql_error_trace(); goto cql_cleanup; }
  _rc_ = compare_lines(_db_);
  if (_rc_ != SQLITE_OK) { cql_error_trace(); goto cql_cleanup; }
  printf("\n");
  if (errors) {
    cql_alloc_cstr(_cstr_6, expected_name);
    printf("EXPECTED INPUT FILE: %s\n", _cstr_6);
    cql_free_cstr(_cstr_6, expected_name);
    cql_alloc_cstr(_cstr_7, actual_name);
    printf("  ACTUAL INPUT FILE: %s\n", _cstr_7);
    cql_free_cstr(_cstr_7, actual_name);
  }
  printf("Verification results: %d procedures matched %d patterns of which %d were errors.\n", proc_count, compares, errors);
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
  E(linetest_main(db, args));

error:
  if (db) sqlite3_close(db);
  cql_object_release(args);
  exit(errors ? 1 : 0);
}
#pragma clang diagnostic pop
