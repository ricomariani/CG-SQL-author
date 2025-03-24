/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#pragma once

#include <assert.h>
#include <stddef.h>
#include <stdint.h>
#include <math.h>
#include <sqlite3.h>

#ifdef CQL_SQLITE_EXT
#include <sqlite3ext.h>
#endif

#ifdef CQLRT_DIAG
#include "diags.h"
#endif

#ifndef __clang__
#ifndef _Nonnull
    /* Hide Clang-only nullability specifiers if not Clang */
    #define _Nonnull
    #define _Nullable
#endif
#endif

// Assertion macro for API contract violations, these should stay in the release build.
#define cql_contract assert

// Assertion for internal invariant broken, these should stay in the release build.
#define cql_invariant assert

// Assertion for a failure that we might like to promote to an invariant
// but there may be exceptions yet.  This should fire in debug builds.
#define cql_tripwire assert

// Logging database error;
#define cql_log_database_error(...)

// value types
typedef unsigned char cql_bool;
#define cql_true ((cql_bool)1)
#define cql_false ((cql_bool)0)

// metatypes for the straight C implementation
#define CQL_C_TYPE_STRING 0
#define CQL_C_TYPE_BLOB 1
#define CQL_C_TYPE_RESULTS 2
#define CQL_C_TYPE_OBJECT 3

typedef uint64_t cql_hash_code;
typedef int32_t cql_int32;
typedef uint32_t cql_uint32;
typedef uint16_t cql_uint16;
typedef sqlite3_int64 cql_int64;
typedef double cql_double;

// The data type for a cql return code
// Note: normally we prefer int32_t or int64_t but we have to match the sqlite3 API
typedef int cql_code;

// base ref counting struct
typedef struct cql_type *cql_type_ref;
typedef struct cql_type {
  int type;
  int ref_count;
  void (*_Nullable finalize)(cql_type_ref _Nonnull ref);
} cql_type;

void cql_retain(cql_type_ref _Nullable ref);
void cql_release(cql_type_ref _Nullable ref);
cql_hash_code cql_ref_hash(cql_type_ref _Nonnull typeref);
cql_bool cql_ref_equal(cql_type_ref _Nullable typeref1, cql_type_ref _Nullable typeref2);

// builtin object
typedef struct cql_object *cql_object_ref;
typedef struct cql_object {
  cql_type base;
  void *_Nonnull ptr;
  void (*_Nonnull finalize)(void *_Nonnull ptr);
} cql_object;

// Adds a reference count to the object.
// @param obj The  object to be retained.
// void cql_object_retain(cql_object_ref _Nullable obj);
#define cql_object_retain(object) cql_retain((cql_type_ref)object);

// Subtracts a reference count from the object.  When it reaches 0, the object SHOULD be freed.
// @param str The object to be released.
// void cql_object_release(cql_object_ref _Nullable obj);
#define cql_object_release(object) cql_release((cql_type_ref)object);

// builtin statement box
typedef struct cql_boxed_stmt *cql_boxed_stmt_ref;
typedef struct cql_boxed_stmt {
  cql_type base;
  sqlite3_stmt *_Nullable stmt;
} cql_boxed_stmt;

// builtin blob
typedef struct cql_blob *cql_blob_ref;

typedef struct cql_blob {
  cql_type base;
  const void *_Nonnull ptr;
  cql_int32 size;
} cql_blob;

// Adds a reference count to the blob.
// @param blob The blob to be retained.
// void cql_blob_retain(cql_blob_ref _Nullable blob);
#define cql_blob_retain(object) cql_retain((cql_type_ref)object);

// Subtracts a reference count from the blob.  When it reaches 0, the blob SHOULD be freed.
// @param str The blob to be released.
// void cql_blob_release(cql_blob_ref _Nullable blob);
#define cql_blob_release(object) cql_release((cql_type_ref)object);

// Construct a new blob object.
// @param data the bytes to be stored.
// @param size the number of bytes of the data.
// @return A blob object of the type defined by cql_blob_ref.
// cql_blob_ref cql_blob_ref_new(const void *data, cql_uint32 size);
cql_blob_ref _Nonnull cql_blob_ref_new(const void *_Nonnull data, cql_int32 size);

// Get the bytes of the blob object.  This is not null, even if the blob is zero
// size and in general the memory allocated might be larger than the size of the blob.
// Get cql_get_blob_size must be used to know how much you can read.
// @param blob The blob object to get the bytes from.
// @return The bytes of the blob.
#define cql_get_blob_bytes(data) (data->ptr)

// Get size of a blob ref in bytes.
// @param blob The blob object to get the size from.
// @return The size of the blob in bytes.
#define cql_get_blob_size(data) (data->size)

// Creates a hash code for the blob object.
// @param blob The blob object to be hashed.
// cql_hash_code cql_blob_hash(cql_string_ref _Nullable str);
cql_hash_code cql_blob_hash(cql_blob_ref _Nullable str);

// Checks if two blob objects are equal.
// NOTE: If both objects are NULL, they are equal; if only 1 is NULL, they are not equal.
// @param str1 The first blob to compare.
// @param str2 The second blob to compare.
// @return cql_true if they are equal, otherwise cql_false.
// cql_bool cql_blob_equal(cql_blob_ref _Nullable bl1, cql_blob_ref _Nullable bl2);
cql_bool cql_blob_equal(cql_blob_ref _Nullable blob1, cql_blob_ref _Nullable blob2);

// builtin string
typedef struct cql_string *cql_string_ref;
typedef struct cql_string {
  cql_type base;
  const char *_Nullable ptr;
} cql_string;

// Construct a new string object.
// @param cstr The C string to be stored.
// @return A string object of the type defined by cql_string_ref.
// cql_string_ref cql_string_ref_new(const char *cstr);
cql_string_ref _Nonnull cql_string_ref_new(const char *_Nonnull cstr);

// Adds a reference count to the string object.
// @param str The string object to be retained.
// void cql_string_retain(cql_string_ref _Nullable str);
#define cql_string_retain(string) cql_retain((cql_type_ref)string);

// Subtracts a reference count from the string object.  When it reaches 0, the string SHOULD be freed.
// @param str The string object to be released.
// void cql_string_release(cql_string_ref _Nullable str);
#define cql_string_release(string) cql_release((cql_type_ref)string);

// Declare a static const string literal object. This must be a global object
// and will be executed in the global context.
// NOTE: This MUST be implemented as a macro as it both declares and assigns
// the value.
// @param name The name of the object.
// @param text The text to be stored in the object.
// cql_string_literal(cql_string_ref name, const char *text);
#define cql_string_literal(name, text) \
  static cql_string name##_ = { \
    .base = { \
      .type = CQL_C_TYPE_STRING, \
      .ref_count = 1, \
      .finalize = NULL, \
    }, \
    .ptr = text, \
  }; \
  static cql_string_ref name = &name##_

// Declare a const string that holds the name of a stored procedure. This must
// be a global object and will be executed in the global context.
// NOTE: This MUST be implemented as a macro as it both declares and assigns
// the value.
// @param name The name of the object.
// @param proc_name The procedure name to be stored in the object.
// cql_string_literal(cql_string_ref name, const char *proc_name);
#define cql_string_proc_name(name, proc_name) \
  cql_string name##_ = { \
    .base = { \
      .type = CQL_C_TYPE_STRING, \
      .ref_count = 1, \
      .finalize = NULL, \
    }, \
    .ptr = proc_name, \
  }; \
  cql_string_ref name = &name##_

// Compares two string objects.
// @param str1 The first string to compare.
// @param str2 The second string to compare.
// @return < 0 if str1 is less than str2, > 0 if str2 is less than str1, = 0 if str1 is equal to str2.
// int cql_string_compare(cql_string_ref str1, cql_string_ref str2);
int cql_string_compare(cql_string_ref _Nonnull s1, cql_string_ref _Nonnull s2);

// Creates a hash code for the string object.
// @param str The string object to be hashed.
// cql_hash_code cql_string_hash(cql_string_ref _Nullable str);
cql_hash_code cql_string_hash(cql_string_ref _Nullable str);

// Checks if two string objects are equal.
// NOTE: If both objects are NULL, they are equal; if only 1 is NULL, they are not equal.
// @param str1 The first string to compare.
// @param str2 The second string to compare.
// @return cql_true if they are equal, otherwise cql_false.
// cql_bool cql_string_equal(cql_string_ref _Nullable str1, cql_string_ref _Nullable str2);
cql_bool cql_string_equal(cql_string_ref _Nullable s1, cql_string_ref _Nullable s2);

// Compares two string objects with SQL LIKE semantics.
// NOTE: If either object is NULL, the result should be 1.
// @param str1 The first string to compare.
// @param str2 The second string to compare.
// @return 0 if the str1 is LIKE str2, else != 0.
// int cql_string_like(cql_string_ref str1, cql_string_ref str2);
int cql_string_like(cql_string_ref _Nonnull s1, cql_string_ref _Nonnull s2);

// Declare and allocate a C string from a string object.
// NOTE: This MUST be implemented as a macro, as it both declares and assigns the value.
// @param cstr The C string var to be declared and assigned.
// @param str The string object that contains the string value.
// cql_alloc_cstr(const char *cstr, cql_string_ref str);
#define cql_alloc_cstr(cstr, str) const char *_Nonnull cstr = (str)->ptr

// Free a C string that was allocated by cql_alloc_cstr
// @param cstr The C string to be freed.
// @param str The string object that the C string was allocated from.
// cql_free_cstr(const char *cstr, cql_string_ref str);
#define cql_free_cstr(cstr, str) 0

// The type for a generic cql result set.
// NOTE: Result sets are cast to this type before being passed to the cql_result_set_get_count/_data functions.
typedef struct cql_result_set *cql_result_set_ref;

// The struct must have the following fields, by name.  A different
// runtime implementation can add additional fields for its own use.
// Extra fields just go along for the right but, since you can
// recover the "meta" from the result set, you can always get to
// to your extra fields.  Note that the meta is one copy per result
// set *type* these are not instance fields.  Hence, helper functions,
// offsets common to all instances, stuff like that can go in the meta.
typedef struct cql_result_set_meta {
  // release the internal memory for the rowset
  void (*_Nonnull teardown)(cql_result_set_ref _Nonnull result_set);

  // copy a slice of a result set starting at from of length count
  void (*_Nullable copy)(
    cql_result_set_ref _Nonnull result_set,
    cql_result_set_ref _Nullable *_Nonnull to_result_set,
    cql_int32 from,
    cql_int32 count);

 // hash a row in a row set using the metadata
  cql_hash_code (*_Nullable rowHash)(
    cql_result_set_ref _Nonnull result_set,
    cql_int32 row);

 // compare two rows for equality
  cql_bool (*_Nullable rowsEqual)(
    cql_result_set_ref _Nonnull rs1,
    cql_int32 row1,
    cql_result_set_ref _Nonnull rs2,
    cql_int32 row2);

  // compare two rows for the same identity column value(s)
  cql_bool (*_Nullable rowsSame)(
    cql_result_set_ref _Nonnull rs1,
    cql_int32 row1,
    cql_result_set_ref _Nonnull rs2,
    cql_int32 row2);

  // count of references and offset to the first
  uint16_t refsCount;
  uint16_t refsOffset;

  // offsets to all the columns
  uint16_t *_Nullable columnOffsets;

  // size of the row
  size_t rowsize;

  // number of columns
  cql_int32 columnCount;

  // count and column indexes of all the columns in the identity
  uint16_t *_Nullable identityColumns;

  // all datatypes of the columns
  uint8_t *_Nullable dataTypes;

} cql_result_set_meta;

typedef struct cql_result_set {
  cql_type base;
  cql_result_set_meta meta;
  cql_int32 count;
  void *_Nonnull data;
} cql_result_set;

#define cql_result_set_type_decl(result_set_type, result_set_ref) \
  typedef struct _##result_set_type *result_set_ref;

// Construct a new result set object.
// @param data The data to be stored in the result set.
// @param count The count of records represented by the data in the result_set.
// @param callbacks The callbacks that are used for the data access.
// @return A result_set object of the type.
// cql_result_set_ref _Nonnull cql_result_set_create(
//     void *_Nonnull data,
//     cql_int32 count,
//     cql_result_set_meta meta);
cql_result_set_ref _Nonnull cql_result_set_create(
  void *_Nonnull data,
  cql_int32 count,
  cql_result_set_meta meta);

// Adds a reference count to the result_set object.
// NOTE: This MUST be implemented as a macro, as it takes a result set as a param, which has an undefined type.
// @param result_set The result set object to be retained.
// void cql_result_set_retain(** _Nullable result_set);
#define cql_result_set_retain(result_set) cql_retain((cql_type_ref)result_set);

// Subtracts a reference count from the result_set object.  When it reaches 0, the result_set SHOULD be freed.
// NOTE: This MUST be implemented as a macro, as it takes a result set as a param, which has an undefined type.
// @param result_set The result set object to be released.
// void cql_result_set_release(** _Nullable result_set);
#define cql_result_set_release(result_set) cql_release((cql_type_ref)result_set);

// Gives the metadata struct back as provided to the construction above
// NOTE: This MUST be implemented as a macro, as it takes a result set as a param, which has an undefined type.
// @param result_set The cql result_set object.
// @return The data that was previous stored on the result set.
// void *cql_result_set_get_data(** result_set)
#define cql_result_set_get_meta(result_set) (&((cql_result_set_ref)result_set)->meta)

// Retrieve the storage of the query data.
// NOTE: This MUST be implemented as a macro, as it takes a result set as a param, which has an undefined type.
// @param result_set The cql result_set object.
// @return The data that was previous stored on the result set.
// void *cql_result_set_get_data(** result_set)
#define cql_result_set_get_data(result_set) ((cql_result_set_ref)result_set)->data

// Get the count of the query data.
// NOTE: This MUST be implemented as a macro, as it takes a result set as a param, which has an undefined type.
// @param result_set The cql result set object.
// @return The count that was previous stored on the result set.
// cql_int32 cql_result_set_get_count(** result_set);
// CQLABI
#define cql_result_set_get_count(result_set) ((cql_result_set_ref)result_set)->count

#ifdef CQL_RUN_TEST
#define sqlite3_step mockable_sqlite3_step
SQLITE_API cql_code mockable_sqlite3_step(sqlite3_stmt *_Nonnull);
#endif

// No-op implementation of profiling
// * Note: we emit the crc as an expression just to be sure that there are no compiler
//   errors caused by names being incorrect.  This improves the quality of the CQL
//   code gen tests significantly.  If these were empty macros (as they once were)
//   you could emit any junk in the call and it would still compile.
#define cql_profile_start(crc, index) (void)crc; (void)index;
#define cql_profile_stop(crc, index)  (void)crc; (void)index;

// implementation of encoding values. All sensitive values read from sqlite db will
// be encoded at the source. CQL never decode encoded sensitive string unless the
// user call explicitly decode function from code.
cql_object_ref _Nullable cql_copy_encoder(sqlite3 *_Nonnull db);

cql_bool cql_encode_bool(
  cql_object_ref _Nullable encoder,
  cql_bool value,
  cql_int32 context_type,
  void *_Nullable context);

cql_int32 cql_encode_int32(
  cql_object_ref _Nullable encoder,
  cql_int32 value,
  cql_int32 context_type,
  void *_Nullable context);

cql_int64 cql_encode_int64(
  cql_object_ref _Nullable encoder,
  cql_int64 value,
  cql_int32 context_type,
  void *_Nullable context);

cql_double cql_encode_double(
  cql_object_ref _Nullable encoder,
  cql_double value,
  cql_int32 context_type,
  void *_Nullable context);

cql_string_ref _Nonnull cql_encode_string_ref_new(
  cql_object_ref _Nullable encoder,
  cql_string_ref _Nonnull value,
  cql_int32 context_type,
  void *_Nullable context);

cql_blob_ref _Nonnull cql_encode_blob_ref_new(
  cql_object_ref _Nullable encoder,
  cql_blob_ref _Nonnull value,
  cql_int32 context_type,
  void *_Nullable context);

cql_bool cql_decode_bool(
  cql_object_ref _Nullable encoder,
  cql_bool value,
  cql_int32 context_type,
  void *_Nullable context);

cql_int32 cql_decode_int32(
  cql_object_ref _Nullable encoder,
  cql_int32 value,
  cql_int32 context_type,
  void *_Nullable context);

cql_int64 cql_decode_int64(
  cql_object_ref _Nullable encoder,
  cql_int64 value,
  cql_int32 context_type,
  void *_Nullable context);

cql_double cql_decode_double(
  cql_object_ref _Nullable encoder,
  cql_double value,
  cql_int32 context_type,
  void *_Nullable context);

cql_string_ref _Nonnull cql_decode_string_ref_new(
  cql_object_ref _Nullable encoder,
  cql_string_ref _Nonnull value,
  cql_int32 context_type,
  void *_Nullable context);

cql_blob_ref _Nonnull cql_decode_blob_ref_new(
  cql_object_ref _Nullable encoder,
  cql_blob_ref _Nonnull value,
  cql_int32 context_type,
  void *_Nullable context);

// NOTE: This must be included *after* all of the above symbols/macros.
#include "cqlrt_common.h"
