/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */
#pragma once

#include "cqlrt.h"


// Generated from cql-verify.sql:1

// Generated from cql-verify.sql:1

// Generated from cql-verify.sql:1

// Generated from cql-verify.sql:50
extern cql_string_ref _Nullable sql_file_name;

// Generated from cql-verify.sql:51
extern cql_string_ref _Nullable result_file_name;

// Generated from cql-verify.sql:52
extern cql_int32 attempts;

// Generated from cql-verify.sql:53
extern cql_int32 errors;

// Generated from cql-verify.sql:54
extern cql_int32 tests;

// Generated from cql-verify.sql:55
extern cql_int64 last_rowid;

// Generated from cql-verify.sql:76
// static CQL_WARN_UNUSED cql_code setup(sqlite3 *_Nonnull _db_);

// Generated from cql-verify.sql:104
// static CQL_WARN_UNUSED cql_code find_test_output_line(sqlite3 *_Nonnull _db_, cql_int32 expectation_line, cql_int32 *_Nonnull test_output_line);

// Generated from cql-verify.sql:123
// static CQL_WARN_UNUSED cql_code find_next(sqlite3 *_Nonnull _db_, cql_string_ref _Nonnull pattern, cql_int32 test_output_line, cql_int32 *_Nonnull found);

// Generated from cql-verify.sql:134
// static CQL_WARN_UNUSED cql_code find_same(sqlite3 *_Nonnull _db_, cql_string_ref _Nonnull pattern, cql_int32 *_Nonnull found);

// Generated from cql-verify.sql:144
// static CQL_WARN_UNUSED cql_code find_count(sqlite3 *_Nonnull _db_, cql_string_ref _Nonnull pattern, cql_int32 test_output_line, cql_int32 *_Nonnull found);

// Generated from cql-verify.sql:161
// static CQL_WARN_UNUSED cql_code prev_line(sqlite3 *_Nonnull _db_, cql_int32 test_output_line, cql_int32 *_Nonnull prev);

// Generated from cql-verify.sql:179
// static CQL_WARN_UNUSED cql_code dump_source(sqlite3 *_Nonnull _db_, cql_int32 line1, cql_int32 line2, cql_int32 current_line);

// Generated from cql-verify.sql:202
// static CQL_WARN_UNUSED cql_code dump_output(sqlite3 *_Nonnull _db_, cql_int32 test_output_line, cql_string_ref _Nonnull pat);

// Generated from cql-verify.sql:231
// static CQL_WARN_UNUSED cql_code print_fail_details(sqlite3 *_Nonnull _db_, cql_string_ref _Nonnull pat, cql_int32 test_output_line, cql_int32 expected);

// Generated from cql-verify.sql:260
// static CQL_WARN_UNUSED cql_code print_error_block(sqlite3 *_Nonnull _db_, cql_int32 test_output_line, cql_string_ref _Nonnull pat, cql_int32 expectation_line, cql_int32 expected);

// Generated from cql-verify.sql:276
// static void match_multiline(cql_string_ref _Nonnull buffer, cql_bool *_Nonnull result);

// Generated from cql-verify.sql:359
extern CQL_WARN_UNUSED cql_code match_actual(sqlite3 *_Nonnull _db_, cql_string_ref _Nonnull buffer, cql_int32 expectation_line);

// Generated from cql-verify.sql:370
// static CQL_WARN_UNUSED cql_code do_match(sqlite3 *_Nonnull _db_, cql_string_ref _Nonnull buffer, cql_int32 expectation_line);

// Generated from cql-verify.sql:385
// static CQL_WARN_UNUSED cql_code process(sqlite3 *_Nonnull _db_);

// Generated from cql-verify.sql:421
// static CQL_WARN_UNUSED cql_code read_test_results(sqlite3 *_Nonnull _db_, cql_string_ref _Nonnull result_name);

// Generated from cql-verify.sql:446
// static CQL_WARN_UNUSED cql_code read_test_file(sqlite3 *_Nonnull _db_, cql_string_ref _Nonnull sql_name);

// Generated from cql-verify.sql:453
// static CQL_WARN_UNUSED cql_code load_data(sqlite3 *_Nonnull _db_, cql_string_ref _Nonnull sql_name, cql_string_ref _Nonnull result_name);

// Generated from cql-verify.sql:470
// static CQL_WARN_UNUSED cql_code parse_args(sqlite3 *_Nonnull _db_, cql_object_ref _Nonnull args);

// Generated from cql-verify.sql:482
extern CQL_WARN_UNUSED cql_code dbhelp_main(sqlite3 *_Nonnull _db_, cql_object_ref _Nonnull args);
