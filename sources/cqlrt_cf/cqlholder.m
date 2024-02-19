/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#include "cqlrt_cf.h"

// CQLHolder is entirely private

@interface CQLHolder : NSObject

@property (nonatomic) void *bytes;
@property (nonatomic) void (*generic_finalizer)(void *);
@property (nonatomic) int type;

@end

@implementation CQLHolder

// The CQLHolder is a simple wrapper around a pointer and a type.  The type
// tells us how to clean up the pointer when the holder is deallocated.
// The holder is a CF object so it can be used with ARC.
- (instancetype)initWithBytes:(void *)bytesIn andType:(int)typeIn
{
  self = [super init];
  self.bytes = bytesIn;
  self.type = typeIn;
  return self;
}

// The point of all this is use the dynamic teardown function to clean up
- (void)dealloc
{
  if (self.bytes)
  {
    [self dynamicTeardown];
  }
}

// The kinds of things we know how to hold.

#define CF_HELD_TYPE_RESULT_SET 1
#define CF_HELD_TYPE_GENERIC 2

// The dynamic teardown function is the key to cleaning up the bytes
// There is only one known type -- RESULT SET -- all other types
// get the generic treatment... which is to call the finalizer if there is one.
- (void)dynamicTeardown
{
  switch (self.type) {
  case CF_HELD_TYPE_RESULT_SET:
    {
      // the result set knows how to clean itself up
      cql_result_set_ref ref = (__bridge cql_result_set_ref)self;
      cql_result_set *result_set = (cql_result_set *)self.bytes;
      result_set->meta.teardown(ref);
      break;
    }

  case CF_HELD_TYPE_GENERIC:
    {
      // the generic finalizer frees the bytes as needed
      if (self.generic_finalizer) {
        self.generic_finalizer(self.bytes);
      }

      // we do not call free() or anything like that
      // the finalizer is responsible for freeing the bytes
      // since we don't even know how they were allocated
      // or if they even need to be freed at all.
      self.bytes = NULL;
      self.type = 0;
      self.generic_finalizer = NULL;
      return;
    }
  }

  // this path is only for the result set
  free(self.bytes);
  self.bytes = NULL;
  self.type = 0;
}

@end

// The public interface is C, the CQLHolder object is a detail.

// For holding result sets.

cql_result_set_ref _Nonnull cql_result_set_create(
  void *_Nonnull data,
  cql_int32 count,
  cql_result_set_meta meta)
{
  cql_result_set *result_set = malloc(sizeof(cql_result_set));
  result_set->count = count;
  result_set->data = data;
  result_set->meta = meta;

  CQLHolder *holder = [[CQLHolder alloc] initWithBytes:(void *)result_set andType:CF_HELD_TYPE_RESULT_SET];
  return (__bridge_retained cql_result_set_ref)holder;
}

cql_result_set *_Nonnull cql_get_result_set_from_ref(cql_result_set_ref _Nonnull ref)
{
  CQLHolder *holder = (__bridge CQLHolder *)ref;
  cql_result_set *_Nonnull result_set = (cql_result_set *)holder.bytes;
  return result_set;
}

// This creates holder for the indicated blob of bytes
// the provided finalizer to free the bytes when the holder is deallocated.
// This is the private C interface to do this so basically it just calls
// right back into the object C world to do the job.
cql_object_ref _Nonnull _cql_generic_object_create(void *_Nonnull data, void (*_Nonnull finalizer)(void *_Nonnull))
{
  CQLHolder *holder = [[CQLHolder alloc] initWithBytes:(void *)data andType:CF_HELD_TYPE_GENERIC];
  holder.generic_finalizer = finalizer;
  return (__bridge_retained cql_object_ref)holder;
}

// This gives us the stored data back out of the holder, the caller is
// expected to know what to do with it.
void *_Nonnull _cql_generic_object_get_data(cql_object_ref _Nonnull ref)
{
  CQLHolder *holder = (__bridge CQLHolder *)ref;
  return holder.bytes;
}
