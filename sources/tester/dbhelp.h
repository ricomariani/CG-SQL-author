/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */
#pragma once

#include "cqlrt.h"


// Generated from dbhelp.sql:60
// static CQL_WARN_UNUSED cql_code setup(sqlite3 *_Nonnull _db_);

// Generated from dbhelp.sql:71
// static CQL_WARN_UNUSED cql_code prev_line(sqlite3 *_Nonnull _db_, cql_int32 line_, cql_int32 *_Nonnull prev);

// Generated from dbhelp.sql:82
// static CQL_WARN_UNUSED cql_code dump_output(sqlite3 *_Nonnull _db_, cql_int32 line_);

// Generated from dbhelp.sql:110
// static CQL_WARN_UNUSED cql_code find(sqlite3 *_Nonnull _db_, cql_int32 line_, cql_string_ref _Nonnull pattern, cql_int32 *_Nonnull search_line, cql_int32 *_Nonnull found);

// Generated from dbhelp.sql:121
// static CQL_WARN_UNUSED cql_code dump_source(sqlite3 *_Nonnull _db_, cql_int32 line1, cql_int32 line2);

// Generated from dbhelp.sql:140
// static CQL_WARN_UNUSED cql_code print_error_message(sqlite3 *_Nonnull _db_, cql_string_ref _Nonnull buffer, cql_int32 line, cql_int32 expected);

// Generated from dbhelp.sql:155
// static void match_multiline(cql_string_ref _Nonnull buffer, cql_bool *_Nonnull result);

// Generated from dbhelp.sql:157
extern cql_int32 attempts;

// Generated from dbhelp.sql:158
extern cql_int32 errors;

// Generated from dbhelp.sql:159
extern cql_int32 tests;

// Generated from dbhelp.sql:226
extern CQL_WARN_UNUSED cql_code match_actual(sqlite3 *_Nonnull _db_, cql_string_ref _Nonnull buffer, cql_int32 line);

// Generated from dbhelp.sql:238
// static CQL_WARN_UNUSED cql_code do_match(sqlite3 *_Nonnull _db_, cql_string_ref _Nonnull buffer, cql_int32 line);

// Generated from dbhelp.sql:253
// static CQL_WARN_UNUSED cql_code process(sqlite3 *_Nonnull _db_);

// Generated from dbhelp.sql:291
// static CQL_WARN_UNUSED cql_code read_test_results(sqlite3 *_Nonnull _db_, cql_string_ref _Nonnull result_name);

// Generated from dbhelp.sql:317
// static CQL_WARN_UNUSED cql_code read_test_file(sqlite3 *_Nonnull _db_, cql_string_ref _Nonnull sql_name);

// Generated from dbhelp.sql:324
// static CQL_WARN_UNUSED cql_code load_data(sqlite3 *_Nonnull _db_, cql_string_ref _Nonnull sql_name, cql_string_ref _Nonnull result_name);

// Generated from dbhelp.sql:346
// static CQL_WARN_UNUSED cql_code parse_args(sqlite3 *_Nonnull _db_, cql_object_ref _Nonnull args, cql_string_ref _Nullable *_Nonnull sql_name, cql_string_ref _Nullable *_Nonnull result_name);

// Generated from dbhelp.sql:360
extern CQL_WARN_UNUSED cql_code dbhelp_main(sqlite3 *_Nonnull _db_, cql_object_ref _Nonnull args);
