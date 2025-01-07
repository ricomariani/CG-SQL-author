/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#include "cqlrt_cf.h"
#include <memory.h>
#include <stdbool.h>

cql_int32 cql_string_like(cql_string_ref _Nonnull s1, cql_string_ref _Nonnull s2) {
  cql_invariant(s1 != NULL);
  cql_invariant(s2 != NULL);

  cql_alloc_cstr(c1, s1);
  cql_alloc_cstr(c2, s2);
  cql_int32 code = (cql_int32)sqlite3_strlike(c1, c2, '\0');
  cql_free_cstr(c2, s2);
  cql_free_cstr(c1, s1);

  return code;
}

char *_Nullable cql_copy_string_to_stack_or_heap(
  CFStringRef _Nullable cf_string_ref,
  char *_Nullable *_Nonnull result)
{
  // "result" starts with the stack string we can use if we want to
  char *_Nullable stack_string = *result;
  char *_Nullable heap_string = NULL;     // no heap storage to start
  char *cstr = NULL;
  if (cf_string_ref != NULL) {
    cstr = (char *)CFStringGetCStringPtr(cf_string_ref, kCFStringEncodingUTF8);
    if (cstr == NULL) {
      CFIndex length = CFStringGetLength(cf_string_ref);
      CFIndex size = CFStringGetMaximumSizeForEncoding(length, kCFStringEncodingUTF8) + 1;
      if (size <= CF_C_STRING_STACK_MAX_LENGTH &&
          CFStringGetCString(cf_string_ref, stack_string, CF_C_STRING_STACK_MAX_LENGTH, kCFStringEncodingUTF8)) {
          cstr = stack_string;
      }
      else {
        heap_string = malloc(size);
        if (CFStringGetCString(cf_string_ref, heap_string, size, kCFStringEncodingUTF8)) {
          cstr = heap_string;
        }
      }
    }
  }
  *result = cstr;

  // this is what has to be freed, we return NULL if we did not allocate a heap string
  return heap_string;
}

void cql_retain(CFTypeRef _Nullable ref) {
  if (ref) CFRetain(ref);
}

void cql_release(CFTypeRef _Nullable ref) {
  if (ref) CFRelease(ref);
}

cql_hash_code cql_ref_hash(CFTypeRef _Nonnull ref) {
  return CFHash(ref);
}

cql_bool cql_ref_equal(CFTypeRef  _Nonnull r1, CFTypeRef  _Nonnull r2) {
 return CFEqual(r1, r2);
}

void cql_blob_retain(cql_blob_ref _Nullable obj) {
  cql_retain(obj);
}

void cql_blob_release(cql_blob_ref _Nullable obj) {
  cql_release(obj);
}

void *_Nonnull cql_get_blob_bytes(cql_blob_ref _Nonnull blob)  {
  return (void *_Nonnull)CFDataGetBytePtr(blob);
}

cql_int64 cql_get_blob_size(cql_blob_ref _Nonnull blob)  {
  return CFDataGetLength(blob);
}

cql_blob_ref _Nonnull cql_blob_ref_new(const void *_Nonnull bytes, cql_int64 size) {
  return CFDataCreate(NULL, bytes, size);
}

cql_bool cql_blob_equal(cql_blob_ref _Nullable  b1, cql_blob_ref _Nullable b2) {
  if (b1 == NULL && b2 == NULL) return cql_true;
  if (b1 == NULL || b2 == NULL) return cql_false;
  return CFEqual(b1,b2);
}

void cql_object_retain(cql_object_ref _Nullable obj) {
  cql_retain(obj);
}

void cql_object_release(cql_object_ref _Nullable obj) {
  cql_release(obj);
}

void cql_string_retain(cql_string_ref _Nullable str) {
  cql_retain(str);
}

void cql_string_release(cql_string_ref _Nullable str) {
  cql_release(str);
}

cql_string_ref _Nonnull cql_string_ref_new(const char *_Nonnull cstr) {
  return CFStringCreateWithCString(NULL, cstr, kCFStringEncodingUTF8);
}

cql_hash_code cql_string_hash(cql_string_ref _Nonnull str) {
  return CFHash(str);
}

cql_int32 cql_string_equal(cql_string_ref _Nullable s1, cql_string_ref _Nullable s2) {
  if (s1 == NULL && s2 == NULL) return cql_true;
  if (s1 == NULL || s2 == NULL) return cql_false;
  return CFEqual(s1, s2);
}

cql_int32 cql_string_compare(cql_string_ref _Nonnull s1, cql_string_ref _Nonnull s2) {
  return (cql_int32)CFStringCompare(s1, s2, 0);
}

#include "cqlrt_common.c"
