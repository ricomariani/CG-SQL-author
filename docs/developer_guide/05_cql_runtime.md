---
title: "Part 5: CQL Runtime"
weight: 5
---
<!---
-- Copyright (c) Meta Platforms, Inc. and affiliates.
--
-- This source code is licensed under the MIT license found in the
-- LICENSE file in the root directory of this source tree.
-->

### Preface

Part 5 continues with a discussion of the essentials of the CQL Runtime. As in
the previous sections, the goal here is not to delve into every detail but
rather to provide an overview of how the runtime operates in general — focusing
on core strategies and implementation choices — so that when you read the
source, you'll have an understanding of how it all fits together. To achieve
this, we'll highlight the main components that can be customized and discuss
some intriguing cases.

## CQL Runtime

The parts of the runtime that you can modify are located in `cqlrt.h`. This file
inevitably concludes by including `cqlrt_common.h`, which contains the runtime
components that you shouldn't modify. Of course, since this is open source, you
have the freedom to modify anything, but typically, the common elements don't
require alteration. `cqlrt.h` should equip you with everything necessary to
target new environments.

The compiler itself can be tailored; refer to `rt.c` to generate different
strings for compatibility with your runtime. This customization process is
relatively straightforward and avoids creating a complicated merging situation.
For example, Meta Platforms has its own customized CQL runtime designed for
mobile phones, but it's not open source (and frankly, I doubt anyone would
desire it anyway). Nevertheless, the key point is that you can create your own
runtime. In fact, I'm aware of two custom runtimes within Meta Platforms alone.

We'll dissect `cqlrt.h` step by step, keeping in mind that it might undergo
changes, but this is essentially its function. Moreover, the fundamental aspects
tend to remain stable over time.

### Standard headers

The remainder of the system relies on these components. `cqlrt.h` is tasked with
importing what you'll require later or what `cqlrt_common.h` necessitates on
your system.

```c
#pragma once

#include <assert.h>
#include <stddef.h>
#include <stdint.h>
#include <math.h>
#include <sqlite3.h>

#ifndef __clang__
#ifndef _Nonnull
    /* Hide Clang-only nullability specifiers if not Clang */
    #define _Nonnull
    #define _Nullable
#endif
#endif
```

### Contract and Error Macros

CQL employs several macros for handling errors: `contract`, `invariant`, and
`tripwire`, which typically all map to `assert`. It's worth noting that
`tripwire` doesn't necessarily need to result in a fatal error; it can log
information in a production environment and continue execution. This represents
a "softer" assertion — useful for scenarios where you want to enforce a
condition like a `contract`, but there may be outstanding issues that need to be
addressed first.

```c
#define cql_contract assert
#define cql_invariant assert
#define cql_tripwire assert
#define cql_log_database_error(...)
#define cql_error_trace()
```

### The Value Types

You can define these types according to what is suitable for your system.
Typically, the mapping is straightforward. The standard configuration is
shown below:

```c
// value types
typedef unsigned char cql_bool;
#define cql_true ((cql_bool)1)
#define cql_false ((cql_bool)0)

typedef uint64_t cql_hash_code;
typedef int32_t cql_int32;
typedef uint32_t cql_uint32;
typedef uint16_t cql_uint16;
typedef sqlite3_int64 cql_int64;
typedef double cql_double;
typedef int cql_code;
```

### The Reference Types

The default runtime defines four types of reference objects. These are the only
reference types that CQL generates internally. Actually, CQL doesn't directly
create `CQL_C_TYPE_OBJECT`, but the tests do. CQL never generates raw object
instances itself; only external functions have that capability. CQL can be
instructed to invoke such functions, which leads to object types entering the
calculus.

```c
// metatypes for the straight C implementation
#define CQL_C_TYPE_STRING 0
#define CQL_C_TYPE_BLOB 1
#define CQL_C_TYPE_RESULTS 2
#define CQL_C_TYPE_OBJECT 3
```

All reference types are reference counted. Therefore, they require a basic "base
type" that enables them to identify their own type and maintain a count.
Additionally, they possess a finalize method to manage memory cleanup when the
count reaches zero.

You have the freedom to define `cql_type_ref` according to your preferences.

```c
// base ref counting struct
typedef struct cql_type *cql_type_ref;
typedef struct cql_type {
  int type;
  int ref_count;
  void (*_Nullable finalize)(cql_type_ref _Nonnull ref);
} cql_type;
```

Regardless of what you do with the types, you'll need to define a `retain` and
`release` function with your types in the signature. Normal references should
include a generic value comparison and a hash function.

```c
void cql_retain(cql_type_ref _Nullable ref);
void cql_release(cql_type_ref _Nullable ref);

cql_hash_code cql_ref_hash(cql_type_ref _Nonnull typeref);
cql_bool cql_ref_equal(cql_type_ref _Nullable typeref1, cql_type_ref _Nullable typeref2);
```

Each type of reference requires an object, which likely includes the
aforementioned base type. However, this is adaptable. You can opt for some other
universal method to perform these operations. For example, on iOS, reference
types can easily be mapped to `CF` types.

The specialized versions of the `retain` and `release` macros for strings and
blobs should all map to the same operations. The compiler generates different
variations for readability purposes only. Functionally, the code depends on all
reference types having identical retain/release semantics. In certain contexts,
they are handled generically, such as when cleaning up the reference fields of a
cursor.

```c
// builtin object
typedef struct cql_object *cql_object_ref;
typedef struct cql_object {
  cql_type base;
  void *_Nonnull ptr;
  void (*_Nonnull finalize)(void *_Nonnull ptr);
} cql_object;

#define cql_object_retain(object) cql_retain((cql_type_ref)object);
#define cql_object_release(object) cql_release((cql_type_ref)object);
```

Boxed statement gets its own implementation, same as object.

```c
// builtin statement box
typedef struct cql_boxed_stmt *cql_boxed_stmt_ref;
typedef struct cql_boxed_stmt {
  cql_type base;
  sqlite3_stmt *_Nullable stmt;
} cql_boxed_stmt;
```

The same applies to blobs, and they also have a couple of additional helper
macros used to retrieve information. Blobs also come with hash and equality
functions.

```c
// builtin blob
typedef struct cql_blob *cql_blob_ref;
typedef struct cql_blob {
  cql_type base;
  const void *_Nonnull ptr;
  cql_int32 size;
} cql_blob;
#define cql_blob_retain(object) cql_retain((cql_type_ref)object);
#define cql_blob_release(object) cql_release((cql_type_ref)object);
cql_blob_ref _Nonnull cql_blob_ref_new(const void *_Nonnull data, cql_int32 size);
#define cql_get_blob_bytes(data) (data->ptr)
#define cql_get_blob_size(data) (data->size)
cql_hash_code cql_blob_hash(cql_blob_ref _Nullable str);
cql_bool cql_blob_equal(cql_blob_ref _Nullable blob1, cql_blob_ref _Nullable blob2);
```

String references are the same as the others but they have many more functions
associated with them.

```c
// builtin string
typedef struct cql_string *cql_string_ref;
typedef struct cql_string {
  cql_type base;
  const char *_Nullable ptr;
} cql_string;
cql_string_ref _Nonnull cql_string_ref_new(const char *_Nonnull cstr);
#define cql_string_retain(string) cql_retain((cql_type_ref)string);
#define cql_string_release(string) cql_release((cql_type_ref)string);
```

The compiler uses the string literal macro to generate a named string
literal. You determine the implementation of these literals right here.

```c
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
```

Strings have various comparison and hashing functions. It's worth noting that
blobs also possess a hash function.

```c
int cql_string_compare(cql_string_ref _Nonnull s1, cql_string_ref _Nonnull s2);
cql_hash_code cql_string_hash(cql_string_ref _Nullable str);
cql_bool cql_string_equal(cql_string_ref _Nullable s1, cql_string_ref _Nullable s2);
int cql_string_like(cql_string_ref _Nonnull s1, cql_string_ref _Nonnull s2);
```

Strings can be converted from their reference form to standard C form using
these macros. It's important to note that temporary allocations are possible
with these conversions, but the standard implementation typically doesn't
require any allocation. It stores UTF-8 in the string pointer, making it readily
available.

```c
#define cql_alloc_cstr(cstr, str) const char *_Nonnull cstr = (str)->ptr
#define cql_free_cstr(cstr, str) 0
```

The macros for result sets offer somewhat less flexibility. The primary
customization available here is adding additional fields to the "meta"
structure. This structure requires those key fields because it's created by the
compiler. However, the API used to create a result set can be any object of your
choice. It only needs to respond to the `get_meta`, `get_data`, and `get_count`
APIs, which you can map as desired. In principle, there could have been a macro
to create the "meta" as well (pull requests for this are welcome), but it's
quite cumbersome for minimal benefit. The advantage of defining your own "meta"
is that you can utilize it to add additional custom APIs to your result set that
might require some storage.

The additional API `cql_result_set_note_ownership_transferred(result_set)` is
employed when transferring ownership of the buffers from CQL's universe. For
instance, if JNI or Objective C absorbs the result. The default implementation
is a no-op.

```c
// builtin result set
typedef struct cql_result_set *cql_result_set_ref;

typedef struct cql_result_set_meta {
 ...
}

typedef struct cql_result_set {
  cql_type base;
  cql_result_set_meta meta;
  cql_int32 count;
  void *_Nonnull data;
} cql_result_set;

#define cql_result_set_type_decl(result_set_type, result_set_ref) \
  typedef struct _##result_set_type *result_set_ref;

cql_result_set_ref _Nonnull cql_result_set_create(
  void *_Nonnull data,
  cql_int32 count,
  cql_result_set_meta meta);

#define cql_result_set_retain(result_set) cql_retain((cql_type_ref)result_set);
#define cql_result_set_release(result_set) cql_release((cql_type_ref)result_set);
#define cql_result_set_note_ownership_transferred(result_set)
#define cql_result_set_get_meta(result_set) (&((cql_result_set_ref)result_set)->meta)
#define cql_result_set_get_data(result_set) ((cql_result_set_ref)result_set)->data
#define cql_result_set_get_count(result_set) ((cql_result_set_ref)result_set)->count
```

### Mocking

The CQL "run test" needs to do some mocking. This bit is here for that test. If
you want to use the run test with your version of `cqlrt` you'll need to define
a shim for `sqlite3_step` that can be intercepted. This probably isn't going to
come up.

```c
#ifdef CQL_RUN_TEST
#define sqlite3_step mockable_sqlite3_step
SQLITE_API cql_code mockable_sqlite3_step(sqlite3_stmt *_Nonnull);
#endif
```

### Profiling

If you wish to support profiling, you can implement `cql_profile_start` and
`cql_profile_stop` to perform custom actions. The provided CRC uniquely
identifies a procedure (which you can log), while the `index` parameter provides
a place to store a handle in your logging system, typically an integer. This
enables you to assign indices to the procedures observed in any given run and
then log them or perform other operations. Notably, no data about parameters is
provided intentionally.

```c
// No-op implementation of profiling
// * Note: we emit the crc as an expression just to be sure that there are no compiler
//   errors caused by names being incorrect.  This improves the quality of the CQL
//   code gen tests significantly.  If these were empty macros (as they once were)
//   you could emit any junk in the call and it would still compile.
#define cql_profile_start(crc, index) (void)crc; (void)index;
#define cql_profile_stop(crc, index)  (void)crc; (void)index;
```

### Encoding of Sensitive Columns

By setting an attribute on any procedure that produces a result set you can
have the selected sensitive values encoded.  If this happens CQL first asks
for the encoder and then calls the encode methods passing in the encoder.
These aren't meant to be cryptographically secure but rather to provide some
ability to prevent mistakes.  If you opt in, sensitive values have to be deliberately
decoded and that provides an audit trail.

The default implementation of all this is a no-op.

```c
// implementation of encoding values. All sensitive values read from sqlite db will
// be encoded at the source. CQL never decode encoded sensitive string unless the
// user call explicitly decode function from code.
cql_object_ref _Nullable cql_copy_encoder(sqlite3 *_Nonnull db);
cql_bool cql_encode_bool(...)
cql_int32 cql_encode_int32(...)
cql_int64 cql_encode_int64(...)
cql_double cql_encode_double(...)
cql_string_ref _Nonnull cql_encode_string_ref_new(...);
cql_blob_ref _Nonnull cql_encode_blob_ref_new(..);
cql_bool cql_decode_bool(...);
cql_int32 cql_decode_int32(...);
cql_int64 cql_decode_int64(...);
cql_double cql_decode_double(...);
cql_string_ref _Nonnull cql_decode_string_ref_new(...);
cql_blob_ref _Nonnull cql_decode_blob_ref_new(...);
```

### The Common Headers

The standard APIs all build on the above, so they should be included last.

Now in some cases the signature of the things you provide in `cqlrt.h` is basically fixed,
so it seems like it would be easier to move the prototypes into `cqlrt_common.h`.
However, in many cases additional things are needed like `declspec` or `export` or
other system specific things.  The result is that `cqlrt.h` is maybe a bit more
verbose that it strictly needs to be.  Also some versions of cqlrt.h choose to
implement some of the APIs as macros...

```c
// NOTE: This must be included *after* all of the above symbols/macros.
#include "cqlrt_common.h"
```

### The `cqlrt_cf` Runtime

In order to use the Objective-C code-gen (`--rt objc`) you need a runtime that has reference
types that are friendly to Objective-C.  For this purpose we created an open-source
version of such a runtime: it can be found in the `sources/cqlrt_cf` directory.
This runtime is also a decent example of how much customization you can do with just
a little code. Some brief notes:

* This runtime really only makes sense on macOS, iOS, or maybe some other place that Core Foundation (`CF`) exists
  * As such its build process is considerably less portable than other parts of the system
* The CQL reference types have been redefined so that they map to:
   * `CFStringRef` (strings)
   * `CFTypeRef` (objects)
   * `CFDataRef` (blobs)
* The key worker functions use `CF`, e.g.
   * `cql_ref_hash` maps to `CFHash`
   * `cql_ref_equal` maps to `CFEqual`
   * `cql_retain` uses `CFRetain` (with a null guard)
   * `cql_release` uses `CFRelease` (with a null guard)
* Strings use `CF` idioms, e.g.
   * string literals are created with `CFSTR`
   * C strings are created by using `CFStringGetCStringPtr` or `CFStringGetCString` when needed

Of course, since the meaning of some primitive types has changed, the contract to the CQL generated
code has changed accordingly.  For instance:

* procedures compiled against this runtime expect string arguments to be `CFStringRef`
* result sets provide `CFStringRef` values for string columns

The consequence of this is that the Objective-C code generation `--rt objc` finds friendly
contracts that it can freely convert to types like `NSString *` which results in
seamless integration with the rest of an Objective-C application.

Of course the downside of all this is that the `cqlrt_cf` runtime is less portable.  It can only go
where `CF` exists.  Still, it is an interesting demonstration of the flexibility of the system.

The system could be further improved by creating a custom result type (e.g. `--rt c_cf`) and using
some of the result type options for the C code generation. For instance, the compiler could do these things:

  * generate `CFStringRef foo;` instead of `cql_string_ref foo;` for declarations
  * generate `SInt32 an_integer` instead of `cql_int32 an_integer`

Even though `cqlrt_cf` is already mapping `cql_int32` to something compatible with `CF`,
making such changes would make the C output a little bit more `CF` idiomatic. This educational
exercise could probably be completed in just a few minutes by interested readers.

The `make.sh` file in the `sources/cqlrt_cf` directory illustrates how to get CQL to use
this new runtime.  The demo itself is a simple port of the code in [Appendix 10](./appendices/10_working_example.md).

### The `cqlrt.lua` Runtime

Obviously even the generic functions of `cqlrt_common.c` are not applicable to Lua. The included
`cqlrt.lua` runtime provides methods that are isomorphic to the ones in the C runtime, usually
even with identical names.  It has made fairly simple choices about how to encode a result
set.  How to profile (it doesn't) and other such things.  These choices can be changed by
replacing `cqlrt.lua` in your environment.

### Recap

The CQL runtime, `cqlrt.c`, is intended to be replaced.  The version that ships with the distribution
is a simple, portable implementation that is single threaded. Serious users of CQL will likely
want to replace the default version of the runtime with something more tuned to their use case.

Topics covered included:

* contract, error, and tracing macros
* how value types are defined
* how reference types are defined
* mocking (for use in a test suite)
* profiling
* encoding of sensitive columns
* boxing statements
* the `cqlrt_cf` runtime

As with the other parts, no attempt was made to cover every detail.  That is
best done by reading the source code.
