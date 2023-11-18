/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */
#pragma once

#include "cqlrt.h"


// Generated from linetest.sql:35
extern cql_int32 proc_count;

// Generated from linetest.sql:36
extern cql_int32 compares;

// Generated from linetest.sql:37
extern cql_int32 errors;

// Generated from linetest.sql:38
extern cql_string_ref _Nullable expected_name;

// Generated from linetest.sql:39
extern cql_string_ref _Nullable actual_name;

// Generated from linetest.sql:57
// static CQL_WARN_UNUSED cql_code setup(sqlite3 *_Nonnull _db_);

// Generated from linetest.sql:65
// static CQL_WARN_UNUSED cql_code add_linedata(sqlite3 *_Nonnull _db_, cql_string_ref _Nonnull source_, cql_string_ref _Nonnull procname_, cql_int32 line_, cql_string_ref _Nonnull data_, cql_int32 physical_line_);

// Generated from linetest.sql:75
// static CQL_WARN_UNUSED cql_code dump_proc_records(sqlite3 *_Nonnull _db_, cql_string_ref _Nonnull source_, cql_string_ref _Nonnull procname_);

// Generated from linetest.sql:85
// static CQL_WARN_UNUSED cql_code dump(sqlite3 *_Nonnull _db_, cql_string_ref _Nonnull procname);

// Generated from linetest.sql:144
// static CQL_WARN_UNUSED cql_code compare_lines(sqlite3 *_Nonnull _db_);

// Generated from linetest.sql:217
// static CQL_WARN_UNUSED cql_code read_file(sqlite3 *_Nonnull _db_, cql_string_ref _Nonnull input_name, cql_string_ref _Nonnull source);

// Generated from linetest.sql:234
// static CQL_WARN_UNUSED cql_code parse_args(sqlite3 *_Nonnull _db_, cql_object_ref _Nonnull args);

// Generated from linetest.sql:258
extern CQL_WARN_UNUSED cql_code linetest_main(sqlite3 *_Nonnull _db_, cql_object_ref _Nonnull args);
