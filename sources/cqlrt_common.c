/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

// Note: the terms "rowset" and "result set" are used pretty much interchangebly
// to mean the same thing.

#include <stdlib.h>

// Enable this to print a trace of running statements to stderr
// #define CQL_TRACE_STATEMENTS 1

#if defined(TARGET_OS_LINUX) && TARGET_OS_LINUX
#include <alloca.h>
#endif // TARGET_OS_LINUX

#ifndef STACK_BYTES_ALLOC
#if defined(TARGET_OS_WIN32) && TARGET_OS_WIN32
#define STACK_BYTES_ALLOC(N, C) char *N = (char *)_alloca(C)
#elif defined(TARGET_OS_LINUX) && TARGET_OS_LINUX
#define STACK_BYTES_ALLOC(N, C) char *N = (char *)alloca(C)
#else // TARGET_OS_WIN32
#define STACK_BYTES_ALLOC(N, C) char N[C]
#endif // TARGET_OS_WIN32
#endif // STACK_BYTES_ALLLOC

static cql_bool cql_blobtype_vs_argtype_compat(
  sqlite3_value *_Nonnull field_value_arg,
  int8_t blob_column_type,
  uint64_t *_Nonnull variable_size);

// This code is used in the event of a THROW inside a stored proc.  When that
// happens we want to keep the result code we have if there was a recent error.
// If we recently got a success, then use SQLITE_ERROR as the thrown error
// instead.
cql_code cql_best_error(cql_code rc) {
  if (rc == SQLITE_OK || rc == SQLITE_DONE || rc == SQLITE_ROW) {
    return SQLITE_ERROR;
  }
  return rc;
}

// The indicated statement should be immediately finalized out latest result was
// not SQLITE_OK This code is used during binding (which is now always done with
// multibind) in order to ensure that the statement exits finalized in the event
// of any binding failure.
void cql_finalize_on_error(
  cql_code rc,
  sqlite3_stmt *_Nullable *_Nonnull pstmt) {
  cql_contract(pstmt && *pstmt);
  if (rc != SQLITE_OK) {
    cql_finalize_stmt(pstmt);
  }
}

// This method is used when handling CQL cursors; the cursor local variable may
// already contain a statement.  When preparing a new statement, we want to
// finalize any statement the cursor used to hold.  This lets us do simple
// preparation in a loop without added conditionals in the generated code.
cql_code cql_prepare(
  sqlite3 *_Nonnull db,
  sqlite3_stmt *_Nullable *_Nonnull pstmt,
  const char *_Nonnull sql)
{

  cql_finalize_stmt(pstmt);
  cql_code rc = cql_sqlite3_prepare_v2(db, sql, -1, pstmt, NULL);

#ifdef CQL_TRACE_STATEMENTS
  if (rc) {
    fprintf(stderr, "PREP> %s\n", sql);
    fprintf(stderr, "Error %d %s\n", rc, sqlite3_errmsg(db));
  }
#endif
  return rc;
}

// create a single string from the varargs and count provided
static char *_Nonnull cql_vconcat(
  cql_uint32 count,
  const char *_Nullable preds,
  va_list *_Nonnull args)
{
  va_list pass1, pass2;
  va_copy(pass1, *args);
  va_copy(pass2, *args);

  cql_uint32 bytes = 0;

  // first we have to figure out how much to allocate
  for (cql_uint32 istr = 0; istr < count; istr++) {
    const char *str = va_arg(pass1, const char *);
    if (!preds || preds[istr]) {
      bytes += strlen(str);
    }
  }

  char *result = malloc(bytes + 1);

  cql_int32 offset = 0;

  for (cql_uint32 istr = 0; istr < count; istr++) {
    const char *str = va_arg(pass2, const char *);
    if (!preds || preds[istr]) {
      size_t len = strlen(str);
      memcpy(result + offset, str, len + 1); // copies the trailing null byte
      offset += len;
    }
  }

  va_end(pass1);
  va_end(pass2);

  return result;
}

// This method is used when handling CQL cursors; the cursor local variable may
// already contain a statement.  When preparing a new statement, we want to
// finalize any statement the cursor used to hold.  This lets us do simple
// preparation in a loop without added conditionals in the generated code.  This
// is the varargs version
cql_code cql_prepare_var(
  sqlite3 *_Nonnull db,
  sqlite3_stmt *_Nullable *_Nonnull pstmt,
  cql_uint32 count,
  const char *_Nullable preds, ...)
{
  cql_finalize_stmt(pstmt);
  va_list args;
  va_start(args, preds);
  char *sql = cql_vconcat(count, preds, &args);
  cql_code rc = cql_sqlite3_prepare_v2(db, sql, -1, pstmt, NULL);
  va_end(args);
#ifdef CQL_TRACE_STATEMENTS
  if (rc) {
    fprintf(stderr, "PREP> %s\n", sql);
    fprintf(stderr, "Error %d %s\n", rc, sqlite3_errmsg(db));
  }
#endif
  free(sql);
  return rc;
}

// This is a simple wrapper for the sqlite3_exec method with the usual extra
// arguments. This code is here just to reduce the code size of exec calls in
// the generated code. There are a lot of such calls.
cql_code cql_exec(sqlite3 *_Nonnull db, const char *_Nonnull sql) {
  cql_code rc = cql_sqlite3_exec(db, sql);

#ifdef CQL_TRACE_STATEMENTS
  if (rc) {
    fprintf(stderr, "EXEC> %s\n", sql);
    fprintf(stderr, "Error %d %s\n", rc, sqlite3_errmsg(db));
  }
#endif
  return rc;
}

// This is a simple wrapper for the sqlite3_exec method with the usual extra
// arguments. This code is here just to reduce the code size of exec calls in
// the generated code. There are a lot of such calls.
cql_code cql_exec_var(
  sqlite3 *_Nonnull db,
  cql_uint32 count,
  const char *_Nullable preds, ...)
{
  va_list args;
  va_start(args, preds);
  char *sql = cql_vconcat(count, preds, &args);
  cql_code rc = cql_sqlite3_exec(db, sql);
  va_end(args);
#ifdef CQL_TRACE_STATEMENTS
  if (rc) {
    fprintf(stderr, "EXEC> %s\n", sql);
    fprintf(stderr, "Error %d %s\n", rc, sqlite3_errmsg(db));
  }
#endif
  free(sql);
  return rc;
}

// This version of exec takes a string variable and is therefore more dangerous.
// It is only intended to be used in the context of schema maintenance or other
// cases where there are highly compressible patterns (like DROP TRIGGER %s for
// 1000s of triggers). All we do is convert the incoming string reference into a
// C string and then exec it.
CQL_WARN_UNUSED cql_code cql_exec_internal(
  sqlite3 *_Nonnull db,
  cql_string_ref _Nonnull str_ref)
{
  cql_alloc_cstr(temp, str_ref);
  cql_code rc = cql_sqlite3_exec(db, temp);
  cql_free_cstr(temp, str_ref);
  return rc;
}

char *_Nonnull cql_address_of_col(
  cql_result_set_ref _Nonnull result_set,
  cql_int32 row,
  cql_int32 col,
  cql_int32 *_Nonnull type);

// The variable byte encoding is little endian, you stop when you reach a byte
// that does not have the high bit set.  This is good enough for 2^28 bits in
// four bytes which is more than enough for sql strings...
static const char *_Nonnull cql_decode(
  const char *_Nonnull data,
  cql_int32 *_Nonnull result)
{
  cql_int32 out = 0;
  cql_int32 byte;
  cql_int32 offset = 0;
  do {
    byte = *data++;
    out |= (byte & 0x7f) << offset;
    offset += 7;
  } while (byte & 0x80);
  *result = out;
  return data;
}

// The base pointer contains the address of the string part Each fragment is
// variable length encoded as above with a +1 on the offset If an offset of 0 is
// encountered, that means stop. Since the fragements are represented as a
// string, that means the normal null terminator in the string is the stop
// signal.
static void cql_expand_frags(
  char *_Nonnull result,
  const char *_Nonnull base,
  const char *_Nonnull frags)
{
  cql_int32 offset;
  for (;;) {
    frags = cql_decode(frags, &offset);
    if (offset == 0) {
      break;
    }

    const char *src = base + offset - 1;
    while (*src) {
      *result++ = *src++;
    }
  }
  *result = 0;
}

// To keep the contract as simple as possible we encode everything we need into
// the fragment array.  Including the size of the output and fragment
// terminator.  See above.  This also makes the code gen as simple as possible.
cql_code cql_prepare_frags(
  sqlite3 *_Nonnull db,
  sqlite3_stmt *_Nullable *_Nonnull pstmt,
  const char *_Nonnull base,
  const char *_Nonnull frags)
{
  // NOTE: len is the allocation size (includes trailing \0)
  cql_finalize_stmt(pstmt);
  cql_int32 len;
  frags = cql_decode(frags, &len);
  STACK_BYTES_ALLOC(sql, len);
  cql_expand_frags(sql, base, frags);
  cql_code rc = cql_sqlite3_prepare_v2(db, sql, len, pstmt, NULL);
#ifdef CQL_TRACE_STATEMENTS
  if (rc) {
    fprintf(stderr, "PREP> %s\n", sql);
    fprintf(stderr, "Error %d %s\n", rc, sqlite3_errmsg(db));
  }
#endif
  return rc;
}

// To keep the contract as simple as possible we encode everything we need into
// the fragment array.  Including the size of the output and fragment
// terminator.  See above.  This also makes the code gen as simple as possible.
cql_code cql_exec_frags(
  sqlite3 *_Nonnull db,
  const char *_Nonnull base,
  const char *_Nonnull frags)
{
  // NOTE: len is the allocation size (includes trailing \0)
  cql_int32 len;
  frags = cql_decode(frags, &len);
  STACK_BYTES_ALLOC(sql, len);
  cql_expand_frags(sql, base, frags);
  cql_code rc = cql_sqlite3_exec(db, sql);
#ifdef CQL_TRACE_STATEMENTS
  if (rc) {
    fprintf(stderr, "EXEC> %s\n", sql);
    fprintf(stderr, "Error %d %s\n", rc, sqlite3_errmsg(db));
  }
#endif
  return rc;
}

// Finalizes the statement if it is not null.  Note that the statement pointer
// must be not null but the statement it holds may or may not be initialized.
// Also note that ALL CQL STATEMENTS ARE INITIALIZED TO NULL!!
void cql_finalize_stmt(sqlite3_stmt *_Nullable *_Nonnull pstmt) {
  cql_contract(pstmt);
  if (*pstmt) {
    cql_sqlite3_finalize(*pstmt);
    *pstmt = NULL;
  }
}

// Read a nullable bool from the statement at the indicated index.
// If the column is null then return null.
// If not null then return the value.
// This is used in the general purpose column readers cql_multifetch and
// cql_multifetch_meta. to get column access to bools without having to open
// code the null check every time.
void cql_column_nullable_bool(
  sqlite3_stmt *_Nonnull stmt,
  cql_int32 index,
  cql_nullable_bool *_Nonnull data)
{
  if (sqlite3_column_type(stmt, index) == SQLITE_NULL) {
    cql_set_null(*data);
  }
  else {
    cql_set_notnull(*data, !!sqlite3_column_int(stmt, index));
  }
}

// Read a nullable int32 from the statement at the indicated index.
// If the column is null then return null.
// If not null then return the value.
// This is used in the general purpose column readers cql_multifetch and
// cql_multifetch_meta. to get column access to int32s without having to open
// code the null check every time.
void cql_column_nullable_int32(
  sqlite3_stmt *_Nonnull stmt,
  cql_int32 index,
  cql_nullable_int32 *_Nonnull data)
{
  if (sqlite3_column_type(stmt, index) == SQLITE_NULL) {
    cql_set_null(*data);
  }
  else {
    cql_set_notnull(*data, sqlite3_column_int(stmt, index));
  }
}

// Read a nullable int64 from the statement at the indicated index.
// If the column is null then return null.
// If not null then return the value.
// This is used in the general purpose column readers cql_multifetch and
// cql_multifetch_meta. to get column access to int64s without having to open
// code the null check every time.
void cql_column_nullable_int64(
  sqlite3_stmt *_Nonnull stmt,
  cql_int32 index,
  cql_nullable_int64 *_Nonnull data)
{
  if (sqlite3_column_type(stmt, index) == SQLITE_NULL) {
    cql_set_null(*data);
  }
  else {
    cql_set_notnull(*data, sqlite3_column_int64(stmt, index));
  }
}

// Read a nullable double from the statement at the indicated index.
// If the column is null then return null.
// If not null then return the value.
// This is used in the general purpose column readers cql_multifetch and
// cql_multifetch_meta. to get column access to doubles without having to open
// code the null check every time.
void cql_column_nullable_double(
  sqlite3_stmt *_Nonnull stmt,
  cql_int32 index,
  cql_nullable_double *_Nonnull data)
{
  if (sqlite3_column_type(stmt, index) == SQLITE_NULL) {
    cql_set_null(*data);
  }
  else {
    cql_set_notnull(*data, sqlite3_column_double(stmt, index));
  }
}

// Read a nullable string reference from the statement at the indicated index.
// If the column is null then return null.
// If not null then return the value.
// This is used in the general purpose column readers cql_multifetch and
// cql_multifetch_meta. to get column access to strings without having to open
// code the null check every time.
void cql_column_nullable_string_ref(
  sqlite3_stmt *_Nonnull stmt,
  cql_int32 index,
  cql_string_ref _Nullable *_Nonnull data)
{
  // the target may already have data, release it if it does
  cql_string_release(*data);
  if (sqlite3_column_type(stmt, index) == SQLITE_NULL) {
    *data = NULL;
  }
  else {
    *data = cql_string_ref_new((const char *)sqlite3_column_text(stmt, index));
  }
}

// Read a string reference from the statement at the indicated index.
// This is used in the general purpose column readers cql_multifetch and
// cql_multifetch_meta.
void cql_column_string_ref(
  sqlite3_stmt *_Nonnull stmt,
  cql_int32 index,
  cql_string_ref _Nonnull *_Nonnull data)
{
  // the target may already have data, release it if it does
  cql_string_release(*data);
  *data = cql_string_ref_new((const char *)sqlite3_column_text(stmt, index));
}

// Read a nullable blob reference from the statement at the indicated index.
// If the column is null then return null.
// If not null then return the value.
// This is used in the general purpose column readers cql_multifetch and
// cql_multifetch_meta. to get column access to blobs without having to open
// code the null check every time.
void cql_column_nullable_blob_ref(
  sqlite3_stmt *_Nonnull stmt,
  cql_int32 index,
  cql_blob_ref _Nullable *_Nonnull data)
{
  // the target may already have data, release it if it does
  cql_blob_release(*data);
  if (sqlite3_column_type(stmt, index) == SQLITE_NULL) {
    *data = NULL;
  }
  else {
    const void *bytes = sqlite3_column_blob(stmt, index);
    cql_int32 size = (cql_int32)sqlite3_column_bytes(stmt, index);
    *data = cql_blob_ref_new(bytes, size);
  }
}

// Read a blob reference from the statement at the indicated index. This is used
// in the general purpose column readers cql_multifetch and cql_multifetch_meta.
void cql_column_blob_ref(
  sqlite3_stmt *_Nonnull stmt,
  cql_int32 index,
  cql_blob_ref _Nonnull *_Nonnull data)
{
  // the target may already have data, release it if it does
  cql_blob_release(*data);
  const void *bytes = sqlite3_column_blob(stmt, index);
  cql_int32 size = (cql_int32)sqlite3_column_bytes(stmt, index);
  *data = cql_blob_ref_new(bytes, size);
}

// This helper is used by CQL to set an object reference.  It does the primitive
// retain/release operations. For now all the reference types are the same in
// this regard but there are different helpers for additional type safety in the
// generated code and readability (and breakpoints).
void cql_set_object_ref(
  cql_object_ref _Nullable *_Nonnull target,
  cql_object_ref _Nullable source)
{
  // upcount first in case source is an alias for target
  cql_object_retain(source);
  cql_object_release(*target);
  *target = source;
}

// This variant is for when you call a Create function and get a ref with a +1 on it
// and have to store that reference.
void cql_set_created_object_ref(
  cql_object_ref _Nullable *_Nonnull target,
  cql_object_ref _Nullable source)
{
  // no upcount, we were given an upcounted ref. We just release what we had and store
  cql_object_release(*target);
  *target = source;
}

// This helper is used by CQL to set a string reference.  It does the primitive
// retain/release operations. For now all the reference types are the same in
// this regard but there are different helpers for additional type safety in the
// generated code and readability (and breakpoints).
void cql_set_string_ref(
  cql_string_ref _Nullable *_Nonnull target,
  cql_string_ref _Nullable source)
{
  // upcount first in case source is an alias for target
  cql_string_retain(source);
  cql_string_release(*target);
  *target = source;
}

// This variant is for when you call a Create function and get a ref with a +1 on it
// and have to store that reference.
void cql_set_created_string_ref(
  cql_string_ref _Nullable *_Nonnull target,
  cql_string_ref _Nullable source)
{
  // no upcount, we were given an upcounted ref. We just release what we had and store
  cql_string_release(*target);
  *target = source;
}

// This helper is used by CQL to set a blob reference.  It does the primitive
// retain/release operations. For now all the reference types are the same in
// this regard but there are different helpers for additional type safety in the
// generated code and readability (and breakpoints).
void cql_set_blob_ref(
  cql_blob_ref _Nullable *_Nonnull target,
  cql_blob_ref _Nullable source)
{
  // upcount first in case source is an alias for target
  cql_blob_retain(source);
  cql_blob_release(*target);
  *target = source;
}

// This variant is for when you call a Create function and get a ref with a +1 on it
// and have to store that reference.
void cql_set_created_blob_ref(
  cql_blob_ref _Nullable *_Nonnull target,
  cql_blob_ref _Nullable source)
{
  // no upcount, we were given an upcounted ref. We just release what we had and store
  cql_blob_release(*target);
  *target = source;
}

#ifdef CQL_RUN_TEST
jmp_buf *_Nullable cql_contract_argument_notnull_tripwire_jmp_buf;
#endif

// Wraps calls to `cql_tripwire` to allow us to longjmp, if required. This is
// called for both the argument itself and, in the case of an INOUT NOT NULL
// reference type argument, what the argument points to as well.
static void cql_contract_argument_notnull_tripwire(
  void *_Nullable ptr,
  cql_uint32 position)
{
#ifdef CQL_RUN_TEST
  if (cql_contract_argument_notnull_tripwire_jmp_buf && !ptr) {
    longjmp(*cql_contract_argument_notnull_tripwire_jmp_buf, position);
  }
#endif
  cql_tripwire(ptr);
}

// This will be called in the case of an INOUT NOT NULL reference type argument
// to ensure that `argument` does not point to NULL. This function does not need
// per-position variants (as `DEFINE_ARGUMENT_AT_POSITION_N_MUST_NOT_BE_NULL`
// enables) as such a function will always be above this in the stack.
// `__attribute__((optnone))` is used to ensure we actually see this in stack
// traces and it doesn't get inlined or merged away.
CQL_OPT_NONE static void cql_inout_reference_type_notnull_argument_must_not_point_to_null(
  void *_Nullable *_Nonnull argument,
  cql_uint32 position)
{
  cql_contract_argument_notnull_tripwire(*argument, position);
}

// This helps us generate variants of nonnull argument enforcement for each of
// the first eight arguments. As above, `__attribute__((optnone))` prevents
// these from getting inlined or merged.
#define DEFINE_ARGUMENT_AT_POSITION_N_MUST_NOT_BE_NULL(N) \
  CQL_OPT_NONE \
  static void cql_argument_at_position_ ## N ## _must_not_be_null(void *_Nullable argument, cql_bool inout_notnull) { \
   cql_contract_argument_notnull_tripwire(argument, N); \
    if (inout_notnull) { \
      cql_inout_reference_type_notnull_argument_must_not_point_to_null(argument, N); \
    } \
  }

DEFINE_ARGUMENT_AT_POSITION_N_MUST_NOT_BE_NULL(1);
DEFINE_ARGUMENT_AT_POSITION_N_MUST_NOT_BE_NULL(2);
DEFINE_ARGUMENT_AT_POSITION_N_MUST_NOT_BE_NULL(3);
DEFINE_ARGUMENT_AT_POSITION_N_MUST_NOT_BE_NULL(4);
DEFINE_ARGUMENT_AT_POSITION_N_MUST_NOT_BE_NULL(5);
DEFINE_ARGUMENT_AT_POSITION_N_MUST_NOT_BE_NULL(6);
DEFINE_ARGUMENT_AT_POSITION_N_MUST_NOT_BE_NULL(7);
DEFINE_ARGUMENT_AT_POSITION_N_MUST_NOT_BE_NULL(8);

CQL_OPT_NONE static void cql_argument_at_position_9_or_greater_must_not_be_null(
  void *_Nullable argument,
  cql_uint32 position,
  cql_bool deref)
{
  cql_contract_argument_notnull_tripwire(argument, position);
  if (deref) {
    cql_inout_reference_type_notnull_argument_must_not_point_to_null(argument, position);
  }
}

// Calls a position-specific function that will call `cql_tripwire(argument)`
// (and `cql_tripwire(*argument)` when `deref` is true, as in the case of `INOUT
// arg R NOT NULL`, where `R` is some reference type). This is done so that a
// maximally informative function name will appear in stack traces.
//
// NOTE: This function takes a `position` starting from 1 instead of an `index`
// starting from 0 so that, when someone is debugging a crash, `position` will
// line up with the name of the position-specific function and not cause
// confusion. Having the "first argument" be "position 1", as opposed to "index
// 0", seems to be the most intuitive. It also makes things a bit cleaner when
// performing a longjmp during testing (because jumping with 0 is
// indistinguishable from jumping with 1).
static void cql_contract_argument_notnull_with_optional_dereference_check(
  void *_Nullable argument,
  cql_uint32 position,
  cql_bool deref)
{
  switch (position) {
    case 1:
      return cql_argument_at_position_1_must_not_be_null(argument, deref);
    case 2:
      return cql_argument_at_position_2_must_not_be_null(argument, deref);
    case 3:
      return cql_argument_at_position_3_must_not_be_null(argument, deref);
    case 4:
      return cql_argument_at_position_4_must_not_be_null(argument, deref);
    case 5:
      return cql_argument_at_position_5_must_not_be_null(argument, deref);
    case 6:
      return cql_argument_at_position_6_must_not_be_null(argument, deref);
    case 7:
      return cql_argument_at_position_7_must_not_be_null(argument, deref);
    case 8:
      return cql_argument_at_position_8_must_not_be_null(argument, deref);
    default:
      return cql_argument_at_position_9_or_greater_must_not_be_null(argument, position, deref);
  }
}

void cql_contract_argument_notnull(
  void * _Nullable argument,
  cql_uint32 position)
{
  cql_contract_argument_notnull_with_optional_dereference_check(argument, position, false);
}

void cql_contract_argument_notnull_when_dereferenced(
  void * _Nullable argument,
  cql_uint32 position)
{
  cql_contract_argument_notnull_with_optional_dereference_check(argument, position, true);
}

// Creates a growable byte-buffer.  This code is used in the creation of the
// data blob for a result set. The buffer will double in size when it would
// otherwise overflow resulting in at most 2N data operations for N rows.
void cql_bytebuf_open(cql_bytebuf *_Nonnull b) {
  b->max = BYTEBUF_GROWTH_SIZE;
  b->ptr = malloc(b->max);
  b->used = 0;
}

// Dispenses the buffer's memory when it is closed.
void cql_bytebuf_close(cql_bytebuf *_Nonnull b) {
  free(b->ptr);
  b->max = 0;
  b->ptr = NULL;
}

// Get more memory from the byte buffer.  This will be used to get memory for
// each new row in a result set. Note: the data is assumed to be location
// independent and reference count invariant. (i.e. you can memcpy it safely if
// you then also destroy the old copy)
void *_Nonnull cql_bytebuf_alloc(
  cql_bytebuf *_Nonnull b,
  cql_uint32 needed)
{
  cql_uint32 avail = b->max - b->used;

  if (needed > avail) {
    if (b->max > BYTEBUF_EXP_GROWTH_CAP) {
      b->max = needed + BYTEBUF_GROWTH_SIZE_AFTER_CAP + b->max;
    }
    else {
      b->max = needed + 2 * b->max;
    }
    char *newptr = malloc(b->max);

    memcpy(newptr, b->ptr, b->used);
    free(b->ptr);
    b->ptr = newptr;
  }

  void *result = b->ptr + b->used;
  b->used += needed;
  return result;
}

// simple helper to append into a byte buffer
void cql_bytebuf_append(
  cql_bytebuf *_Nonnull buffer,
  const void *_Nonnull data,
  cql_uint32 bytes)
{
  void *pv = cql_bytebuf_alloc(buffer, bytes);
  memcpy(pv, data, bytes);
}

// This is a simple wrapper on vsnprintf, we do two passes first to compute the
// bytes needed which we allocate using cql_bytebuf_alloc and then we write the
// formatted string.  Note that it's normal to call this many times or in mixed
// ways so the null terminator is not desired. The buffer gets the text of the
// string only.  Use cql_bytebuf_append_null to null terminate.
static void cql_vbprintf(
  cql_bytebuf *_Nonnull buffer,
  const char *_Nonnull format,
  va_list *_Nonnull args)
{
  va_list pass1, pass2;
  va_copy(pass1, *args);
  va_copy(pass2, *args);

  // +1 to include the trailing null we will need (but don't want)
  uint32_t needed = (uint32_t)vsnprintf(NULL, 0, format, pass1) + 1;

  char *newptr = cql_bytebuf_alloc(buffer, needed);

  // We can't stop this from writing a null terminator
  vsnprintf(newptr, needed, format, pass2);

  // We don't want the null terminator, se we remove it.
  buffer->used--;

  va_end(pass1);
  va_end(pass2);
}

// This allows you to write into a bytebuf using a format string and varargs
// All the work is delegated really, vsnprinf ultimately does everything but
// first we need to call the function that does the size computation.
void cql_bprintf(
  cql_bytebuf *_Nonnull buffer,
  const char *_Nonnull format, ...)
{
  va_list args;
  va_start(args, format);
  cql_vbprintf(buffer, format, &args);
  va_end(args);
}

// After using cql_bprintf it's pretty normal to need to add a null terminator
// to create a C style string.  Though not always depending on where the buffer
// is going. This helps with that need.
void cql_bytebuf_append_null(cql_bytebuf *_Nonnull buffer) {
  char var = 0;
  cql_bytebuf_append(buffer, &var, sizeof(var));
}

// If there is no row available we can use this helper to ensure that the output
// data is put into a known state.
static void cql_multinull(
  cql_uint32 count,
  va_list *_Nonnull args)
{
  for (cql_int32 column = 0; column < count; column++) {
    cql_int32 type = va_arg(*args, cql_int32);
    cql_int32 core_data_type = CQL_CORE_DATA_TYPE_OF(type);

    if (type & CQL_DATA_TYPE_NOT_NULL) {
      switch (core_data_type) {
        case CQL_DATA_TYPE_INT32: {
          cql_int32 *int32_data = va_arg(*args, cql_int32 *);
          *int32_data = 0;
          break;
        }
        case CQL_DATA_TYPE_INT64: {
          cql_int64 *int64_data = va_arg(*args, cql_int64 *);
          *int64_data = 0;
          break;
        }
        case CQL_DATA_TYPE_DOUBLE: {
          cql_double *double_data = va_arg(*args, cql_double *);
          *double_data = 0;
          break;
        }
        case CQL_DATA_TYPE_BOOL: {
          cql_bool *bool_data = va_arg(*args, cql_bool *);
          *bool_data = 0;
          break;
        }
        case CQL_DATA_TYPE_STRING: {
          cql_string_ref *str_ref = va_arg(*args, cql_string_ref *);
          cql_set_string_ref(str_ref, NULL);
          break;
        }
        case CQL_DATA_TYPE_BLOB: {
          cql_blob_ref *blob_ref = va_arg(*args, cql_blob_ref *);
          cql_set_blob_ref(blob_ref, NULL);
          break;
        }
        case CQL_DATA_TYPE_OBJECT: {
          cql_object_ref *object_ref = va_arg(*args, cql_object_ref *);
          cql_set_object_ref(object_ref, NULL);
          break;
        }
      }
    }
    else {
      switch (core_data_type) {
        case CQL_DATA_TYPE_INT32: {
          cql_nullable_int32 *_Nonnull int32p = va_arg(*args, cql_nullable_int32 *_Nonnull);
          cql_set_null(*int32p);
          break;
        }
        case CQL_DATA_TYPE_INT64: {
          cql_nullable_int64 *_Nonnull int64p = va_arg(*args, cql_nullable_int64 *_Nonnull);
          cql_set_null(*int64p);
          break;
        }
        case CQL_DATA_TYPE_DOUBLE: {
          cql_nullable_double *_Nonnull doublep = va_arg(*args, cql_nullable_double *_Nonnull);
          cql_set_null(*doublep);
          break;
        }
        case CQL_DATA_TYPE_BOOL: {
          cql_nullable_bool *_Nonnull boolp = va_arg(*args, cql_nullable_bool *_Nonnull);
          cql_set_null(*boolp);
          break;
        }
        case CQL_DATA_TYPE_STRING: {
          cql_string_ref *str_ref = va_arg(*args, cql_string_ref *);
          cql_set_string_ref(str_ref, NULL);
          break;
        }
        case CQL_DATA_TYPE_BLOB: {
          cql_blob_ref *blob_ref = va_arg(*args, cql_blob_ref *);
          cql_set_blob_ref(blob_ref, NULL);
          break;
        }
        // presently unreachable -- will add coverage when this is reachable
        // case CQL_DATA_TYPE_OBJECT: {
        //   cql_object_ref *object_ref = va_arg(*args, cql_object_ref *);
        //   cql_set_object_ref(object_ref, NULL);
        //   break;
        // }
      }
    }
  }
}

// This helper fetch a column value from sqlite and store it in the holder.
static void cql_fetch_field(
  cql_int32 type,
  cql_int32 column,
  sqlite3 *_Nonnull db,
  sqlite3_stmt *_Nullable stmt,
  char *_Nonnull field)
{
  cql_int32 core_data_type_and_not_null = type;

  switch (core_data_type_and_not_null) {
    case CQL_DATA_TYPE_INT32 | CQL_DATA_TYPE_NOT_NULL: {
      cql_int32 *int32_data = (cql_int32 *)field;
      *int32_data = sqlite3_column_int(stmt, column);
      break;
    }
    case CQL_DATA_TYPE_INT64 | CQL_DATA_TYPE_NOT_NULL: {
      cql_int64 *int64_data = (cql_int64 *)field;
      *int64_data = sqlite3_column_int64(stmt, column);
      break;
    }
    case CQL_DATA_TYPE_DOUBLE | CQL_DATA_TYPE_NOT_NULL: {
      cql_double *double_data = (cql_double *)field;
      *double_data = sqlite3_column_double(stmt, column);
      break;
    }
    case CQL_DATA_TYPE_BOOL | CQL_DATA_TYPE_NOT_NULL: {
      cql_bool *bool_data = (cql_bool *)field;
      *bool_data = !!sqlite3_column_int(stmt, column);
      break;
    }
    case CQL_DATA_TYPE_STRING | CQL_DATA_TYPE_NOT_NULL: {
      cql_string_ref *str_ref = (cql_string_ref *)field;
      cql_column_string_ref(stmt, column, str_ref);
      break;
    }
    case CQL_DATA_TYPE_BLOB | CQL_DATA_TYPE_NOT_NULL: {
      cql_blob_ref *blob_ref = (cql_blob_ref *)field;
      cql_column_blob_ref(stmt, column, blob_ref);
      break;
    }
    case CQL_DATA_TYPE_INT32: {
      cql_nullable_int32 *_Nonnull int32p = (cql_nullable_int32 *)field;
      cql_column_nullable_int32(stmt, column, int32p);
      break;
    }
    case CQL_DATA_TYPE_INT64: {
      cql_nullable_int64 *_Nonnull int64p = (cql_nullable_int64 *)field;
      cql_column_nullable_int64(stmt, column, int64p);
      break;
    }
    case CQL_DATA_TYPE_DOUBLE: {
      cql_nullable_double *_Nonnull doublep = (cql_nullable_double *)field;
      cql_column_nullable_double(stmt, column, doublep);
      break;
    }
    case CQL_DATA_TYPE_BOOL: {
      cql_nullable_bool *_Nonnull boolp = (cql_nullable_bool *)field;
      cql_column_nullable_bool(stmt, column, boolp);
      break;
    }
    case CQL_DATA_TYPE_STRING: {
      cql_string_ref *str_ref = (cql_string_ref *)field;
      cql_column_nullable_string_ref(stmt, column, str_ref);
      break;
    }
    case CQL_DATA_TYPE_BLOB: {
      cql_blob_ref *blob_ref = (cql_blob_ref *)field;
      cql_column_nullable_blob_ref(stmt, column, blob_ref);
      break;
    }
  }
}

// This method lets us get lots of columns out of a statement with one call in
// the generated code saving us a lot of error management and reducing the
// generated code cost to just the offsets and types.  This version does the
// fetch based on the "fetch info" which includes, among other things an array
// of types and an array of offsets.
void cql_multifetch_meta(
  char *_Nonnull data,
  cql_fetch_info *_Nonnull info)
{
  cql_contract(info->stmt);
  cql_contract(info->db);
  sqlite3_stmt *stmt = info->stmt;
  sqlite3 *db = info->db;
  uint8_t *_Nonnull data_types = info->data_types;
  uint16_t *_Nonnull col_offsets = info->col_offsets;

  uint32_t count = col_offsets[0];
  col_offsets++;

  for (cql_int32 column = 0; column < count; column++) {
    uint8_t type = data_types[column];
    char *field = data + col_offsets[column];
    cql_fetch_field(type, column, db, stmt, field);
  }
}

// This method lets us get lots of columns out of a statement with one call in
// the generated code saving us a lot of error management and reducing the
// generated code cost to just the offsets and types. This version does the
// fetching using varargs with types and addresses. This is the most flexible
// as it allows writing into local variables and out parameters.
void cql_multifetch(
  cql_code rc,
  sqlite3_stmt *_Nullable stmt,
  cql_uint32 count, ...)
{
  va_list args;
  va_start(args, count);

  if (rc != SQLITE_ROW) {
    cql_multinull(count, &args);
    va_end(args);
    return;
  }

  cql_contract(stmt);
  sqlite3 *db = sqlite3_db_handle(stmt);

  for (cql_int32 column = 0; column < count; column++) {
    cql_int32 type = va_arg(args, cql_int32);
    void *field = va_arg(args, void *);
    cql_fetch_field(type, column, db, stmt, field);
  }

  va_end(args);
}

// This method lets us get lots of columns out of a statement with one call
// in the generated code saving us a lot of error management and reducing the
// generated code cost to just the offsets and types.  This version does the
// fetching using varargs with types and addresses.  This is the most flexible
// as it allows writing into local variables and out parameters.
void cql_copyoutrow(
  sqlite3 *_Nullable db,
  cql_result_set_ref _Nonnull result_set,
  cql_int32 row,
  cql_uint32 count, ...)
{
  cql_contract(result_set);

  va_list args;
  va_start(args, count);

  cql_int32 row_count = cql_result_set_get_count(result_set);

  if (row >= row_count || row < 0) {
    cql_multinull(count, &args);
    va_end(args);
    return;
  }

  // Find vault context column

  for (cql_int32 column = 0; column < count; column++) {
    cql_int32 type = va_arg(args, cql_int32);
    cql_int32 core_data_type_and_not_null = CQL_CORE_DATA_TYPE_OF(type) | (type & CQL_DATA_TYPE_NOT_NULL);

    switch (core_data_type_and_not_null) {
      case CQL_DATA_TYPE_INT32 | CQL_DATA_TYPE_NOT_NULL: {
        cql_int32 *int32_data = va_arg(args, cql_int32 *);
        *int32_data = cql_result_set_get_int32_col(result_set, row, column);
        break;
      }
      case CQL_DATA_TYPE_INT64 | CQL_DATA_TYPE_NOT_NULL: {
        cql_int64 *int64_data = va_arg(args, cql_int64 *);
        *int64_data = cql_result_set_get_int64_col(result_set, row, column);
        break;
      }
      case CQL_DATA_TYPE_DOUBLE | CQL_DATA_TYPE_NOT_NULL: {
        cql_double *double_data = va_arg(args, cql_double *);
        *double_data = cql_result_set_get_double_col(result_set, row, column);
        break;
      }
      case CQL_DATA_TYPE_BOOL | CQL_DATA_TYPE_NOT_NULL: {
        cql_bool *bool_data = va_arg(args, cql_bool *);
        *bool_data = cql_result_set_get_bool_col(result_set, row, column);
        break;
      }
      case CQL_DATA_TYPE_STRING | CQL_DATA_TYPE_NOT_NULL: {
        cql_string_ref *str_ref = va_arg(args, cql_string_ref *);
        cql_set_string_ref(str_ref, cql_result_set_get_string_col(result_set, row, column));
        break;
      }
      case CQL_DATA_TYPE_BLOB | CQL_DATA_TYPE_NOT_NULL: {
        cql_blob_ref *blob_ref = va_arg(args, cql_blob_ref *);
        cql_set_blob_ref(blob_ref, cql_result_set_get_blob_col(result_set, row, column));
        break;
      }
      case CQL_DATA_TYPE_OBJECT | CQL_DATA_TYPE_NOT_NULL: {
        cql_object_ref *obj_ref = va_arg(args, cql_object_ref *);
        cql_set_object_ref(obj_ref, cql_result_set_get_object_col(result_set, row, column));
        break;
      }
      case CQL_DATA_TYPE_INT32: {
        cql_nullable_int32 *_Nonnull int32p = va_arg(args, cql_nullable_int32 *_Nonnull);
        if (cql_result_set_get_is_null_col(result_set, row, column)) {
          cql_set_null(*int32p);
        }
        else {
          cql_set_notnull(*int32p, cql_result_set_get_int32_col(result_set, row, column));
        }
        break;
      }
      case CQL_DATA_TYPE_INT64: {
        cql_nullable_int64 *_Nonnull int64p = va_arg(args, cql_nullable_int64 *_Nonnull);
        if (cql_result_set_get_is_null_col(result_set, row, column)) {
          cql_set_null(*int64p);
        }
        else {
          cql_set_notnull(*int64p, cql_result_set_get_int64_col(result_set, row, column));
        }
        break;
      }
      case CQL_DATA_TYPE_DOUBLE: {
        cql_nullable_double *_Nonnull doublep = va_arg(args, cql_nullable_double *_Nonnull);
        if (cql_result_set_get_is_null_col(result_set, row, column)) {
          cql_set_null(*doublep);
        }
        else {
          cql_set_notnull(*doublep, cql_result_set_get_double_col(result_set, row, column));
        }
        break;
      }
      case CQL_DATA_TYPE_BOOL: {
        cql_nullable_bool *_Nonnull boolp = va_arg(args, cql_nullable_bool *_Nonnull);
        if (cql_result_set_get_is_null_col(result_set, row, column)) {
          cql_set_null(*boolp);
        }
        else {
          cql_set_notnull(*boolp, cql_result_set_get_bool_col(result_set, row, column));
        }
        break;
      }
      case CQL_DATA_TYPE_STRING: {
        cql_string_ref *str_ref = va_arg(args, cql_string_ref *);
        cql_set_string_ref(str_ref, cql_result_set_get_string_col(result_set, row, column));
        break;
      }
      case CQL_DATA_TYPE_BLOB: {
        cql_blob_ref *blob_ref = va_arg(args, cql_blob_ref *);
        cql_set_blob_ref(blob_ref, cql_result_set_get_blob_col(result_set, row, column));
        break;
      }
      case CQL_DATA_TYPE_OBJECT: {
        cql_object_ref *obj_ref = va_arg(args, cql_object_ref *);
        cql_set_object_ref(obj_ref, cql_result_set_get_object_col(result_set, row, column));
        break;
      }
    }
  }

  va_end(args);
}

// This is just the helper to ignore the indicated arg because the predicates
// array tell us it is to be skipped
static void cql_skip_arg(
  cql_int32 type,
  va_list *_Nonnull args)
{
  cql_int32 core_data_type = CQL_CORE_DATA_TYPE_OF(type);

  if (type & CQL_DATA_TYPE_NOT_NULL) {
    switch (core_data_type) {
      case CQL_DATA_TYPE_INT32:
        (void)va_arg(*args, cql_int32);
        break;
      case CQL_DATA_TYPE_INT64:
        (void)va_arg(*args, cql_int64);
        break;
      case CQL_DATA_TYPE_DOUBLE:
        (void)va_arg(*args, cql_double);
        break;
      case CQL_DATA_TYPE_BOOL:
        (void)va_arg(*args, cql_int32);
        break;
      case CQL_DATA_TYPE_STRING:
        (void)va_arg(*args, cql_string_ref);
        break;
      case CQL_DATA_TYPE_BLOB:
        (void)va_arg(*args, cql_blob_ref);
        break;
      case CQL_DATA_TYPE_OBJECT:
        (void)va_arg(*args, cql_object_ref);
        break;
    }
  }
  else {
    switch (core_data_type) {
      case CQL_DATA_TYPE_INT32:
        (void)va_arg(*args, const cql_nullable_int32 *_Nonnull);
        break;
      case CQL_DATA_TYPE_INT64:
        (void)va_arg(*args, const cql_nullable_int64 *_Nonnull);
        break;
      case CQL_DATA_TYPE_DOUBLE:
        (void)va_arg(*args, const cql_nullable_double *_Nonnull);
        break;
      case CQL_DATA_TYPE_BOOL:
        (void)va_arg(*args, const cql_nullable_bool *_Nonnull);
        break;
      case CQL_DATA_TYPE_STRING:
        (void)va_arg(*args, cql_string_ref);
        break;
      case CQL_DATA_TYPE_BLOB:
        (void)va_arg(*args, cql_blob_ref);
        break;
      case CQL_DATA_TYPE_OBJECT:
        (void)va_arg(*args, cql_object_ref);
        break;
    }
  }
}

// This helper lets us bind many variables to a statement with one call.  The
// resulting code gen can be a lot smaller as there is only the one error check
// needed and you need only provide the values to bind and the offsets for each
// of the variables.  The resulting code is much more economical.
static void cql_multibind_v(
  cql_code *_Nonnull prc,
  sqlite3 *_Nonnull db,
  sqlite3_stmt *_Nullable *_Nonnull pstmt,
  cql_uint32 count,
  const char *_Nullable vpreds,
  va_list *_Nonnull args)
{
  cql_int32 column = 1;

  for (cql_int32 i = 0; *prc == SQLITE_OK && i < count; i++) {
    cql_contract(pstmt && *pstmt);
    cql_int32 type = va_arg(*args, cql_int32);
    cql_int32 core_data_type = CQL_CORE_DATA_TYPE_OF(type);

    if (vpreds && !vpreds[i]) {
      cql_skip_arg(type, args);
      continue;
    }

    if (type & CQL_DATA_TYPE_NOT_NULL) {
      switch (core_data_type) {
        case CQL_DATA_TYPE_INT32: {
          cql_int32 int32_data = va_arg(*args, cql_int32);
          *prc = sqlite3_bind_int(*pstmt, column, int32_data);
          column++;
          break;
        }
        case CQL_DATA_TYPE_INT64: {
          cql_int64 int64_data = va_arg(*args, cql_int64);
          *prc = sqlite3_bind_int64(*pstmt, column, int64_data);
          column++;
          break;
        }
        case CQL_DATA_TYPE_DOUBLE: {
          cql_double double_data = va_arg(*args, cql_double);
          *prc = sqlite3_bind_double(*pstmt, column, double_data);
          column++;
          break;
        }
        case CQL_DATA_TYPE_BOOL: {
          cql_bool bool_data = !!(cql_bool)va_arg(*args, cql_int32);
          *prc = sqlite3_bind_int(*pstmt, column, bool_data);
          column++;
          break;
        }
        case CQL_DATA_TYPE_STRING: {
          cql_string_ref str_ref = va_arg(*args, cql_string_ref);
          cql_alloc_cstr(temp, str_ref);
          *prc = sqlite3_bind_text(*pstmt, column, temp, -1, SQLITE_TRANSIENT);
          cql_free_cstr(temp, str_ref);
          column++;
          break;
        }
        case CQL_DATA_TYPE_BLOB: {
          cql_blob_ref blob_ref = va_arg(*args, cql_blob_ref);
          const void *bytes = cql_get_blob_bytes(blob_ref);
          cql_int32 size = cql_get_blob_size(blob_ref);
          *prc = sqlite3_bind_blob(*pstmt, column, bytes, size, SQLITE_TRANSIENT);
          column++;
          break;
        }
        case CQL_DATA_TYPE_OBJECT: {
          cql_object_ref obj_ref = va_arg(*args, cql_object_ref);
          *prc = sqlite3_bind_int64(*pstmt, column, (int64_t)obj_ref);
          column++;
          break;
        }
      }
    }
    else {
      switch (core_data_type) {
        case CQL_DATA_TYPE_INT32: {
          const cql_nullable_int32 *_Nonnull int32p = va_arg(*args, const cql_nullable_int32 *_Nonnull);
          *prc = int32p->is_null ? sqlite3_bind_null(*pstmt, column) :
                                   sqlite3_bind_int(*pstmt, column, int32p->value);
          column++;
          break;
        }
        case CQL_DATA_TYPE_INT64: {
          const cql_nullable_int64 *_Nonnull int64p = va_arg(*args, const cql_nullable_int64 *_Nonnull);
          *prc =int64p->is_null ? sqlite3_bind_null(*pstmt, column) :
                                  sqlite3_bind_int64(*pstmt, column, int64p->value);
          column++;
          break;
        }
        case CQL_DATA_TYPE_DOUBLE: {
          const cql_nullable_double *_Nonnull doublep = va_arg(*args, const cql_nullable_double *_Nonnull);
          *prc = doublep->is_null ? sqlite3_bind_null(*pstmt, column) :
                                    sqlite3_bind_double(*pstmt, column, doublep->value);
          column++;
          break;
        }
        case CQL_DATA_TYPE_BOOL: {
          const cql_nullable_bool *_Nonnull boolp = va_arg(*args, const cql_nullable_bool *_Nonnull);
          *prc =boolp->is_null ? sqlite3_bind_null(*pstmt, column) :
                                 sqlite3_bind_int(*pstmt, column, !!boolp->value);
          column++;
          break;
        }
        case CQL_DATA_TYPE_STRING: {
          cql_string_ref _Nullable nullable_str_ref = va_arg(*args, cql_string_ref);
          if (!nullable_str_ref) {
            *prc = sqlite3_bind_null(*pstmt, column);
          }
          else {
            cql_alloc_cstr(temp, nullable_str_ref);
            *prc = sqlite3_bind_text(*pstmt, column, temp, -1, SQLITE_TRANSIENT);
            cql_free_cstr(temp, nullable_str_ref);
          }
          column++;
          break;
        }
        case CQL_DATA_TYPE_BLOB: {
          cql_blob_ref _Nullable nullable_blob_ref = va_arg(*args, cql_blob_ref);
          if (!nullable_blob_ref) {
            *prc = sqlite3_bind_null(*pstmt, column);
          }
          else {
            const void *bytes = cql_get_blob_bytes(nullable_blob_ref);
            cql_int32 size = cql_get_blob_size(nullable_blob_ref);
            *prc = sqlite3_bind_blob(*pstmt, column, bytes, size, SQLITE_TRANSIENT);
          }
          column++;
          break;
        }
        case CQL_DATA_TYPE_OBJECT: {
          cql_object_ref _Nullable nullable_obj_ref = va_arg(*args, cql_object_ref);
          *prc = sqlite3_bind_int64(*pstmt, column, (int64_t)nullable_obj_ref);
          column++;
          break;
        }
      }
    }
    cql_finalize_on_error(*prc, pstmt);
  }
}

// This wraps the underlying varargs worker, with no variable predicates
void cql_multibind(
  cql_code *_Nonnull prc,
  sqlite3 *_Nonnull db,
  sqlite3_stmt *_Nullable *_Nonnull pstmt,
  cql_uint32 count, ...)
{
  va_list args;
  va_start(args, count);
  cql_multibind_v(prc, db, pstmt, count, NULL, &args);
  va_end(args);
}

// This wraps the underlying varargs worker, with variable predicates
void cql_multibind_var(
  cql_code *_Nonnull prc,
  sqlite3 *_Nonnull db,
  sqlite3_stmt *_Nullable *_Nonnull pstmt,
  cql_uint32 count,
  const char *_Nullable vpreds, ...)
{
  va_list args;
  va_start(args, vpreds);
  cql_multibind_v(prc, db, pstmt, count, vpreds, &args);
  va_end(args);
}

// In a single row of a result set or a single auto-cursor, release all the references in that row
// Note that all the references are together and they begin at refs_offset.
void cql_release_offsets(void *_Nonnull pv, cql_uint16 refs_count, cql_uint16 refs_offset) {
  if (refs_count) {
    // first entry in the array is the count
    char *base = pv;

    // each entry then tells us the offset of an embedded pointer
    for (cql_int32 i = 0; i < refs_count; i++) {
      cql_release(*(cql_type_ref *)(base + refs_offset));
      *(cql_type_ref *)(base + refs_offset) = NULL;
      refs_offset += sizeof(cql_type_ref);
    }
  }
}

// In a single row of a result set or a single auto-cursor, retain all the references in that row
// Note that all the references are together and they begin at refs_offset.
void cql_retain_offsets(void *_Nonnull pv, cql_uint16 refs_count, cql_uint16 refs_offset) {
  if (refs_count) {
    char *base = pv;

    // each entry then tells us the offset of an embedded pointer
    for (cql_int32 i = 0; i < refs_count; i++) {
      cql_retain(*(cql_type_ref *)(base + refs_offset));
      refs_offset += sizeof(cql_type_ref);
    }
  }
}

// Teardown an entire result set by iterating the rows and then releasing all of
// the references in each row using cql_release_offsets.  Once that is done,
// it's safe to free the entire blob of storage.
void cql_result_set_teardown(cql_result_set_ref _Nonnull result_set) {
  cql_result_set_meta *meta = cql_result_set_get_meta(result_set);
  size_t row_size = meta->rowsize;
  cql_int32 count = cql_result_set_get_count(result_set);
  cql_uint16 refs_count = meta->refsCount;
  cql_uint16 refs_offset = meta->refsOffset;
  char *_Nullable data = (char *)cql_result_set_get_data(result_set);
  char *_Nullable row = data;

  if (refs_count && count) {
    for (cql_int32 i = 0; i < count; i++) {
      cql_release_offsets(row, refs_count, refs_offset);
      row += row_size;
    }
  }

  free(data);
}

// Hash a cursor or row as described by the buffer size and refs offset
static cql_hash_code cql_hash_buffer(
  const char *_Nonnull data,
  size_t row_size,
  cql_uint16 refs_count,
  cql_uint16 refs_offset)
{
  // we'll do a normal hash on everything up to the first reference type note:
  // the refs are all guaranteed to be at the end AND the padding is guaranteed
  // to be zero-filled.  These are important invariants that let us do a much
  // simpler/faster/smaller hash.
  size_t size = row_size;
  if (refs_count) {
    size = refs_offset;
  }

  // Note that we hash even pad bytes because we always fully clear rows before
  // set set them to anything so any pad bytes are known to be 0 and hence will
  // not randomize the hash (but they will change it).
  cql_hash_code hash = 0;
  unsigned char *bytes = (unsigned char *)data;
  hash = 5381;   // djb2
  while (size--) {
    hash = ((hash << 5) + hash) + *bytes++; /* hash * 33 + c */
  }

  if (refs_count) {
    // first entry is the count, then there are count more entries hence loop <= count
    for (uint32_t i = 0; i < refs_count; i++) {
      cql_hash_code ref_hash = cql_ref_hash(*(cql_type_ref *)(data + refs_offset));
      hash = ((hash << 5) + hash) + ref_hash;
      refs_offset += sizeof(cql_type_ref);
    }
  }

  return hash;
}

// Hash the indicated row using a general purpose hash method and the reference
// type hashers.
// * the non-reference data is at the start of the row until the refs_offset
// * the references follow and there are refs_count of them.
// * these values are available in the metadata This single function can hash
//   any row of any result set, thereby saving a lot of code generation.
cql_hash_code cql_row_hash(
  cql_result_set_ref _Nonnull result_set,
  cql_int32 row)
{
  cql_int32 count = cql_result_set_get_count(result_set);
  cql_contract(row < count);

  cql_result_set_meta *meta = cql_result_set_get_meta(result_set);
  cql_uint16 refs_count = meta->refsCount;
  cql_uint16 refs_offset = meta->refsOffset;
  size_t row_size = meta->rowsize;
  char *data = ((char *)cql_result_set_get_data(result_set)) + ((size_t)row) * row_size;

  return cql_hash_buffer(data, row_size, refs_count, refs_offset);
}

static cql_bool cql_buffers_equal(
  const char *_Nonnull data1,
  const char *_Nonnull data2,
  size_t row_size,
  cql_uint16 refs_count,
  cql_uint16 refs_offset)
{
  // We'll do a normal memory comparison on everything up to the first reference
  // type note: the refs are all guaranteed to be at the end AND the padding is
  // guaranteed to be zero-filled.  These are important invariants that let us
  // do a much simpler/faster/smaller comparison.
  size_t size = row_size;
  if (refs_count) {
    size = refs_offset;
  }

  if (memcmp(data1, data2, size)) {
    return false;
  }

  if (refs_count) {
    // first entry is the count, then there are count more entries hence loop <= count
    for (uint32_t i = 0; i < refs_count; i++) {
      if (!cql_ref_equal(*(cql_type_ref *)(data1 + refs_offset),
                         *(cql_type_ref *)(data2 + refs_offset))) {
        return false;
      }
      refs_offset += sizeof(cql_type_ref);
    }
  }

  return true;
}

// Check for equality of rows using the metadata to drive the comparison.
// Similar to hashing about we compare the non-references part of the rows by
// checking the leading part and doing a bytewise comparison.  Note that any
// padding is always carefully zeroed out so we can memcmp that as well. If that
// bit matches then we can use the reference equality helper on each reference
// type.  Again we have this general helper so that the codegen for result sets
// can be more economical.  All result sets can use this one function.
cql_bool cql_rows_equal(
  cql_result_set_ref _Nonnull rs1,
  cql_int32 row1,
  cql_result_set_ref _Nonnull rs2,
  cql_int32 row2)
{
  cql_int32 count1 = cql_result_set_get_count(rs1);
  cql_int32 count2 = cql_result_set_get_count(rs2);
  cql_contract(row1 < count1);
  cql_contract(row2 < count2);

  // get offsets and verify this is the SAME metadata
  cql_result_set_meta *meta1 = cql_result_set_get_meta(rs1);
  cql_result_set_meta *meta2 = cql_result_set_get_meta(rs2);
  cql_uint16 refs_count = meta1->refsCount;
  cql_uint16 refs_offset = meta1->refsOffset;
  cql_contract(meta2->refsCount == refs_count);
  cql_contract(meta2->refsOffset == refs_offset);

  size_t row_size = meta1->rowsize;
  char *data1 = ((char *)cql_result_set_get_data(rs1)) + ((size_t)row1) * row_size;
  char *data2 = ((char *)cql_result_set_get_data(rs2)) + ((size_t)row2) * row_size;

  return cql_buffers_equal(data1, data2, row_size, refs_count, refs_offset);
}

// sizes for the various data types (not null)
static cql_uint32 normal_datasizes[] = {
  0,                             // 0: unused
  sizeof(cql_int32),             // 1: CQL_DATA_TYPE_INT32
  sizeof(cql_int64),             // 2: CQL_DATA_TYPE_INT64
  sizeof(double),                // 3: CQL_DATA_TYPE_DOUBLE
  sizeof(cql_bool),              // 4: CQL_DATA_TYPE_BOOL
};

// sizes for the various data types (nullable)
static cql_uint32 nullable_datasizes[] = {
  0,                             // 0: unused
  sizeof(cql_nullable_int32),    // 1: CQL_DATA_TYPE_INT32 (nullable)
  sizeof(cql_nullable_int64),    // 2: CQL_DATA_TYPE_INT64 (nullable)
  sizeof(cql_nullable_double),   // 3: CQL_DATA_TYPE_DOUBLE (nullable)
  sizeof(cql_nullable_bool),     // 4: CQL_DATA_TYPE_BOOL (nullable)
};

// This helper is a little trickier than the strict equality.  "Sameness" is
// defined by a set of columns that correspond to the rows identity. CQL doesn't
// know what that means but the columns can be specified and presumably it's
// meaningful.  So for instance the "keys" of a row might need to be compared.
// Note that the two result sets must have exactly the same shape as defined by
// the metadata in order to be comparable. To do the comparison we have to check
// each identity column.  If it's a reference type then we use the reference
// type comparison helper and otherwise we use strict memory comparison.
// There's more decoding because you can skip columns and column order is not
// guaranteed to be offset order.
cql_bool cql_rows_same(
  cql_result_set_ref _Nonnull rs1,
  cql_int32 row1,
  cql_result_set_ref _Nonnull rs2,
  cql_int32 row2)
{
  cql_int32 count1 = cql_result_set_get_count(rs1);
  cql_int32 count2 = cql_result_set_get_count(rs2);
  cql_contract(row1 < count1);
  cql_contract(row2 < count2);

  cql_result_set_meta *meta1 = cql_result_set_get_meta(rs1);
  cql_result_set_meta *meta2 = cql_result_set_get_meta(rs2);
  cql_contract(memcmp(meta1, meta2, sizeof(cql_result_set_meta)) == 0);

  cql_contract(meta1->identityColumns);
  uint16_t identityColumnCount = meta1->identityColumns[0];
  cql_contract(identityColumnCount > 0);
  uint16_t *identityColumns = &(meta1->identityColumns[1]);
  uint16_t *columnOffsets = &(meta1->columnOffsets[1]);

  size_t row_size = meta1->rowsize;
  char *data1 = ((char *)cql_result_set_get_data(rs1)) + ((size_t)row1) * row_size;
  char *data2 = ((char *)cql_result_set_get_data(rs2)) + ((size_t)row2) * row_size;

  for (uint16_t i = 0; i < identityColumnCount; i++) {
    uint16_t col = identityColumns[i];
    uint16_t offset = columnOffsets[col];
    // note: the refs are all guaranteed to be at the end AND the padding is
    // guaranteed to be zero-filled.  These are important invariants that let us
    // do a much simpler/faster/smaller comparison.
    if (offset < meta1->refsOffset) {
      // note: the column offsets are not in order because all refs are moved to
      // the end so we compute the size using the datatype (there is a small
      // lookup table for our few types)
      uint8_t type  = meta1->dataTypes[col];
      cql_bool notnull = !!(type & CQL_DATA_TYPE_NOT_NULL);
      type &= CQL_DATA_TYPE_CORE;
      size_t size = notnull ? normal_datasizes[type] : nullable_datasizes[type];
      if (memcmp(data1 + offset, data2 + offset, size)) {
        return false;
      }
    }
    else {
      // this is a ref type
      if (!cql_ref_equal(*(cql_type_ref *)(data1 + offset), *(cql_type_ref *)(data2 + offset))) {
        return false;
      }
    }
  }

  return true;
}

// This helper allows you to copy out some of the rows of a result set to make a
// new result set. The helper uses only metadata to do its job so, as with the
// others, codegen for this is very economical.  The result set includes in it
// already all the metadata necessary to do the column.
//  * allocate data for the row count times rowsize
//  * memcpy the old data into the new
//  * add 1 to the retain count of all the references in the new data
//  * wrap it all in a result set object
//  * profit :D
void cql_rowset_copy(
  cql_result_set_ref _Nonnull result_set,
  cql_result_set_ref _Nonnull *_Nonnull to_result_set,
  cql_int32 from,
  cql_int32 count)
{
  cql_contract(from >= 0);
  cql_contract(from + count <= cql_result_set_get_count(result_set));

  // get offsets and rowsize metadata
  cql_result_set_meta *meta = cql_result_set_get_meta(result_set);
  cql_uint16 refs_count = meta->refsCount;
  cql_uint16 refs_offset = meta->refsOffset;

  size_t row_size = cql_result_set_get_meta(result_set)->rowsize;

  char *new_data = calloc((size_t)count, row_size);
  char *old_data = ((char *)cql_result_set_get_data(result_set)) + row_size * (size_t)from;

  memcpy(new_data, old_data, ((size_t)(count) * row_size));

  char *row = new_data;
  for (cql_int32 i = 0; i < count; i++, row += row_size) {
    cql_retain_offsets(row, refs_count, refs_offset);
  }

  *to_result_set = cql_result_set_create(new_data, count, *meta);
}

// This method is the workhorse of result set reading, the contract is a bit
// unusual again to allow for economy in the generated code.  Most of the error
// checking of result set access actually happens here in a generic fashion. The
// checks needed are as follows:
//  * the row requested must be in range
//  * the column requested must be in range
//  * the data type of the column must be the requested type
//     * but it could be the nullable version of the same type
//  * the exact data type (including nullability) is stored in "type"
//    * so type is an in/out parameter, it begins with the base type like
//      "int32"
//    * its result is the exact type like "int32" or "nullable int32"
//  * the return value is the addresss of the indicated column
//
// If one of the contracts fails it means:
//   * the provided row/column value is bogus, or uninitialized
//   * the result set object is bogus, it's not a result set at all for instance
//   * the result set object has been previously freed
//   * the result set provided is actually the wrong one
//      * maybe there are several in play
//   * the code that is accessing the result set was recompiled but the code
//     that creates the result set was not, now they disagree as to how many
//     columns there are and what type they are. You can use the "meta" object
//     below to debug these situations.
//   * does the meta object look reasonable
//     * number of columns is not negative, or huge
//     * data types of each of the columns is one of the legal values
//       * see (e.g.) CQL_DATA_TYPE_INT32 in cqlrt_common.h
//     * rowsize seems reasonabe (e.g. not negative or massive)
//   * if the rowset looks reasonable then see if you're passing the right one
//     in
//   * if the rowset looks unreasonable, maybe it's been freed and you're
//     looking at stale memory
//   * if the rowset pointer looks insane, maybe its value was never initialized
//     or something like that.
//
// If one of the contracts does fail, look a few frames up the stack for the
// source of the problem. This helper code is pretty stupid and it's unlikely
// there is a problem actually in this code.
char *_Nonnull cql_address_of_col(
  cql_result_set_ref _Nonnull result_set,
  cql_int32 row,
  cql_int32 col,
  cql_int32 *_Nonnull type)
{
  // Check to make sure the requested row is a valid row
  // See above for reasons why this might fail.
  cql_int32 count = cql_result_set_get_count(result_set);
  cql_contract(row < count);

  // Check to make sure the meta data has column data
  // See above for reasons why this might fail.
  cql_result_set_meta *meta = cql_result_set_get_meta(result_set);
  cql_contract(meta->columnOffsets != NULL);

  // Check to make sure the requested column is a valid column
  // See above for reasons why this might fail.
  cql_int32 columnCount = meta->columnCount;
  cql_contract(col < columnCount);

  // Check to make sure the requested column is of the correct type
  // See above for reasons why this might fail.
  uint8_t data_type = meta->dataTypes[col];
  cql_contract(CQL_CORE_DATA_TYPE_OF(data_type) == *type);
  *type = data_type;

  // We have a valid row and column so it's safe to do the real work Get the
  // column offset, and rowsize and do the math to compute the data pointer.
  cql_uint16 offset = meta->columnOffsets[col + 1];
  size_t row_size = meta->rowsize;
  return ((char *)cql_result_set_get_data(result_set)) + ((size_t)row) * row_size + offset;
}

// This is the helper method that reads an int32 out of a rowset at a particular
// row and column. The same helper is used for reading the value from a nullable
// or not nullable value, so the address helper has to report which kind of
// datum it is.  All the error checking is in cql_address_of_col.
// CQLABI
cql_int32 cql_result_set_get_int32_col(
  cql_result_set_ref _Nonnull result_set,
  cql_int32 row,
  cql_int32 col)
{
  cql_int32 data_type = CQL_DATA_TYPE_INT32;
  char *data = cql_address_of_col(result_set, row, col, &data_type);

  if (data_type & CQL_DATA_TYPE_NOT_NULL) {
    return *(cql_int32 *)data;
  }
  return ((cql_nullable_int32 *)data)->value;
}

// This is the helper method that write an int32 into a rowset at a particular
// row and column. The same helper is used for writing the value from a nullable
// or not nullable value, so the address helper has to report which kind of
// datum it is.  All the error checking is in cql_address_of_col.
// CQLABI
void cql_result_set_set_int32_col(
  cql_result_set_ref _Nonnull result_set,
  cql_int32 row,
  cql_int32 col,
  cql_int32 new_value)
{
  cql_int32 data_type = CQL_DATA_TYPE_INT32;
  char *data = cql_address_of_col(result_set, row, col, &data_type);

  if (data_type & CQL_DATA_TYPE_NOT_NULL) {
    *(cql_int32 *)data = new_value;
  }
  else {
    ((cql_nullable_int32 *)data)->value = new_value;
    ((cql_nullable_int32 *)data)->is_null = false;
  }
}

// This is the helper method that reads an int64 out of a rowset at a particular
// row and column. The same helper is used for reading the value from a nullable
// or not nullable value, so the address helper has to report which kind of
// datum it is.  All the error checking is in cql_address_of_col.
// CQLABI
cql_int64 cql_result_set_get_int64_col(
  cql_result_set_ref _Nonnull result_set,
  cql_int32 row,
  cql_int32 col)
{
  cql_int32 data_type = CQL_DATA_TYPE_INT64;
  char *data = cql_address_of_col(result_set, row, col, &data_type);

  if (data_type & CQL_DATA_TYPE_NOT_NULL) {
    return *(cql_int64 *)data;
  }
  return ((cql_nullable_int64 *)data)->value;
}

// This is the helper method that write an int64 into a rowset at a particular
// row and column. The same helper is used for writing the value from a nullable
// or not nullable value, so the address helper has to report which kind of
// datum it is.  All the error checking is in cql_address_of_col.
// CQLABI
void cql_result_set_set_int64_col(
  cql_result_set_ref _Nonnull result_set,
  cql_int32 row,
  cql_int32 col,
  cql_int64 new_value)
{
  cql_int32 data_type = CQL_DATA_TYPE_INT64;
  char *data = cql_address_of_col(result_set, row, col, &data_type);

  if (data_type & CQL_DATA_TYPE_NOT_NULL) {
    *(cql_int64 *)data = new_value;
  }
  else {
    ((cql_nullable_int64 *)data)->value = new_value;
    ((cql_nullable_int64 *)data)->is_null = false;
  }
}

// This is the helper method that reads a double out of a rowset at a particular
// row and column. The same helper is used for reading the value from a nullable
// or not nullable value, so the address helper has to report which kind of
// datum it is.  All the error checking is in cql_address_of_col.
// CQLABI
cql_double cql_result_set_get_double_col(
  cql_result_set_ref _Nonnull result_set,
  cql_int32 row,
  cql_int32 col)
{
  cql_int32 data_type = CQL_DATA_TYPE_DOUBLE;
  char *data = cql_address_of_col(result_set, row, col, &data_type);

  if (data_type & CQL_DATA_TYPE_NOT_NULL) {
    return *(cql_double *)data;
  }
  return ((cql_nullable_double *)data)->value;
}

// This is the helper method that write an double into a rowset at a particular
// row and column. The same helper is used for writing the value from a nullable
// or not nullable value, so the address helper has to report which kind of
// datum it is.  All the error checking is in cql_address_of_col.
// CQLABI
void cql_result_set_set_double_col(
  cql_result_set_ref _Nonnull result_set,
  cql_int32 row,
  cql_int32 col,
  cql_double new_value)
{
  cql_int32 data_type = CQL_DATA_TYPE_DOUBLE;
  char *data = cql_address_of_col(result_set, row, col, &data_type);

  if (data_type & CQL_DATA_TYPE_NOT_NULL) {
    *(cql_double *)data = new_value;
  }
  else {
    ((cql_nullable_double *)data)->value = new_value;
    ((cql_nullable_double *)data)->is_null = false;
  }
}

// This is the helper method that reads an bool out of a rowset at a particular
// row and column. The same helper is used for reading the value from a nullable
// or not nullable value, so the address helper has to report which kind of
// datum it is.  All the error checking is in cql_address_of_col.
// CQLABI
cql_bool cql_result_set_get_bool_col(
  cql_result_set_ref _Nonnull result_set,
  cql_int32 row,
  cql_int32 col)
{
  cql_int32 data_type = CQL_DATA_TYPE_BOOL;
  char *data = cql_address_of_col(result_set, row, col, &data_type);

  if (data_type & CQL_DATA_TYPE_NOT_NULL) {
    return *(cql_bool *)data;
  }
  return ((cql_nullable_bool *)data)->value;
}

// This is the helper method that write an bool into a rowset at a particular
// row and column. The same helper is used for writing the value from a nullable
// or not nullable value, so the address helper has to report which kind of
// datum it is.  All the error checking is in cql_address_of_col.
// CQLABI
void cql_result_set_set_bool_col(
  cql_result_set_ref _Nonnull result_set,
  cql_int32 row,
  cql_int32 col,
  cql_bool new_value)
{
  cql_int32 data_type = CQL_DATA_TYPE_BOOL;
  char *data = cql_address_of_col(result_set, row, col, &data_type);

  if (data_type & CQL_DATA_TYPE_NOT_NULL) {
    *(cql_bool *)data = new_value;
  }
  else {
    ((cql_nullable_bool *)data)->value = new_value;
    ((cql_nullable_bool *)data)->is_null = false;
  }
}

// This is the helper method that reads a string out of a rowset at a particular
// row and column. The same helper is used for reading the value from a nullable
// or not nullable value, so the address helper has to report which kind of
// datum it is.  All the error checking is in cql_address_of_col.
// CQLABI
cql_string_ref _Nullable cql_result_set_get_string_col(
  cql_result_set_ref _Nonnull result_set,
  cql_int32 row,
  cql_int32 col)
{
  cql_int32 data_type = CQL_DATA_TYPE_STRING;
  char *data = cql_address_of_col(result_set, row, col, &data_type);
  return *(cql_string_ref *)data;
}

// This is the helper method that write an string into a rowset at a particular
// row and column. The same helper is used for writing the value from a nullable
// or not nullable value, so the address helper has to report which kind of
// datum it is.  All the error checking is in cql_address_of_col.
// CQLABI
void cql_result_set_set_string_col(
  cql_result_set_ref _Nonnull result_set,
  cql_int32 row,
  cql_int32 col,
  cql_string_ref _Nullable new_value)
{
  cql_int32 data_type = CQL_DATA_TYPE_STRING;
  char *data = cql_address_of_col(result_set, row, col, &data_type);
  cql_set_string_ref((cql_string_ref *)data, new_value);
}

// This is the helper method that reads a object out of a rowset at a particular
// row and column. The same helper is used for reading the value from a nullable
// or not nullable value, so the address helper has to report which kind of
// datum it is.  All the error checking is in cql_address_of_col.
// CQLABI
cql_object_ref _Nullable cql_result_set_get_object_col(
  cql_result_set_ref _Nonnull result_set,
  cql_int32 row,
  cql_int32 col)
{
  cql_int32 data_type = CQL_DATA_TYPE_OBJECT;
  char *data = cql_address_of_col(result_set, row, col, &data_type);
  return *(cql_object_ref *)data;
}

// This is the helper method that write an object into a rowset at a particular
// row and column. The same helper is used for writing the value from a nullable
// or not nullable value, so the address helper has to report which kind of
// datum it is.  All the error checking is in cql_address_of_col.
// CQLABI
void cql_result_set_set_object_col(
  cql_result_set_ref _Nonnull result_set,
  cql_int32 row,
  cql_int32 col,
  cql_object_ref _Nullable new_value)
{
  cql_int32 data_type = CQL_DATA_TYPE_OBJECT;
  char *data = cql_address_of_col(result_set, row, col, &data_type);
  cql_set_object_ref((cql_object_ref *)data, new_value);
}

// This is the helper method that reads a blob out of a rowset at a particular
// row and column. The same helper is used for reading the value from a nullable
// or not nullable value, so the address helper has to report which kind of
// datum it is.  All the error checking is in cql_address_of_col.
// CQLABI
cql_blob_ref _Nullable cql_result_set_get_blob_col(
  cql_result_set_ref _Nonnull result_set,
  cql_int32 row,
  cql_int32 col)
{
  cql_int32 data_type = CQL_DATA_TYPE_BLOB;
  char *data = cql_address_of_col(result_set, row, col, &data_type);
  return *(cql_blob_ref *)data;
}

// This is the helper method that write an blob into a rowset at a particular
// row and column. The same helper is used for writing the value from a nullable
// or not nullable value, so the address helper has to report which kind of
// datum it is.  All the error checking is in cql_address_of_col.
// CQLABI
void cql_result_set_set_blob_col(
  cql_result_set_ref _Nonnull result_set,
  cql_int32 row,
  cql_int32 col,
  cql_blob_ref _Nullable new_value)
{
  cql_int32 data_type = CQL_DATA_TYPE_BLOB;
  char *data = cql_address_of_col(result_set, row, col, &data_type);
  cql_set_blob_ref((cql_blob_ref *)data, new_value);
}

// This is the helper method that determines if a nullable column column is null
// or not. If the data type of the column is string or blob then we look for a
// null value for the pointer in question If the data type is not nullable, we
// return false. If the data type is nullable then we read the is_null value out
// of the row
// CQLABI
cql_bool cql_result_set_get_is_null_col(
  cql_result_set_ref _Nonnull result_set,
  cql_int32 row_,
  cql_int32 col_)
{
  cql_uint32 row = (cql_uint32)row_;
  cql_uint32 col = (cql_uint32)col_;

  // Check to make sure the requested row is a valid row See cql_address_of_col
  // for reasons why this might fail.
  cql_int32 count = cql_result_set_get_count(result_set);
  cql_contract(row < count);

  // Check to make sure the meta data has column data See cql_address_of_col for
  // reasons why this might fail.
  cql_result_set_meta *meta = cql_result_set_get_meta(result_set);
  cql_contract(meta->columnOffsets != NULL);

  // Check to make sure the requested column is a valid column See
  // cql_address_of_col for reasons why this might fail.
  cql_int32 columnCount = meta->columnCount;
  cql_contract(col < columnCount);

  uint8_t data_type = meta->dataTypes[col];

  cql_uint16 offset = meta->columnOffsets[col + 1];
  size_t row_size = meta->rowsize;
  char *data =((char *)cql_result_set_get_data(result_set)) + row * row_size + offset;

  cql_int32 core_data_type = CQL_CORE_DATA_TYPE_OF(data_type);

  if (core_data_type == CQL_DATA_TYPE_BLOB
    || core_data_type == CQL_DATA_TYPE_STRING
    || core_data_type == CQL_DATA_TYPE_OBJECT) {
     return !*(void **)data;
  }

  if (data_type & CQL_DATA_TYPE_NOT_NULL) {
     return false;
  }

  cql_bool is_null = 1;

  switch (core_data_type) {
    case CQL_DATA_TYPE_BOOL:
     is_null = ((cql_nullable_bool *)data)->is_null;
     break;

    case CQL_DATA_TYPE_INT32:
     is_null = ((cql_nullable_int32 *)data)->is_null;
     break;

    case CQL_DATA_TYPE_INT64:
     is_null = ((cql_nullable_int64 *)data)->is_null;
     break;

    default:
     // nothing else left
     cql_contract(core_data_type == CQL_DATA_TYPE_DOUBLE);
     is_null = ((cql_nullable_double *)data)->is_null;
     break;
  }

  return is_null;
}

// This is the helper method that sets a nullable column to null
void cql_result_set_set_to_null_col(
  cql_result_set_ref _Nonnull result_set,
  cql_int32 row_,
  cql_int32 col_)
{
  cql_uint32 row = (cql_uint32)row_;
  cql_uint32 col = (cql_uint32)col_;

  // Check to make sure the requested row is a valid row See cql_address_of_col
  // for reasons why this might fail.
  cql_int32 count = cql_result_set_get_count(result_set);
  cql_contract(row < count);

  // Check to make sure the meta data has column data See cql_address_of_col for
  // reasons why this might fail.
  cql_result_set_meta *meta = cql_result_set_get_meta(result_set);
  cql_contract(meta->columnOffsets != NULL);

  // Check to make sure the requested column is a valid column See
  // cql_address_of_col for reasons why this might fail.
  cql_int32 columnCount = meta->columnCount;
  cql_contract(col < columnCount);

  uint8_t data_type = meta->dataTypes[col];

  cql_uint16 offset = meta->columnOffsets[col + 1];
  size_t row_size = meta->rowsize;
  char *data =((char *)cql_result_set_get_data(result_set)) + row * row_size + offset;

  cql_int32 core_data_type = CQL_CORE_DATA_TYPE_OF(data_type);

  // if this fails you are attempting to set a not null column to null
  cql_contract(!(data_type & CQL_DATA_TYPE_NOT_NULL));

  // if this fails it means you're using the null set helper on an reference
  // type you can just use the normal setter on those types because they are
  // references and so NULL is valid.  You only use this method for setting
  // primitive types to null.
  cql_contract(core_data_type != CQL_DATA_TYPE_BLOB);
  cql_contract(core_data_type != CQL_DATA_TYPE_STRING);
  cql_contract(core_data_type != CQL_DATA_TYPE_OBJECT);

  switch (core_data_type) {
    case CQL_DATA_TYPE_BOOL:
      cql_set_null(*(cql_nullable_bool *)data);
      break;

    case CQL_DATA_TYPE_INT32:
      cql_set_null(*(cql_nullable_int32 *)data);
      break;

    case CQL_DATA_TYPE_INT64:
      cql_set_null(*(cql_nullable_int64 *)data);
      break;

    default:
     // nothing else left but double
     cql_contract(core_data_type == CQL_DATA_TYPE_DOUBLE);
     cql_set_null(*(cql_nullable_double *)data);
     break;
  }
}

// Tables contains a list of tables we need to drop.  The format is
// "table1\0table2\0table3\0\0".  The list is terminated by a double null.
// We try to drop all those tables.
static void cql_autodrop_tables(
  sqlite3 *_Nullable db,
  const char *_Nullable tables)
{
  if (!tables) {
    return;
  }

  // semantic analysis prevents any autodrop tables in cases where there is no db pointer
  cql_contract(db);

  const char *drop_table = "DROP TABLE IF EXISTS ";
  const char *p = tables;
  cql_int32 max_len = 0;
  cql_int32 drop_len = (cql_int32)strlen(drop_table);

  // find the longest table name so we can make a suitable buffer
  for (;;) {
    // stop when we find the zero length table name
    cql_int32 len = (cql_int32)strlen(p);
    if (!len) {
      break;
    }

    if (len > max_len) {
      max_len = len;
    }

    p += len + 1;
  }

  // we need enough room for the drop command plus the longest table name
  // plus the ";" and the null.
  STACK_BYTES_ALLOC(sql, drop_len + max_len + 2);

  // this part will be constant for all the iterations
  strcpy(sql, drop_table);

  p = tables;
  for (;;) {
    // stop when we find the zero length table name
    cql_int32 len = (cql_int32)strlen(p);
    if (!len) {
      break;
    }

    // form the drop command from the fragments
    strcpy(sql + drop_len, p);
    strcpy(sql + drop_len + len, ";");

    // Try to drop the table, if it fails we disregard the failure code
    // there's nothing we could do to recover anyway.
    cql_exec(db, sql);

    p += len + 1;
  }
}

void cql_initialize_meta(
  cql_result_set_meta *_Nonnull meta,
  cql_fetch_info *_Nonnull info)
{
  memset(meta, 0, sizeof(*meta));
  meta->teardown = cql_result_set_teardown;
  meta->rowsize = info->rowsize;
  meta->rowHash = cql_row_hash;
  meta->rowsEqual = cql_rows_equal;
  meta->rowsSame = cql_rows_same;
  meta->refsCount = info->refs_count;
  meta->refsOffset = info->refs_offset;
  meta->columnOffsets = info->col_offsets;
  meta->columnCount = info->col_offsets[0];
  meta->identityColumns = info->identity_columns;
  meta->dataTypes = info->data_types;
  meta->copy = cql_rowset_copy;
}

// By the time we get here, a CQL stored proc has completed execution and there
// is now a statement (or an error result).  This function iterates the rows
// that come out of the statement using the fetch info to describe the shape of
// the expected results.  All of this code is shared so that the cost of any
// given stored procedure is minimized.  Even the error handling is
// consolidated.
cql_code cql_fetch_all_results(
  cql_fetch_info *_Nonnull info,
  cql_result_set_ref _Nullable *_Nonnull result_set)
{
  *result_set = NULL;
  cql_int32 count = 0;
  cql_bytebuf b;
  cql_bytebuf_open(&b);
  sqlite3_stmt *stmt = info->stmt;
  cql_uint32 rowsize = info->rowsize;
  char *row;
  cql_code rc = info->rc;

  if (rc != SQLITE_OK) goto cql_error;

  for (;;) {
    rc = sqlite3_step(stmt);
    if (rc == SQLITE_DONE) break;
    if (rc != SQLITE_ROW) goto cql_error;
    count++;
    row = cql_bytebuf_alloc(&b, rowsize);
    memset(row, 0, rowsize);

    cql_multifetch_meta((char *)row, info);
  }

  // If all is well, we close the statement and we're done with OK result. If
  // anything went wrong we free all the memory and we're outta here.

  cql_finalize_stmt(&stmt);
  cql_result_set_meta meta;
  cql_initialize_meta(&meta, info);

  *result_set = cql_result_set_create(b.ptr, count, meta);
  cql_autodrop_tables(info->db, info->autodrop_tables);
  cql_profile_stop(info->crc, info->perf_index);
  return SQLITE_OK;

cql_error:
  // If we have allocated any rows, and they need cleanup, clean them up now
  if (info->refs_count) {
    row = b.ptr;
    for (cql_int32 i = 0; i < count ; i++, row += rowsize) {
      cql_release_offsets(row, info->refs_count, info->refs_offset);
    }
  }
  cql_bytebuf_close(&b);
  cql_finalize_stmt(&stmt);
  cql_log_database_error(info->db, "cql", "database error");
  cql_autodrop_tables(info->db, info->autodrop_tables);
  cql_profile_stop(info->crc, info->perf_index);
  return rc;
}

// In this result set creator, the rows are sitting pretty in a buffer we've
// already constructed. The return code tells us if we're exiting clean or not.
// If we're not clean then the buffer should be disposed, there will be no
// result set returned.
void cql_results_from_data(
  cql_code rc,
  cql_bytebuf *_Nonnull buffer,
  cql_fetch_info *_Nonnull info,
  cql_result_set_ref _Nullable *_Nonnull result_set)
{
  *result_set = NULL;
  cql_uint32 rowsize = info->rowsize;
  cql_int32 count = (cql_int32)(buffer->used / rowsize);

  if (rc == SQLITE_OK) {
    cql_result_set_meta meta;
    cql_initialize_meta(&meta, info);
    *result_set = cql_result_set_create(buffer->ptr, count, meta);
  }
  else {
    if (info->refs_count) {
      char *row = buffer->ptr;
      for (cql_int32 i = 0; i < count ; i++, row += rowsize) {
        cql_release_offsets(row, info->refs_count, info->refs_offset);
      }
    }
    cql_bytebuf_close(buffer);
  }

  cql_autodrop_tables(info->db, info->autodrop_tables);
  cql_profile_stop(info->crc, info->perf_index);
}

// Just like cql_fetch_all_results but for the "one row result" case In that
// case the data has already been fetched.  Its shape is described just like the
// above.  All we need to do is wrap the row in a result set and we're done.  As
// above the error cases are also handled here.
cql_code cql_one_row_result(
  cql_fetch_info *_Nonnull info,
  char *_Nullable data,
  cql_int32 count,
  cql_result_set_ref _Nullable *_Nonnull result_set)
{
  cql_code rc = info->rc;
  *result_set = NULL;
  if (rc != SQLITE_OK) goto cql_error;

  cql_result_set_meta meta;
  cql_initialize_meta(&meta, info);
  *result_set = cql_result_set_create(data, count, meta);
  cql_autodrop_tables(info->db, info->autodrop_tables);
  cql_profile_stop(info->crc, info->perf_index);
  return SQLITE_OK;

cql_error:
  cql_release_offsets(data, info->refs_count, info->refs_offset);
  free(data);
  cql_log_database_error(info->db, "cql", "database error");
  cql_autodrop_tables(info->db, info->autodrop_tables);
  cql_profile_stop(info->crc, info->perf_index);
  return rc;
}

// these are some structures we need so that we can make an empty result set it
// has a canonical shape (1 column) but there are no rows so no column getter
// will ever succeed not matter the shape that was expected.

typedef struct cql_no_rows_row {
  cql_int32 x;
} cql_no_rows_row;

static cql_int32 cql_no_rows_row_perf_index;

uint8_t cql_no_rows_row_data_types[] = {
  CQL_DATA_TYPE_INT32 | CQL_DATA_TYPE_NOT_NULL, // x
};

static cql_uint16 cql_no_rows_row_col_offsets[] = { 1,
  cql_offsetof(cql_no_rows_row, x)
};

cql_fetch_info cql_no_rows_row_info = {
  .rc = SQLITE_OK,
  .data_types = cql_no_rows_row_data_types,
  .col_offsets = cql_no_rows_row_col_offsets,
  .rowsize = sizeof(cql_no_rows_row),
  .crc = 0,
  .perf_index = &cql_no_rows_row_perf_index,
};

// The most trivial empty result set that still looks like a result set
cql_result_set_ref _Nonnull cql_no_rows_result_set(void) {
  cql_result_set_meta meta;
  cql_initialize_meta(&meta, &cql_no_rows_row_info);
  return cql_result_set_create(malloc(1), 0, meta);
}

// This statement for sure has no rows in it
cql_code cql_no_rows_stmt(sqlite3 *_Nonnull db, sqlite3_stmt *_Nullable *_Nonnull pstmt) {
  cql_finalize_stmt(pstmt);
  return cql_sqlite3_prepare_v2(db, "select 0 where 0", -1, pstmt, NULL);
}

// basic closed hash table, small initial size with doubling
#define HASHTAB_INIT_SIZE 4
#define HASHTAB_LOAD_FACTOR .75

// helper to set the payload array, used at init time and during rehash
static void cql_hashtab_set_payload(cql_hashtab *_Nonnull ht) {
  ht->payload = (cql_hashtab_entry *)calloc(ht->capacity, sizeof(cql_hashtab_entry));
}


// fwd ref needed for rehash
static cql_bool cql_hashtab_add(cql_hashtab *_Nonnull ht, cql_int64 key_new, cql_int64 val_new);

// Rehash to a bigger size, all the items are re-inserted. Note we have to
// release the old values because the new values are retained upon insertion.
// This keeps the reference counting correct.
static void cql_hashtab_rehash(cql_hashtab *_Nonnull ht) {
  uint32_t old_capacity = ht->capacity;
  cql_hashtab_entry *old_payload = ht->payload;

  ht->count = 0;
  ht->capacity *= 2;
  cql_hashtab_set_payload(ht);

  for (uint32_t i = 0; i < old_capacity; i++) {
    cql_int64 key = old_payload[i].key;
    cql_int64 val = old_payload[i].val;
    if (key) {
      cql_hashtab_add(ht, key, val);
      ht->release_key(ht->context, key);
      ht->release_val(ht->context, val);
    }
  }

  free(old_payload);
}

// Making a new hash table, initial size
static cql_hashtab *_Nonnull cql_hashtab_new(
  uint64_t (*_Nonnull hash_key)(void *_Nullable context, cql_int64 key),
  bool (*_Nonnull compare_keys)(void *_Nullable context, cql_int64 key1, cql_int64 key2),
  void (*_Nonnull retain_key)(void *_Nullable context, cql_int64 key),
  void (*_Nonnull retain_val)(void *_Nullable context, cql_int64 val),
  void (*_Nonnull release_key)(void *_Nullable context, cql_int64 key),
  void (*_Nonnull release_val)(void *_Nullable context, cql_int64 val),
  void *_Nullable context)
{
  cql_hashtab *ht = malloc(sizeof(cql_hashtab));
  ht->hash_key = hash_key;
  ht->compare_keys = compare_keys;
  ht->retain_key = retain_key;
  ht->retain_val = retain_val;
  ht->release_key = release_key;
  ht->release_val = release_val;
  ht->count = 0;
  ht->capacity = HASHTAB_INIT_SIZE;
  ht->context = context;
  cql_hashtab_set_payload(ht);
  return ht;
}

// release the memory for the hash table including
// releasing all the strings stored as keys.
static void cql_hashtab_delete(cql_hashtab *_Nonnull ht) {
  for (uint32_t i = 0; i < ht->capacity; i++) {
    cql_int64 key = ht->payload[i].key;
    cql_int64 val = ht->payload[i].val;
    if (key) {
      ht->release_key(ht->context, key);
    }
    if (val) {
      ht->release_val(ht->context, val);
    }
  }

  free(ht->payload);
  free(ht);
}

// Add a new key to the hash table
// * if the key is addred return true
// * if the key exists return false and do nothing
static cql_bool cql_hashtab_add(
  cql_hashtab *_Nonnull ht,
  cql_int64 key_new,
  cql_int64 val_new)
{
  uint32_t hash = (uint32_t)ht->hash_key(ht->context, key_new);
  uint32_t offset = hash % ht->capacity;
  cql_hashtab_entry *payload = ht->payload;

  for (;;) {
    cql_int64 key = payload[offset].key;
    if (!key) {
      ht->retain_key(ht->context, key_new);
      ht->retain_val(ht->context, val_new);

      payload[offset].key = key_new;
      payload[offset].val = val_new;

      ht->count++;
      if (ht->count > ht->capacity * HASHTAB_LOAD_FACTOR) {
        cql_hashtab_rehash(ht);
      }

      return true;
    }

    if (ht->compare_keys(ht->context, key, key_new)) {
      return false;
    }

    offset++;
    if (offset >= ht->capacity) {
      offset = 0;
    }
  }
}

// returns the payload item for the indicated key (allowing mutation)
// if the key is not found returns null
static cql_hashtab_entry *_Nullable cql_hashtab_find(
  cql_hashtab *_Nonnull ht,
  cql_int64 key_needed)
{
  uint32_t hash = (uint32_t)ht->hash_key(ht->context, key_needed);
  uint32_t offset = hash % ht->capacity;
  cql_hashtab_entry *payload = ht->payload;

  for (;;) {
    cql_int64 key = ht->payload[offset].key;
    if (!key) {
      return NULL;
    }

    if (ht->compare_keys(ht->context, key, key_needed)) {
      return &payload[offset];
    }

    offset++;
    if (offset >= ht->capacity) {
      offset = 0;
    }
  }
}

// These are CQL friendly versions of the hashtable for a string to integer map,
// these signatures are directly callable from CQL

static void cql_no_op_retain_release(
  void *_Nullable context,
  cql_int64 data)
{
}

static void cql_key_retain(void *_Nullable context, cql_int64 key) {
  if (key) {
    cql_retain((cql_type_ref)(key));
  }
}

static void cql_key_release(
  void *_Nullable context,
  cql_int64 key)
{
  if (key) {
    cql_release((cql_type_ref)(key));
  }
}

static uint64_t cql_key_str_hash(
  void *_Nullable context,
  cql_int64 key)
{
  return cql_string_hash((cql_string_ref)key);
}

static bool cql_key_str_eq(
  void *_Nullable context,
  cql_int64 key1,
  cql_int64 key2)
{
  return cql_string_equal((cql_string_ref)key1, (cql_string_ref)key2);
}

// Defer finalization to the hash table which has all it needs to do the job
static void cql_facets_finalize(void *_Nonnull data) {
  cql_hashtab *_Nonnull self = data;
  cql_hashtab_delete(self);
}

// create the facets storage using the hashtable
cql_object_ref _Nonnull cql_facets_create(void) {

  cql_hashtab * self = cql_hashtab_new(
    cql_key_str_hash,
    cql_key_str_eq,
    cql_key_retain,
    cql_no_op_retain_release,  // value retain is a no-op
    cql_key_release,
    cql_no_op_retain_release,  // value release is a no-op
    NULL
  );

  return _cql_generic_object_create(self, cql_facets_finalize);
}

// add a facet value to the hash table
cql_bool cql_facet_add(
  cql_object_ref _Nullable facets,
  cql_string_ref _Nonnull name,
  cql_int64 crc)
{
  cql_bool result = false;
  if (facets) {
    cql_hashtab *_Nonnull self = _cql_generic_object_get_data(facets);
    result = cql_hashtab_add(self, (cql_int64)name, crc);
  }
  return result;
}

// Search for the facet value in the hash table, if not found return -1
cql_int64 cql_facet_find(
  cql_object_ref _Nullable facets,
  cql_string_ref _Nonnull name)
{
  cql_int64 result = -1;
  if (facets) {
    cql_hashtab *_Nonnull self = _cql_generic_object_get_data(facets);
    cql_hashtab_entry *payload = cql_hashtab_find(self, (cql_int64)name);
    if (payload) {
      result = payload->val;
    }
  }
  return result;
}

// Search for the facet value in the hash table, replace it if it exists add it
// if it doesn't
cql_bool cql_facet_upsert(
  cql_object_ref _Nullable facets,
  cql_string_ref _Nonnull name,
  cql_int64 crc)
{
  cql_bool result = false;
  if (facets) {
    cql_hashtab *_Nonnull self = _cql_generic_object_get_data(facets);
    cql_hashtab_entry *payload = cql_hashtab_find(self, (cql_int64)name);
    if (!payload) {
      // this will return true because we just checked and it's not there
      result = cql_hashtab_add(self, (cql_int64)name, crc);
    }
    else {
      // did not add path
      payload->val = crc;
    }
  }

  return result;
}

#define cql_append_value(b, var) cql_bytebuf_append(b, &var, sizeof(var))

#define cql_append_nullable_value(b, var) \
  if (!var.is_null) { \
    cql_setbit(bits, nullable_index); \
    cql_append_value(b, var.value); \
  }

static void cql_setbit(uint8_t *_Nonnull bytes, uint16_t index) {
  bytes[index / 8] |= (1 << (index % 8));
}

static cql_bool cql_getbit(const uint8_t *_Nonnull bytes, uint16_t index) {
  return !!(bytes[index / 8] & (1 << (index % 8)));
}

typedef struct cql_input_buf {
  const unsigned char *_Nonnull data;
  uint32_t remaining;
} cql_input_buf;

static bool cql_input_read(
  cql_input_buf *_Nonnull buf,
  void *_Nonnull dest,
  uint32_t bytes)
{
  if (bytes > buf->remaining) {
    return false;
  }

  memcpy(dest, buf->data, bytes);
  buf->remaining -= bytes;
  buf->data += bytes;

  return true;
}

static bool cql_input_inline_str(
  cql_input_buf *_Nonnull buf,
  const char *_Nonnull *_Nonnull dest)
{
  unsigned char *nullchar = memchr(buf->data, 0, buf->remaining);
  if (nullchar) {
    uint32_t bytes = (uint32_t)(nullchar - buf->data) + 1;
    *dest = (const char *)buf->data;
    buf->remaining -= bytes;
    buf->data += bytes;
    return true;
  }

  return false;
}

static bool cql_input_inline_bytes(
  cql_input_buf *_Nonnull buf,
  const uint8_t *_Nonnull *_Nonnull dest,
  uint32_t bytes)
{
  if (bytes <= buf->remaining) {
    *dest = buf->data;
    buf->remaining -= bytes;
    buf->data += bytes;
    return true;
  }

  return false;
}

static uint32_t cql_zigzag_encode_32 (cql_int32 i) {
  return (uint32_t)((i >> 31) ^ (i << 1));
}

static cql_int32 cql_zigzag_decode_32 (uint32_t i) {
  return (i >> 1) ^ -(i & 1);
}

static uint64_t cql_zigzag_encode_64 (cql_int64 i) {
  return (uint64_t)((i >> 63) ^ (i << 1));
}

static cql_int64 cql_zigzag_decode_64 (uint64_t i) {
  return (i >> 1) ^ -(i & 1);
}

// variable length encoding using zigzag and 7 bits with extension note that
// this also takes care of any endian issues
static bool cql_read_varint_32(
  cql_input_buf *_Nonnull buf,
  cql_int32 *_Nonnull out)
{
  uint32_t result = 0;
  uint8_t byte;
  uint8_t i = 0;
  uint8_t offset = 0;
  while (i < 5) {
    if (!cql_input_read(buf, &byte, 1)) {
      return false;
    }
    result |= ((uint32_t)(byte & 0x7f)) << offset;
    if (!(byte & 0x80)) {
      *out = cql_zigzag_decode_32(result);
      return true;
    }
    offset += 7;
    i++;
  }

  // badly formed buffer, 5 bytes is the most we need for a 32 bit varint
  return false;
}

// variable length encoding using zigzag and 7 bits with extension note that
// this also takes care of any endian issues
static bool cql_read_varint_64(
  cql_input_buf *_Nonnull buf,
  cql_int64 *_Nonnull out)
{
  uint64_t result = 0;
  uint8_t byte;
  uint8_t i = 0;
  uint8_t offset = 0;
  while (i < 10) {
    if (!cql_input_read(buf, &byte, 1)) {
      return false;
    }
    result |= ((uint64_t)(byte & 0x7f)) << offset;
    if (!(byte & 0x80)) {
      *out = cql_zigzag_decode_64(result);
      return true;
    }
    offset += 7;
    i++;
  }

  // badly formed buffer, 10 bytes is the most we need for a 64 bit varint
  return false;
}

// variable length encoding using zigzag and 7 bits with extension
// note that this also takes care of any endian issues
static void cql_write_varint_32(cql_bytebuf *_Nonnull buf, cql_int32 si) {
  uint32_t i = cql_zigzag_encode_32(si);
  do {
    uint8_t byte = i & 0x7f;
    i >>= 7;
    if (i) {
      byte |= 0x80;
    }
    cql_append_value(buf, byte);
  } while (i);
}

// variable length encoding using zigzag and 7 bits with extension
// note that this also takes care of any endian issues
static void cql_write_varint_64(cql_bytebuf *_Nonnull buf, int64_t si) {
  uint64_t i = cql_zigzag_encode_64(si);
  do {
    uint8_t byte = i & 0x7f;
    i >>= 7;
    if (i) {
      byte |= 0x80;
    }
    cql_append_value(buf, byte);
  } while (i);
}

// This standard helper walks any cursor and creates a versionable encoding of
// it in a blob.  The dynamic cursor structure has all the necessary metadata
// about the cursor.  By the time this is called many checks have been made
// about the suitability of this cursor for serialization (e.g. no OBJECT
// fields). As a consequence we get a nice simple strategy that is flexible.
void cql_cursor_to_bytebuf(
  cql_dynamic_cursor *_Nonnull dyn_cursor,
  cql_bytebuf *_Nonnull b)
{
  cql_invariant(b);
  cql_invariant(*dyn_cursor->cursor_has_row);

  uint16_t *offsets = dyn_cursor->cursor_col_offsets;
  uint8_t *types = dyn_cursor->cursor_data_types;
  uint16_t count = offsets[0];  // the first index is the count of fields
  uint8_t *cursor = dyn_cursor->cursor_data;  // we will be using char offsets

  uint8_t code = 0;
  uint16_t nullable_count = 0;
  uint16_t bool_count = 0;

  for (uint16_t i = 0; i < count; i++) {
    uint8_t type = types[i];
    cql_bool nullable = !(type & CQL_DATA_TYPE_NOT_NULL);
    int8_t core_data_type = CQL_CORE_DATA_TYPE_OF(type);

    code = 0;
    if (nullable) {
      nullable_count++;
      code = 'a' - 'A';  // lower case for nullable
    }

    // this makes upper or lower case depending on nullable
    switch (core_data_type) {
      case CQL_DATA_TYPE_INT32:  code += 'I'; break;
      case CQL_DATA_TYPE_INT64:  code += 'L'; break;
      case CQL_DATA_TYPE_DOUBLE: code += 'D'; break;
      case CQL_DATA_TYPE_BOOL:   code += 'F'; bool_count++; break;
      case CQL_DATA_TYPE_STRING: code += 'S'; break;
      case CQL_DATA_TYPE_BLOB:   code += 'B'; break;
    }

    // verifies that we set code
    cql_invariant(code != 0 && code != 'a' - 'A');

    cql_append_value(b, code);
  }

  // null terminate the type info
  code = 0;
  cql_append_value(b, code);

  uint16_t bitvector_bytes_needed = (nullable_count + bool_count + 7) / 8;
  uint8_t *bits = cql_bytebuf_alloc(b, bitvector_bytes_needed);
  memset(bits, 0, bitvector_bytes_needed);
  uint16_t nullable_index = 0;
  uint16_t bool_index = 0;

  for (uint16_t i = 0; i < count; i++) {
    uint16_t offset = offsets[i+1];
    uint8_t type = types[i];

    int8_t core_data_type = CQL_CORE_DATA_TYPE_OF(type);

    if (type & CQL_DATA_TYPE_NOT_NULL) {
      switch (core_data_type) {
        case CQL_DATA_TYPE_INT32: {
          cql_int32 int32_data = *(cql_int32 *)(cursor + offset);
          cql_write_varint_32(b, int32_data);
          break;
        }
        case CQL_DATA_TYPE_INT64: {
          cql_int64 int64_data = *(cql_int64 *)(cursor + offset);
          cql_write_varint_64(b, int64_data);
          break;
        }
        case CQL_DATA_TYPE_DOUBLE: {
          // IEEE 754 big endian seems to be everywhere we need it to be it's
          // good enough for SQLite so it's good enough for us. We're punting on
          // their ARM7 mixed endian support, we don't care about ARM7
          cql_double double_data = *(cql_double *)(cursor + offset);
          cql_append_value(b, double_data);
          break;
        }
        case CQL_DATA_TYPE_BOOL: {
          cql_bool bool_data = *(cql_bool *)(cursor + offset);
          if (bool_data) {
            cql_setbit(bits, nullable_count + bool_index);
          }
          bool_index++;
          break;
        }
        case CQL_DATA_TYPE_STRING: {
          cql_string_ref str_ref = *(cql_string_ref *)(cursor + offset);
          cql_alloc_cstr(temp, str_ref);
          cql_bytebuf_append(b, temp, (uint32_t)(strlen(temp) + 1));
          cql_free_cstr(temp, str_ref);
          break;
        }
        case CQL_DATA_TYPE_BLOB: {
          cql_blob_ref blob_ref = *(cql_blob_ref *)(cursor + offset);
          const void *bytes = cql_get_blob_bytes(blob_ref);
          cql_int32 size = cql_get_blob_size(blob_ref);
          cql_write_varint_32(b, size);
          cql_bytebuf_append(b, bytes, (cql_uint32)size);
          break;
        }
      }
    }
    else {
      switch (core_data_type) {
        case CQL_DATA_TYPE_INT32: {
          cql_nullable_int32 int32_data = *(cql_nullable_int32 *)(cursor + offset);
          if (!int32_data.is_null) {
            cql_setbit(bits, nullable_index);
            cql_write_varint_32(b, int32_data.value);
          }
          break;
        }
        case CQL_DATA_TYPE_INT64: {
          cql_nullable_int64 int64_data = *(cql_nullable_int64 *)(cursor + offset);
          if (!int64_data.is_null) {
            cql_setbit(bits, nullable_index);
            cql_write_varint_64(b, int64_data.value);
          }
          break;
        }
        case CQL_DATA_TYPE_DOUBLE: {
          // IEEE 754 big endian seems to be everywhere we need it to be it's
          // good enough for SQLite so it's good enough for us. We're punting on
          // their ARM7 mixed endian support, we don't care about ARM7
          cql_nullable_double double_data = *(cql_nullable_double *)(cursor + offset);
          cql_append_nullable_value(b, double_data);
          break;
        }
        case CQL_DATA_TYPE_BOOL: {
          cql_nullable_bool bool_data = *(cql_nullable_bool *)(cursor + offset);
          if (!bool_data.is_null) {
            cql_setbit(bits, nullable_index);
            if (bool_data.value) {
              cql_setbit(bits, nullable_count + bool_index);
            }
          }
          bool_index++;
          break;
        }
        case CQL_DATA_TYPE_STRING: {
          cql_string_ref str_ref = *(cql_string_ref *)(cursor + offset);
          if (str_ref) {
            cql_setbit(bits, nullable_index);
            cql_alloc_cstr(temp, str_ref);
            cql_bytebuf_append(b, temp, (uint32_t)(strlen(temp) + 1));
            cql_free_cstr(temp, str_ref);
          }
          break;
        }
        case CQL_DATA_TYPE_BLOB: {
          cql_blob_ref blob_ref = *(cql_blob_ref *)(cursor + offset);
          if (blob_ref) {
            cql_setbit(bits, nullable_index);
            const void *bytes = cql_get_blob_bytes(blob_ref);
            cql_int32 size = cql_get_blob_size(blob_ref);
            cql_write_varint_32(b, size);
            cql_bytebuf_append(b, bytes, (cql_uint32)size);
          }
          break;
        }
      }
      nullable_index++;
    }
  }
  cql_invariant(nullable_index == nullable_count);
}

// This standard helper walks any cursor and creates a versionable encoding of
// it in a blob.  The dynamic cursor structure has all the necessary metadata
// about the cursor.  By the time this is called many checks have been made
// about the suitability of this cursor for serialization (e.g. no OBJECT
// fields). As a consequence we get a nice simple strategy that is flexible.
// CQLABI
cql_code cql_cursor_to_blob(
  sqlite3 *_Nonnull db,
  cql_dynamic_cursor *_Nonnull dyn_cursor,
  cql_blob_ref _Nullable *_Nonnull blob)
{
  if (!*dyn_cursor->cursor_has_row) {
    return SQLITE_ERROR;
  }

  cql_bytebuf b;
  cql_bytebuf_open(&b);

  cql_cursor_to_bytebuf(dyn_cursor, &b);

  cql_blob_ref new_blob = cql_blob_ref_new((const uint8_t *)b.ptr, (cql_int32)b.used);
  cql_blob_release(*blob);
  *blob = new_blob;

  cql_bytebuf_close(&b);
  return SQLITE_OK;
}

// create a single blob for the whole stream of appended blobs
// with offsets for easy array style access.
cql_blob_ref _Nonnull cql_make_blob_stream(cql_object_ref _Nonnull blob_list)
{
  cql_contract(blob_list);

  cql_bytebuf b;
  cql_bytebuf_open(&b);
  cql_uint32 count = (cql_uint32)cql_blob_list_count(blob_list);

  // note that we're assuming little endian here, this could be generalized
  cql_append_value(&b, count);

  cql_int32 offset_next = (cql_int32)((1 + count)*sizeof(cql_int32));

  for (cql_int32 i = 0; i < count; i++) {
    cql_blob_ref blob = cql_blob_list_get_at(blob_list, i);
    cql_contract(blob);

    cql_int32 size = cql_get_blob_size(blob);
    offset_next += size;

    // note that we're assuming little endian here, this could be generalized
    cql_append_value(&b, offset_next);
  }

  for (cql_int32 i = 0; i < count; i++) {
    cql_blob_ref blob = cql_blob_list_get_at(blob_list, i);
    cql_uint32 size = (cql_uint32)cql_get_blob_size(blob);
    const uint8_t *bytes = (const uint8_t *)cql_get_blob_bytes(blob);
   
    cql_bytebuf_append(&b, bytes, size);
  }

  cql_blob_ref result = cql_blob_ref_new((const uint8_t *)b.ptr, (cql_int32)b.used);
  cql_bytebuf_close(&b);

  return result;
}

// Generic method to hash a dynamic cursor: Note this code takes advantage of
// the fact that null valued primitives are normalized to "isnull = 1" and
// "value = 0" so the whole thing can be hashed with impunity even when it is in
// the null state.  With not much work this assumption could be removed if
// needed at a later time.
// CQLABI
cql_int64 cql_cursor_hash(
  cql_dynamic_cursor *_Nonnull dyn_cursor)
{
  if (!*dyn_cursor->cursor_has_row) {
    return 0;
  }

  return (cql_int64)cql_hash_buffer(
    dyn_cursor->cursor_data,
    dyn_cursor->cursor_size,
    dyn_cursor->cursor_refs_count,
    dyn_cursor->cursor_refs_offset);
}

// Generic method to compare two dynamic cursors Note this code takes advantage
// of the fact that null valued primitives are normalized to "isnull = 1" and
// "value = 0" so the whole thing can be hashed with impunity even when it is in
// the null state.  With not much work this assumption could be removed if
// needed at a later time.
// CQLABI
cql_bool cql_cursors_equal(
  cql_dynamic_cursor *_Nonnull c1,
  cql_dynamic_cursor *_Nonnull c2)
{
  // first check metadata for equivalence, and both must have a row, or not have a row

  if (c1->cursor_size != c2->cursor_size ||
      c1->cursor_refs_count != c2->cursor_refs_count ||
      c1->cursor_refs_offset != c2->cursor_refs_offset ||
      *c1->cursor_has_row != *c2->cursor_has_row) {
    return false;
  }

  // if metadata matches and neither has data that's a match (empty cursors are equal)
  // note we already know their has_row values are the same
  if (!*c1->cursor_has_row) {
    cql_invariant(!*c2->cursor_has_row);
    return true;
  }

  return cql_buffers_equal(
    c1->cursor_data,
    c2->cursor_data,
    c1->cursor_size,
    c1->cursor_refs_count,
    c1->cursor_refs_offset);
}

// release the references in a cursor using the types and offsets info
static void cql_clear_references_before_deserialization(
  cql_dynamic_cursor *_Nonnull dyn_cursor)
{
  // this is just a normal release of ref columns from the dyn cursor structure
  cql_release_offsets(dyn_cursor->cursor_data, dyn_cursor->cursor_refs_count, dyn_cursor->cursor_refs_offset);
}

#define cql_read_var(buf, var) \
   if (!cql_input_read(buf, &var, sizeof(var))) { \
     goto error; \
   }

// This is the inverse of cql_cursor_to_bytebuf, it takes a byte stream and
// reconstructs a dynamic cursor from it.  The byte stream is assumed to be
// hostile. It could be corrupted in any kind of way and this code is expected
// to handle that.
cql_code cql_cursor_from_bytes(
  cql_dynamic_cursor *_Nonnull dyn_cursor,
  const uint8_t *_Nonnull bytes,
  uint32_t size)
{
  cql_invariant(bytes);

  cql_bool *has_row = dyn_cursor->cursor_has_row;
  uint16_t *offsets = dyn_cursor->cursor_col_offsets;
  uint8_t *types = dyn_cursor->cursor_data_types;
  uint8_t *cursor = dyn_cursor->cursor_data;  // we will be using char offsets

  // we have to release the existing cursor before we start
  // we'll be clobbering the fields while we build it.

  *has_row = false;
  cql_clear_references_before_deserialization(dyn_cursor);

  cql_input_buf input;
  input.data = bytes;
  input.remaining = size;

  uint16_t needed_count = offsets[0];  // the first index is the count of fields

  uint16_t nullable_count = 0;
  uint16_t bool_count = 0;
  uint16_t actual_count = 0;
  uint16_t i = 0;

  for (;;) {
    char code;
    cql_read_var(&input, code);

    if (!code) {
      break;
    }

    bool nullable_code = (code >= 'a' && code <= 'z');
    nullable_count += nullable_code;
    actual_count++;

    if (code == 'f' || code == 'F') {
      bool_count++;
    }

    // Extra fields do not have to match, the assumption is that this is a
    // future version of the type talking to a past version.  The past version
    // sees only what it expects to see.  However, we did have to compute the
    // nullable_count and bool_count to get the bit vector size correct.
    if (actual_count <= needed_count) {
      uint8_t type = types[i++];
      bool nullable_type = !(type & CQL_DATA_TYPE_NOT_NULL);
      uint8_t core_data_type = CQL_CORE_DATA_TYPE_OF(type);

      // it's ok if we need a nullable but we're getting a non-nullable
      if (!nullable_type && nullable_code) {
        // nullability must match
        goto error;
      }

      // normalize to the not null type, we've already checked nullability match
      code = nullable_code ? code - ('a' - 'A') : code;

      // ensure that what we have is what we need for all of what we have
      bool code_ok = false;
      switch (core_data_type) {
        case CQL_DATA_TYPE_INT32:  code_ok = code == 'I'; break;
        case CQL_DATA_TYPE_INT64:  code_ok = code == 'L'; break;
        case CQL_DATA_TYPE_DOUBLE: code_ok = code == 'D'; break;
        case CQL_DATA_TYPE_BOOL:   code_ok = code == 'F'; break;
        case CQL_DATA_TYPE_STRING: code_ok = code == 'S'; break;
        case CQL_DATA_TYPE_BLOB:   code_ok = code == 'B'; break;
      }

      if (!code_ok) {
        goto error;
      }
    }
  }

  // if we have too few fields we can use null fillers, this is the versioning
  // policy, we will check that any missing fields are nullable.
  while (i < needed_count) {
    uint8_t type = types[i++];
    if (type & CQL_DATA_TYPE_NOT_NULL) {
      goto error;
    }
  }

  // get the bool bits we need
  const uint8_t *bits;
  uint16_t bytes_needed = (nullable_count + bool_count + 7) / 8;
  if (!cql_input_inline_bytes(&input, &bits, bytes_needed)) {
    goto error;
  }

  uint16_t nullable_index = 0;
  uint16_t bool_index = 0;

  // The types are compatible and we have enough of them, we can start
  // trying to decode.

  for (i = 0; i < needed_count; i++) {
    uint16_t offset = offsets[i+1];
    uint8_t type = types[i];

    cql_int32 core_data_type = CQL_CORE_DATA_TYPE_OF(type);

    bool fetch_data = false;
    bool needed_notnull = !!(type & CQL_DATA_TYPE_NOT_NULL);

    if (i >= actual_count) {
      // we don't have this field
      fetch_data = false;
    }
    else {
      bool actual_notnull = bytes[i] >= 'A' && bytes[i] <= 'Z';

      if (actual_notnull) {
        // marked not null in the metadata means it is always present
        fetch_data = true;
      }
      else {
        // fetch any nullable field if and only if its not null bit is set
        fetch_data = cql_getbit(bits, nullable_index++);
      }
    }

    if (fetch_data) {
      switch (core_data_type) {
        case CQL_DATA_TYPE_INT32: {
          cql_int32 *result;
          if (needed_notnull) {
            result = (cql_int32 *)(cursor + offset);
          }
          else {
            cql_nullable_int32 *nullable_storage = (cql_nullable_int32 *)(cursor+offset);
            nullable_storage->is_null = false;
            result = &nullable_storage->value;
          }
          if (!cql_read_varint_32(&input, result)) {
            goto error;
          }

          break;
        }
        case CQL_DATA_TYPE_INT64: {
          cql_int64 *result;
          if (needed_notnull) {
            result = (cql_int64 *)(cursor + offset);
          }
          else {
            cql_nullable_int64 *nullable_storage = (cql_nullable_int64 *)(cursor+offset);
            nullable_storage->is_null = false;
            result = &nullable_storage->value;
          }
          if (!cql_read_varint_64(&input, result)) {
            goto error;
          }
          break;
        }
        case CQL_DATA_TYPE_DOUBLE: {
          // IEEE 754 big endian seems to be everywhere we need it to be
          // it's good enough for SQLite so it's good enough for us.
          // We're punting on their ARM7 mixed endian support, we don't care about ARM7
          cql_double *result;
          if (needed_notnull) {
            result = (cql_double *)(cursor + offset);
          }
          else {
            cql_nullable_double *nullable_storage = (cql_nullable_double *)(cursor+offset);
            nullable_storage->is_null = false;
            result = &nullable_storage->value;
          }
          cql_read_var(&input, *result);
          break;
        }
        case CQL_DATA_TYPE_BOOL: {
          cql_bool *result;
          if (needed_notnull) {
            result = (cql_bool *)(cursor + offset);
          }
          else {
            cql_nullable_bool *nullable_storage = (cql_nullable_bool *)(cursor+offset);
            nullable_storage->is_null = false;
            result = &nullable_storage->value;
          }
          *result = cql_getbit(bits, nullable_count + bool_index);
          bool_index++;
          break;
        }
        case CQL_DATA_TYPE_STRING: {
          cql_string_ref *str_ref = (cql_string_ref *)(cursor + offset);
          const char *result;
          if (!cql_input_inline_str(&input, &result)) {
            goto error;
          }
          *str_ref = cql_string_ref_new(result);
          break;
        }
        case CQL_DATA_TYPE_BLOB: {
          cql_blob_ref *blob_ref = (cql_blob_ref *)(cursor + offset);
          cql_int32 byte_count;
          if (!cql_read_varint_32(&input, &byte_count)) {
            goto error;
          }
          const uint8_t *result;
          if (!cql_input_inline_bytes(&input, &result, (cql_uint32)byte_count)) {
            goto error;
          }
          *blob_ref = cql_blob_ref_new(result, byte_count);
          break;
        }
      }
    }
    else {
      switch (core_data_type) {
        case CQL_DATA_TYPE_INT32: {
          cql_nullable_int32 *int32_data = (cql_nullable_int32 *)(cursor + offset);
          int32_data->value = 0;
          int32_data->is_null = true;
          break;
        }
        case CQL_DATA_TYPE_INT64: {
          cql_nullable_int64 *int64_data = (cql_nullable_int64 *)(cursor + offset);
          int64_data->value = 0;
          int64_data->is_null = true;
          break;
        }
        case CQL_DATA_TYPE_DOUBLE: {
          cql_nullable_double *double_data = (cql_nullable_double *)(cursor + offset);
          double_data->value = 0;
          double_data->is_null = true;
          break;
        }
        case CQL_DATA_TYPE_BOOL: {
          cql_nullable_bool *bool_data = (cql_nullable_bool *)(cursor + offset);
          bool_data->value = 0;
          bool_data->is_null = true;
          bool_index++;
          break;
        }
        case CQL_DATA_TYPE_STRING: {
          cql_string_ref *str_ref = (cql_string_ref *)(cursor + offset);
          *str_ref = NULL;
          break;
        }
        case CQL_DATA_TYPE_BLOB: {
          cql_blob_ref *blob_ref = (cql_blob_ref *)(cursor + offset);
          *blob_ref = NULL;
          break;
        }
      }
    }
  }

  *has_row = true;
  return SQLITE_OK;

error:
  *has_row = false;
  cql_clear_references_before_deserialization(dyn_cursor);
  return SQLITE_ERROR;
}

// cql friendly wrapper for blob deserialization
// CQLABI
cql_code cql_cursor_from_blob(
  sqlite3 *_Nonnull db,
  cql_dynamic_cursor *_Nonnull dyn_cursor,
  cql_blob_ref _Nullable b)
{
  cql_bool *has_row = dyn_cursor->cursor_has_row;

  if (!b) {
    goto error;
  }

  const uint8_t *bytes = (const uint8_t *)cql_get_blob_bytes(b);
  const uint32_t len = (uint32_t)cql_get_blob_size(b);
  return cql_cursor_from_bytes(dyn_cursor, bytes, len);

error:
  *has_row = false;
  cql_clear_references_before_deserialization(dyn_cursor);
  return SQLITE_ERROR;
}

// extract the count from the blob stream
// CQLABI
cql_int32 cql_blob_stream_count(cql_blob_ref _Nonnull b)
{
  cql_contract(b);

  const uint8_t *bytes = (const uint8_t *)cql_get_blob_bytes(b);
  const uint32_t len = (uint32_t)cql_get_blob_size(b);

  // the first 4 bytes are the count of blobs
  return len >= 4 ? *(cql_int32 *)bytes : 0;
}


// cql friendly wrapper for blob deserialization from blob array
// CQLABI
cql_code cql_cursor_from_blob_stream(
  sqlite3 *_Nonnull db,
  cql_dynamic_cursor *_Nonnull dyn_cursor,
  cql_blob_ref _Nonnull b,
  cql_int32 index)
{
  cql_contract(b);
  cql_bool *has_row = dyn_cursor->cursor_has_row;

  const uint8_t *bytes = (const uint8_t *)cql_get_blob_bytes(b);
  const uint32_t len = (uint32_t)cql_get_blob_size(b);

  if (len < 4) {
    goto error;
  }

  // the first 4 bytes are the count of blobs
  // note that we're assuming little endian here, this could be generalized
  uint32_t count = *(uint32_t *)bytes;

  if (index < 0 || index >= count || (index + 1) * 4 >= len) {
    goto error;
  }

  // note that we're assuming little endian here, this could be generalized
  uint32_t end = *(uint32_t *)(bytes + (index + 1) * 4);
  if (end > len) {
    goto error;
  }

  // the first blob starts after the offsets and count
  uint32_t start = (count + 1) * sizeof(cql_int32);

  if (index > 0) {
    // the first blob starts at 0 which is not recorded
    // note that we're assuming little endian here, this could be generalized
    start = *(uint32_t *)(bytes + index * 4);
  }

  if (start > end) {
    goto error;
  }

  return cql_cursor_from_bytes(dyn_cursor, bytes + start, end - start);

error:
  *has_row = false;
  cql_clear_references_before_deserialization(dyn_cursor);
  return SQLITE_ERROR;
}

// The outside world does not need to know the details of the partitioning
// so it's defined locally.
typedef struct cql_partition {
  cql_hashtab *_Nonnull ht;
  cql_object_ref _Nullable empty_result; // all empty result sets are the same
  cql_dynamic_cursor c_key; // this captures the shape of the key, all must be the same
  cql_dynamic_cursor c_key2; // two copies of the key shape (for equality checks)
  cql_dynamic_cursor c_val; // row values must also be all the same
  cql_bool has_row; // the stored dynamic cursors above need a has row field, it's here, always true
  cql_bool did_extract; // true if we have begun extracting (no more adding after that)
} cql_partition;

// Any remaining keys should release their references and give back their
// memory. We only have to release if there is at least one reference.
static void cql_partition_key_release(
  void *_Nullable context,
  cql_int64 key)
{
  cql_partition *_Nonnull self = context;
  void *pv = (void *)key;
  if (self->c_key.cursor_refs_count) {
    cql_release_offsets(pv, self->c_key.cursor_refs_count, self->c_key.cursor_refs_offset);
  }
  free((void *)pv);
}

// We're just going to look at the buffer and release any pointers in any rows
// before releasing the buffer itself.  We only have to do the release
// operations if there was at least one reference in the data.  Otherwise
// closing the buffer releases its internal storage.  The buffer itself doesn't
// know what it's holding so we have to do the internal releases for it.
static void cql_partition_val_release(
  void *_Nullable context,
  cql_int64 val)
{
  if (val & 1) {
    // this means there is a pre-allocated result set here, we just release it
    cql_object_ref obj = (cql_object_ref)(val & ~(cql_int64)1);
    cql_object_release(obj);
    return;
  }

  cql_partition *_Nonnull self = context;
  cql_bytebuf * buffer = (cql_bytebuf *)val;
  uint16_t refs_count = self->c_val.cursor_refs_count;

  if (refs_count) {
    uint16_t refs_offset = self->c_val.cursor_refs_offset;
    size_t rowsize = self->c_val.cursor_size;
    cql_uint32 count = buffer->used / rowsize;

    char *row = buffer->ptr;
    for (cql_uint32 i = 0; i < count ; i++, row += rowsize) {
      cql_release_offsets(row, refs_count, refs_offset);
    }
  }
  // releases the internal buffer
  cql_bytebuf_close(buffer);
  free(buffer);
}

// When we're going to tear down the partition we want to release anything left
// in it. We just change the release functions now so that they actually do
// something.  The helpers above will free the keys/values including iterating
// the buffer contents if there are any unused buffers left.
static void cql_partition_finalize(void *_Nonnull data) {
  // recover self
  cql_partition *_Nonnull self = data;

  // we're doing final cleanup now so attach the release code these are not ref
  // counted so normally you just copy them (hence no-op retain/release) but now
  // we are doing for real cleanup.
  self->ht->release_key = cql_partition_key_release;
  self->ht->release_val = cql_partition_val_release;

  if (self->empty_result) {
    cql_object_release(self->empty_result);
  }

  cql_hashtab_delete(self->ht);

  free(self);
}

// We just defer to the cursor helper using the stored key metadata
static uint64_t cql_key_cursor_hash(
  void *_Nullable context,
  cql_int64 key)
{
  cql_contract(context);
  cql_partition *_Nonnull self = context;

  // c_key is preloaded with the unique meta data for this partition all we need
  // to do is copy in the cursor data.  We already verified all metadata is the
  // one and only legal metadata for this partitioning
  self->c_key.cursor_data = (void *)key;
  return (uint64_t)cql_cursor_hash(&self->c_key);
}

// We just defer to the cursor helper using the stored key metadata
static bool cql_key_cursor_eq(
  void *_Nullable context,
  cql_int64 key1,
  cql_int64 key2)
{
  cql_contract(context);
  cql_partition *_Nonnull self = context;

  // c_key and c_key2 are preloaded with the unique meta data for this partition
  // all we need to do is copy in the cursor data.  We already verified all
  // metadata is the one and only legal metadata for this partitioning
  self->c_key.cursor_data = (void *)key1;
  self->c_key2.cursor_data = (void *)key2;
  return cql_cursors_equal(&self->c_key, &self->c_key2);
}

// This makes an empty partitioning object, which is basically just a configured
// hash table.  The hash table is set to use the helpers above.  Normally there
// is no need to retain/release when rehashing or copying as the hash table is
// the one and only owner of this particular data.  However, we change the
// finalization functions at shutdown to allow the hashtable to help us clean up
// its contents when they are condemned.
cql_object_ref _Nonnull cql_partition_create(void) {

  cql_partition *_Nonnull self = calloc(1, sizeof(cql_partition));

  cql_object_ref obj = _cql_generic_object_create(self, cql_partition_finalize);

  self->has_row = true;  // we only store cursors with data in them
  self->did_extract = false;  // we haven't yet started extracting

  self->ht = cql_hashtab_new(
    cql_key_cursor_hash,
    cql_key_cursor_eq,
    cql_no_op_retain_release,
    cql_no_op_retain_release,
    cql_no_op_retain_release,
    cql_no_op_retain_release,
    self
  );

  return obj;
}

// This is the main workhorse.  Here the idea is that we are given key columns
// from a particular row as well as the whole row, later we will look up the row
// by its key.  Of course the key doesn't have to be in the row but that's the
// normal pattern.  That is, normally key and val are looking at the same data
// with key being a subset of the columns of val. We are going to hash the key
// and then append the val to a buffer associated with that key.  We make the
// buffers on demand so, there are never really any empty buffers except for a
// brief instant. Any missing keys will have no data.  We use the cursor hashing
// and equality helpers to do the hash table work.  We use the usual
// retain/release helpers for cursors to ensure that the right number of
// retain/release calls happen on each key/value.
cql_bool cql_partition_cursor(
  cql_object_ref _Nonnull obj,
  cql_dynamic_cursor *_Nonnull key,
  cql_dynamic_cursor *_Nonnull val)
{
  cql_partition *_Nonnull self = _cql_generic_object_get_data(obj);

  // If this contract fails it means you tried to add more rows after extraction
  // began. This is not allowed.  Look up the stack for the invalid call.
  cql_contract(!self->did_extract);

  if (self->c_key.cursor_size) {
    // we're not seeing the first key/val cursor, all copies must be from the
    // same metadata
    cql_contract(self->c_key.cursor_size == key->cursor_size);
    cql_contract(self->c_key.cursor_refs_count == key->cursor_refs_count);
    cql_contract(self->c_key.cursor_refs_offset == key->cursor_refs_offset);
    cql_contract(self->c_val.cursor_size == val->cursor_size);
    cql_contract(self->c_val.cursor_refs_count == val->cursor_refs_count);
    cql_contract(self->c_val.cursor_refs_offset == val->cursor_refs_offset);
  }
  else {
    // we want 2 copies of the metadata for keys (for comparison) one copy of
    // the values shape will do.
    self->c_key = *key;
    self->c_key2 = *key;
    self->c_val = *val;

    // the pointer has to be fixed up to point to the shared (always true) has row
    self->c_key.cursor_has_row = &self->has_row;
    self->c_key2.cursor_has_row = &self->has_row;
    self->c_val.cursor_has_row = &self->has_row;
  }

  if (!*key->cursor_has_row || !*val->cursor_has_row) {
    return false;
  }

  // we want to avoid storing the whole dynamic cursor since they are all the
  // same so we hash on the data and we use the context to get the cursor back
  cql_hashtab_entry *entry = cql_hashtab_find(self->ht, (cql_int64)key->cursor_data);
  cql_bytebuf *buf = NULL;

  if (entry) {
    // we already have a buffer, we can append
    buf = (cql_bytebuf *)entry->val;
  }
  else {
    // create buffer and add to hash table
    buf = malloc(sizeof(*buf));
    cql_bytebuf_open(buf);

    char *k = malloc(key->cursor_size);
    memcpy(k, key->cursor_data, key->cursor_size);
    cql_retain_offsets(k, key->cursor_refs_count, key->cursor_refs_offset);

    cql_bool added = cql_hashtab_add(self->ht, (cql_int64)k, (cql_int64)buf);
    cql_invariant(added);
  }

  cql_invariant(buf);

  // append this value to the growable buffer
  char *new_data = cql_bytebuf_alloc(buf, (cql_uint32)val->cursor_size);
  memcpy(new_data, val->cursor_data, val->cursor_size);
  cql_retain_offsets(new_data, val->cursor_refs_count, val->cursor_refs_offset);

  return true;
}

// Here we have created partitions previously and we're going to look them up.
// The idea is that if rows for a particular key combo exists then we make a
// result set out of that bunch of rows. If not, we return an empty result set
// (0 rows).  To save space we only create one empty result set for all cases in
// any given partition because all empty results are the same.
cql_object_ref _Nonnull cql_extract_partition(
  cql_object_ref _Nonnull obj,
  cql_dynamic_cursor *_Nonnull key)
{
  cql_partition *_Nonnull self = _cql_generic_object_get_data(obj);

  self->did_extract = true;

  if (self->c_key.cursor_size) {
    cql_contract(self->c_key.cursor_size == key->cursor_size);
    cql_contract(self->c_key.cursor_refs_count == key->cursor_refs_count);
    cql_contract(self->c_key.cursor_refs_offset == key->cursor_refs_offset);
    cql_contract(self->c_val.cursor_size);

    cql_hashtab_entry *entry = cql_hashtab_find(self->ht, (cql_int64)key->cursor_data);
    cql_bytebuf *buf = NULL;

    if (entry) {
      // If we've already computed the value then re-use what we returned
      // before. When used for parent/child processing (the normal case) this
      // would be like having a parent result set where two parent rows refer to
      // the same child result.
      if (entry->val & 1) {
        // strip the lower bit and make the object
        cql_object_ref result_set = (cql_object_ref)(entry->val & ~(cql_int64)1);
        cql_object_retain(result_set);
        return result_set;
      }

      // we have data for this key
      buf = (cql_bytebuf *)entry->val;

      // We always load a valid buffer, if this is zero something very bad has
      // happened.
      cql_invariant(buf);

      cql_int32 count = (cql_int32)(buf->used / self->c_val.cursor_size);

      cql_fetch_info info = {
        .data_types = self->c_val.cursor_data_types,
        .col_offsets = self->c_val.cursor_col_offsets,
        .refs_count = self->c_val.cursor_refs_count,
        .refs_offset = self->c_val.cursor_refs_offset,
        .rowsize = (uint32_t)self->c_val.cursor_size,
      };

      // make the meta from standard info
      cql_result_set_meta meta;
      cql_initialize_meta(&meta, &info);

      void *data = buf->ptr;

      // the bytebuf has been harvested, we can free it now.  We do not "close"
      // it because the result set is taking over the growable buffer, we don't
      // want the buffer to be freed.
      free(buf);

      // retain our copy in case we need it again
      cql_object_ref result = (cql_object_ref)cql_result_set_create(data, count, meta);
      cql_object_retain(result);

      // store the result but set the LSB so we know it's not a buffer
      entry->val = 1|(cql_int64)result;
      return result;
    }
  }

  if (!self->empty_result) {
    static uint8_t empty_dataTypes[] = { };
    static uint16_t empty_colOffsets[] = { 0 };

    cql_fetch_info empty_info = {
      .data_types = empty_dataTypes,
      .col_offsets = empty_colOffsets,
    };

    // make the meta from standard info
    cql_result_set_meta empty_meta;
    cql_initialize_meta(&empty_meta, &empty_info);
    self->empty_result = (cql_object_ref)cql_result_set_create(malloc(1), 0, empty_meta);
  }

  cql_invariant(self->empty_result);
  cql_object_retain(self->empty_result);
  return self->empty_result;
}

// Check the table definition "haystack" searching for the column definition
// string "needle" The needle must start after a space or an open paren (start
// of lexical unit) to match a possible column defintion.
cql_bool _cql_contains_column_def(
  cql_string_ref _Nullable haystack_,
  cql_string_ref _Nullable needle_)
{
  if (!haystack_ || !needle_) {
    return false;
  }

  cql_alloc_cstr(haystack, haystack_);
  cql_alloc_cstr(needle, needle_);

  cql_bool found = false;

  if (!needle[0] || !haystack[0]) {
    goto cleanup;
  }

  const char *p = haystack + 1;

  for (;;) {
    p = strstr(p, needle);
    if (!p) {
      goto cleanup;
    }

    // if column info found at start of word, it's a match
    if (p[-1] == ' ' || p[-1] == '(') {
      found = true;
      goto cleanup;
    }

    p++;
  }

cleanup:
  cql_free_cstr(needle, needle_);
  cql_free_cstr(haystack, haystack_);
  return found;
}

// Defer finalization to the hash table which has all it needs to do the job
static void cql_string_dictionary_finalize(void *_Nonnull data) {
  // recover self
  cql_hashtab *_Nonnull self = data;
  cql_hashtab_delete(self);
}

// This makes a simple string dictionary with retained strings
// CQLABI
cql_object_ref _Nonnull cql_string_dictionary_create(void) {

  // we can re-use the hash, equality, retain, and release from the
  // cql_string_dictionary keys and values are the same in this hash table so we
  // can use the same function to retain/release either
  cql_hashtab *self = cql_hashtab_new(
      cql_key_str_hash,
      cql_key_str_eq,
      cql_key_retain,
      cql_key_retain,
      cql_key_release,
      cql_key_release,
      NULL
    );

  cql_object_ref obj = _cql_generic_object_create(
    self,
    cql_string_dictionary_finalize);

  return obj;
}

// Delegate the add operation to the internal hashtable
// CQLABI
cql_bool cql_string_dictionary_add(
  cql_object_ref _Nonnull dict,
  cql_string_ref _Nonnull key,
  cql_string_ref _Nonnull val)
{
  cql_contract(dict);
  cql_contract(key);
  cql_contract(val);

  cql_hashtab *_Nonnull self = _cql_generic_object_get_data(dict);

  cql_hashtab_entry *entry = cql_hashtab_find(self, (cql_int64)key);

  if (entry) {
    // mutate the value in place, retain the new value first
    // in case it is the same as the old value
    cql_string_retain(val);
    cql_string_release((cql_string_ref)entry->val);
    entry->val = (cql_int64)val;
    return false;
  }

  // retain/release defined above, the key/value will be retained
  return cql_hashtab_add(self, (cql_int64)key, (cql_int64)val);
}

// Lookup the given string in the hash table, note that we do not retain the string
// CQLABI
cql_string_ref _Nullable cql_string_dictionary_find(
  cql_object_ref _Nonnull dict,
  cql_string_ref _Nullable key)
{
  cql_contract(dict);

  if (!key) {
     return NULL;
  }

  cql_hashtab *_Nonnull self = _cql_generic_object_get_data(dict);

  cql_hashtab_entry *entry = cql_hashtab_find(self, (cql_int64)key);

  return entry ? (cql_string_ref)entry->val : NULL;
}

// This makes a simple long dictionary with string keys.  The storage
// is the usual cql_hashtab but the keys are strings and the values are
// longs.  The keys are retained and released as strings.  The long values
// of course fit directly in the hash table which holds cql_int64 natively.
// CQLABI
cql_object_ref _Nonnull cql_long_dictionary_create(void) {

  // we can re-use the hash, equality, retain, and release from the
  // cql_string_dictionary keys.  Values are not objects so they
  // need no cleanup.
  cql_hashtab *self = cql_hashtab_new(
      cql_key_str_hash,
      cql_key_str_eq,
      cql_key_retain,
      cql_no_op_retain_release, // value retain is a no-op
      cql_key_release,
      cql_no_op_retain_release, // value release is a no-op
      NULL
    );

  // the dictionary finalizer is the same for all dictionaries
  cql_object_ref obj = _cql_generic_object_create(
    self,
    cql_string_dictionary_finalize);

  return obj;
}

// Delegate the add operation to the internal hashtable
// CQLABI
cql_bool cql_long_dictionary_add(
  cql_object_ref _Nonnull dict,
  cql_string_ref _Nonnull key,
  cql_int64 val)
{
  cql_contract(dict);
  cql_contract(key);

  cql_hashtab *_Nonnull self = _cql_generic_object_get_data(dict);
  cql_hashtab_entry *entry = cql_hashtab_find(self, (cql_int64)key);

  if (entry) {
    // mutate the value in place
    entry->val = val;
    return false;
  }

  // retain/release defined above, the key will be retained
  return cql_hashtab_add(self, (cql_int64)key, val);
}

// Lookup the given string in the hash table, note that we do not retain the string
// CQLABI
cql_nullable_int64 cql_long_dictionary_find(
  cql_object_ref _Nonnull dict,
  cql_string_ref _Nullable key)
{
  cql_contract(dict);
  cql_nullable_int64 result = {
     .is_null = true,
     .value = 0,
  };

  if (key) {
    cql_hashtab *_Nonnull self = _cql_generic_object_get_data(dict);
    cql_hashtab_entry *entry = cql_hashtab_find(self, (cql_int64)key);

    if (entry) {
      // we have a result
       result.value = entry->val;
       result.is_null = 0;
    }
  }

  return result;
}

// This makes a simple real dictionary with string keys, the values are doubles.
// We have to assume that a double is the same size as an int64 so we can store
// it directly in the hash table.  The keys are retained and released as
// strings. The double values are not objects so they need no cleanup. The
// storage is the usual cql_hashtab. There are asserts to verify that the size
// of a double is the same as an int64. If you need this to work somewhere this
// isn't true then cqlrt.h will need to provide a wrapper to do the platform
// specific conversion for you.  cql_hashtab could be generalized so that it
// holds a union for its values but at this point int64 does the job so we just
// go with that.
// CQLABI
cql_object_ref _Nonnull cql_real_dictionary_create(void) {

  // we can re-use the hash, equality, retain, and release from the
  // cql_string_dictionary keys.  Values are not objects so they
  // need no cleanup.
  cql_hashtab *self = cql_hashtab_new(
      cql_key_str_hash,
      cql_key_str_eq,
      cql_key_retain,
      cql_no_op_retain_release, // value retain is a no-op
      cql_key_release,
      cql_no_op_retain_release, // value release is a no-op
      NULL
    );

  // the dictionary finalizer is the same for all dictionaries
  cql_object_ref obj = _cql_generic_object_create(
    self,
    cql_string_dictionary_finalize);

  return obj;
}

// Delegate the add operation to the internal hashtable
// CQLABI
cql_bool cql_real_dictionary_add(
  cql_object_ref _Nonnull dict,
  cql_string_ref _Nonnull key,
  cql_double val)
{
  cql_contract(dict);
  cql_contract(key);

  cql_hashtab *_Nonnull self = _cql_generic_object_get_data(dict);
  cql_hashtab_entry *entry = cql_hashtab_find(self, (cql_int64)key);

  // We need to cast the double to an int64 to store it in the hash table but we
  // do it in such as way as to preserve the bit pattern of the double so that
  // we can recover the double later. This assumes that a double is exactly the
  // same size as an int64 which is true on all platforms we care about.  If
  // this stops being true we can add a wrapper in cqlrt.h to do the platform
  // specific conversion for us or otherwise generalize the payload.
  CQL_C_ASSERT(sizeof(cql_double) == sizeof(cql_int64));
  cql_int64 v = *(cql_int64 *)&val;

  if (entry) {
    // mutate the value in place
    entry->val = v;
    return false;
  }

  // retain/release defined above, the key will be retained
  return cql_hashtab_add(self, (cql_int64)key, v);
}

// Lookup the given string in the hash table, note that we do not retain the string
// CQLABI
cql_nullable_double cql_real_dictionary_find(
  cql_object_ref _Nonnull dict,
  cql_string_ref _Nullable key)
{
  cql_contract(dict);

  cql_nullable_double result = {
     .is_null = true,
     .value = 0,
  };

  if (key) {
    cql_hashtab *_Nonnull self = _cql_generic_object_get_data(dict);
    cql_hashtab_entry *entry = cql_hashtab_find(self, (cql_int64)key);

    if (entry) {
      // This is the reverse mapping, think of the bits as a double again
      CQL_C_ASSERT(sizeof(cql_double) == sizeof(cql_int64));
      result.value = *(cql_double*)&entry->val;
      result.is_null = 0;
    }
  }

  return result;
}

// This makes a simple object dictionary with retained strings
// CQLABI
cql_object_ref _Nonnull cql_object_dictionary_create(void) {
  // it's the same as a string dictionary internally as it's just object refs
  return cql_string_dictionary_create();
}

// Delegate the add operation to the internal hashtable
// CQLABI
cql_bool cql_object_dictionary_add(
  cql_object_ref _Nonnull dict,
  cql_string_ref _Nonnull key,
  cql_object_ref _Nonnull val)
{
  // again we can cheat... the guts are the same and the value is only retained
  // this could change some day but for now we live for free
  return cql_string_dictionary_add(dict, key, (cql_string_ref)val);
}

// Lookup the given string in the hash table, note that we do not retain the result
// CQLABI
cql_object_ref _Nullable cql_object_dictionary_find(
  cql_object_ref _Nonnull dict,
  cql_string_ref _Nullable key)
{
  // and again, the lookup only borrows the value so we can re-use string
  // dictionary for free.
  return (cql_object_ref)cql_string_dictionary_find(dict, key);
}

// This makes a simple blob dictionary with retained strings
// CQLABI
cql_object_ref _Nonnull cql_blob_dictionary_create(void) {
  // it's the same as a string dictionary internally as it's just object refs
  return cql_string_dictionary_create();
}

// Delegate the add operation to the internal hashtable
// CQLABI
cql_bool cql_blob_dictionary_add(
  cql_object_ref _Nonnull dict,
  cql_string_ref _Nonnull key,
  cql_blob_ref _Nonnull val)
{
  // again we can cheat... the guts are the same and the value is only retained
  // this could change some day but for now we live for free
  return cql_string_dictionary_add(dict, key, (cql_string_ref)val);
}

// Lookup the given string in the hash table, note that we do not retain the result
// CQLABI
cql_blob_ref _Nullable cql_blob_dictionary_find(
  cql_object_ref _Nonnull dict,
  cql_string_ref _Nullable key)
{
  // and again, the lookup only borrows the value so we can re-use string
  // dictionary for free.
  return (cql_blob_ref)cql_string_dictionary_find(dict, key);
}

// We have to release all the strings in the buffer then release the buffer memory
static void cql_string_list_finalize(void *_Nonnull data) {
  cql_bytebuf *_Nonnull self = data;
  cql_uint32 count = self->used / sizeof(cql_string_ref);
  for (uint32_t i = 0; i < count; i++) {
    size_t offset = i * sizeof(cql_string_ref);
    cql_string_ref string = *(cql_string_ref *)(self->ptr + offset);
    cql_string_release(string);
  }
  cql_bytebuf_close(self);
  free(self);
}

// Creates the string list storage using a byte buffer
// CQLABI
cql_object_ref _Nonnull cql_string_list_create(void) {
  cql_bytebuf *self = calloc(1, sizeof(cql_bytebuf));
  cql_bytebuf_open(self);
  return _cql_generic_object_create(self, cql_string_list_finalize);
}

// Adds a string to the given string list and retains it.
// CQLABI
cql_object_ref _Nonnull cql_string_list_add(cql_object_ref _Nonnull list, cql_string_ref _Nonnull string) {
  cql_contract(list);
  cql_contract(string);

  cql_string_retain(string);
  cql_bytebuf *_Nonnull self = _cql_generic_object_get_data(list);
  cql_bytebuf_append(self, &string, sizeof(string));
  return list;
}

// Returns the number of elements in the given string list
// CQLABI
cql_int32 cql_string_list_count(cql_object_ref _Nonnull list) {
  cql_contract(list);

  cql_bytebuf *_Nonnull self = _cql_generic_object_get_data(list);
  return self->used / sizeof(cql_string_ref);
}

// Returns the nth string from the string list with no extra retain (get semantics)
// CQLABI
cql_string_ref _Nonnull cql_string_list_get_at(
  cql_object_ref _Nonnull list,
  cql_int32 index_)
{
  cql_contract(list);
  cql_string_ref result = NULL;
  cql_uint32 index = (cql_uint32)index_; // CQL ABI has no unsigned

  cql_bytebuf *_Nonnull self = _cql_generic_object_get_data(list);
  cql_uint32 count = self->used / sizeof(cql_string_ref);
  cql_contract(index >= 0 && index < count);
  cql_invariant(self->ptr);
  size_t offset = index * sizeof(cql_string_ref);
  result = *(cql_string_ref *)(self->ptr + offset);
  return result;
}

// Edits the string item in place
// CQLABI
cql_object_ref _Nonnull cql_string_list_set_at(
  cql_object_ref _Nonnull list,
  cql_int32 index_,
  cql_string_ref _Nonnull value)
{
  cql_contract(list);
  cql_contract(value);

  cql_uint32 index = (cql_uint32)index_; // CQL ABI has no unsigned

  cql_bytebuf *_Nonnull self = _cql_generic_object_get_data(list);
  cql_uint32 count = self->used / sizeof(cql_string_ref);
  cql_contract(index >= 0 && index < count);
  cql_invariant(self->ptr);
  size_t offset = index * sizeof(cql_string_ref);
  cql_string_ref *data = (cql_string_ref *)(self->ptr + offset);
  cql_set_string_ref(data, value);

  return list;
}

// CQLABI
cql_object_ref _Nonnull cql_object_list_create(void) {
  // the details are the same for strings as objects
  return cql_string_list_create();
}

cql_object_ref _Nonnull cql_object_list_add(
  cql_object_ref _Nonnull list,
  cql_object_ref _Nonnull value)
{
  // the details are the same for strings as objects
  return cql_string_list_add(list, (cql_string_ref)value);
}

// CQLABI
cql_int32 cql_object_list_count(cql_object_ref _Nonnull list) {
  // the details are the same for strings as objects
  return cql_string_list_count(list);
}

// CQLABI
cql_object_ref _Nonnull cql_object_list_get_at(
  cql_object_ref _Nonnull list,
  cql_int32 index)
{
  // the details are the same for strings as objects
  return (cql_object_ref)cql_string_list_get_at(list, index);
}

// CQLABI
cql_object_ref _Nonnull cql_object_list_set_at(
  cql_object_ref _Nonnull list,
  cql_int32 index,
  cql_object_ref _Nonnull value)
{
  // the details are the same for strings as objects
  return cql_string_list_set_at(list, index, (cql_string_ref)value);
}

// CQLABI
cql_object_ref _Nonnull cql_blob_list_create(void) {
  // the details are the same for strings as blobs
  return cql_string_list_create();
}

// CQLABI
cql_object_ref _Nonnull cql_blob_list_add(
  cql_object_ref _Nonnull list,
  cql_blob_ref _Nonnull value)
{
  // the details are the same for strings as blobs
  return cql_string_list_add(list, (cql_string_ref)value);
}

// CQLABI
cql_int32 cql_blob_list_count(cql_object_ref _Nonnull list) {
  // the details are the same for strings as blobs
  return cql_string_list_count(list);
}

// CQLABI
cql_blob_ref _Nonnull cql_blob_list_get_at(
  cql_object_ref _Nonnull list,
  cql_int32 index)
{
  // the details are the same for strings as blobs
  return (cql_blob_ref)cql_string_list_get_at(list, index);
}

// CQLABI
cql_object_ref _Nonnull cql_blob_list_set_at(
  cql_object_ref _Nonnull list,
  cql_int32 index,
  cql_blob_ref _Nonnull value)
{
  // the details are the same for strings as blobs
  return cql_string_list_set_at(list, index, (cql_string_ref)value);
}

// We just release the buffer memory
static void cql_long_list_finalize(void *_Nonnull data) {
  cql_bytebuf *_Nonnull self = data;
  cql_bytebuf_close(self);
  free(self);
}

// Creates the list storage using a byte buffer
// CQLABI
cql_object_ref _Nonnull cql_long_list_create(void) {
  cql_bytebuf *self = calloc(1, sizeof(cql_bytebuf));
  cql_bytebuf_open(self);
  return _cql_generic_object_create(self, cql_long_list_finalize);
}

// Adds a long to the given list
// CQLABI
cql_object_ref _Nonnull cql_long_list_add(
  cql_object_ref _Nonnull list,
  cql_int64 value)
{
  cql_contract(list);
  cql_bytebuf *_Nonnull self = _cql_generic_object_get_data(list);
  cql_bytebuf_append(self, &value, sizeof(value));
  return list;
}

// Returns the number of elements in the given list
// CQLABI
cql_int32 cql_long_list_count(cql_object_ref _Nonnull list) {
  cql_contract(list);

  cql_bytebuf *_Nonnull self = _cql_generic_object_get_data(list);
  return self->used / sizeof(cql_int64);
}

// Returns the nth long from the list
// CQLABI
cql_int64 cql_long_list_get_at(
  cql_object_ref _Nonnull list,
  cql_int32 index_)
{
  cql_contract(list);
  cql_uint32 index = (cql_uint32)index_; // CQL ABI has no unsigned

  cql_bytebuf *_Nonnull self = _cql_generic_object_get_data(list);
  cql_uint32 count = self->used / sizeof(cql_int64);
  cql_contract(index >= 0 && index < count);
  cql_invariant(self->ptr);
  size_t offset = index * sizeof(cql_int64);
  return *(cql_int64 *)(self->ptr + offset);
}

// Edits the item in place
// CQLABI
cql_object_ref _Nonnull cql_long_list_set_at(
  cql_object_ref _Nonnull list,
  cql_int32 index_,
  cql_int64 value)
{
  cql_contract(list);
  cql_contract(value);
  cql_uint32 index = (cql_uint32)index_; // CQL ABI has no unsigned

  cql_bytebuf *_Nonnull self = _cql_generic_object_get_data(list);
  cql_uint32 count = self->used / sizeof(cql_int64);
  cql_contract(index >= 0 && index < count);
  cql_invariant(self->ptr);
  size_t offset = index * sizeof(cql_int64);
  *(cql_int64 *)(self->ptr + offset) = value;

  return list;
}

// Creates the list storage using a byte buffer
// CQLABI
cql_object_ref _Nonnull cql_real_list_create(void) {
  cql_bytebuf *self = calloc(1, sizeof(cql_bytebuf));
  cql_bytebuf_open(self);
  // the long list finalizer works, it just releases the buffer
  return _cql_generic_object_create(self, cql_long_list_finalize);
}

// Adds a real to the given list
// CQLABI
cql_object_ref _Nonnull cql_real_list_add(
  cql_object_ref _Nonnull list,
  cql_double value)
{
  cql_contract(list);
  cql_bytebuf *_Nonnull self = _cql_generic_object_get_data(list);
  cql_bytebuf_append(self, &value, sizeof(value));
  return list;
}

// Returns the number of elements in the given list
// CQLABI
cql_int32 cql_real_list_count(cql_object_ref _Nonnull list) {
  cql_contract(list);

  cql_bytebuf *_Nonnull self = _cql_generic_object_get_data(list);
  return self->used / sizeof(cql_double);
}

// Returns the nth long from the list
// CQLABI
cql_double cql_real_list_get_at(
  cql_object_ref _Nonnull list,
  cql_int32 index_)
{
  cql_contract(list);
  cql_uint32 index = (cql_uint32)index_; // CQL ABI has no unsigned

  cql_bytebuf *_Nonnull self = _cql_generic_object_get_data(list);
  cql_uint32 count = self->used / sizeof(cql_double);
  cql_contract(index >= 0 && index < count);
  cql_invariant(self->ptr);
  size_t offset = index * sizeof(cql_double);
  return *(cql_double *)(self->ptr + offset);
}

// Edits the item in place
// CQLABI
cql_object_ref _Nonnull cql_real_list_set_at(
  cql_object_ref _Nonnull list,
  cql_int32 index_,
  cql_double value)
{
  cql_contract(list);
  cql_contract(value);
  cql_uint32 index = (cql_uint32)index_; // CQL ABI has no unsigned

  cql_bytebuf *_Nonnull self = _cql_generic_object_get_data(list);
  cql_uint32 count = self->used / sizeof(cql_double);
  cql_contract(index >= 0 && index < count);
  cql_invariant(self->ptr);
  size_t offset = index * sizeof(cql_double);
  *(cql_double *)(self->ptr + offset) = value;

  return list;
}

// This is called when the reference count of the boxed statement becomes zero
// It will finalize the actual SQLite statement.  i.e. this is a
// destructor/finalizer
static void cql_boxed_stmt_finalize(void *_Nonnull data) {
  // note that we use cql_finalize_stmt because it can be and often is
  // intercepted to allow for cql statement pooling.
  sqlite3_stmt *stmt = (sqlite3_stmt *)data;
  cql_finalize_stmt(&stmt);
}

// Wraps the given SQLite statement in an object with a reference count
cql_object_ref _Nonnull cql_box_stmt(sqlite3_stmt *_Nullable stmt) {
  return _cql_generic_object_create(stmt, cql_boxed_stmt_finalize);
}

// Extracts the SQL statement from an embedded object for use. Note that this
// does not affect the reference count!
sqlite3_stmt *_Nullable cql_unbox_stmt(cql_object_ref _Nonnull ref) {
  return (sqlite3_stmt *)_cql_generic_object_get_data(ref);
}

static void cql_format_one_cursor_column(
  cql_bytebuf *_Nonnull b,
  cql_dynamic_cursor *_Nonnull dyn_cursor,
  cql_int32 i)
{
  uint16_t *offsets = dyn_cursor->cursor_col_offsets;
  uint8_t *types = dyn_cursor->cursor_data_types;
  uint8_t *cursor = dyn_cursor->cursor_data;  // we will be using char offsets

  uint16_t offset = offsets[i+1];
  uint8_t type = types[i];

  int8_t core_data_type = CQL_CORE_DATA_TYPE_OF(type);

  if (type & CQL_DATA_TYPE_NOT_NULL) {
    switch (core_data_type) {
      case CQL_DATA_TYPE_INT32: {
        cql_int32 int32_data = *(cql_int32 *)(cursor + offset);
        cql_bprintf(b, "%d", int32_data);
        break;
      }
      case CQL_DATA_TYPE_INT64: {
        cql_int64 int64_data = *(cql_int64 *)(cursor + offset);
        cql_bprintf(b, "%lld", (llint_t)int64_data);
        break;
      }
      case CQL_DATA_TYPE_DOUBLE: {
        cql_double double_data = *(cql_double *)(cursor + offset);
        cql_bprintf(b, "%g", double_data);
        break;
      }
      case CQL_DATA_TYPE_BOOL: {
        cql_bool bool_data = *(cql_bool *)(cursor + offset);
        cql_bprintf(b, "%s", bool_data ? "true": "false");
        break;
      }
      case CQL_DATA_TYPE_STRING: {
        cql_string_ref str_ref = *(cql_string_ref *)(cursor + offset);
        cql_alloc_cstr(temp, str_ref);
        cql_bprintf(b, "%s", temp);
        cql_free_cstr(temp, str_ref);
        break;
      }
      case CQL_DATA_TYPE_BLOB: {
        cql_blob_ref blob_ref = *(cql_blob_ref *)(cursor + offset);
        cql_int32 size = cql_get_blob_size(blob_ref);
        cql_bprintf(b, "length %d blob", size);
        break;
      }
      case CQL_DATA_TYPE_OBJECT: {
        cql_bprintf(b, "generic object");
        break;
      }
    }
  }
  else {
    switch (core_data_type) {
      case CQL_DATA_TYPE_INT32: {
        cql_nullable_int32 int32_data = *(cql_nullable_int32 *)(cursor + offset);
        if (int32_data.is_null) {
          cql_bprintf(b, "null");
        }
        else {
          cql_bprintf(b, "%d", int32_data.value);
        }
        break;
      }
      case CQL_DATA_TYPE_INT64: {
        cql_nullable_int64 int64_data = *(cql_nullable_int64 *)(cursor + offset);
        if (int64_data.is_null) {
          cql_bprintf(b, "null");
        }
        else {
          cql_bprintf(b, "%lld", (llint_t)int64_data.value);
        }
        break;
      }
      case CQL_DATA_TYPE_DOUBLE: {
        cql_nullable_double double_data = *(cql_nullable_double *)(cursor + offset);
        if (double_data.is_null) {
          cql_bprintf(b, "null");
        }
        else {
          cql_bprintf(b, "%g", double_data.value);
        }
        break;
      }
      case CQL_DATA_TYPE_BOOL: {
        cql_nullable_bool bool_data = *(cql_nullable_bool *)(cursor + offset);
        if (bool_data.is_null) {
          cql_bprintf(b, "null");
        }
        else {
          cql_bprintf(b, "%s", bool_data.value ? "true" : "false");
        }
        break;
      }
      case CQL_DATA_TYPE_STRING: {
        cql_string_ref str_ref = *(cql_string_ref *)(cursor + offset);
        if (!str_ref) {
          cql_bprintf(b, "null");
        }
        else {
          cql_alloc_cstr(temp, str_ref);
          cql_bprintf(b, "%s", temp);
          cql_free_cstr(temp, str_ref);
        }
        break;
      }
      case CQL_DATA_TYPE_BLOB: {
        cql_blob_ref blob_ref = *(cql_blob_ref *)(cursor + offset);
        if (!blob_ref) {
          cql_bprintf(b, "null");
        }
        else {
          cql_int32 size = cql_get_blob_size(blob_ref);
          cql_bprintf(b, "length %d blob", size);
        }
        break;
      }
      case CQL_DATA_TYPE_OBJECT: {
        cql_object_ref obj_ref = *(cql_object_ref *)(cursor + offset);
        if (!obj_ref) {
          cql_bprintf(b, "null");
        }
        else {
          cql_bprintf(b, "generic object");
        }
        break;
      }
    }
  }
}

// The cursor formatting logic is really super simple
// * we use the bprintf growable buffer format
// * we use the usual dynamic cursor info to find the fields
// * we emit the name of the column and its value
// * if the value is null then we emit the string "null" for its value
// * we put | between fields
// * we use %g for floats
//
// Note that because we use bprintf we're going to get vsnprintf and not the
// sqlite formatting.  This might be slightly different but the point of this
// method is for diagnostics anyway.  It's already the case that floating point
// formatting can vary between systems and that's really where things might be
// different between runtimes. Making this invariant would be pretty costly.
// I'm not even sure sqlite printf is invariant between systems on that score.
//
// this is also available as <some_cursor>:format
// CQLABI
cql_string_ref _Nonnull cql_cursor_format(
  cql_dynamic_cursor *_Nonnull dyn_cursor)
{
  uint16_t *offsets = dyn_cursor->cursor_col_offsets;
  uint16_t count = offsets[0];  // the first index is the count of fields
  const char **fields = dyn_cursor->cursor_fields; // field names for printing

  cql_bytebuf b;
  cql_bytebuf_open(&b);

  for (uint16_t i = 0; i < count; i++) {
    const char *field = fields[i];

    if (i != 0) {
      cql_bprintf(&b, "|");
    }

    cql_bprintf(&b, "%s:", field);

    cql_format_one_cursor_column(&b, dyn_cursor, i);
  }

  cql_bytebuf_append_null(&b);
  cql_string_ref result = cql_string_ref_new(b.ptr);
  cql_bytebuf_close(&b);
  return result;
}

static cql_bool cql_compare_one_cursor_column(
  cql_dynamic_cursor *_Nonnull dyn_cursor1,
  cql_dynamic_cursor *_Nonnull dyn_cursor2,
  cql_int32 i)
{
  uint16_t *offsets1 = dyn_cursor1->cursor_col_offsets;
  uint8_t *types1 = dyn_cursor1->cursor_data_types;
  uint8_t *cursor1 = dyn_cursor1->cursor_data;  // we will be using char offsets
  uint16_t *offsets2 = dyn_cursor2->cursor_col_offsets;
  uint8_t *types2 = dyn_cursor2->cursor_data_types;
  uint8_t *cursor2 = dyn_cursor2->cursor_data;  // we will be using char offsets

  // the type must be an exact match for cursor equality
  // down to nullability.  If we relax this then the combinatorics
  // go through the roof and we just don't need to support all of that.
  // This is pre-verified in semantic analysis for this function
  // so if it reaches this point it's a contract violation.
  uint8_t type1 = types1[i];
  uint8_t type2 = types2[i];
  cql_contract(type1 == type2);

  uint16_t offset1 = offsets1[i+1];
  uint16_t offset2 = offsets2[i+1];

  // count is stored in first offset
  uint16_t count1 = offsets1[0];
  uint16_t count2 = offsets2[0];

  // also pre-verified
  cql_contract(count1 == count2);
  cql_contract(i >= 0 && i < count1);

  int8_t core_data_type = CQL_CORE_DATA_TYPE_OF(type1);

  // handle the reference types first
  switch (core_data_type) {
      case CQL_DATA_TYPE_STRING: {
        cql_string_ref str_ref1 = *(cql_string_ref *)(cursor1 + offset1);
        cql_string_ref str_ref2 = *(cql_string_ref *)(cursor2 + offset2);
        return str_ref1 == str_ref2 || cql_string_equal(str_ref1, str_ref2);
      }
      case CQL_DATA_TYPE_BLOB: {
        cql_blob_ref blob_ref1 = *(cql_blob_ref *)(cursor1 + offset1);
        cql_blob_ref blob_ref2 = *(cql_blob_ref *)(cursor2 + offset2);
        return blob_ref1 == blob_ref2 || cql_blob_equal(blob_ref1, blob_ref2);
      }
      case CQL_DATA_TYPE_OBJECT: {
        cql_object_ref object_ref1 = *(cql_object_ref *)(cursor1 + offset1);
        cql_object_ref object_ref2 = *(cql_object_ref *)(cursor2 + offset2);
        return object_ref1 == object_ref2;
      }
  }

  // value types have to be treated differently depending on nullability

  if (type1 & CQL_DATA_TYPE_NOT_NULL) {
    switch (core_data_type) {
      case CQL_DATA_TYPE_BOOL: {
        cql_bool bool_data1 = *(cql_bool *)(cursor1 + offset1);
        cql_bool bool_data2 = *(cql_bool *)(cursor2 + offset2);
        return bool_data1 == bool_data2;
      }
      case CQL_DATA_TYPE_INT32: {
        cql_int32 int32_data1 = *(cql_int32 *)(cursor1 + offset1);
        cql_int32 int32_data2 = *(cql_int32 *)(cursor2 + offset2);
        return int32_data1 == int32_data2;
      }
      case CQL_DATA_TYPE_INT64: {
        cql_int64 int64_data1 = *(cql_int64 *)(cursor1 + offset1);
        cql_int64 int64_data2 = *(cql_int64 *)(cursor2 + offset2);
        return int64_data1 == int64_data2;
      }
      default: {
        // this is all that's left
        cql_contract(core_data_type == CQL_DATA_TYPE_DOUBLE);

        cql_double double_data1 = *(cql_double *)(cursor1 + offset1);
        cql_double double_data2 = *(cql_double *)(cursor2 + offset2);
        return double_data1 == double_data2;
      }
    }
  }
  else {
    switch (core_data_type) {
      case CQL_DATA_TYPE_BOOL: {
        cql_nullable_bool bool_data1 = *(cql_nullable_bool *)(cursor1 + offset1);
        cql_nullable_bool bool_data2 = *(cql_nullable_bool *)(cursor2 + offset2);
        if (bool_data1.is_null != bool_data2.is_null) {
          return false;
        }
        if (bool_data1.is_null) {
          return true;
        }
        return bool_data1.value == bool_data2.value;
      }
      case CQL_DATA_TYPE_INT32: {
        cql_nullable_int32 int32_data1 = *(cql_nullable_int32 *)(cursor1 + offset1);
        cql_nullable_int32 int32_data2 = *(cql_nullable_int32 *)(cursor2 + offset2);
        if (int32_data1.is_null != int32_data2.is_null) {
          return false;
        }
        if (int32_data1.is_null) {
          return true;
        }
        return int32_data1.value == int32_data2.value;
        break;
      }
      case CQL_DATA_TYPE_INT64: {
        cql_nullable_int64 int64_data1 = *(cql_nullable_int64 *)(cursor1 + offset1);
        cql_nullable_int64 int64_data2 = *(cql_nullable_int64 *)(cursor2 + offset2);
        if (int64_data1.is_null != int64_data2.is_null) {
          return false;
        }
        if (int64_data1.is_null) {
          return true;
        }
        return int64_data1.value == int64_data2.value;
      }
      default: {
        // this is all that's left
        cql_contract(core_data_type == CQL_DATA_TYPE_DOUBLE);

        cql_nullable_double double_data1 = *(cql_nullable_double *)(cursor1 + offset1);
        cql_nullable_double double_data2 = *(cql_nullable_double *)(cursor2 + offset2);
        if (double_data1.is_null != double_data2.is_null) {
          return false;
        }
        if (double_data1.is_null) {
          return true;
        }
        return double_data1.value == double_data2.value;
      }
    }
  }
}

// CQLABI
cql_int32 cql_cursor_diff_index(
  cql_dynamic_cursor *_Nonnull dyn_cursor1,
  cql_dynamic_cursor *_Nonnull dyn_cursor2)
{
  // count is stored in first offset
  uint16_t count1 = dyn_cursor1->cursor_col_offsets[0];
  uint16_t count2 = dyn_cursor2->cursor_col_offsets[0];

  // -2 indicates one has a row and the other doesn't
  if (*dyn_cursor1->cursor_has_row != *dyn_cursor2->cursor_has_row) {
    return -2;
  }

  // both empty is a match
  if (!*dyn_cursor1->cursor_has_row) {
    return -1;
  }

  // pre-verified by semantic analysis
  cql_contract(count1 == count2);

  for (uint16_t i = 0; i < count1; i++) {
    if (!cql_compare_one_cursor_column(dyn_cursor1, dyn_cursor2, i)) {
      return i;
    }
  }

  return -1;
}

// CQLABI
cql_string_ref _Nullable cql_cursor_diff_col(
  cql_dynamic_cursor *_Nonnull dyn_cursor1,
  cql_dynamic_cursor *_Nonnull dyn_cursor2)
{
  cql_int32 i = cql_cursor_diff_index(dyn_cursor1, dyn_cursor2);
  if (i >= 0) {
    return cql_cursor_column_name(dyn_cursor1, i);
  }

  if (i == -2) {
    return cql_string_ref_new("_has_row_");
  }

  return NULL;
}

// CQLABI
cql_string_ref _Nullable cql_cursor_diff_val(
  cql_dynamic_cursor *_Nonnull dyn_cursor1,
  cql_dynamic_cursor *_Nonnull dyn_cursor2)
{
  cql_int32 i = cql_cursor_diff_index(dyn_cursor1, dyn_cursor2);

  if (i >= 0) {
    cql_bytebuf b;
    cql_bytebuf_open(&b);

    // field names for printing
    const char **fields = dyn_cursor1->cursor_fields;
    cql_bprintf(&b, "column:%s", fields[i]);

    cql_bprintf(&b, " c1:");
    cql_format_one_cursor_column(&b, dyn_cursor1, i);
    cql_bprintf(&b, " c2:");
    cql_format_one_cursor_column(&b, dyn_cursor2, i);

    cql_bytebuf_append_null(&b);

    cql_string_ref result = cql_string_ref_new(b.ptr);
    cql_bytebuf_close(&b);
    return result;
  }

  if (i == -2) {
    cql_bytebuf b;
    cql_bytebuf_open(&b);

    // field names for printing
    cql_bprintf(&b, "column:_has_row_ c1:%s c2:%s",
      *dyn_cursor1->cursor_has_row ? "true" : "false",
      *dyn_cursor2->cursor_has_row ? "true" : "false");

    cql_bytebuf_append_null(&b);

    cql_string_ref result = cql_string_ref_new(b.ptr);
    cql_bytebuf_close(&b);
    return result;
  }

  return NULL;
}

// Create a blob from an integer value, this is used
// for dummy data generation and pretty much not interesting
// for anything else.  The blob is just the ascii representation
// of the integer value. The blob is not null terminated.
// CQLABI
cql_blob_ref _Nonnull cql_blob_from_int(
  cql_string_ref _Nullable prefix,
  cql_int32 value)
{
  cql_bytebuf b;
  cql_bytebuf_open(&b);
  if (prefix) {
    cql_alloc_cstr(temp, prefix);
    cql_bprintf(&b, "%s", temp);
    cql_free_cstr(temp, prefix);
  }
  cql_bprintf(&b, "%d", value);
  cql_blob_ref result = cql_blob_ref_new(b.ptr, (cql_int32)b.used);
  cql_bytebuf_close(&b);
  return result;
}

// type of the indicated field
// this is also available as <some_cursor>:type(i)
// CQLABI
cql_int32 cql_cursor_column_type(
  cql_dynamic_cursor *_Nonnull dyn_cursor,
  cql_int32 i)
{
  uint16_t *offsets = dyn_cursor->cursor_col_offsets;
  cql_int32 type = -1;
  uint16_t count = offsets[0];  // the first index is the count of fields

  if (i >= 0 && i < count) {
    uint8_t *types = dyn_cursor->cursor_data_types;
    type = (cql_int32)types[i];
    type &= CQL_DATA_TYPE_CORE|CQL_DATA_TYPE_NOT_NULL;
  }
  return type;
}

// name of the indicated field
// this is also available as <some_cursor>:name(i)
// CQLABI
cql_string_ref _Nullable cql_cursor_column_name(
  cql_dynamic_cursor *_Nonnull dyn_cursor,
  cql_int32 i)
{
  uint16_t *offsets = dyn_cursor->cursor_col_offsets; // field offsets for values
  const char **fields = dyn_cursor->cursor_fields; // field names for printing

  uint16_t count = offsets[0];  // the first index is the count of fields

  if (i < 0 || i >= count) {
    return NULL;
  }

  return cql_string_ref_new(fields[i]);
}

// extract a boolean from the indicated field number of the cursor if there is one
// this is also available as <some_cursor>:to_bool(i)
// CQLABI
cql_nullable_bool cql_cursor_get_bool(
  cql_dynamic_cursor *_Nonnull dyn_cursor,
  cql_int32 i)
{
  cql_nullable_bool result;
  result.value = 0;
  result.is_null = true;
  uint16_t *offsets = dyn_cursor->cursor_col_offsets;
  uint8_t *types = dyn_cursor->cursor_data_types;
  uint8_t *cursor = dyn_cursor->cursor_data;  // we will be using char offsets
  uint16_t count = offsets[0];  // the first index is the count of fields

  if (i >= 0 && i < count) {
    uint16_t offset = offsets[i+1];

    switch (types[i])  {
      case CQL_DATA_TYPE_BOOL:
        result = *(cql_nullable_bool *)(cursor + offset);
        break;

      case CQL_DATA_TYPE_BOOL | CQL_DATA_TYPE_NOT_NULL:
        result.value = *(cql_bool *)(cursor + offset);
        result.is_null = false;
        break;
    }
  }
  return result;
}

// extract an int32 from the indicated field number of the cursor if there is one
// this is also available as <some_cursor>:to_int(i)
// CQLABI
cql_nullable_int32 cql_cursor_get_int(
  cql_dynamic_cursor *_Nonnull dyn_cursor,
  cql_int32 i)
{
  cql_nullable_int32 result;
  result.value = 0;
  result.is_null = true;
  uint16_t *offsets = dyn_cursor->cursor_col_offsets;
  uint8_t *types = dyn_cursor->cursor_data_types;
  uint8_t *cursor = dyn_cursor->cursor_data;  // we will be using char offsets
  uint16_t count = offsets[0];  // the first index is the count of fields

  if (i >= 0 && i < count) {
    uint16_t offset = offsets[i+1];

    switch (types[i])  {
      case CQL_DATA_TYPE_INT32:
        result = *(cql_nullable_int32 *)(cursor + offset);
        break;

      case CQL_DATA_TYPE_INT32 | CQL_DATA_TYPE_NOT_NULL:
        result.value = *(cql_int32 *)(cursor + offset);
        result.is_null = false;
        break;
    }
  }
  return result;
}

// extract an int64 from the indicated field number of the cursor if there is one
// this is also available as <some_cursor>:to_long(i)
// CQLABI
cql_nullable_int64 cql_cursor_get_long(
  cql_dynamic_cursor *_Nonnull dyn_cursor,
  cql_int32 i)
{
  cql_nullable_int64 result;
  result.value = 0;
  result.is_null = true;
  uint16_t *offsets = dyn_cursor->cursor_col_offsets;
  uint8_t *types = dyn_cursor->cursor_data_types;
  uint8_t *cursor = dyn_cursor->cursor_data;  // we will be using char offsets
  uint16_t count = offsets[0];  // the first index is the count of fields

  if (i >= 0 && i < count) {
    uint16_t offset = offsets[i+1];

    switch (types[i])  {
      case CQL_DATA_TYPE_INT64:
        result = *(cql_nullable_int64 *)(cursor + offset);
        break;

      case CQL_DATA_TYPE_INT64 | CQL_DATA_TYPE_NOT_NULL:
        result.value = *(cql_int64 *)(cursor + offset);
        result.is_null = false;
        break;
    }
  }
  return result;
}

// extract a double from the indicated field number of the cursor if there is one
// this is also available as <some_cursor>:to_real(i)
// CQLABI
cql_nullable_double cql_cursor_get_real(
  cql_dynamic_cursor *_Nonnull dyn_cursor,
  cql_int32 i)
{
  cql_nullable_double result;
  result.value = 0;
  result.is_null = true;
  uint16_t *offsets = dyn_cursor->cursor_col_offsets;
  uint8_t *types = dyn_cursor->cursor_data_types;
  uint8_t *cursor = dyn_cursor->cursor_data;  // we will be using char offsets
  uint16_t count = offsets[0];  // the first index is the count of fields

  if (i >= 0 && i < count) {
    uint16_t offset = offsets[i+1];

    switch (types[i])  {
      case CQL_DATA_TYPE_DOUBLE:
        result = *(cql_nullable_double *)(cursor + offset);
        break;

      case CQL_DATA_TYPE_DOUBLE | CQL_DATA_TYPE_NOT_NULL:
        result.value = *(cql_double *)(cursor + offset);
        result.is_null = false;
        break;
    }
  }
  return result;
}

// extract a string from the indicated field number of the cursor if there is one
// this is also available as <some_cursor>:to_text(i)
// CQLABI
cql_string_ref _Nullable cql_cursor_get_text(
  cql_dynamic_cursor *_Nonnull dyn_cursor,
  cql_int32 i)
{
  cql_string_ref result = NULL;
  uint16_t *offsets = dyn_cursor->cursor_col_offsets;
  uint8_t *types = dyn_cursor->cursor_data_types;
  uint8_t *cursor = dyn_cursor->cursor_data;  // we will be using char offsets
  uint16_t count = offsets[0];  // the first index is the count of fields

  if (i >= 0 && i < count) {
    uint16_t offset = offsets[i+1];

    switch (types[i])  {
      case CQL_DATA_TYPE_STRING:
      case CQL_DATA_TYPE_STRING | CQL_DATA_TYPE_NOT_NULL:
        result = *(cql_string_ref *)(cursor + offset);
        break;
    }
  }
  return result;
}

// extract a blob from the indicated field number of the cursor if there is one
// this is also available as <some_cursor>:to_blob(i)
// CQLABI
cql_blob_ref _Nullable cql_cursor_get_blob(
  cql_dynamic_cursor *_Nonnull dyn_cursor,
  cql_int32 i)
{
  cql_blob_ref result = NULL;
  uint16_t *offsets = dyn_cursor->cursor_col_offsets;
  uint8_t *types = dyn_cursor->cursor_data_types;
  uint8_t *cursor = dyn_cursor->cursor_data;  // we will be using char offsets
  uint16_t count = offsets[0];  // the first index is the count of fields

  if (i >= 0 && i < count) {
    uint16_t offset = offsets[i+1];

    switch (types[i])  {
      case CQL_DATA_TYPE_BLOB:
      case CQL_DATA_TYPE_BLOB | CQL_DATA_TYPE_NOT_NULL:
        result = *(cql_blob_ref *)(cursor + offset);
        break;
    }
  }
  return result;
}

// extract an object from the indicated field number of the cursor if there is one
// this is also available as <some_cursor>:to_object(i)
// CQLABI
cql_object_ref _Nullable cql_cursor_get_object(
  cql_dynamic_cursor *_Nonnull dyn_cursor,
  cql_int32 i)
{
  cql_object_ref result = NULL;
  uint16_t *offsets = dyn_cursor->cursor_col_offsets;
  uint8_t *types = dyn_cursor->cursor_data_types;
  uint8_t *cursor = dyn_cursor->cursor_data;  // we will be using char offsets
  uint16_t count = offsets[0];  // the first index is the count of fields

  if (i >= 0 && i < count) {
    uint16_t offset = offsets[i+1];

    switch (types[i])  {
      case CQL_DATA_TYPE_OBJECT:
      case CQL_DATA_TYPE_OBJECT | CQL_DATA_TYPE_NOT_NULL:
        result = *(cql_object_ref *)(cursor + offset);
        break;
    }
  }
  return result;
}

// CQLABI
cql_string_ref _Nonnull cql_cursor_format_column(
  cql_dynamic_cursor *_Nonnull dyn_cursor,
  cql_int32 i)
{
  uint16_t *offsets = dyn_cursor->cursor_col_offsets;
  uint16_t count = offsets[0];  // the first index is the count of fields

  cql_contract(i >= 0);
  cql_contract(i < count);

  cql_bytebuf b;
  cql_bytebuf_open(&b);

  cql_format_one_cursor_column(&b, dyn_cursor, i);
  cql_bytebuf_append_null(&b);
  cql_string_ref result = cql_string_ref_new(b.ptr);
  cql_bytebuf_close(&b);

  return result;
}

// total number of fields in the cursor
// CQLABI
cql_int32 cql_cursor_column_count(cql_dynamic_cursor *_Nonnull dyn_cursor) {
  uint16_t *offsets = dyn_cursor->cursor_col_offsets;
  return (cql_int32)offsets[0];  // the first index is the count of fields
}

// To keep the contract as simple as possible we encode everything we need into
// the fragment array.  Including the size of the output and fragment
// terminator.  See above.  This also makes the code gen as simple as possible.
cql_string_ref _Nonnull cql_uncompress(
  const char *_Nonnull base,
  const char *_Nonnull frags)
{
  // we never try to encode the empty string
  cql_contract(frags[0]);

  // NOTE: len is the allocation size (includes trailing \0)
  cql_int32 len;
  frags = cql_decode(frags, &len);
  STACK_BYTES_ALLOC(str, len);
  cql_expand_frags(str, base, frags);
  return cql_string_ref_new(str);
}

// This function splits a string by the pattern in parseWord. We use this
// function to listify a series of creates (parseWord = "CREATE ") or deletes
// (parseWord = "DROP") after receiving a concatenated string from the CQL
// upgrader. We need some parsing logic with quotes to make sure the parseWord
// is not found inside string literals.
static cql_object_ref _Nonnull _cql_create_upgrader_input_statement_list(
  cql_string_ref _Nonnull str,
  char* _Nonnull parse_word)
{
  cql_object_ref list = cql_string_list_create();
  cql_alloc_cstr(c_str, str);

  if (strlen(c_str) == 0) goto cleanup;

  const char *lineStart = c_str;
  // skip leading whitespace
  while (lineStart[0] == ' ') {
    lineStart++;
  }

  // Text has been normalized for SQL so only '' strings no "" strings hence the
  // only escape sequence is ''  e.g.  'That''s all folks'. CQL never generates
  // tabs, formfeeds, or other whitespace except inside quotes, where we already
  // must carefully skip without matching.

  cql_string_ref currLine;
  cql_uint32 bytes;

  bool in_quote = false;
  const char *p;
  for (p = lineStart; *p; p++) {
    if (in_quote) {
      if (p[0] == '\'') {
        if (p[1] == '\'') {
          p++;
        }
        else {
          in_quote = false;
        }
      }
    }
    else if (p[0] == '\'') {
      in_quote = true;
    }
    else if (!in_quote && !strncmp(p, parse_word, strlen(parse_word))) {
      // Add the current statement (i.e. create statement, drop statement) to
      // our list when we find the delimiting parseWord for the next statement
      if (lineStart != p) {
        bytes = (cql_uint32)(p - lineStart);
        char* temp = malloc(bytes + 1);
        memcpy(temp, lineStart, bytes);
        temp[bytes] = '\0';
        currLine = cql_string_ref_new(temp);
        free(temp);
        cql_string_list_add(list, currLine);
        cql_string_release(currLine);
        lineStart = p;
      }
    }
  }

  // The last statement is pending because we have been adding statements to the
  // list after seeing the entire statement i.e. beginning of the next
  // statement. We must flush it here.
  bytes = (cql_uint32)(p - lineStart);
  char *temp = malloc(bytes + 1);
  memcpy(temp, lineStart, bytes);
  temp[bytes] = '\0';
  currLine = cql_string_ref_new(temp);
  free(temp);
  cql_string_list_add(list, currLine);
  cql_string_release(currLine);

cleanup:
  cql_free_cstr(c_str, str);
  return list;
}

// This function assumes the input follows CQL normalized syntax and contains
// characters until at least the first "(" if it exists.  Which is to say we
// expect to be reading back our own schema, not arbitrary SQL.  We can't
// upgrade arbitrary SQL because we don't know what weird things it might have.
static char* _Nonnull _cql_create_table_name_from_table_creation_statement(
  cql_string_ref _Nonnull create)
{
  // table name always preceeds "USING "
  cql_alloc_cstr(c_create, create);

  // These cannot go into recreate groups so this case can't happen
  cql_bool virtual_table = !strncmp("CREATE VIRTUAL TABLE ", c_create, sizeof("CREATE VIRTUAL TABLE ") - 1);
  cql_contract(!virtual_table);
  char *p = strchr(c_create, '(');
  cql_contract(p);
  cql_contract(p > c_create);

  // We found the '(' so we know there is a table name before it Now we back up
  // past spaces (if they exist). We don't want extra spaces in our table names.
  while (p[-1] == ' ') p--;
  const char *lineStart = p;

  // if the table name is of the form [foo bar] then we need to back up to the
  // the introducing '[' to get the whole table name
  if (lineStart[-1] == ']') {
    while (lineStart[-1] != '[') {
      lineStart--;
    }
    lineStart--;
  }
  else {
    // otherwise we just find the space preceding the table name to get the
    // whole name
    while (lineStart[-1] != ' ') {
      lineStart--;
    }
  }

  cql_uint32 bytes = (cql_uint32)(p - lineStart);
  char *table_name = malloc(bytes + 1);
  memcpy(table_name, lineStart, bytes);
  table_name[bytes] = '\0';

  cql_free_cstr(c_create, create);
  return table_name;
}

// This function is passed in an index creation statement generated from the CQL
// upgrader. We need this helper to be able to map indices to tables.
static char *_Nonnull _cql_create_table_name_from_index_creation_statement(
  cql_string_ref _Nonnull index_create)
{
  // table name follows "ON " in the create_index_stmt pattern
  // table name is followed by an open paren
  cql_alloc_cstr(c_index_create, index_create);
  const char *lineStart = strstr(c_index_create, "ON ") + strlen("ON ");
  const char *q = strchr(lineStart, '('); // add space logic
  // backspace spaces between index name and (
  while (q[-1] == ' ') {
    q--;
  }
  cql_uint32 index_bytes = (cql_uint32)(q - lineStart);
  char *index_table_name = malloc(index_bytes + 1);
  memcpy(index_table_name, lineStart, index_bytes);
  index_table_name[index_bytes] = '\0';
  cql_free_cstr(c_index_create, index_create);
  return index_table_name;
}

// This function provides the naive implementation of cql_rebuild_recreate_group
// called in the cg_schema CQL upgrader. We take input three recreate-group
// specific strings.
//  * tables: series of semi-colon separated CREATE (VIRTUAL) TABLE statements
//  * indices: series of semi-colon separated CREATE INDEX statements
//  * deletes: series of semi-colon separated DROP TABLE statements (ex:
//    unsubscribed or deleted tables)
//
// We currently always do recreate here (no rebuild). We just drop our tables,
// and recreate the tables and any indices that might have been dropped.
cql_code cql_rebuild_recreate_group(
  sqlite3 *_Nonnull db,
  cql_string_ref _Nonnull tables,
  cql_string_ref _Nonnull indices,
  cql_string_ref _Nonnull deletes,
  cql_bool *_Nonnull result)
{
  *result = false; // result holds false because we default to recreate (no rebuild)

  // process parseWord separated strings into lists
  cql_object_ref tableList = _cql_create_upgrader_input_statement_list(tables, "CREATE ");
  cql_object_ref indexList = _cql_create_upgrader_input_statement_list(indices, "CREATE ");
  cql_object_ref deleteList = _cql_create_upgrader_input_statement_list(deletes, "DROP ");

  cql_code rc = SQLITE_OK;
  // Execute all delete table drops Note deleteList provides table drops in
  // create order, so we must execute them in reverse.
  for (cql_int32 i = cql_string_list_count(deleteList) ; --i >= 0; ) {
    cql_string_ref delete = cql_string_list_get_at(deleteList, i);
    rc = cql_exec_internal(db, delete);
    if (rc != SQLITE_OK) goto cleanup;
  }

  // Execute all table drops based on the list of creates given by the CQL
  // upgrader backwards. Intuitively, need to drop the tables with the most
  // dependencies first.
  for (cql_int32 i = cql_string_list_count(tableList) ; --i >= 0; ) {
    cql_string_ref tableCreate = cql_string_list_get_at(tableList, i);
    char *table_name = _cql_create_table_name_from_table_creation_statement(tableCreate);

    cql_bytebuf drop;
    cql_bytebuf_open(&drop);
    cql_bprintf(&drop, "DROP TABLE IF EXISTS %s", table_name);
    cql_bytebuf_append_null(&drop);
    rc = cql_exec(db, drop.ptr);
    cql_bytebuf_close(&drop);
    free(table_name);

    if (rc != SQLITE_OK) goto cleanup;
  }

  // Execute all table creates in the order provided
  for (cql_int32 i = 0; i < cql_string_list_count(tableList); i++) {
    cql_string_ref tableCreate = cql_string_list_get_at(tableList, i);
    rc = cql_exec_internal(db, tableCreate);
    if (rc != SQLITE_OK) goto cleanup;
    char* table_name = _cql_create_table_name_from_table_creation_statement(tableCreate);

    // Indices are already deleted with the table drops We need to recreate
    // indices alongside the tables incase future table creates refer to the
    // index
    for (cql_int32 j = 0; j < cql_string_list_count(indexList); j++) {
      cql_string_ref indexCreate = cql_string_list_get_at(indexList, j);
      char* index_table_name = _cql_create_table_name_from_index_creation_statement(indexCreate);
      if (!strcmp(table_name, index_table_name)) {
        free(index_table_name);
        rc = cql_exec_internal(db, indexCreate);
        if (rc != SQLITE_OK) goto cleanup;
      }
      else {
        free(index_table_name);
      }
    }
    free(table_name);
  }

cleanup:
  cql_object_release(tableList);
  cql_object_release(indexList);
  cql_object_release(deleteList);
  return rc;
}

// this is not normally called but we need something here for linkage
static void _stub_udf_callback(
  sqlite3_context *_Nullable context,
  int argc,
  sqlite3_value *_Nullable *_Nullable argv)
{
}

// set up a do nothing UDF, this is used to stub out UDFs in the query plan
// generated code the function is not normally called
cql_code cql_create_udf_stub(
  sqlite3 *_Nonnull db,
  cql_string_ref _Nonnull name)
{
  cql_alloc_cstr(temp, name);

  cql_code rc = sqlite3_create_function_v2(
   db,
   temp,
   -1, // stub function takes any number of args
   SQLITE_UTF8 | SQLITE_DETERMINISTIC,
   NULL,
   &_stub_udf_callback,
   NULL,
   NULL,
   NULL
   );

  // force one call, only for coverage
  _stub_udf_callback(NULL, 0, NULL);

  cql_free_cstr(temp, str_ref);
  return rc;
}

// two byte portable big endian encoding
static void cql_write_big_endian_u16(uint8_t *_Nonnull b, uint16_t val) {
  b[0] = (uint8_t)(val >> 8);
  b[1] = (uint8_t)(val & 0xff);
}

// four byte portable big endian encoding
static void cql_write_big_endian_u32(uint8_t *_Nonnull b, uint32_t val) {
  cql_write_big_endian_u16(b,   (uint16_t)(val >> 16));
  cql_write_big_endian_u16(b+2, (uint16_t)val & 0xffff);
}

// eight byte portable big endian encoding
static void cql_write_big_endian_u64(uint8_t *_Nonnull b, uint64_t val) {
  cql_write_big_endian_u32(b,   (uint32_t)(val >> 32));
  cql_write_big_endian_u32(b+4, (uint32_t)val & 0xffffffff);
}

// four byte portable big endian decoding
static uint32_t cql_read_big_endian_u32(const uint8_t *_Nonnull b) {
  uint32_t val = b[0];
  val = (val << 8) | b[1];
  val = (val << 8) | b[2];
  val = (val << 8) | b[3];
  return (cql_uint32)val;
}

// eight byte portable big endian decoding
static uint64_t cql_read_big_endian_u64(const uint8_t *_Nonnull b) {
  uint64_t val = cql_read_big_endian_u32(b);
  val = (val<<32) | (uint64_t)cql_read_big_endian_u32(b+4);
  return val;
}

// encodes the type of blob it is in case of version change
#define CQL_BLOB_MAGIC 0x524d3030

typedef struct cql_blob_header {
  uint32_t magic;
  uint32_t column_count;
  uint64_t record_type;
} cql_blob_header;

static void cql_read_blob_header(
  const uint8_t *_Nonnull blob,
  cql_blob_header *_Nonnull header,
  uint32_t original_bytes)
{
  if (original_bytes < sizeof(cql_blob_header)) {
    memset(header, 0, sizeof(cql_blob_header));
    return;
  }
  header->record_type = cql_read_big_endian_u64(blob);
  header->magic = cql_read_big_endian_u32(blob + 8);
  header->column_count = cql_read_big_endian_u32(blob + 12);
}

static void cql_write_blob_header(
  uint8_t *_Nonnull blob,
  const cql_blob_header *_Nonnull header)
{
  cql_write_big_endian_u64(blob, header->record_type);
  cql_write_big_endian_u32(blob + 8, header->magic);
  cql_write_big_endian_u32(blob + 12, header->column_count);
}

// Key blobs have:
//  - the standard header
//    - record type
//    - magic word
//    - count of columns
//  - the storage area, one int64 per column
//  - the type area, one byte per column
//  - variable space to hold strings and blobs
// This record has the size and offset of all those things
typedef struct cql_key_blob_shape {
  uint64_t header_size;
  uint64_t storage_size;
  uint64_t type_codes_size;
  uint64_t variable_size;
  uint64_t total_bytes;
  uint64_t storage_offset;
  uint64_t type_codes_offset;
  uint64_t variable_offset;
} cql_key_blob_shape;

// Computes the sizes and offsets of all the items in a key blob given the
// column count and variable size required.  Note that sometimes we don't know
// the variable size yet so zero is used.  In that case you simply adjust the
// total size and variable size when it's known.
static void cql_compute_key_blob_shape(
  cql_key_blob_shape *_Nonnull shape,
  uint64_t column_count,
  uint64_t variable_size)
{
  shape->header_size = sizeof(cql_blob_header);
  shape->storage_size = column_count * sizeof(int64_t);
  shape->type_codes_size = column_count * sizeof(int8_t);
  shape->variable_size = variable_size;
  shape->total_bytes = shape->header_size + shape->type_codes_size + shape->storage_size + variable_size;

  // we don't support records this big, they are insane already
  cql_contract(shape->total_bytes == (cql_uint32)shape->total_bytes);

  shape->storage_offset = shape->header_size;
  shape->type_codes_offset = shape->storage_offset + shape->storage_size;
  shape->variable_offset = shape->type_codes_offset + shape->type_codes_size;
}

// Returns a blob with the given items in value format
// bcreatekey(
//    record_code,
//    [field value, field type]+
// )
void bcreatekey(
  sqlite3_context *_Nonnull context,
  cql_int32 argc,
  sqlite3_value *_Nonnull *_Nonnull argv)
{
  // if there is an even number of args or there is not at least one column specified
  // then we are outta here with a big fat null blob.
  if (argc < 3 || argc % 2 == 0) {
    goto cql_error;
  }

  // argv[0] must be the record type and it must be an integer
  if (sqlite3_value_type(argv[0]) != SQLITE_INTEGER) {
    goto cql_error;
  }

  // extract the record type
  uint64_t rtype = (uint64_t)sqlite3_value_int64(argv[0]);

  // type and value for each argument
  // plus the
  cql_uint32 column_count = (uint32_t)((argc - 1) / 2);
  cql_invariant(column_count >= 1);

  // In the first pass we verify the provided values are compatible with
  // the provided types and compute the needed variable size.
  uint64_t variable_size = 0;
  for (uint32_t icol = 0; icol < column_count; icol++) {
    cql_uint32 index = icol * 2 + 1;
    sqlite3_value *field_value_arg = argv[index];
    sqlite3_value *field_type_arg = argv[index + 1];

    if (sqlite3_value_type(argv[index + 1]) != SQLITE_INTEGER) {
      goto cql_error;
    }

    int8_t blob_column_type = (int8_t)sqlite3_value_int64(field_type_arg);

    uint64_t field_variable_size = 0;
    cql_bool compat = cql_blobtype_vs_argtype_compat(field_value_arg, blob_column_type, &field_variable_size);
    if (!compat) {
      goto cql_error;
    }

    variable_size += field_variable_size;
  }

  // At this point we know everything we need to know about our storage so we
  // can use the helper to make the shape for us.
  cql_key_blob_shape shape;
  cql_compute_key_blob_shape(&shape, column_count, variable_size);

  uint8_t *b = sqlite3_malloc((cql_int32)shape.total_bytes);
  cql_contract(b != NULL);

  // The helper writes the header in place for us
  cql_blob_header header;
  header.record_type = rtype;
  header.column_count = column_count;
  header.magic = CQL_BLOB_MAGIC;
  cql_write_blob_header(b, &header);

  // These will track the next available position to write storage
  // types, or blob/string data.
  uint64_t storage_offset = shape.storage_offset;
  uint64_t type_codes_offset = shape.type_codes_offset;
  uint64_t variable_offset = shape.variable_offset;

  // In the second pass we write the arguments into the blob
  // using the offsets computed above.
  for (uint32_t icol = 0; icol < column_count; icol++) {
    uint32_t index = icol * 2 + 1;
    sqlite3_value *field_value_arg = argv[index];
    sqlite3_value *field_type_arg = argv[index + 1];

    int64_t blob_column_type = sqlite3_value_int64(field_type_arg);
    b[type_codes_offset++] = (uint8_t)blob_column_type;

    switch (blob_column_type) {
      // Boolean values are stored in the int64 storage, but are normalized
      // to zero or one first.
      case CQL_BLOB_TYPE_BOOL:
      {
        int64_t val = sqlite3_value_int64(field_value_arg);
        cql_write_big_endian_u64(b + storage_offset, (uint64_t)!!val);
        break;
      }

      // These are written in big endian format for portability.
      // Any fixed endian order would have worked.
      case CQL_BLOB_TYPE_INT64:
      case CQL_BLOB_TYPE_INT32:
      {
        int64_t val = sqlite3_value_int64(field_value_arg);
        cql_write_big_endian_u64(b + storage_offset, (uint64_t)val);
        break;
      }

      // Always IEEE 754 "double" (8 bytes) format in the blob.
      case CQL_BLOB_TYPE_FLOAT:
      {
        double val = sqlite3_value_double(field_value_arg);
        *(double *)(b + storage_offset) = val;
        break;
      }

      // String field is stored in the variable space.
      // The int64 storage encodes the length and offset.
      // Length does not include the trailing null.
      case CQL_BLOB_TYPE_STRING:
      {
        const unsigned char *val = sqlite3_value_text(field_value_arg);
        uint32_t len = (uint32_t)sqlite3_value_bytes(field_value_arg);
        uint64_t info = (uint64_t)(variable_offset << 32) | (uint64_t)len;
        cql_write_big_endian_u64(b + storage_offset, info);

        // known length does not include trailing null
        memcpy(b + variable_offset, val, len + 1);
        variable_offset += len + 1;
        break;
      }

      // Blob field is stored in the variable space.
      // The int64 storage encodes the length and offset.
      case CQL_BLOB_TYPE_BLOB:
      {
        const void *val = sqlite3_value_blob(field_value_arg);
        uint32_t len = (uint32_t)sqlite3_value_bytes(field_value_arg);
        uint64_t info = (uint64_t)(variable_offset << 32) | (uint64_t)len;
        cql_write_big_endian_u64(b + storage_offset, info);

        memcpy(b + variable_offset, val, len);
        variable_offset += len;
        break;
      }
    }

    storage_offset += sizeof(int64_t);
  }

  sqlite3_result_blob(context, b, (int)shape.total_bytes, sqlite3_free);
  return;

cql_error:
  // If anything goes wrong we just return a null blob
  // We could probably do better than this.
  sqlite3_result_null(context);
}

// Returns the indicated column from the blob using the type info in the blob
// bgetkey(
//    blob, column number
// )
void bgetkey(
  sqlite3_context *_Nonnull context,
  cql_int32 argc,
  sqlite3_value *_Nonnull *_Nonnull argv)
{
  // these are enforced at compile time
  cql_contract(argc == 2);
  cql_contract(sqlite3_value_type(argv[0]) == SQLITE_BLOB);
  cql_contract(sqlite3_value_type(argv[1]) == SQLITE_INTEGER);

  uint64_t icol = (uint64_t)sqlite3_value_int64(argv[1]);
  const uint8_t *b = (const uint8_t *)sqlite3_value_blob(argv[0]);
  uint32_t original_bytes = (uint32_t)sqlite3_value_bytes(argv[0]);

  // read the header to get the basic info
  cql_blob_header header;
  cql_read_blob_header(b, &header, original_bytes);

  // bad blob or invalid column gives nil result
  if (icol < 0 || icol >= header.column_count || header.magic != CQL_BLOB_MAGIC) {
    goto cql_error;
  }

  // we know enough to make the shape and get the offsets the variable size is
  // not computed but that is of no import since we are not yet validating all
  // the internal offsets (blobs are assumed to be well formed for now)
  cql_key_blob_shape shape;
  cql_compute_key_blob_shape(&shape, header.column_count, 0);
  uint64_t type_code_offset = shape.type_codes_offset + icol;
  uint64_t storage_offset = shape.storage_offset + icol * sizeof(int64_t);

  uint8_t blob_column_type = b[type_code_offset];

  switch (blob_column_type) {
    // Boolean values are stored in the int64 storage, but are normalized to
    // zero or one first.
    case CQL_BLOB_TYPE_BOOL:
    {
      uint64_t val = cql_read_big_endian_u64(b + storage_offset);
      sqlite3_result_int64(context, !!val);
      return;
    }

    // These are written in big endian format for portability. Any fixed endian
    // order would have worked.
    case CQL_BLOB_TYPE_INT32:
    case CQL_BLOB_TYPE_INT64:
    {
      uint64_t val = cql_read_big_endian_u64(b + storage_offset);
      sqlite3_result_int64(context, (int64_t)val);
      return;
    }

    // Always IEEE 754 "double" (8 bytes) format in the blob.
    case CQL_BLOB_TYPE_FLOAT:
    {
      double val = *(const double *)(b + storage_offset);
      sqlite3_result_double(context, val);
      return;
    }

    // String field is stored in the variable space. The int64 storage encodes
    // the length and offset. Length does not include the trailing null.
    case CQL_BLOB_TYPE_STRING:
    {
      uint64_t val = cql_read_big_endian_u64(b + storage_offset);
      uint32_t len = val & 0xffffffff;
      uint32_t offset = val >> 32;
      const char *text = (const char *)b + offset;
      sqlite3_result_text(context, text, (int)len, SQLITE_TRANSIENT);
      return;
    }

    // Blob field is stored in the variable space. The int64 storage encodes the
    // length and offset.
    case CQL_BLOB_TYPE_BLOB:
    {
      uint64_t val = cql_read_big_endian_u64(b + storage_offset);
      uint32_t len = val & 0xffffffff;
      uint32_t offset = val >> 32;
      const uint8_t *data = b + offset;
      sqlite3_result_blob(context, data, (int)len, SQLITE_TRANSIENT);
      return;
    }
  }

cql_error:
  sqlite3_result_null(context);
}

// Returns the record type from a key blob
// Returns the indicated column from the blob using the type info in the blob
// bgetkey_type(
//    blob
// )
void bgetkey_type(
  sqlite3_context *_Nonnull context,
  cql_int32 argc,
  sqlite3_value *_Nonnull *_Nonnull argv)
{
  // these are enforced at compile time
  cql_contract(argc == 1);
  cql_contract(sqlite3_value_type(argv[0]) == SQLITE_BLOB);

  const uint8_t *b = (const uint8_t *)sqlite3_value_blob(argv[0]);
  uint32_t original_bytes = (uint32_t)sqlite3_value_bytes(argv[0]);

  // extract the header
  cql_blob_header header;
  cql_read_blob_header(b, &header, original_bytes);

  // if the magic value is correct then use the record type
  if (header.magic != CQL_BLOB_MAGIC) {
    sqlite3_result_null(context);
  }
  else {
    sqlite3_result_int64(context, (int64_t)header.record_type);
  }
}

// Returns a new blob with the indicated items updated in value format
// bupdatekey(
//    blob,
//    [field value, field index zero based]*
// )
void bupdatekey(
  sqlite3_context *_Nonnull context,
  cql_int32 argc,
  sqlite3_value *_Nonnull *_Nonnull argv)
{
  // copy of the header of the storage
  uint8_t *_Nullable b = NULL;

  // if there is an even number of args or there is not at least one column
  // specified then we are outta here with a big fat null blob.
  if (argc < 3 || argc % 2 == 0) {
    goto cql_error;
  }

  // if the first argument is not a blob, go to the error path
  if (sqlite3_value_type(argv[0]) != SQLITE_BLOB) {
    goto cql_error;
  }

  // we have to make a copy of the buffer because sqlite3_value_bytes is not
  // durable
  uint32_t original_bytes = (uint32_t)sqlite3_value_bytes(argv[0]);
  b = (uint8_t *)malloc(original_bytes);
  memcpy(b, sqlite3_value_blob(argv[0]), original_bytes);

  // read out the header
  cql_blob_header header;
  cql_read_blob_header(b, &header, original_bytes);

  // bogus blob leads us to the error path
  if (header.magic != CQL_BLOB_MAGIC) {
    goto cql_error;
  }

  // compute the incoming blob shape using the column count variable size not
  // known yet, not needed really.
  cql_key_blob_shape shape;
  cql_compute_key_blob_shape(&shape, header.column_count, 0);

  // We need to track how much variable space we need to add or remove we'll do
  // it here.
  int64_t variable_size_adjustment = 0;

  // In the first pass we validate the indexes we are updating, we ensure that
  // there are not cases of the same column being updated twice, and we make
  // sure that the values provided are compatible with the column data type.
  // Note that you can't change the column data type and in key blobs all
  // columns are always present.
  cql_int32 updates = (argc - 1) / 2;
  for (cql_int32 iupdate = 0; iupdate < updates; iupdate++) {
    cql_int32 index = iupdate * 2 + 1;
    sqlite3_value *field_index_arg = argv[index];
    sqlite3_value *field_value_arg = argv[index + 1];

    if (sqlite3_value_type(field_index_arg) != SQLITE_INTEGER) {
      goto cql_error;
    }

    uint64_t icol = (uint64_t)sqlite3_value_int64(field_index_arg);

    if (icol < 0 || icol >= header.column_count) {
      goto cql_error;
    }

    // Now that we have a valid column, we can compute the offset to
    // the places where its info is stored.
    uint64_t storage_offset = shape.storage_offset + icol * sizeof(int64_t);
    uint64_t type_code_offset = shape.type_codes_offset + icol * sizeof(int8_t);
    uint8_t blob_column_type = b[type_code_offset];

    // we fail if we ever try to update the same field twice
    if (blob_column_type & CQL_BLOB_TYPE_DIRTY) {
      goto cql_error;
    }

    // This column is now "dirty", attempting to update it again
    // will take us down the error path above.
    b[type_code_offset] = blob_column_type | CQL_BLOB_TYPE_DIRTY;

    // Ensure the data provided is compatible with the stored type
    uint64_t field_variable_size = 0;
    cql_bool compat = cql_blobtype_vs_argtype_compat(field_value_arg, (int8_t)blob_column_type, &field_variable_size);
    if (!compat) {
      goto cql_error;
    }

    // add the variable size of the replacement data if any
    variable_size_adjustment += field_variable_size;

    // subtract the existing variable length from the adjustment (if there is any)

    switch (blob_column_type) {
      // String field is stored in the variable space.
      // The int64 storage encodes the length and offset.
      // Length does not include the trailing null.
      case CQL_BLOB_TYPE_STRING:
      {
        uint64_t val = cql_read_big_endian_u64(b + storage_offset);
        uint32_t len = val & 0xffffffff;
        variable_size_adjustment -= (int64_t)len + 1;
        break;
      }

      // Blob field is stored in the variable space.
      // The int64 storage encodes the length and offset.
      case CQL_BLOB_TYPE_BLOB:
      {
        uint64_t val = cql_read_big_endian_u64(b + storage_offset);
        uint32_t len = val & 0xffffffff;
        variable_size_adjustment -= (int64_t)len;
      }
    }
  }

  // adjust for change in length of variable length payload
  uint64_t total_bytes = (uint64_t)(original_bytes + variable_size_adjustment);

  // we don't support records this big, they are insane already
  cql_contract(total_bytes == (cql_int32)total_bytes);

  uint8_t *result = sqlite3_malloc((int)total_bytes);
  cql_contract(result != NULL);

  // copy the original buffer before changes (but with dirty bits)
  // this also copies the header
  memcpy(result, b, shape.variable_offset);

  // start variable storage in the variable section
  uint64_t variable_offset = shape.variable_offset;

  // In the second pass, we copy over any provided values
  // At this point everything is known to be compatible.
  for (cql_uint32 iupdate = 0; iupdate < updates; iupdate++) {
    cql_uint32 index = iupdate * 2 + 1;
    sqlite3_value *field_index_arg = argv[index];
    sqlite3_value *field_value_arg = argv[index + 1];

    uint64_t icol = (uint64_t)sqlite3_value_int64(field_index_arg);

    uint64_t storage_offset = shape.storage_offset + icol * sizeof(int64_t);
    uint64_t type_code_offset = shape.type_codes_offset + icol * sizeof(int8_t);

    uint8_t blob_column_type = b[type_code_offset] & ~CQL_BLOB_TYPE_DIRTY;
    result[type_code_offset] = blob_column_type;

    switch (blob_column_type) {
      // Boolean values are stored in the int64 storage, but are normalized
      // to zero or one first.
      case CQL_BLOB_TYPE_BOOL:
      {
        int64_t val = sqlite3_value_int64(field_value_arg);
        cql_write_big_endian_u64(result + storage_offset, (uint64_t)!!val);
        break;
      }

      // These are written in big endian format for portability.
      // Any fixed endian order would have worked.
      case CQL_BLOB_TYPE_INT64:
      case CQL_BLOB_TYPE_INT32:
      {
        int64_t val = sqlite3_value_int64(field_value_arg);
        cql_write_big_endian_u64(result + storage_offset, (uint64_t)val);
        break;
      }

      // Always IEEE 754 "double" (8 bytes) format in the blob.
      case CQL_BLOB_TYPE_FLOAT:
      {
        double val = sqlite3_value_double(field_value_arg);
        *(double *)(result + storage_offset) = val;
        break;
      }

      // It's important that the variable storage always be written in column
      // order so that there is one canonical key blob for any combination of
      // key values. This is so that the PK constraint on the key blob can do
      // its job.  If we reorder the fields so that the result looks different
      // than it would have if we hade used bcreatekey then there is the
      // possibiliity of duplicate keys in the storage and updates might not
      // update the row we intended.
      case CQL_BLOB_TYPE_STRING:
      case CQL_BLOB_TYPE_BLOB:
      {
        // Record the source of the blob or string and that's it we will copy
        // later in the correct order.  We only need the arg index so we can get
        // it from argv later.
        *(uint64_t *)(result + storage_offset) = (uint64_t)index + 1;
        break;
      }
    }
  }

  // In the third pass, we have to copy over the variable length items.  We do
  // this in column order, so that the resulting variable blob section is in the
  // same order as it would be after a blob create even if the arguments in the
  // update case are in a different order, or partly specified.
  for (uint32_t icol = 0; icol < header.column_count; icol++) {
    uint64_t storage_offset = shape.storage_offset + icol * sizeof(int64_t);
    uint64_t type_code_offset = shape.type_codes_offset + icol * sizeof(int8_t);

    uint8_t blob_column_type = b[type_code_offset];

    // We have to copy the dirty and clean columns in their original order.
    switch (blob_column_type) {
      // String field is stored in the variable space. The int64 storage encodes
      // the length and offset. Length does not include the trailing null. In
      // this case we copy the variable data from the original stored data i.e.
      // this data is unchanged.
      case CQL_BLOB_TYPE_STRING:
      {
        uint64_t val = cql_read_big_endian_u64(b + storage_offset);
        uint32_t len = val & 0xffffffff;
        uint32_t offset = val >> 32;
        const char *text = (const char *)b + offset;

        uint64_t info = (uint64_t)(variable_offset << 32) | (uint64_t)len;
        cql_write_big_endian_u64(result + storage_offset, info);

        // copy existing string
        memcpy(result + variable_offset, text, len + 1);  // known length does not include trailing null
        variable_offset += len + 1;
        break;
      }

      // Blob field is stored in the variable space. The int64 storage encodes
      // the length and offset. In this case we copy the variable data from the
      // original stored data i.e. this data is unchanged.
      case CQL_BLOB_TYPE_BLOB:
      {
        uint64_t val = cql_read_big_endian_u64(b + storage_offset);
        uint32_t len = val & 0xffffffff;
        uint32_t offset = val >> 32;
        const void *data = (const void *)b + offset;

        uint64_t info = (uint64_t)(variable_offset << 32) | (uint64_t)len;
        cql_write_big_endian_u64(result + storage_offset, info);

        // copy existing blob
        memcpy(result + variable_offset, data, len);  //  length  includes trailing null
        variable_offset += len;
        break;
      }

      // String field is stored in the variable space. The int64 storage encodes
      // the length and offset. Length does not include the trailing null. In
      // this case we copy the variable data from argv
      case CQL_BLOB_TYPE_STRING | CQL_BLOB_TYPE_DIRTY:
      {
        // we previously stashed the index of the argument we need here
        uint64_t iarg = *(uint64_t *)(result + storage_offset);
        sqlite3_value *field_value_arg = argv[iarg];

        const unsigned char *val = sqlite3_value_text(field_value_arg);
        uint32_t len = (uint32_t)sqlite3_value_bytes(field_value_arg);
        uint64_t info = (uint64_t)(variable_offset << 32) | (uint64_t)len;
        cql_write_big_endian_u64(result + storage_offset, info);

        memcpy(result + variable_offset, val, len + 1);  // known length does not include trailing null
        variable_offset += len + 1;
        break;
      }

      // Blob field is stored in the variable space. The int64 storage encodes
      // the length and offset. In this case we copy the variable data from argv
      case CQL_BLOB_TYPE_BLOB | CQL_BLOB_TYPE_DIRTY:
      {
        // we previously stashed the index of the argument we need here
        uint64_t iarg = *(uint64_t *)(result + storage_offset);
        sqlite3_value *field_value_arg = argv[iarg];

        const void *val = sqlite3_value_blob(field_value_arg);
        uint32_t len = (uint32_t)sqlite3_value_bytes(field_value_arg);
        uint64_t info = (uint64_t)(variable_offset << 32) | (uint64_t)len;
        cql_write_big_endian_u64(result + storage_offset, info);

        memcpy(result + variable_offset, val, len);
        variable_offset += len;
        break;
      }
    }
  }

  sqlite3_result_blob(context, result, (int)total_bytes, sqlite3_free);
  goto cleanup;

cql_error:
  sqlite3_result_null(context);

cleanup:
  if (b) {
    free(b);
  }
}

// test if the incoming argument is compatible with blob field type report the
// variable size of the incoming arg if there is any variable size
static cql_bool cql_blobtype_vs_argtype_compat(
  sqlite3_value *_Nonnull field_value_arg,
  int8_t blob_column_type,
  uint64_t *_Nonnull variable_size)
{
  *variable_size = 0;
  int64_t field_value_type = sqlite3_value_type(field_value_arg);
  switch (blob_column_type) {
  // These three are fixed length and stored in an int64
  // the value provided must be an integer
  case CQL_BLOB_TYPE_BOOL:
  case CQL_BLOB_TYPE_INT32:
  case CQL_BLOB_TYPE_INT64:
    if (field_value_type != SQLITE_INTEGER) {
      return false;
    }
    break;

  // Always IEEE 754 "double" (8 bytes) format in the blob.
  case CQL_BLOB_TYPE_FLOAT:
    if (field_value_type != SQLITE_FLOAT && field_value_type != SQLITE_INTEGER) {
      return false;
    }
    break;

  // String field is stored in the variable space. The int64 storage encodes the
  // length and offset. Length does not include the trailing null.
  case CQL_BLOB_TYPE_STRING:
    if (field_value_type != SQLITE3_TEXT) {
      return false;
    }
    *variable_size += (uint64_t)sqlite3_value_bytes(field_value_arg) + 1;
    break;

  // Blob field is stored in the variable space. The int64 storage encodes the
  // length and offset.
  case CQL_BLOB_TYPE_BLOB:
    if (field_value_type != SQLITE_BLOB) {
      return false;
    }
    *variable_size = (uint64_t)sqlite3_value_bytes(field_value_arg);
    break;

  default:
    return false;
  }

  return true;
}

// Value blobs have:
//  - the standard header
//    - record type
//    - magic word
//    - count of columns
//  - the field ids, one int64 per column
//  - the storage area, one int64 per column
//  - the type area, one byte per column
//  - variable space to hold strings and blobs
// This record has the size and offset of all those things
typedef struct cql_val_blob_shape {
  uint64_t header_size;
  uint64_t field_ids_size;
  uint64_t storage_size;
  uint64_t type_codes_size;
  uint64_t variable_size;
  uint64_t total_bytes;
  uint64_t field_ids_offset;
  uint64_t storage_offset;
  uint64_t type_codes_offset;
  uint64_t variable_offset;
} cql_val_blob_shape;

// Computes the sizes and offsets of all the items in a val blob given the
// column count and variable size required.  Note that sometimes we don't know
// the variable size yet so zero is used.  In that case you simply adjust the
// total size and variable size when it's known.
static void cql_compute_val_blob_shape(
  cql_val_blob_shape *_Nonnull shape,
  uint64_t column_count,
  uint64_t variable_size) {

  shape->header_size = sizeof(cql_blob_header);
  shape->field_ids_size = column_count * sizeof(int64_t);
  shape->storage_size = column_count * sizeof(int64_t);
  shape->type_codes_size = column_count * sizeof(int8_t);
  shape->variable_size = variable_size;
  shape->total_bytes = shape->header_size + shape->field_ids_size + shape->type_codes_size + shape->storage_size + variable_size;

  // we don't support records this big, they are insane already
  cql_contract(shape->total_bytes == (cql_int32)shape->total_bytes);

  shape->field_ids_offset = shape->header_size;
  shape->storage_offset = shape->field_ids_offset + shape->field_ids_size;
  shape->type_codes_offset = shape->storage_offset + shape->storage_size;
  shape->variable_offset = shape->type_codes_offset + shape->type_codes_size;
}

// returns a blob with the given items in value format
// bcreateval(
//    record_code,
//    [field id, field value, field type]+
// )
// Note: any null valued columns are ignored, a null value is represented by its
// absence.
void bcreateval(
  sqlite3_context *_Nonnull context,
  cql_int32 argc,
  sqlite3_value *_Nonnull *_Nonnull argv)
{
  // the number of args must be a multiple of 3 plus 1
  // and there must be at least 4
  if (argc < 1 || argc % 3 != 1) {
    goto cql_error;
  }

  // argv[0] must be the record type and it must be an integer
  if (sqlite3_value_type(argv[0]) != SQLITE_INTEGER) {
    goto cql_error;
  }
  uint64_t rtype = (uint64_t)sqlite3_value_int64(argv[0]);

  cql_int32 colspecs = (argc - 1)  / 3;
  cql_invariant(colspecs >= 0);

  // In the first pass we verify the provided values are compatible with the
  // provided types and compute the needed variable size.  We also need to know
  // the actual number of columns, null provided values don't count.
  uint64_t variable_size = 0;
  cql_uint32 actual_cols = 0;
  for (cql_int32 ispec = 0; ispec < colspecs; ispec++) {
    cql_int32 index = ispec * 3 + 1;
    sqlite3_value *field_id_arg = argv[index];
    sqlite3_value *field_value_arg = argv[index + 1];
    sqlite3_value *field_type_arg = argv[index + 2];

    if (sqlite3_value_type(field_type_arg) != SQLITE_INTEGER) {
      goto cql_error;
    }

    if (sqlite3_value_type(field_id_arg) != SQLITE_INTEGER) {
      goto cql_error;
    }

    int8_t blob_column_type = (int8_t)sqlite3_value_int64(field_type_arg);
    int64_t field_value_type = sqlite3_value_type(field_value_arg);

    // if field_value_type is SQLITE_NULL then ignore this column
    // there is no need to store nulls, an absent column will do
    if (field_value_type == SQLITE_NULL) {
      // don't increase actual columns, this item may as well be absent
      continue;
    }

    uint64_t field_variable_size = 0;
    cql_bool compat = cql_blobtype_vs_argtype_compat(
      field_value_arg,
      blob_column_type,
      &field_variable_size);

    if (!compat) {
      goto cql_error;
    }
    variable_size += field_variable_size ;

    // validated column discovered
    actual_cols++;
  }

  // At this point we know everything we need to know about our storage so we
  // can use the helper to make the shape for us.
  cql_val_blob_shape shape;
  cql_compute_val_blob_shape(&shape, actual_cols, variable_size);

  uint8_t *b = sqlite3_malloc((cql_int32)shape.total_bytes);
  cql_contract(b != NULL);

  cql_blob_header header;
  header.record_type = rtype;
  header.column_count = actual_cols;
  header.magic = CQL_BLOB_MAGIC;

  cql_write_blob_header(b, &header);

  // These will track the next available position to write storage
  // types, or blob/string data.
  uint64_t field_ids_offset = shape.field_ids_offset;
  uint64_t storage_offset = shape.storage_offset;
  uint64_t type_codes_offset = shape.type_codes_offset;
  uint64_t variable_offset = shape.variable_offset;

  // In the second pass we write the arguments into the blob
  // using the offsets computed above.
  for (cql_int32 ispec = 0; ispec < colspecs; ispec++) {
    cql_int32 index = ispec * 3 + 1;
    sqlite3_value *field_id_arg = argv[index];
    sqlite3_value *field_value_arg = argv[index + 1];
    sqlite3_value *field_type_arg = argv[index + 2];

    int64_t field_value_type = sqlite3_value_type(field_value_arg);

    // if field_value_type is SQLITE_NULL then ignore this column
    // there is no need to store nulls, an absent column will do
    if (field_value_type == SQLITE_NULL) {
      // don't increase actual columns, this item may as well be absent
      continue;
    }

    int8_t blob_column_type = (int8_t)sqlite3_value_int64(field_type_arg);
    b[type_codes_offset++] = (uint8_t)blob_column_type;

    uint64_t field_id = (uint64_t)sqlite3_value_int64(field_id_arg);
    cql_write_big_endian_u64(b + field_ids_offset, field_id);
    field_ids_offset += sizeof(uint64_t);

    switch (blob_column_type) {
      // Boolean values are stored in the int64 storage, but are normalized
      // to zero or one first.
      case CQL_BLOB_TYPE_BOOL:
      {
        int64_t val = sqlite3_value_int64(field_value_arg);
        cql_write_big_endian_u64(b + storage_offset, (uint64_t)!!val);
        break;
      }

      // These are written in big endian format for portability.
      // Any fixed endian order would have worked.
      case CQL_BLOB_TYPE_INT64:
      case CQL_BLOB_TYPE_INT32:
      {
        int64_t val = sqlite3_value_int64(field_value_arg);
        cql_write_big_endian_u64(b + storage_offset, (uint64_t)val);
        break;
      }

      // Always IEEE 754 "double" (8 bytes) format in the blob.
      case CQL_BLOB_TYPE_FLOAT:
      {
        double val = sqlite3_value_double(field_value_arg);
        *(double *)(b + storage_offset) = val;
        break;
      }

      // String field is stored in the variable space.
      // The int64 storage encodes the length and offset.
      // Length does not include the trailing null.
      case CQL_BLOB_TYPE_STRING:
      {
        const unsigned char *val = sqlite3_value_text(field_value_arg);
        uint32_t len = (uint32_t)sqlite3_value_bytes(field_value_arg);
        uint64_t info = (uint64_t)(variable_offset << 32) | (uint64_t)len;
        cql_write_big_endian_u64(b + storage_offset, info);

        memcpy(b + variable_offset, val, len + 1);  // known length does not include trailing null
        variable_offset += len + 1;
        break;
      }

      // Blob field is stored in the variable space.
      // The int64 storage encodes the length and offset.
      case CQL_BLOB_TYPE_BLOB:
      {
        const void *val = sqlite3_value_blob(field_value_arg);
        uint32_t len = (uint32_t)sqlite3_value_bytes(field_value_arg);
        uint64_t info = (uint64_t)(variable_offset << 32) | (uint64_t)len;
        cql_write_big_endian_u64(b + storage_offset, info);

        memcpy(b + variable_offset, val, len);
        variable_offset += len;
        break;
      }
    }

    storage_offset += sizeof(int64_t);
  }

  sqlite3_result_blob(context, b, (int)shape.total_bytes, sqlite3_free);
  return;

cql_error:
  sqlite3_result_null(context);
}

// Returns the indicated column from the blob using the type info in the blob
// bgetval(
//    blob, field code
// )
void bgetval(
  sqlite3_context *_Nonnull context,
  cql_int32 argc,
  sqlite3_value *_Nonnull *_Nonnull argv)
{
  // these are enforced at compile time
  cql_contract(argc == 2);
  cql_contract(sqlite3_value_type(argv[0]) == SQLITE_BLOB);
  cql_contract(sqlite3_value_type(argv[1]) == SQLITE_INTEGER);

  int64_t field_id = sqlite3_value_int64(argv[1]);
  const uint8_t *b = (const uint8_t *)sqlite3_value_blob(argv[0]);
  uint32_t original_bytes = (uint32_t)sqlite3_value_bytes(argv[0]);

  // read the header to get the basic info
  cql_blob_header header;
  cql_read_blob_header(b, &header, original_bytes);

  // bad blob gives nil result
  if (header.magic != CQL_BLOB_MAGIC) {
    goto cql_error;
  }

  // we know enough to make the shape and get the offsets
  // the variable size is not computed but that is of no import
  // since we are not yet validating all the internal offsets
  // (blobs are assumed to be well formed for now)
  cql_val_blob_shape shape;
  cql_compute_val_blob_shape(&shape, header.column_count, 0);

  // we have to find the column using the field id
  cql_uint32 icol;
  for (icol = 0; icol < header.column_count; icol++) {
    uint64_t field_id_offset = shape.field_ids_offset + icol * sizeof(uint64_t);
    int64_t stored_field_id = (int64_t)cql_read_big_endian_u64(b + field_id_offset);
    if (stored_field_id == field_id) {
      break;
    }
  }

  if (icol >= header.column_count) {
    // field not found, the error path will return null as expected
    goto cql_error;
  }

  uint64_t type_code_offset = shape.type_codes_offset + icol * sizeof(uint8_t);
  uint64_t storage_offset = shape.storage_offset + icol * sizeof(uint64_t);

  uint8_t blob_column_type = b[type_code_offset];

  switch (blob_column_type) {
    // Boolean values are stored in the int64 storage, but are normalized
    // to zero or one first.
    case CQL_BLOB_TYPE_BOOL:
    {
      uint64_t val = cql_read_big_endian_u64(b + storage_offset);
      sqlite3_result_int64(context, !!val);
      return;
    }

    // These are written in big endian format for portability.
    // Any fixed endian order would have worked.
    case CQL_BLOB_TYPE_INT32:
    case CQL_BLOB_TYPE_INT64:
    {
      uint64_t val = cql_read_big_endian_u64(b + storage_offset);
      sqlite3_result_int64(context, (int64_t)val);
      return;
    }

    // Always IEEE 754 "double" (8 bytes) format in the blob.
    case CQL_BLOB_TYPE_FLOAT:
    {
      double val = *(const double *)(b + storage_offset);
      sqlite3_result_double(context, val);
      return;
    }

    // String field is stored in the variable space. The int64 storage encodes
    // the length and offset. Length does not include the trailing null.
    case CQL_BLOB_TYPE_STRING:
    {
      uint64_t val = cql_read_big_endian_u64(b + storage_offset);
      uint32_t len = val & 0xffffffff;
      uint32_t offset = val >> 32;
      const char *text = (const char *)b + offset;
      sqlite3_result_text(context, text, (int)len, SQLITE_TRANSIENT);
      return;
    }

    // Blob field is stored in the variable space. The int64 storage encodes the
    // length and offset.
    case CQL_BLOB_TYPE_BLOB:
    {
      uint64_t val = cql_read_big_endian_u64(b + storage_offset);
      uint32_t len = val & 0xffffffff;
      uint32_t offset = val >> 32;
      const uint8_t *data = b + offset;
      sqlite3_result_blob(context, data, (int)len, SQLITE_TRANSIENT);
      return;
    }
  }

cql_error:
  sqlite3_result_null(context);
}

// Returns the record type from a key blob
// Returns the indicated column from the blob using the type info in the blob
// bgetval_type(
//    blob
// )
void bgetval_type(
  sqlite3_context *_Nonnull context,
  cql_int32 argc,
  sqlite3_value *_Nonnull *_Nonnull argv)
{
  // these are enforced at compile time
  cql_contract(argc == 1);
  cql_contract(sqlite3_value_type(argv[0]) == SQLITE_BLOB);

  const uint8_t *b = (const uint8_t *)sqlite3_value_blob(argv[0]);
  uint32_t original_bytes = (uint32_t)sqlite3_value_bytes(argv[0]);

  // extract the header
  cql_blob_header header;
  cql_read_blob_header(b, &header, original_bytes);

  // if the magic value is correct then use the record type
  if (header.magic != CQL_BLOB_MAGIC) {
    sqlite3_result_null(context);
  }
  else {
    sqlite3_result_int64(context, (int64_t)header.record_type);
  }
}

// Returns a new blob with the indicated items updated in value format
// bupdateval(
//    blob,
//    [field id, field value, field type]*
// )
//
// NOTE: THIS CODE DOES NOT HANDLE THE CASE WHERE NEW COLUMNS ARE ADDED
void bupdateval(
  sqlite3_context *_Nonnull context,
  cql_int32 argc,
  sqlite3_value *_Nonnull *_Nonnull argv)
{
  // copy of the header of the storage
  uint8_t *_Nullable b = NULL;

  // the number of args must be a multiple of 3 plus 1
  // and there must be at least 4
  if (argc < 4 || argc % 3 != 1) {
    goto cql_error;
  }

  // if the first argument is not a blob, go to the error path
  if (sqlite3_value_type(argv[0]) != SQLITE_BLOB) {
    goto cql_error;
  }

  // we have to make a copy of the buffer because sqlite3_value_bytes is not
  // durable
  uint32_t original_bytes = (uint32_t)sqlite3_value_bytes(argv[0]);
  b = (uint8_t *)malloc(original_bytes);
  memcpy(b, sqlite3_value_blob(argv[0]), original_bytes);

  // read out the header
  cql_blob_header header;
  cql_read_blob_header(b, &header, original_bytes);

  // bogus blob leads us to the error path
  if (header.magic != CQL_BLOB_MAGIC) {
    goto cql_error;
  }

  uint64_t column_count_original = header.column_count;

  cql_val_blob_shape original_shape;
  cql_compute_val_blob_shape(&original_shape, header.column_count, 0);
  original_shape.total_bytes = original_bytes;
  original_shape.variable_size = original_bytes - original_shape.variable_offset;

  // We need to track how much variable space we need to add or remove we'll do
  // it here.  Likewise we track if columns were added or removed.
  int64_t variable_size_adjustment = 0;
  cql_int32 col_adjustment = 0;

  // In the first pass we're going to go over the arguments, we're going to
  // figure out how many columns are going to be added/removed and we're going
  // to figure out how much more/less variable storage we need. At this time we
  // will check all the arguments for compatability with any already stored
  // values and for consistency.
  //   * no duplicate field ids
  //   * stored field id must match provided field id if there is a stored field
  //     id
  //   * data type of field_value_arg (the provided value) must be compatible
  //     with value of field_type_arg (the provided type)
  cql_int32 updates = (argc - 1) / 3;
  for (cql_int32 iupdate = 0; iupdate < updates; iupdate++) {
    cql_int32 index = iupdate * 3 + 1;
    sqlite3_value *field_id_arg = argv[index];
    sqlite3_value *field_value_arg = argv[index + 1];
    sqlite3_value *field_type_arg = argv[index + 2];

    if (sqlite3_value_type(field_id_arg) != SQLITE_INTEGER) {
      goto cql_error;
    }

    int64_t field_id = sqlite3_value_int64(field_id_arg);

    cql_uint32 icol_original;
    for (icol_original = 0; icol_original < column_count_original; icol_original++) {
      uint64_t field_id_offset = original_shape.field_ids_offset + icol_original * sizeof(uint64_t);
      int64_t stored_field_id = (int64_t)cql_read_big_endian_u64(b + field_id_offset);
      if (stored_field_id == field_id) {
        break;
      }
    }

    int8_t blob_column_type = (int8_t)sqlite3_value_int64(field_type_arg);
    int64_t field_value_type = sqlite3_value_type(field_value_arg);

    // this column is missing, if the value we are inserting is not null then we
    // need to add a column
    if (icol_original >= column_count_original) {

      // we're adding a new column if the column type is not null
      if (field_value_type != SQLITE_NULL) {
        // we'll need a new column now (unless the types don't match)
        col_adjustment++;

        // Since the value is not null, we'll be adding this column.
        // Accordingly, the update arg value must be compatible with the column
        // type provided.
        uint64_t field_variable_size = 0;
        cql_bool compat = cql_blobtype_vs_argtype_compat(field_value_arg, blob_column_type, &field_variable_size);
        if (!compat) {
          goto cql_error;
        }

        // this column is missing so it needs the full variable size whatever
        // that is
        variable_size_adjustment += field_variable_size;
      }

      // move on to the next column specification, this is a new column
      continue;
    }

    cql_contract(icol_original < column_count_original);

    // Now that we have a valid column, we can compute the offset to the places
    // where its info is stored.
    uint64_t type_code_offset = original_shape.type_codes_offset + icol_original * sizeof(uint8_t);
    uint64_t storage_offset = original_shape.storage_offset + icol_original * sizeof(uint64_t);
    int8_t stored_blob_column_type = (int8_t)(b[type_code_offset]);

    // this will fail if the type is changed or if it was already altered by
    // adding CQL_BLOB_TYPE_DIRTY
    if (blob_column_type != stored_blob_column_type) {
      goto cql_error;
    }

    // Marking this dirty will cause an error if we try to update it twice and
    // will cause us to not copy the value in the second pass.  We use the arg
    // value rather then the previous value for changed fields.
    b[type_code_offset] = (uint8_t)(blob_column_type | CQL_BLOB_TYPE_DIRTY);

    uint64_t variable_size_new = 0;
    uint64_t variable_size_stored = 0;

    // If the provided value is not null then we are actually replacing a
    // column. No column count adjustment is needed.
    if (field_value_type != SQLITE_NULL) {
      cql_bool compat = cql_blobtype_vs_argtype_compat(field_value_arg, blob_column_type, &variable_size_new);
      if (!compat) {
        goto cql_error;
      }

      switch (blob_column_type) {
        // String field is stored in the variable space. The int64 storage
        // encodes the length and offset. Length does not include the trailing
        // null.
        case CQL_BLOB_TYPE_STRING:
        {
          uint64_t val = cql_read_big_endian_u64(b + storage_offset);
          uint32_t len = val & 0xffffffff;
          variable_size_stored = len + 1;
          break;
        }

        // Blob field is stored in the variable space. The int64 storage encodes
        // the length and offset.
        case CQL_BLOB_TYPE_BLOB:
        {
          uint64_t val = cql_read_big_endian_u64(b + storage_offset);
          uint32_t len = val & 0xffffffff;
          variable_size_stored = len;
        }
      }
    }
    else {
      // The provided value is null, so we're deleting this column. There will
      // be one less column in the result.
      col_adjustment--;
    }

    variable_size_adjustment += variable_size_new - variable_size_stored;
  }

  // compute the final shape parameters of the updated blob
  uint64_t column_count_new = (uint64_t)(((int64_t)column_count_original) + col_adjustment);
  uint64_t new_variable_size = (uint64_t)(((int64_t)original_shape.variable_size) + variable_size_adjustment);

  // now we know enough to compute all the offsets, go ahead and do that.
  cql_val_blob_shape new_shape;
  cql_compute_val_blob_shape(&new_shape, column_count_new, new_variable_size);

  uint8_t *result = sqlite3_malloc((cql_int32)new_shape.total_bytes);
  cql_contract(result != NULL);

  // this is where we will be storing values as we encounter them
  uint64_t new_field_ids_offset = new_shape.field_ids_offset;
  uint64_t new_storage_offset = new_shape.storage_offset;
  uint64_t new_type_codes_offset = new_shape.type_codes_offset;
  uint64_t new_variable_offset = new_shape.variable_offset;

  // In the second pass we use the provided arguments to update the storage. We
  // copy them over just like we would in bcreateval, making a new group of
  // arrays of field ids, storage, and types.  When this is done we have
  // consumed the arguments.
  for (cql_int32 iupdate = 0; iupdate < updates; iupdate++) {
    cql_int32 index = iupdate * 3 + 1;
    sqlite3_value *field_id_arg = argv[index];
    sqlite3_value *field_value_arg = argv[index + 1];
    sqlite3_value *field_type_arg = argv[index + 2];

    int64_t field_id = sqlite3_value_int64(field_id_arg);
    int64_t field_value_type = sqlite3_value_type(field_value_arg);

    if (field_value_type == SQLITE_NULL) {
      // don't record a null value, this deletes the field from the record
      continue;
    }

    int8_t blob_column_type = (int8_t)sqlite3_value_int64(field_type_arg);
    result[new_type_codes_offset++] = (uint8_t)blob_column_type;
    cql_write_big_endian_u64(result + new_field_ids_offset, (uint64_t)field_id);
    new_field_ids_offset += sizeof(int64_t);

    switch (blob_column_type) {
      // Boolean values are stored in the int64 storage, but are normalized to
      // zero or one first.
      case CQL_BLOB_TYPE_BOOL:
      {
        int64_t val = sqlite3_value_int64(field_value_arg);
        cql_write_big_endian_u64(result + new_storage_offset, (uint64_t)!!val);
        break;
      }

      // These are written in big endian format for portability. Any fixed
      // endian order would have worked.
      case CQL_BLOB_TYPE_INT64:
      case CQL_BLOB_TYPE_INT32:
      {
        int64_t val = sqlite3_value_int64(field_value_arg);
        cql_write_big_endian_u64(result + new_storage_offset, (uint64_t)val);
        break;
      }

      // Always IEEE 754 "double" (8 bytes) format in the blob.
      case CQL_BLOB_TYPE_FLOAT:
      {
        double val = sqlite3_value_double(field_value_arg);
        *(double *)(result + new_storage_offset) = val;
        break;
      }

      // String field is stored in the variable space. The int64 storage encodes
      // the length and offset. Length does not include the trailing null.
      case CQL_BLOB_TYPE_STRING:
      {
        const unsigned char *val = sqlite3_value_text(field_value_arg);
        uint32_t len = (uint32_t)sqlite3_value_bytes(field_value_arg);
        uint64_t info = (uint64_t)(new_variable_offset << 32) | (uint64_t)len;
        cql_write_big_endian_u64(result + new_storage_offset, info);

        memcpy(result + new_variable_offset, val, len + 1);
        new_variable_offset += len + 1;
        break;
      }

      // Blob field is stored in the variable space. The int64 storage encodes
      // the length and offset.
      case CQL_BLOB_TYPE_BLOB:
      {
        const void *val = sqlite3_value_blob(field_value_arg);
        uint32_t len = (uint32_t)sqlite3_value_bytes(field_value_arg);
        uint64_t info = (uint64_t)(new_variable_offset << 32) | (uint64_t)len;
        cql_write_big_endian_u64(result + new_storage_offset, info);

        memcpy(result + new_variable_offset, val, len);
        new_variable_offset += len;
        break;
      }
    }
    new_storage_offset += sizeof(int64_t);
  }

  // In the final pass, we go over all of the columns that were not updated.
  // These columns are copied into the new blob to create the final output.  We
  // can do this more economically in most cases because the stored values are
  // already big endian encoded. We do have to recode the offset of all the
  // variable length items.
  for (cql_uint32 icol = 0; icol < column_count_original; icol++) {
    uint8_t blob_column_type = b[original_shape.type_codes_offset + icol];
    uint64_t data_offset = original_shape.storage_offset + icol * sizeof(int64_t);
    uint64_t field_id_offset = original_shape.field_ids_offset + icol * sizeof(int64_t);

    // this will only match CLEAN fields. New or dirty fields have already been taken care of
    switch (blob_column_type) {
      // primitive types, we can just copy them they are already encoded
      case CQL_BLOB_TYPE_BOOL:
      case CQL_BLOB_TYPE_INT32:
      case CQL_BLOB_TYPE_INT64:
      case CQL_BLOB_TYPE_FLOAT:
      {
        // copy already encoded item
        memcpy(result + new_storage_offset, b + data_offset, sizeof(int64_t));
        break;
      }

      // String field is stored in the variable space. The int64 storage encodes
      // the length and offset. Length does not include the trailing null.
      case CQL_BLOB_TYPE_STRING:
      {
        uint64_t val = cql_read_big_endian_u64(b + data_offset);
        uint32_t len = val & 0xffffffff;
        uint32_t offset = val >> 32;
        const char *text = (const char *)b + offset;

        uint64_t info = (uint64_t)(new_variable_offset << 32) | (uint64_t)len;
        cql_write_big_endian_u64(result + new_storage_offset, info);

        // copy existing string
        memcpy(result + new_variable_offset, text, len + 1);  // stored length does not include trailing null
        new_variable_offset += len + 1;
        break;
      }

      // Blob field is stored in the variable space. The int64 storage encodes
      // the length and offset.
      case CQL_BLOB_TYPE_BLOB:
      {
        uint64_t val = cql_read_big_endian_u64(b + data_offset);
        uint32_t len = val & 0xffffffff;
        uint32_t offset = val >> 32;
        const void *data = (const void *)b + offset;

        uint64_t info = (uint64_t)(new_variable_offset << 32) | (uint64_t)len;
        cql_write_big_endian_u64(result + new_storage_offset, info);

        // copy existing blob
        memcpy(result + new_variable_offset, data, len);  //  length  includes trailing null
        new_variable_offset += len;
        break;
      }

      default:
        continue;  // do not store a field that is null or was updated
    }

    result[new_type_codes_offset] = blob_column_type;
    memcpy(result + new_field_ids_offset, b  + field_id_offset, sizeof(int64_t));
    new_storage_offset += sizeof(int64_t);
    new_field_ids_offset += sizeof(int64_t);
    new_type_codes_offset++;
  }

  // magic number and record type perserved
  header.column_count = (cql_uint32)column_count_new;
  cql_write_blob_header(result, &header);

  sqlite3_result_blob(context, result, (int)new_shape.total_bytes, sqlite3_free);
  goto cleanup;

cql_error:
  sqlite3_result_null(context);

cleanup:
  if (b) {
    free(b);
  }
}

// use the code to create an "exception" if non-zero
// CQLABI
cql_code cql_throw(sqlite3 *_Nonnull db, int code)
{
   // this is how we throw
   return code;
}

// A boxed value can hold any scalar type in the space
// of an int64 or else an object reference.  The type
// comes from the type field which is one of the CQL_DATA_TYPE_*
// values.  The object reference is retained if it is not null.
// The scalar value is meaninful only for non-reference types.
typedef struct {
   cql_int64 scalar;
   cql_object_ref _Nullable obj;
   cql_int32 type;
} cql_boxed_value;

// Defer finalization to the hash table which has all it needs to do the job
static void cql_boxed_value_finalize(void *_Nonnull data) {
  cql_boxed_value *_Nonnull self = data;
  cql_release(*(cql_type_ref *)(&self->obj));
  free(data);
}

// get the type of the thing in the box
// CQLABI
cql_int32 cql_box_get_type(cql_object_ref _Nullable box) {
  if (!box) {
    return CQL_DATA_TYPE_NULL;
  }
  cql_boxed_value *_Nonnull self = _cql_generic_object_get_data(box);
  return self->type;
}
// create the facets storage using the hashtable
static cql_object_ref _Nonnull cql_boxed_value_create(void) {
  cql_boxed_value * self = malloc(sizeof(cql_boxed_value));
  memset(self, 0, sizeof(*self));
  return _cql_generic_object_create(self, cql_boxed_value_finalize);
}

// Box a bool, note that even null can be boxed and return a not null box
// that contains null.
// This is also available as <expr>:box
// CQLABI
cql_object_ref _Nonnull cql_box_bool(cql_nullable_bool data) {
    cql_object_ref _Nonnull box = cql_boxed_value_create();
    cql_boxed_value *_Nonnull self = _cql_generic_object_get_data(box);
    if (data.is_null) {
      self->type = 0;
    }
    else {
      self->type = CQL_DATA_TYPE_BOOL;
      *(cql_bool *)(&self->scalar) = data.value;
    }
    return box;
}

// Extract a bool from a box, if the box is null or the type is wrong
// the result will be null.
// This is also available as object<cql_box>:to_bool
// CQLABI
cql_nullable_bool cql_unbox_bool(cql_object_ref _Nullable box) {
    cql_nullable_bool result;
    if (!box) {
       result.is_null = true;
       result.value = 0;
       return result;
    }
    cql_boxed_value *_Nonnull self = _cql_generic_object_get_data(box);
    if (self->type == CQL_DATA_TYPE_BOOL) {
       result.is_null = false;
       result.value = *(cql_bool *)(&self->scalar);
    }
    else {
       result.is_null = true;
       result.value = false;
    }

    return result;
}

// Box an integer, note that even null can be boxed and return a not null box
// that contains null.
// This is also available as <expr>:box
// CQLABI
cql_object_ref _Nonnull cql_box_int(cql_nullable_int32 data) {
    cql_object_ref _Nonnull box = cql_boxed_value_create();
    cql_boxed_value *_Nonnull self = _cql_generic_object_get_data(box);
    if (data.is_null) {
      self->type = 0;
    }
    else {
      self->type = CQL_DATA_TYPE_INT32;
      *(cql_int32 *)(&self->scalar) = data.value;
    }
    return box;
}

// Extract an integer from a box, if the box is null or the type is wrong
// the result will be null.
// This is also available as object<cql_box>:to_int
// CQLABI
cql_nullable_int32 cql_unbox_int(cql_object_ref _Nullable box) {
    cql_nullable_int32 result;
    if (!box) {
       result.is_null = true;
       result.value = 0;
       return result;
    }
    cql_boxed_value *_Nonnull self = _cql_generic_object_get_data(box);
    if (self->type == CQL_DATA_TYPE_INT32) {
       result.is_null = false;
       result.value = *(cql_int32 *)(&self->scalar);
    }
    else {
       result.is_null = true;
       result.value = 0;
    }

    return result;
}

// Box a long, note that even null can be boxed and return a not null box
// that contains null.
// This is also available as <expr>:box
// CQLABI
cql_object_ref _Nonnull cql_box_long(cql_nullable_int64 data) {
    cql_object_ref _Nonnull box = cql_boxed_value_create();
    cql_boxed_value *_Nonnull self = _cql_generic_object_get_data(box);
    if (data.is_null) {
      self->type = 0;
    }
    else {
      self->type = CQL_DATA_TYPE_INT64;
      *(cql_int64 *)(&self->scalar) = data.value;
    }
    return box;
}

// Unbox a long from a box, if the box is null or the type is wrong
// the result will be null.
// This is also available as object<cql_box>:to_long
// CQLABI
cql_nullable_int64 cql_unbox_long(cql_object_ref _Nullable box) {
    cql_nullable_int64 result;
    if (!box) {
       result.is_null = true;
       result.value = 0;
       return result;
    }
    cql_boxed_value *_Nonnull self = _cql_generic_object_get_data(box);
    if (self->type == CQL_DATA_TYPE_INT64) {
       result.is_null = false;
       result.value = *(cql_int64 *)(&self->scalar);
    }
    else {
       result.is_null = true;
       result.value = 0;
    }

    return result;
}

// Box a double, note that even null can be boxed and return a not null box
// that contains null.
// This is also available as <expr>:box
// CQLABI
cql_object_ref _Nonnull cql_box_real(cql_nullable_double data) {
    cql_object_ref _Nonnull box = cql_boxed_value_create();
    cql_boxed_value *_Nonnull self = _cql_generic_object_get_data(box);
    if (data.is_null) {
      self->type = 0;
    }
    else {
      self->type = CQL_DATA_TYPE_DOUBLE;
      *(cql_double *)(&self->scalar) = data.value;
    }
    return box;
}

// Extract a double from a box, if the box is null or the type is wrong
// the result will be null.
// This is also available as object<cql_box>:to_real
// CQLABI
cql_nullable_double cql_unbox_real(cql_object_ref _Nullable box) {
    cql_nullable_double result;
    if (!box) {
       result.is_null = true;
       result.value = 0;
       return result;
    }
    cql_boxed_value *_Nonnull self = _cql_generic_object_get_data(box);
    if (self->type == CQL_DATA_TYPE_DOUBLE) {
       result.is_null = false;
       result.value = *(cql_double *)(&self->scalar);
    }
    else {
       result.is_null = true;
       result.value = 0;
    }

    return result;
}


// Box a string, note that even null can be boxed and return a not null box
// that contains null.
// This is also available as <expr>:box
// CQLABI
cql_object_ref _Nonnull cql_box_text(cql_string_ref _Nullable data) {
    cql_object_ref _Nonnull box = cql_boxed_value_create();
    cql_boxed_value *_Nonnull self = _cql_generic_object_get_data(box);
    if (!data) {
      self->type = 0;
    }
    else {
      self->type = CQL_DATA_TYPE_STRING;
      cql_set_object_ref(&self->obj, (cql_object_ref)data);
    }
    return box;
}

// Extract a string from a box or else return null if the type is wrong
// or if the box is null, or contains null.
// This is also available as object<cql_box>:to_text
// CQLABI
cql_string_ref _Nullable cql_unbox_text(cql_object_ref _Nullable box) {
    if (!box) {
       return NULL;
    }
    cql_boxed_value *_Nonnull self = _cql_generic_object_get_data(box);
    if (self->type == CQL_DATA_TYPE_STRING) {
       return (cql_string_ref)self->obj;
    }
    else {
       return NULL;
    }
}

// Box a blob, note that even null can be boxed and return a not null box
// that contains null.
// This is also available as <expr>:box
// CQLABI
cql_object_ref _Nonnull cql_box_blob(cql_blob_ref _Nullable data) {
    cql_object_ref _Nonnull box = cql_boxed_value_create();
    cql_boxed_value *_Nonnull self = _cql_generic_object_get_data(box);
    if (!data) {
      self->type = 0;
    }
    else {
      self->type = CQL_DATA_TYPE_BLOB;
      cql_set_object_ref(&self->obj, (cql_object_ref)data);
    }
    return box;
}

// Extract a blob from a box or else return null if the type is wrong
// or if the box is null, or contains null.
// This is also available as object<cql_box>:to_blob
// CQLABI
cql_blob_ref _Nullable cql_unbox_blob(cql_object_ref _Nullable box) {
    if (!box) {
       return NULL;
    }
    cql_boxed_value *_Nonnull self = _cql_generic_object_get_data(box);
    if (self->type == CQL_DATA_TYPE_BLOB) {
       return (cql_blob_ref)self->obj;
    }
    else {
       return NULL;
    }
}
// Box an object, note that even null can be boxed and return a not null box
// that contains null.
// This is also available as <expr>:box
// CQLABI
cql_object_ref _Nonnull cql_box_object(cql_object_ref _Nullable data) {
    cql_object_ref _Nonnull box = cql_boxed_value_create();
    cql_boxed_value *_Nonnull self = _cql_generic_object_get_data(box);
    if (!data) {
      self->type = 0;
    }
    else {
      self->type = CQL_DATA_TYPE_OBJECT;
      cql_set_object_ref(&self->obj, data);
    }
    return box;
}

// Extract an object from a box or else return null if the type is wrong
// or if the box is null, or contains null.
// This is also available as object<cql_box>:to_object
// CQLABI
cql_object_ref _Nullable cql_unbox_object(cql_object_ref _Nullable box) {
    if (!box) {
       return NULL;
    }
    cql_boxed_value *_Nonnull self = _cql_generic_object_get_data(box);
    if (self->type == CQL_DATA_TYPE_OBJECT) {
       return self->obj;
    }
    else {
       return NULL;
    }
}

#define CQL_FORMAT_VAL(name, type, code) \
cql_string_ref _Nonnull cql_format_##name(type val) { \
  cql_bool yes = true; \
  uint16_t offsets[] = { 1, 0 }; \
  uint8_t types[] = { code }; \
  /* make a skeletal cursor */ \
  cql_dynamic_cursor c = { \
   .cursor_col_offsets = offsets, \
   .cursor_data_types = types, \
   .cursor_data = &val, \
   .cursor_has_row = &yes \
  }; \
  return cql_cursor_format_column(&c, 0); \
}

CQL_FORMAT_VAL(bool, cql_nullable_bool, CQL_DATA_TYPE_BOOL)
CQL_FORMAT_VAL(int, cql_nullable_int32, CQL_DATA_TYPE_INT32)
CQL_FORMAT_VAL(long, cql_nullable_int64, CQL_DATA_TYPE_INT64)
CQL_FORMAT_VAL(double, cql_nullable_double, CQL_DATA_TYPE_DOUBLE)
CQL_FORMAT_VAL(string, cql_string_ref _Nullable, CQL_DATA_TYPE_STRING)
CQL_FORMAT_VAL(blob, cql_blob_ref _Nullable, CQL_DATA_TYPE_BLOB)
CQL_FORMAT_VAL(object, cql_object_ref _Nullable, CQL_DATA_TYPE_OBJECT)

// CQLABI
cql_string_ref _Nonnull cql_format_null(cql_nullable_bool b) {
  return cql_string_ref_new("null");
}
