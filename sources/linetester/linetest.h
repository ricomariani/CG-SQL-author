/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */
#pragma once

#include "cqlrt.h"


// Generated from linetest.sql:1

// Generated from linetest.sql:47
extern cql_int32 proc_count;

// Generated from linetest.sql:48
extern cql_int32 compares;

// Generated from linetest.sql:49
extern cql_int32 errors;

// Generated from linetest.sql:50
extern cql_string_ref _Nullable expected_name;

// Generated from linetest.sql:51
extern cql_string_ref _Nullable actual_name;

// Generated from linetest.sql:69
// static CQL_WARN_UNUSED cql_code setup(sqlite3 *_Nonnull _db_);

// Generated from linetest.sql:77
// static CQL_WARN_UNUSED cql_code add_linedata(sqlite3 *_Nonnull _db_, cql_string_ref _Nonnull source_, cql_string_ref _Nonnull procname_, cql_int32 line_, cql_string_ref _Nonnull data_, cql_int32 physical_line_);

// Generated from linetest.sql:87
// static CQL_WARN_UNUSED cql_code dump_proc_records(sqlite3 *_Nonnull _db_, cql_string_ref _Nonnull source_, cql_string_ref _Nonnull procname_);

// Generated from linetest.sql:97
// static CQL_WARN_UNUSED cql_code dump(sqlite3 *_Nonnull _db_, cql_string_ref _Nonnull procname);

// Generated from linetest.sql:156
// static CQL_WARN_UNUSED cql_code compare_lines(sqlite3 *_Nonnull _db_);

// Generated from linetest.sql:229
// static CQL_WARN_UNUSED cql_code read_file(sqlite3 *_Nonnull _db_, cql_string_ref _Nonnull input_name, cql_string_ref _Nonnull source);

// Generated from linetest.sql:246
// static CQL_WARN_UNUSED cql_code parse_args(sqlite3 *_Nonnull _db_, cql_object_ref _Nonnull args);

// Generated from linetest.sql:270
extern CQL_WARN_UNUSED cql_code linetest_main(sqlite3 *_Nonnull _db_, cql_object_ref _Nonnull args);
