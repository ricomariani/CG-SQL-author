/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

// note that many customizations can go here in cqlrt.h
// there are many macros defined for the base types etc.
#include "cqlrt.h"

#include <memory.h>
#include <stdbool.h>

// This simple runtime tracks reference counts so that it can
// provide diagnostic info for the CQL test cases.  This is
// obviously single threaded which is fine for our use cases
// but it is one of the many reasons you should not use this
// runtime for "real" production cases.  At the very least
// a more robust retain/release strategy is needed.  See
// refer to the Internals Guide "Part 5: CQL Runtime" and
// Appendix 11 of the main guide "Production Considerations"
// for more thoughts on the runtime.
cql_int32 cql_outstanding_refs = 0;

// Upcount an object pointer (any type)
void cql_retain(cql_type_ref _Nullable ref) {
  if (ref) {
    ref->ref_count++;
    cql_outstanding_refs++;
  }
}

// Downcount an object pointer (any type)
void cql_release(cql_type_ref _Nullable ref) {
  if (ref)  {
    if (--ref->ref_count == 0) {
      if (ref->finalize) {
        ref->finalize(ref);
      }
      free((void *)ref);
    }
    cql_outstanding_refs--;
    cql_invariant(cql_outstanding_refs >= 0);
  }
}

// If a blob object goes to zero references we give back the memory
static void cql_blob_finalize(cql_type_ref _Nonnull ref) {
  cql_blob_ref blob = (cql_blob_ref)ref;
  cql_invariant(blob->ptr != NULL);
  free((void *)blob->ptr);
  blob->size = 0;
}

// We create a new blob from size and count and copy the bytes.  The object
// is set up so that it will use the finalizer above to give the memory back.
// Note that blobs are immutable.
cql_blob_ref _Nonnull cql_blob_ref_new(const void *_Nonnull bytes, cql_uint32 size) {
  cql_invariant(bytes != NULL);
  cql_blob_ref result = malloc(sizeof(cql_blob));
  result->base.type = CQL_C_TYPE_BLOB;
  result->base.ref_count = 1;
  result->base.finalize = &cql_blob_finalize;
  result->ptr = malloc(size);
  result->size = size;
  memcpy((void *)result->ptr, bytes, size);
  cql_outstanding_refs++;
  return result;
}

// Super simple hash for blobs.  This is a rework of hashpjw.
cql_hash_code cql_blob_hash(cql_blob_ref _Nullable blob) {
  cql_hash_code hash = 0;
  if (blob) {
    // djb2
    hash = 5381;
    const unsigned char *bytes = blob->ptr;
    cql_uint32 size = blob->size;
    while (size--) {
      hash = ((hash << 5) + hash) + *bytes++; /* hash * 33 + c */
    }
  }
  return hash;
}

// Comparison for blobs, note that null blobs are equal, this is not
// SQL semantics (!) it's normal C style semantics.
cql_bool cql_blob_equal(cql_blob_ref _Nullable blob1, cql_blob_ref _Nullable blob2) {
  if (blob1 == blob2) {
    return cql_true;
  }
  if (!blob1 || !blob2) {
    return cql_false;
  }

  const unsigned char *bytes1 = blob1->ptr;
  cql_uint32 size1 = blob1->size;
  const unsigned char *bytes2 = blob2->ptr;
  cql_uint32 size2 = blob2->size;

  return size1 == size2 && !memcmp(bytes1, bytes2, size1);
}

// If a string object goes to zero references we give back the memory
static void cql_string_finalize(cql_type_ref _Nonnull ref) {
  cql_string_ref string = (cql_string_ref)ref;
  cql_invariant(string->ptr != NULL);
  free((void *)string->ptr);
  string->ptr = NULL;  // in case of use after free, fail fast
}

// We create a new immutable string reference from a null terminated
// string and use the finalizer above to release the memory
cql_string_ref _Nonnull cql_string_ref_new(const char *_Nonnull cstr) {
  cql_invariant(cstr != NULL);
  cql_string_ref result = malloc(sizeof(cql_string));
  result->base.type = CQL_C_TYPE_STRING;
  result->base.ref_count = 1;
  result->base.finalize = &cql_string_finalize;
  size_t cstrlen = strlen(cstr);
  result->ptr = malloc(cstrlen + 1);
  memcpy((void *)result->ptr, cstr, cstrlen + 1);
  cql_outstanding_refs++;
  return result;
}

// Comparison is via strcmp
cql_int32 cql_string_compare(cql_string_ref _Nonnull s1, cql_string_ref _Nonnull s2) {
  cql_invariant(s1 != NULL);
  cql_invariant(s2 != NULL);
  return strcmp(s1->ptr, s2->ptr);
}

// Super simple hash for strings.  This is a rework of hashpjw.
cql_hash_code cql_string_hash(cql_string_ref _Nullable str) {
  cql_hash_code hash = 0;
  if (str) {
    // djb2
    hash = 5381;
    const char *chars = str->ptr;
    int c;
    while ((c = *chars++))
      hash = ((hash << 5) + hash) + c; /* hash * 33 + c */
  }
  return hash;
}

// String equality, null strings compare equal to each other and not equal
// to all else.  Otherwise use string comparison.
cql_bool cql_string_equal(cql_string_ref _Nullable s1, cql_string_ref _Nullable s2) {
  if (s1 == s2) {
    return cql_true;
  }
  if (!s1 || !s2) {
    return cql_false;
  }
  return cql_string_compare(s1, s2) == 0;
}

// Strings support the 'like' operation, we use the SQLite helper for this
// we don't support SQLite verisons too old to offer this helper.
int cql_string_like(cql_string_ref _Nonnull s1, cql_string_ref _Nonnull s2) {
  cql_invariant(s1 != NULL);
  cql_invariant(s2 != NULL);

  // The sqlite3_strlike(P,X,E) interface returns zero if and only if string X matches
  // the LIKE pattern P with escape character E.
  // The definition of LIKE pattern matching used in sqlite3_strlike(P,X,E) is the same
  // as for the "X LIKE P ESCAPE E" operator in the SQL dialect understood by SQLite.
  // For "X LIKE P" without the ESCAPE clause, set the E parameter of
  // sqlite3_strlike(P,X,E) to 0

  return sqlite3_strlike(s2->ptr, s1->ptr, '\0');
}

// If a result set object goes to zero references we give back the memory
// The result set has its own teardown to release all of reference objects inside
// of it.  This code delegates to the helper that does that (if there is one).
// Some result sets have no reference types.
static void cql_result_set_finalize(cql_type_ref _Nonnull ref) {
  cql_result_set_ref result_set = (cql_result_set_ref)ref;

  if (result_set->meta.teardown) {
    result_set->meta.teardown(result_set);
  }
}

// We create a result set with the given metadata block, that metadata defines
// the shape of the result set as well as its cleanup methods.  It is generated
// by the CQL compiler typically but unit tests or such can create fake versions
// of the cql_result_set_meta.  This isn't really a great practice but sometimes
// its proven necessary.
cql_result_set_ref _Nonnull cql_result_set_create(void *_Nonnull data, cql_int32 count, cql_result_set_meta meta) {
  cql_result_set_ref result = malloc(sizeof(cql_result_set));
  result->base.type = CQL_C_TYPE_RESULTS;
  result->base.ref_count = 1;
  result->base.finalize = &cql_result_set_finalize;
  result->meta = meta;
  result->count = count;
  result->data = data;
  cql_outstanding_refs++;
  return result;
}

// This helper can hash any refence type using its ->type member
// to choose the correct hash functions.  It's really only strings and blobs
// that are hashable at this point.
// You can use this for a generic but (homegenous) hash table hash function
// for instance.
cql_hash_code cql_ref_hash(cql_type_ref typeref) {
  if (typeref == NULL) {
    return 0;
  }

  if (typeref->type == CQL_C_TYPE_STRING) {
    return cql_string_hash((cql_string_ref)typeref);
  }

  // only these two types are ever invoked
  cql_contract(typeref->type == CQL_C_TYPE_BLOB);
  return cql_blob_hash((cql_blob_ref)typeref);
}

// Similar to the above, this is a generic helper that
// will apply the correct equality helper based on the
// ->type member.  The types must be compatible (see
// the contract below) so you must pre-check the types
// before using this helper.
// You can use this for a generic but (homegenous) hash table
// comparator for instance.
cql_bool cql_ref_equal(cql_type_ref typeref1, cql_type_ref typeref2) {
  if (typeref1 == typeref2) {
    return true;
  }

  // both are not null, so if either is null then false
  if (typeref1 == NULL || typeref2 == NULL) {
    return false;
  }

  // not used for arbitrary comparisons, types already checked
  cql_contract(typeref1->type == typeref2->type);

  if (typeref1->type == CQL_C_TYPE_STRING) {
    return cql_string_equal((cql_string_ref)typeref1, (cql_string_ref)typeref2);
  }

  // only these two types are ever invoked
  cql_contract(typeref1->type == CQL_C_TYPE_BLOB);
  return cql_blob_equal((cql_blob_ref)typeref1, (cql_blob_ref)typeref2);
}

// The cql common runtime is allowed to create objects of its own choosing
// beyond the standard ones.  It specifies it's own finalizer.  This is
// the finalizer for such a generic object.  When the ref count goes to
// zero the provided method is called, whatever it may be.  Note that
// the built in types like result set predate this functionality and
// were never converted to this pattern. But also there's some expectation
// that a runtime might want to change string, blob, and result set details.
// The generic objects (there are a few) are owned by cqlrt_common and
// therefore can be shared between all runtimes and they are not customizable
// except that the reference counting mechanism is owned by the provided
// cqlrt.
static void _cql_generic_finalize(cql_type_ref _Nonnull ref)
{
  cql_object_ref obj = (cql_object_ref)ref;
  obj->finalize(obj->ptr);
}

// This helper creates a generic object. It holds your void * data and
// your void cleanup function. It doens't know what they mean but you
// get them back during cleanup and the lifetime is otherwise tracked as
// usual.  Note that these kinds of objects are not hashable etc.
cql_object_ref _Nonnull _cql_generic_object_create(void *_Nonnull data, void (*finalize)(void *_Nonnull))
{
  cql_contract(data);
  cql_contract(finalize);

  cql_object_ref obj = (cql_object_ref)calloc(sizeof(cql_object), 1);
  obj->base.type = CQL_C_TYPE_OBJECT;
  obj->base.ref_count = 1;
  obj->base.finalize = _cql_generic_finalize;
  obj->ptr = data;
  obj->finalize = finalize;
  cql_outstanding_refs++;
  return obj;
}

// This helper gives the caller back its stored data
void *_Nonnull _cql_generic_object_get_data(cql_object_ref obj)
{
  cql_contract(obj->base.type == CQL_C_TYPE_OBJECT);
  cql_contract(obj->base.finalize == _cql_generic_finalize);
  return obj->ptr;
}

// the rest of the runtime is standard, all cqlrt implementations should end with this.
// what follows will use the above to do its job.

#include "cqlrt_common.c"
