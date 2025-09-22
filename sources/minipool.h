/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#pragma once

typedef struct minipool {
  struct minipool *_Nullable next;  // Singly-linked list of prior blocks; LIFO growth preserves recent locality.
  char *_Nullable bytes;            // Base pointer for this block so we can free without tracking sub-allocations.
  char *_Nullable current;          // Bump pointer; simple arithmetic beats freelist for append-only lifetime.
  uint32_t available;               // Remaining capacity; avoids recomputing (end - current) each allocation.
} minipool;

// 64K default block balances syscall pressure vs. internal fragmentation for typical
// compile workloads (lots of tiny AST nodes). Too small => many mallocs; too large => cache churn.
#define MINIBLOCK (1024*64)

cql_noexport void minipool_open(minipool *_Nullable *_Nonnull pool);
cql_noexport void minipool_close(minipool *_Nullable *_Nonnull pool);

// Single allocation API; no free. Consumers rely on closing whole pool. Alignment handled internally.
cql_noexport void *_Nonnull minipool_alloc(minipool *_Nonnull pool, uint32_t needed);

// lazy free service for misc pool contents

typedef struct lazy_free {
  struct lazy_free *_Nullable next;                   // Stack-like list; push order irrelevant for teardown correctness.
  void *_Nullable context;                            // Opaque resource handle passed to teardown.
  void (*_Nonnull teardown)(void *_Nullable context); // Function pointer allows heterogenous cleanup without RTTI.
} lazy_free;

// for deferred free of things that need cleanup (e.g. symtab)
cql_noexport void add_lazy_free(lazy_free *_Nonnull p);
cql_noexport void run_lazy_frees(void);

// convenience macros for allocating from any minipool
// Convenience macros hide cast noise and centralize sizeof usage preventing mismatched counts.
#define _pool_new(p, x) ((x*)minipool_alloc(p, (int32_t)sizeof(x)))
#define _pool_new_array(p, x, c) ((x*)minipool_alloc(p, c*(int32_t)sizeof(x)))

// almost everything ends up in the AST pool, so we have a macro for it
// AST dominates allocations; dedicated macros keep call sites concise and signal lifetime.
#define _ast_pool_new(x) _pool_new(ast_pool, x)
#define _ast_pool_new_array(x, c) _pool_new_array(ast_pool, x, c)

cql_data_decl( minipool *_Nullable ast_pool );
cql_data_decl( minipool *_Nullable str_pool );
