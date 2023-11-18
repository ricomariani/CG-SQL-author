/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */
#pragma once

#include "cqlrt.h"


// Generated from cql-verify.sql:38
extern cql_string_ref _Nullable sql_name;

// Generated from cql-verify.sql:39
extern cql_string_ref _Nullable result_name;

// Generated from cql-verify.sql:40
extern cql_int32 attempts;

// Generated from cql-verify.sql:41
extern cql_int32 errors;

// Generated from cql-verify.sql:42
extern cql_int32 tests;

// Generated from cql-verify.sql:43
extern cql_int64 last_rowid;

// Generated from cql-verify.sql:62
// static CQL_WARN_UNUSED cql_code setup(sqlite3 *_Nonnull _db_);

// Generated from cql-verify.sql:73
// static CQL_WARN_UNUSED cql_code prev_line(sqlite3 *_Nonnull _db_, cql_int32 line_, cql_int32 *_Nonnull prev);

// Generated from cql-verify.sql:94
// static CQL_WARN_UNUSED cql_code dump_output(sqlite3 *_Nonnull _db_, cql_int32 line_, cql_string_ref _Nonnull pat);

// Generated from cql-verify.sql:119
// static CQL_WARN_UNUSED cql_code find_search_line(sqlite3 *_Nonnull _db_, cql_int32 line_, cql_int32 *_Nonnull search_line);

// Generated from cql-verify.sql:142
// static CQL_WARN_UNUSED cql_code find_next(sqlite3 *_Nonnull _db_, cql_int32 line_, cql_string_ref _Nonnull pattern, cql_int32 *_Nonnull search_line, cql_int32 *_Nonnull found);

// Generated from cql-verify.sql:153
// static CQL_WARN_UNUSED cql_code find_same(sqlite3 *_Nonnull _db_, cql_int32 line_, cql_string_ref _Nonnull pattern, cql_int32 *_Nonnull search_line, cql_int32 *_Nonnull found);

// Generated from cql-verify.sql:165
// static CQL_WARN_UNUSED cql_code find_count(sqlite3 *_Nonnull _db_, cql_int32 line_, cql_string_ref _Nonnull pattern, cql_int32 *_Nonnull search_line, cql_int32 *_Nonnull found);

// Generated from cql-verify.sql:182
// static CQL_WARN_UNUSED cql_code dump_source(sqlite3 *_Nonnull _db_, cql_int32 line1, cql_int32 line2, cql_int32 current_line);

// Generated from cql-verify.sql:201
// static void print_error_message(cql_string_ref _Nonnull pattern, cql_int32 line, cql_int32 expected);

// Generated from cql-verify.sql:216
// static void match_multiline(cql_string_ref _Nonnull buffer, cql_bool *_Nonnull result);

// Generated from cql-verify.sql:310
extern CQL_WARN_UNUSED cql_code match_actual(sqlite3 *_Nonnull _db_, cql_string_ref _Nonnull buffer, cql_int32 line);

// Generated from cql-verify.sql:322
// static CQL_WARN_UNUSED cql_code do_match(sqlite3 *_Nonnull _db_, cql_string_ref _Nonnull buffer, cql_int32 line);

// Generated from cql-verify.sql:337
// static CQL_WARN_UNUSED cql_code process(sqlite3 *_Nonnull _db_);

// Generated from cql-verify.sql:375
// static CQL_WARN_UNUSED cql_code read_test_results(sqlite3 *_Nonnull _db_, cql_string_ref _Nonnull result_name);

// Generated from cql-verify.sql:400
// static CQL_WARN_UNUSED cql_code read_test_file(sqlite3 *_Nonnull _db_, cql_string_ref _Nonnull sql_name);

// Generated from cql-verify.sql:407
// static CQL_WARN_UNUSED cql_code load_data(sqlite3 *_Nonnull _db_, cql_string_ref _Nonnull sql_name, cql_string_ref _Nonnull result_name);

// Generated from cql-verify.sql:424
// static CQL_WARN_UNUSED cql_code parse_args(sqlite3 *_Nonnull _db_, cql_object_ref _Nonnull args);

// Generated from cql-verify.sql:436
extern CQL_WARN_UNUSED cql_code dbhelp_main(sqlite3 *_Nonnull _db_, cql_object_ref _Nonnull args);
