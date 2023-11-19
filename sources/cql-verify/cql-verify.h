/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */
#pragma once

#include "cqlrt.h"


// Generated from cql-verify.sql:35
extern cql_string_ref _Nullable sql_name;

// Generated from cql-verify.sql:36
extern cql_string_ref _Nullable result_name;

// Generated from cql-verify.sql:37
extern cql_int32 attempts;

// Generated from cql-verify.sql:38
extern cql_int32 errors;

// Generated from cql-verify.sql:39
extern cql_int32 tests;

// Generated from cql-verify.sql:40
extern cql_int64 last_rowid;

// Generated from cql-verify.sql:59
// static CQL_WARN_UNUSED cql_code setup(sqlite3 *_Nonnull _db_);

// Generated from cql-verify.sql:71
// static CQL_WARN_UNUSED cql_code prev_line(sqlite3 *_Nonnull _db_, cql_int32 line_, cql_int32 *_Nonnull prev);

// Generated from cql-verify.sql:92
// static CQL_WARN_UNUSED cql_code dump_output(sqlite3 *_Nonnull _db_, cql_int32 line_, cql_string_ref _Nonnull pat);

// Generated from cql-verify.sql:117
// static CQL_WARN_UNUSED cql_code find_search_line(sqlite3 *_Nonnull _db_, cql_int32 line_, cql_int32 *_Nonnull search_line);

// Generated from cql-verify.sql:138
// static CQL_WARN_UNUSED cql_code find_next(sqlite3 *_Nonnull _db_, cql_int32 line_, cql_string_ref _Nonnull pattern, cql_int32 search_line, cql_int32 *_Nonnull found);

// Generated from cql-verify.sql:149
// static CQL_WARN_UNUSED cql_code find_same(sqlite3 *_Nonnull _db_, cql_int32 line_, cql_string_ref _Nonnull pattern, cql_int32 *_Nonnull found);

// Generated from cql-verify.sql:159
// static CQL_WARN_UNUSED cql_code find_count(sqlite3 *_Nonnull _db_, cql_int32 line_, cql_string_ref _Nonnull pattern, cql_int32 search_line, cql_int32 *_Nonnull found);

// Generated from cql-verify.sql:177
// static CQL_WARN_UNUSED cql_code dump_source(sqlite3 *_Nonnull _db_, cql_int32 line1, cql_int32 line2, cql_int32 current_line);

// Generated from cql-verify.sql:202
// static void print_error_message(cql_string_ref _Nonnull pattern, cql_int32 line, cql_int32 expected, cql_int32 found);

// Generated from cql-verify.sql:217
// static void match_multiline(cql_string_ref _Nonnull buffer, cql_bool *_Nonnull result);

// Generated from cql-verify.sql:318
extern CQL_WARN_UNUSED cql_code match_actual(sqlite3 *_Nonnull _db_, cql_string_ref _Nonnull buffer, cql_int32 line);

// Generated from cql-verify.sql:330
// static CQL_WARN_UNUSED cql_code do_match(sqlite3 *_Nonnull _db_, cql_string_ref _Nonnull buffer, cql_int32 line);

// Generated from cql-verify.sql:345
// static CQL_WARN_UNUSED cql_code process(sqlite3 *_Nonnull _db_);

// Generated from cql-verify.sql:383
// static CQL_WARN_UNUSED cql_code read_test_results(sqlite3 *_Nonnull _db_, cql_string_ref _Nonnull result_name);

// Generated from cql-verify.sql:408
// static CQL_WARN_UNUSED cql_code read_test_file(sqlite3 *_Nonnull _db_, cql_string_ref _Nonnull sql_name);

// Generated from cql-verify.sql:415
// static CQL_WARN_UNUSED cql_code load_data(sqlite3 *_Nonnull _db_, cql_string_ref _Nonnull sql_name, cql_string_ref _Nonnull result_name);

// Generated from cql-verify.sql:432
// static CQL_WARN_UNUSED cql_code parse_args(sqlite3 *_Nonnull _db_, cql_object_ref _Nonnull args);

// Generated from cql-verify.sql:444
extern CQL_WARN_UNUSED cql_code dbhelp_main(sqlite3 *_Nonnull _db_, cql_object_ref _Nonnull args);
