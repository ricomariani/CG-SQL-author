/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#pragma once

#include <sqlite3.h>
#include <stdio.h>
#include <stdbool.h>
#include <stdlib.h>
#include <stddef.h>
#include <string.h>
#include <limits.h>
#include <setjmp.h>

#ifdef __cplusplus
#define CQL_EXTERN_C_BEGIN extern "C" {
#define CQL_EXTERN_C_END }
#else
#define CQL_EXTERN_C_BEGIN
#define CQL_EXTERN_C_END
#endif // __cplusplus

#define CQL_C_ASSERT(e) typedef char __CQL_C_ASSERT__[(e)?1:-1]

#if LONG_MAX > 0x7fffffff
#define _64(x) x##L
#else
#define _64(x) x##LL
#endif

#ifndef cql_error_prepare
// called at the start of every procedure that uses _rc_ (no-op by default)
#define cql_error_prepare()
#endif

#ifndef cql_error_trace
// called each time an "not OK" _rc_ is encountered (no-op by default)
#define cql_error_trace()
#endif

#ifndef cql_error_report
// called at the end of every procedure that uses _rc_ (no-op by default)
#define cql_error_report()
#endif

#ifndef __has_attribute         // Optional of course.
  #define __has_attribute(x) 0  // Compatibility with non-clang compilers.
#endif

#if __has_attribute(optnone)
  #define CQL_OPT_NONE __attribute__((optnone))
#elif __has_attribute(optimize)
  #define CQL_OPT_NONE __attribute__((optimize("O0")))
#else
  #define CQL_OPT_NONE
#endif

#define CQL_EXPORT extern __attribute__((visibility("default")))
#define CQL_WARN_UNUSED __attribute__((warn_unused_result))

CQL_EXTERN_C_BEGIN

typedef struct cql_nullable_int32 {
 cql_bool is_null;
 cql_int32 value;
} cql_nullable_int32;

typedef struct cql_nullable_int64 {
 cql_bool is_null;
 cql_int64 value;
} cql_nullable_int64;

typedef struct cql_nullable_double {
 cql_bool is_null;
 cql_double value;
} cql_nullable_double;

typedef struct cql_nullable_bool {
 cql_bool is_null;
 cql_bool value;
} cql_nullable_bool;

typedef long long llint_t;

// These macros are used for the typed getters
#define CQL_DATA_TYPE_NULL      0       // note these are array offsets, do not reorder them!
#define CQL_DATA_TYPE_INT32     1       // note these are array offsets, do not reorder them!
#define CQL_DATA_TYPE_INT64     2       // note these are array offsets, do not reorder them!
#define CQL_DATA_TYPE_DOUBLE    3       // note these are array offsets, do not reorder them!
#define CQL_DATA_TYPE_BOOL      4       // note these are array offsets, do not reorder them!
#define CQL_DATA_TYPE_STRING    5
#define CQL_DATA_TYPE_BLOB      6
#define CQL_DATA_TYPE_OBJECT    7
#define CQL_DATA_TYPE_CORE      0x3f    // bit mask for core types
#define CQL_DATA_TYPE_ENCODED   0x40    // set if and only if encode
#define CQL_DATA_TYPE_NOT_NULL  0x80    // set if and only if null is not possible
#define CQL_CORE_DATA_TYPE_OF(type) ((type) & CQL_DATA_TYPE_CORE)


// These are the types of blob fields we can create with the standard bcreatekey or bcreateval
// these correspond 1:1 with the SEM_TYPE so they need to stay in sync.  In fact these can
// never change because this is an external format.
// The first 4 types are fixed length encoded in an int64_t

#define CQL_BLOB_TYPE_BOOL   0  // always big endian format in the blob
#define CQL_BLOB_TYPE_INT32  1  // always big endian format in the blob
#define CQL_BLOB_TYPE_INT64  2  // always big endian format in the blob
#define CQL_BLOB_TYPE_FLOAT  3  // always IEEE 754 "double" (8 bytes) format in the blob
#define CQL_BLOB_TYPE_STRING 4  // string field in a blob
#define CQL_BLOB_TYPE_BLOB   5  // blob field in a blob
#define CQL_BLOB_TYPE_ENTITY 6  // Reserved in case object support is needed; Currently unused.
#define CQL_BLOB_TYPE_DIRTY 0x40 // temp status in the blob indicating the column has been updated, this is not durable
#define CQL_BLOB_TYPE_NULL  0x80 // If this bit is set then the stored value is null, the allocated space should be ignored

// This is the general shape for cursor metadata, it can describe the contents of any cursor
// this is useful for generic cursor functions like "hash"
typedef struct cql_dynamic_cursor {
  void *_Nonnull cursor_data;
  cql_bool *_Nonnull cursor_has_row;
  cql_uint16 *_Nonnull cursor_col_offsets;
  uint8_t *_Nonnull cursor_data_types;
  const char *_Nonnull *_Nonnull cursor_fields;
  size_t cursor_size;
  uint16_t cursor_refs_count;
  uint16_t cursor_refs_offset;
} cql_dynamic_cursor;

CQL_EXPORT int32_t cql_outstanding_refs;

CQL_EXPORT void cql_copyoutrow(sqlite3 *_Nullable db, cql_result_set_ref _Nonnull rs, cql_int32 row, cql_int32 count, ...);
CQL_EXPORT void cql_multifetch(cql_code rc, sqlite3_stmt *_Nullable stmt, cql_int32 count, ...);
CQL_EXPORT void cql_multibind(cql_code *_Nonnull rc, sqlite3 *_Nonnull db, sqlite3_stmt *_Nullable *_Nonnull pstmt, cql_int32 count, ...);
CQL_EXPORT void cql_multibind_var(cql_code *_Nonnull rc, sqlite3 *_Nonnull db, sqlite3_stmt *_Nullable *_Nonnull pstmt, cql_int32 count, const char *_Nullable vpreds, ...);
CQL_EXPORT cql_code cql_best_error(cql_code rc);
CQL_EXPORT void cql_set_encoding(uint8_t *_Nonnull data_types, cql_int32 count, cql_int32 col, cql_bool encode);

typedef struct cql_fetch_info {
  cql_code rc;
  sqlite3 *_Nullable db;
  sqlite3_stmt *_Nullable stmt;
  uint8_t *_Nonnull data_types;
  uint16_t *_Nonnull col_offsets;
  uint16_t refs_count;
  uint16_t refs_offset;
  uint16_t *_Nullable identity_columns;
  int16_t encode_context_index;
  int32_t rowsize;
  const char *_Nullable autodrop_tables;
  int64_t crc;
  int32_t *_Nullable perf_index;
  cql_object_ref _Nullable encoder;
} cql_fetch_info;

CQL_EXPORT void cql_multifetch_meta(char *_Nonnull data, cql_fetch_info *_Nonnull info);

CQL_EXPORT cql_code cql_fetch_all_results(cql_fetch_info *_Nonnull info,
                                          cql_result_set_ref _Nullable *_Nonnull result_set);

CQL_EXPORT cql_code cql_one_row_result(cql_fetch_info *_Nonnull info,
                                       char *_Nullable data,
                                       int32_t count,
                                       cql_result_set_ref _Nullable *_Nonnull result_set);

CQL_EXPORT void cql_set_blob_ref(cql_blob_ref _Nullable *_Nonnull target, cql_blob_ref _Nullable source);
CQL_EXPORT void cql_set_string_ref(cql_string_ref _Nullable *_Nonnull target, cql_string_ref _Nullable source);
CQL_EXPORT void cql_set_object_ref(cql_object_ref _Nullable *_Nonnull target, cql_object_ref _Nullable source);
CQL_EXPORT void cql_set_created_blob_ref(cql_blob_ref _Nullable *_Nonnull target, cql_blob_ref _Nullable source);
CQL_EXPORT void cql_set_created_string_ref(cql_string_ref _Nullable *_Nonnull target, cql_string_ref _Nullable source);
CQL_EXPORT void cql_set_created_object_ref(cql_object_ref _Nullable *_Nonnull target, cql_object_ref _Nullable source);

CQL_EXPORT cql_code cql_prepare(sqlite3 *_Nonnull db, sqlite3_stmt *_Nullable *_Nonnull pstmt, const char *_Nonnull sql);

CQL_EXPORT cql_code cql_prepare_var(sqlite3 *_Nonnull db,
                                    sqlite3_stmt *_Nullable *_Nonnull pstmt,
                                    cql_int32 count,
                                    const char *_Nullable preds, ...);

CQL_EXPORT cql_code cql_no_rows_stmt(sqlite3 *_Nonnull db, sqlite3_stmt *_Nullable *_Nonnull pstmt);
CQL_EXPORT cql_result_set_ref _Nonnull cql_no_rows_result_set(void);
CQL_EXPORT cql_code cql_exec(sqlite3 *_Nonnull db, const char *_Nonnull sql);
CQL_EXPORT cql_code cql_exec_var(sqlite3 *_Nonnull db, cql_int32 count, const char *_Nullable preds, ...);
CQL_EXPORT CQL_WARN_UNUSED cql_code cql_exec_internal(sqlite3 *_Nonnull db, cql_string_ref _Nonnull str_ref);

CQL_EXPORT cql_code cql_prepare_frags(sqlite3 *_Nonnull db,
                                      sqlite3_stmt *_Nullable *_Nonnull pstmt,
                                      const char *_Nonnull base,
                                      const char *_Nonnull frags);

CQL_EXPORT cql_code cql_exec_frags(sqlite3 *_Nonnull db,
                                   const char *_Nonnull base,
                                   const char *_Nonnull frags);

CQL_EXPORT void cql_finalize_on_error(cql_code rc, sqlite3_stmt *_Nullable *_Nonnull pstmt);
CQL_EXPORT void cql_finalize_stmt(sqlite3_stmt *_Nullable *_Nonnull pstmt);

CQL_EXPORT void cql_column_nullable_bool(sqlite3_stmt *_Nonnull stmt, cql_int32 index, cql_nullable_bool *_Nonnull data);
CQL_EXPORT void cql_column_nullable_int32(sqlite3_stmt *_Nonnull stmt, cql_int32 index, cql_nullable_int32 *_Nonnull data);
CQL_EXPORT void cql_column_nullable_int64(sqlite3_stmt *_Nonnull stmt, cql_int32 index, cql_nullable_int64 *_Nonnull data);
CQL_EXPORT void cql_column_nullable_double(sqlite3_stmt *_Nonnull stmt, cql_int32 index, cql_nullable_double *_Nonnull data);
CQL_EXPORT void cql_column_nullable_string_ref(sqlite3_stmt *_Nonnull stmt, cql_int32 index, cql_string_ref _Nullable *_Nonnull data);
CQL_EXPORT void cql_column_nullable_blob_ref(sqlite3_stmt *_Nonnull stmt, cql_int32 index, cql_blob_ref _Nullable *_Nonnull data);
CQL_EXPORT void cql_column_string_ref(sqlite3_stmt *_Nonnull stmt, cql_int32 index, cql_string_ref _Nonnull *_Nonnull data);
CQL_EXPORT void cql_column_blob_ref(sqlite3_stmt *_Nonnull stmt, cql_int32 index, cql_blob_ref _Nonnull *_Nonnull data);

#define cql_teardown_row(r) cql_release_offsets(&(r), (r)._refs_count_, (r)._refs_offset_)
#define cql_retain_row(r) cql_retain_offsets(&(r), (r)._refs_count_, (r)._refs_offset_)
#define cql_offsetof(_struct, _field) ((cql_uint16)offsetof(_struct, _field))

#define cql_combine_nullables(output, l_is_null, r_is_null, value_) \
  { cql_bool __saved_is_null = (l_is_null) || (r_is_null); \
   (output).value = __saved_is_null ? 0 : (value_); \
   (output).is_null = __saved_is_null; }

#define cql_set_null(output) \
   (output).is_null = cql_true; (output).value = 0;

#define cql_set_notnull(output, val) \
   (output).value = val; (output).is_null = cql_false;

#define cql_set_nullable(output, isnull_, value_) \
   { cql_bool __saved_is_null = isnull_; \
   (output).value = __saved_is_null  ? 0 : (value_); \
   (output).is_null = __saved_is_null; }

#define cql_is_nullable_true(is_null, value) (!(is_null) && (value))
#define cql_is_nullable_false(is_null, value) (!(is_null) && !(value))

// Enforces (via `cql_tripwire`) that an argument passed in from C to a stored
// procedure is not NULL. `position` indicates for which argument we're doing
// the checking, counting from 1, *not* 0.
CQL_EXPORT void cql_contract_argument_notnull(void *_Nullable argument, cql_uint32 position);

// Like `cql_contract_argument_notnull`, but also checks that `*argument` is not
// NULL. This should only be used for INOUT arguments of a NOT NULL reference
// type; `cql_contract_argument_notnull` should be used in all other cases.
void cql_contract_argument_notnull_when_dereferenced(void *_Nullable argument, cql_uint32 position);

#ifdef CQL_RUN_TEST
// If compiled with `CQL_RUN_TEST`, `cql_contract_argument_notnull` and
// `cql_contract_argument_notnull_when_dereferenced` will longjmp here instead
// of calling `cql_tripwire` when this is not NULL. The jump will be performed
// with a value of `position`, thus allowing tests to know for which argument a
// tripwire would have normally been encountered.
extern jmp_buf *_Nullable cql_contract_argument_notnull_tripwire_jmp_buf;
#endif

#define BYTEBUF_GROWTH_SIZE 1024
#define BYTEBUF_EXP_GROWTH_CAP 1024 * 1024
#define BYTEBUF_GROWTH_SIZE_AFTER_CAP 200 * 1024

typedef struct cql_bytebuf
{
  char *_Nullable ptr;   // pointer to stored data, if any
  int32_t used;          // bytes used in current buffer
  int32_t max;           // max bytes in current buffer
} cql_bytebuf;

CQL_EXPORT int32_t bytebuf_open_count;

CQL_EXPORT void cql_bytebuf_open(cql_bytebuf *_Nonnull b);
CQL_EXPORT void cql_bytebuf_close(cql_bytebuf *_Nonnull b);
CQL_EXPORT void *_Nonnull cql_bytebuf_alloc(cql_bytebuf *_Nonnull b, int needed);
CQL_EXPORT void cql_bytebuf_append(cql_bytebuf *_Nonnull buffer, const void *_Nonnull data, int32_t bytes);
CQL_EXPORT void cql_bprintf(cql_bytebuf *_Nonnull buffer, const char *_Nonnull format, ...)
                   __attribute__ (( format( printf, 2, 3 ) ));
CQL_EXPORT void cql_bytebuf_append_null(cql_bytebuf *_Nonnull buffer);
CQL_EXPORT cql_string_ref _Nonnull cql_cursor_format(cql_dynamic_cursor *_Nonnull dyn_cursor);

// teardown all the internal data for the given result_set
CQL_EXPORT void cql_result_set_teardown(cql_result_set_ref _Nonnull result_set);

// The normal cql_result_set_teardown() function only frees the directly
// allocated columns and rows of the result set.  This is no suprise because
// they're the only one heap allocated in the CQL runtime.
//
// This function allows you to set a callback for your result sets
// when they are finally destroyed so that you can free any extra memory
// you might have allocated.  This can be particularly useful if the
// result set has been proxied into some other language and there are
// wrappers and so forth that need to be taken down.  The code that
// owns memory for those wrappers can be informed by this callback
// that the result set is condemned.
//
// Of course the particular action will be determined by whatever is
// wrapping or otherwise holding on to the result set.
CQL_EXPORT void cql_result_set_set_custom_teardown(
  cql_result_set_ref _Nonnull result_set,
  void(*_Nonnull custom_teardown)(cql_result_set_ref _Nonnull result_set));

// retain/release references in a row using the given offset array
CQL_EXPORT void cql_retain_offsets(void *_Nonnull pv, cql_uint16 refs_count, cql_uint16 refs_offset);
CQL_EXPORT void cql_release_offsets(void *_Nonnull pv, cql_uint16 refs_count, cql_uint16 refs_offset);

// hash a row in a row set using the metadata
CQL_EXPORT cql_hash_code cql_row_hash(cql_result_set_ref _Nonnull result_set, cql_int32 row);

// hash a cursor using the metadata (CQL compatible types)
cql_int64 cql_cursor_hash(cql_dynamic_cursor *_Nonnull dyn_cursor);

// compare cursors using metadata
cql_bool cql_cursors_equal(cql_dynamic_cursor *_Nonnull c1, cql_dynamic_cursor *_Nonnull c2);

// compare two rows for equality
CQL_EXPORT cql_bool cql_rows_equal(cql_result_set_ref _Nonnull rs1, cql_int32 row1, cql_result_set_ref _Nonnull rs2, cql_int32 row2);

// compare two rows for same identity column values
CQL_EXPORT cql_bool cql_rows_same(cql_result_set_ref _Nonnull rs1, cql_int32 row1, cql_result_set_ref _Nonnull rs2, cql_int32 row2);

// copy a set of rows from a result_set
CQL_EXPORT void cql_rowset_copy(cql_result_set_ref _Nonnull result_set, cql_result_set_ref _Nonnull *_Nonnull to_result_set, int32_t from, cql_int32 count);

// getters

// Generic is_null value getter on base result set object.
// NOTE: This function should call through to the
// inline type getters that are passed into the ctor for the result set.
// @param result_set The cql result_set object.
// @param row The row number to fetch the value for.
// @param col The column to fetch the value for.
// @return cql_true if the value is null, otherwise cql_false.
CQL_EXPORT cql_bool cql_result_set_get_is_null_col(cql_result_set_ref _Nonnull result_set, cql_int32 row, cql_int32 col);

// Generic bool value getter on base result set object.
// NOTE: This function should call through to the
// inline type getters that are passed into the ctor for the result set.
// @param result_set The cql result_set object.
// @param row The row number to fetch the value for.
// @param col The column to fetch the value for.
// @return The bool value.
CQL_EXPORT cql_bool cql_result_set_get_bool_col(cql_result_set_ref _Nonnull result_set, cql_int32 row, cql_int32 col);

// Generic int32 value getter on base result set object.
// NOTE: This function should call through to the
// inline type getters that are passed into the ctor for the result set.
// @param result_set The cql result_set object.
// @param row The row number to fetch the value for.
// @param col The column to fetch the value for.
// @return The int32 value.
CQL_EXPORT cql_int32 cql_result_set_get_int32_col(cql_result_set_ref _Nonnull result_set, cql_int32 row, cql_int32 col);

// Generic int64 value getter on base result set object.
// NOTE: This function should call through to the
// inline type getters that are passed into the ctor for the result set.
// @param result_set The cql result_set object.
// @param row The row number to fetch the value for.
// @param col The column to fetch the value for.
// @return The int64 value.ali
CQL_EXPORT cql_int64 cql_result_set_get_int64_col(cql_result_set_ref _Nonnull result_set, cql_int32 row, cql_int32 col);

// Generic double value getter on base result set object.
// NOTE: This function should call through to the
// inline type getters that are passed into the ctor for the result set.
// @param result_set The cql result_set object.
// @param row The row number to fetch the value for.
// @param col The column to fetch the value for.
// @return The double value.
CQL_EXPORT cql_double cql_result_set_get_double_col(cql_result_set_ref _Nonnull result_set, cql_int32 row, cql_int32 col);

// Generic string value getter on base result set object.
// NOTE: This function should call through to the
// inline type getters that are passed into the ctor for the result set.
// @param result_set The cql result_set object.
// @param row The row number to fetch the value for.
// @param col The column to fetch the value for.
// @return The string value.
CQL_EXPORT cql_string_ref _Nullable cql_result_set_get_string_col(cql_result_set_ref _Nonnull result_set, cql_int32 row, cql_int32 col);

// Generic blob value getter on base result set object.
// NOTE: This function should call through to the
// inline type getters that are passed into the ctor for the result set.
// @param result_set The cql result_set object.
// @param row The row number to fetch the value for.
// @param col The column to fetch the value for.
// @return The string value.
CQL_EXPORT cql_blob_ref _Nullable cql_result_set_get_blob_col(cql_result_set_ref _Nonnull result_set, cql_int32 row, cql_int32 col);

// Generic object value getter on base result set object.
// NOTE: This function should call through to the
// inline type getters that are passed into the ctor for the result set.
// @param result_set The cql result_set object.
// @param row The row number to fetch the value for.
// @param col The column to fetch the value for.
// @return The object value. 
CQL_EXPORT cql_object_ref _Nullable cql_result_set_get_object_col(cql_result_set_ref _Nonnull result_set, cql_int32 row, cql_int32 col);

// setters
CQL_EXPORT void cql_result_set_set_to_null_col(cql_result_set_ref _Nonnull result_set, cql_int32 row, cql_int32 col);
CQL_EXPORT void cql_result_set_set_bool_col(cql_result_set_ref _Nonnull result_set, cql_int32 row, cql_int32 col, cql_bool new_value);
CQL_EXPORT void cql_result_set_set_int32_col(cql_result_set_ref _Nonnull result_set, cql_int32 row, cql_int32 col, cql_int32 new_value);
CQL_EXPORT void cql_result_set_set_int64_col(cql_result_set_ref _Nonnull result_set, cql_int32 row, cql_int32 col, cql_int64 new_value);
CQL_EXPORT void cql_result_set_set_double_col(cql_result_set_ref _Nonnull result_set, cql_int32 row, cql_int32 col, cql_double new_value);
CQL_EXPORT void cql_result_set_set_string_col(cql_result_set_ref _Nonnull result_set, cql_int32 row, cql_int32 col, cql_string_ref _Nullable new_value);
CQL_EXPORT void cql_result_set_set_blob_col(cql_result_set_ref _Nonnull result_set, cql_int32 row, cql_int32 col, cql_blob_ref _Nullable new_value);
CQL_EXPORT void cql_result_set_set_object_col(cql_result_set_ref _Nonnull result_set, cql_int32 row, cql_int32 col, cql_object_ref _Nullable new_value);

//  encoded column tests
CQL_EXPORT cql_bool cql_result_set_get_is_encoded_col(cql_result_set_ref _Nonnull result_set, cql_int32 col);

// result set metadata management
CQL_EXPORT void cql_initialize_meta(cql_result_set_meta *_Nonnull meta, cql_fetch_info *_Nonnull info);

#ifndef cql_sqlite3_exec
#define cql_sqlite3_exec(db, sql) sqlite3_exec((db), (sql), NULL, NULL, NULL)
#endif // cql_sqlite3_exec
#ifndef cql_sqlite3_prepare_v2
#define cql_sqlite3_prepare_v2(db, sql, len, stmt, tail) sqlite3_prepare_v2((db), (sql), (len), (stmt), (tail))
#endif // cql_sqlite3_prepare_v2
#ifndef cql_sqlite3_finalize
#define cql_sqlite3_finalize(stmt) sqlite3_finalize((stmt))
#endif // cql_sqlite3_finalize

// The indicated cql_bytebuf has in it exactly the raw row data that we need for a rowset
// we've accumulated it one row at a time.  It becomes the guts of a result set with the
// given metadata.  The incoming "return" code tells the helper if it needs to tear down
// because a failure is in progress so it's an input.
CQL_EXPORT void cql_results_from_data(
  cql_code rc,
  cql_bytebuf *_Nonnull buffer,
  cql_fetch_info *_Nonnull info,
  cql_result_set_ref _Nullable *_Nonnull result_set);

// data entry for a closed hash table
typedef struct cql_hashtab_entry {
 cql_int64 key;
 cql_int64 val;
} cql_hashtab_entry;

// hash table with payloads and capacity info
typedef struct cql_hashtab {
  cql_int32 count;
  cql_int32 capacity;
  cql_hashtab_entry *_Nullable payload;
  uint64_t (*_Nonnull hash_key)(void *_Nullable context, cql_int64 key);
  bool (*_Nonnull compare_keys)(void *_Nullable context, cql_int64 key1, cql_int64 key2);
  void (*_Nonnull retain_key)(void *_Nullable context, cql_int64 key);
  void (*_Nonnull retain_val)(void *_Nullable context, cql_int64 val);
  void (*_Nonnull release_key)(void *_Nullable context, cql_int64 key);
  void (*_Nonnull release_val)(void *_Nullable context, cql_int64 val);
  void *_Nullable context;
} cql_hashtab;

// CQL friendly versions of the hash table things, easy to call from CQL
CQL_EXPORT cql_object_ref _Nonnull cql_facets_create(void);
CQL_EXPORT cql_bool cql_facet_add(cql_object_ref _Nullable facets, cql_string_ref _Nonnull name, cql_int64 crc);
CQL_EXPORT cql_bool cql_facet_upsert(cql_object_ref _Nullable facets, cql_string_ref _Nonnull name, cql_int64 crc);
CQL_EXPORT cql_int64 cql_facet_find(cql_object_ref _Nullable  facets, cql_string_ref _Nonnull key);

// For internal use by the runtime only
CQL_EXPORT cql_object_ref _Nonnull _cql_generic_object_create(void *_Nonnull data,  void (*_Nonnull finalize)(void *_Nonnull));
CQL_EXPORT void *_Nonnull _cql_generic_object_get_data(cql_object_ref _Nonnull obj);

// Allows for the partioning of a result set by the key columns.  This lets us
// stream over a child result set, hash it by the key columns and then lash
// each part of the result to the parent.  The rows could be in any order.
// The dynamic cursor for the key defines the partitioning columns and the
// value is the full child row.  When the partition is extracted the accumulated
// matching rows are provided.  Once extraction begins no more rows can be added.
CQL_EXPORT cql_object_ref _Nonnull cql_partition_create(void);

CQL_EXPORT cql_bool cql_partition_cursor(
  cql_object_ref _Nonnull obj,
  cql_dynamic_cursor *_Nonnull key,
  cql_dynamic_cursor *_Nonnull val);

CQL_EXPORT cql_object_ref _Nonnull cql_extract_partition(
  cql_object_ref _Nonnull obj,
  cql_dynamic_cursor *_Nonnull key);

// String dictionary helpers, a simple hash table wrapper with
// very basic dictionary functions.  Used by lots of things.
CQL_EXPORT cql_object_ref _Nonnull cql_string_dictionary_create(void);

CQL_EXPORT cql_bool cql_string_dictionary_add(
  cql_object_ref _Nonnull dict,
  cql_string_ref _Nonnull key,
  cql_string_ref _Nonnull val);

CQL_EXPORT cql_string_ref _Nullable cql_string_dictionary_find(
  cql_object_ref _Nonnull dict,
  cql_string_ref _Nullable key);

// Long dictionary helpers, a simple hash table wrapper with
// very basic dictionary functions.
CQL_EXPORT cql_object_ref _Nonnull cql_long_dictionary_create(void);

CQL_EXPORT cql_bool cql_long_dictionary_add(
  cql_object_ref _Nonnull dict,
  cql_string_ref _Nonnull key,
  cql_int64 val);

CQL_EXPORT cql_nullable_int64 cql_long_dictionary_find(
  cql_object_ref _Nonnull dict,
  cql_string_ref _Nullable key);

// Real dictionary helpers, a simple hash table wrapper with
// very basic dictionary functions.
CQL_EXPORT cql_object_ref _Nonnull cql_real_dictionary_create(void);

CQL_EXPORT cql_bool cql_real_dictionary_add(
  cql_object_ref _Nonnull dict,
  cql_string_ref _Nonnull key,
  cql_double val);

CQL_EXPORT cql_nullable_double cql_real_dictionary_find(
  cql_object_ref _Nonnull dict,
  cql_string_ref _Nullable key);

// object dictionary has the same contract as string dictionary
// except the stored type. It uses the same code internally

CQL_EXPORT cql_object_ref _Nonnull cql_object_dictionary_create(void);

CQL_EXPORT cql_bool cql_object_dictionary_add(
  cql_object_ref _Nonnull dict,
  cql_string_ref _Nonnull key,
  cql_object_ref _Nonnull val);

CQL_EXPORT cql_object_ref _Nullable cql_object_dictionary_find(
  cql_object_ref _Nonnull dict,
  cql_string_ref _Nullable key);

// String list helpers
CQL_EXPORT cql_object_ref _Nonnull cql_string_list_create(void);
CQL_EXPORT cql_object_ref _Nonnull cql_string_list_add(cql_object_ref _Nonnull list, cql_string_ref _Nonnull string);
CQL_EXPORT int32_t cql_string_list_count(cql_object_ref _Nonnull list);
CQL_EXPORT cql_string_ref _Nonnull cql_string_list_get_at(cql_object_ref _Nonnull list, int32_t index);
CQL_EXPORT cql_object_ref _Nonnull cql_string_list_set_at(cql_object_ref _Nonnull list, int32_t index, cql_string_ref _Nonnull value);

// Blob list helpers
CQL_EXPORT cql_object_ref _Nonnull cql_blob_list_create(void);
CQL_EXPORT cql_object_ref _Nonnull cql_blob_list_add(cql_object_ref _Nonnull list, cql_blob_ref _Nonnull value);
CQL_EXPORT int32_t cql_blob_list_count(cql_object_ref _Nonnull list);
CQL_EXPORT cql_blob_ref _Nonnull cql_blob_list_get_at(cql_object_ref _Nonnull list, int32_t index);
CQL_EXPORT cql_object_ref _Nonnull cql_blob_list_set_at(cql_object_ref _Nonnull list, int32_t index, cql_blob_ref _Nonnull value);

// Long list helpers
CQL_EXPORT cql_object_ref _Nonnull cql_long_list_create(void);
CQL_EXPORT cql_object_ref _Nonnull cql_long_list_add(cql_object_ref _Nonnull list, cql_int64 value);
CQL_EXPORT int32_t cql_long_list_count(cql_object_ref _Nonnull list);
CQL_EXPORT cql_int64 cql_long_list_get_at(cql_object_ref _Nonnull list, int32_t index);
CQL_EXPORT cql_object_ref _Nonnull cql_long_list_set_at(cql_object_ref _Nonnull list, int32_t index, cql_int64 value);

// Real list helpers
CQL_EXPORT cql_object_ref _Nonnull cql_real_list_create(void);
CQL_EXPORT cql_object_ref _Nonnull cql_real_list_add(cql_object_ref _Nonnull list, cql_double value);
CQL_EXPORT int32_t cql_real_list_count(cql_object_ref _Nonnull list);
CQL_EXPORT cql_double cql_real_list_get_at(cql_object_ref _Nonnull list, int32_t index);
CQL_EXPORT cql_object_ref _Nonnull cql_real_list_set_at(cql_object_ref _Nonnull list, int32_t index, cql_double value);

// For internal use by the schema upgrader only, subject to change and generally uninteresting because
// of its unusual matching rules.
CQL_EXPORT cql_bool _cql_contains_column_def(cql_string_ref _Nullable haystack_, cql_string_ref _Nullable needle_);

// Boxing interface (uses generic objects to hold a statement)
CQL_EXPORT cql_object_ref _Nonnull cql_box_stmt(sqlite3_stmt *_Nullable stmt);
CQL_EXPORT sqlite3_stmt *_Nullable cql_unbox_stmt(cql_object_ref _Nonnull ref);


// boxing helpers for primitive types
cql_object_ref _Nonnull cql_box_int(cql_nullable_int32 data);
cql_nullable_int32 cql_unbox_int(cql_object_ref _Nullable box);
cql_object_ref _Nonnull cql_box_real(cql_nullable_double data);
cql_nullable_double cql_unbox_real(cql_object_ref _Nullable box);
cql_object_ref _Nonnull cql_box_bool(cql_nullable_bool data);
cql_nullable_bool cql_unbox_bool(cql_object_ref _Nullable box);
cql_object_ref _Nonnull cql_box_long(cql_nullable_int64 data);
cql_nullable_int64 cql_unbox_long(cql_object_ref _Nullable box);
cql_object_ref _Nonnull cql_box_text(cql_string_ref _Nullable data);
cql_string_ref _Nullable cql_unbox_text(cql_object_ref _Nullable box);
cql_object_ref _Nonnull cql_box_blob(cql_blob_ref _Nullable data);
cql_blob_ref _Nullable cql_unbox_blob(cql_object_ref _Nullable box);
cql_object_ref _Nonnull cql_box_object(cql_object_ref _Nullable data);
cql_object_ref _Nullable cql_unbox_object(cql_object_ref _Nullable box);
int32_t cql_box_get_type(cql_object_ref _Nullable box);

// String literals can be stored in a compressed format using the --compress option
// and the cql_compressed primitive.  This helper function gives us a normal string
// from the compressed fragments.  Note that --compress also makes fragments for the text
// of SQL statements.
CQL_EXPORT cql_string_ref _Nonnull cql_uncompress(const char *_Nonnull base, const char *_Nonnull frags);

// A recreate group can possibly be updated if all we did is add a new table to it.  If we have to do
// something more complicated then we have to drop the whole thing and and rebuild it from scratch.
// This code handles the fallback case.
cql_code cql_rebuild_recreate_group(
  sqlite3 *_Nonnull db,
  cql_string_ref _Nonnull tables,
  cql_string_ref _Nonnull indices,
  cql_string_ref _Nonnull deletes,
  cql_bool *_Nonnull result);

// When emitting code for to generate a query plan we cannot expect that code to run
// in a context where all the UDFs that were mentioned are actually initialized. This
// turns out to be ok because UDFS won't affect the plan anyway.  This code creates
// a stub UDF that does nothing so that the code compiles as written allowing a
// plan to be created.  The query plan code calls this function once for each required UDF.
cql_code cql_create_udf_stub(sqlite3 *_Nonnull db, cql_string_ref _Nonnull name);

void bcreatekey(sqlite3_context *_Nonnull context, int32_t argc, sqlite3_value *_Nonnull *_Nonnull argv);
void bgetkey(sqlite3_context *_Nonnull context, int32_t argc, sqlite3_value *_Nonnull *_Nonnull argv);
void bgetkey_type(sqlite3_context *_Nonnull context, int32_t argc, sqlite3_value *_Nonnull *_Nonnull argv);
void bupdatekey(sqlite3_context *_Nonnull context, int32_t argc, sqlite3_value *_Nonnull *_Nonnull argv);

void bcreateval(sqlite3_context *_Nonnull context, int32_t argc, sqlite3_value *_Nonnull *_Nonnull argv);
void bgetval(sqlite3_context *_Nonnull context, int32_t argc, sqlite3_value *_Nonnull *_Nonnull argv);
void bgetval_type(sqlite3_context *_Nonnull context, int32_t argc, sqlite3_value *_Nonnull *_Nonnull argv);
void bupdateval(sqlite3_context *_Nonnull context, int32_t argc, sqlite3_value *_Nonnull *_Nonnull argv);

cql_code cql_throw(sqlite3 *_Nonnull db, int code);

CQL_EXTERN_C_END
