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

// Generated from cql-verify.sql:1

// Generated from cql-verify.sql:56
extern cql_string_ref _Nullable sql_file_name;

// Generated from cql-verify.sql:57
extern cql_string_ref _Nullable result_file_name;

// Generated from cql-verify.sql:58
extern cql_int32 attempts;

// Generated from cql-verify.sql:59
extern cql_int32 errors;

// Generated from cql-verify.sql:60
extern cql_int32 tests;

// Generated from cql-verify.sql:61
extern cql_int64 last_rowid;

// Generated from cql-verify.sql:82
// static CQL_WARN_UNUSED cql_code setup(sqlite3 *_Nonnull _db_);

// Generated from cql-verify.sql:110
// static CQL_WARN_UNUSED cql_code find_test_output_line(sqlite3 *_Nonnull _db_, cql_int32 expectation_line, cql_int32 *_Nonnull test_output_line);

// Generated from cql-verify.sql:129
// static CQL_WARN_UNUSED cql_code find_next(sqlite3 *_Nonnull _db_, cql_string_ref _Nonnull pattern, cql_int32 test_output_line, cql_int32 *_Nonnull found);

// Generated from cql-verify.sql:140
// static CQL_WARN_UNUSED cql_code find_same(sqlite3 *_Nonnull _db_, cql_string_ref _Nonnull pattern, cql_int32 *_Nonnull found);

// Generated from cql-verify.sql:154
// static CQL_WARN_UNUSED cql_code find_count(sqlite3 *_Nonnull _db_, cql_string_ref _Nonnull pattern, cql_int32 test_output_line, cql_int32 *_Nonnull found);

// Generated from cql-verify.sql:171
// static CQL_WARN_UNUSED cql_code prev_line(sqlite3 *_Nonnull _db_, cql_int32 test_output_line, cql_int32 *_Nonnull prev);

// Generated from cql-verify.sql:189
// static CQL_WARN_UNUSED cql_code dump_source(sqlite3 *_Nonnull _db_, cql_int32 line1, cql_int32 line2, cql_int32 current_line);

// Generated from cql-verify.sql:213
// static CQL_WARN_UNUSED cql_code dump_output(sqlite3 *_Nonnull _db_, cql_int32 test_output_line, cql_string_ref _Nonnull pat);

// Generated from cql-verify.sql:242
// static CQL_WARN_UNUSED cql_code print_fail_details(sqlite3 *_Nonnull _db_, cql_string_ref _Nonnull pat, cql_int32 test_output_line, cql_int32 expected);

// Generated from cql-verify.sql:271
// static CQL_WARN_UNUSED cql_code print_error_block(sqlite3 *_Nonnull _db_, cql_int32 test_output_line, cql_string_ref _Nonnull pat, cql_int32 expectation_line, cql_int32 expected);

// Generated from cql-verify.sql:287
// static void match_multiline(cql_string_ref _Nonnull buffer, cql_bool *_Nonnull result);

// Generated from cql-verify.sql:370
extern CQL_WARN_UNUSED cql_code match_actual(sqlite3 *_Nonnull _db_, cql_string_ref _Nonnull buffer, cql_int32 expectation_line);

// Generated from cql-verify.sql:381
// static CQL_WARN_UNUSED cql_code do_match(sqlite3 *_Nonnull _db_, cql_string_ref _Nonnull buffer, cql_int32 expectation_line);

// Generated from cql-verify.sql:397
// static CQL_WARN_UNUSED cql_code process(sqlite3 *_Nonnull _db_);

// Generated from cql-verify.sql:433
// static CQL_WARN_UNUSED cql_code read_test_results(sqlite3 *_Nonnull _db_, cql_string_ref _Nonnull result_name);

// Generated from cql-verify.sql:458
// static CQL_WARN_UNUSED cql_code read_test_file(sqlite3 *_Nonnull _db_, cql_string_ref _Nonnull sql_name);

// Generated from cql-verify.sql:465
// static CQL_WARN_UNUSED cql_code load_data(sqlite3 *_Nonnull _db_, cql_string_ref _Nonnull sql_name, cql_string_ref _Nonnull result_name);

// Generated from cql-verify.sql:482
// static CQL_WARN_UNUSED cql_code parse_args(sqlite3 *_Nonnull _db_, cql_object_ref _Nonnull args);

// Generated from cql-verify.sql:494
extern CQL_WARN_UNUSED cql_code dbhelp_main(sqlite3 *_Nonnull _db_, cql_object_ref _Nonnull args);
