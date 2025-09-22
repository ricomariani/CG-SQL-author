/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#pragma once

#include "bytebuf.h"
#include "charbuf.h"

// Minimal entry shape keeps symbol table generic; keys are borrowed, not owned.
// Each symbol table entry is a key/value pair. Key lifetime is managed by upstream
// allocators (AST pools, cached strings). We deliberately avoid copying keys to
// minimize churn and leverage arena lifetime. Value is void* so callers can attach
// AST nodes, metadata structs, nested symbol tables, or small buffers uniformly.
typedef struct symtab_entry {
 const char *_Nullable sym;
 void *_Nullable val;
} symtab_entry;

// The symbol table itself is the usual close hash table form
// we need the used count and the capacity to manage it
// additionally the hash function and the comparision function
// can be changed.  There is a teardown function that can be
// provided to clean up the payloads when the table is deleted.
// The normal cleanup just deletes the payload array.  The
// strings are assumed to be long-lived and owned by something else
// like the AST.
typedef struct symtab {
  uint32_t count;
  uint32_t capacity;
  symtab_entry *_Nullable payload;
  uint32_t (*_Nonnull hash)(const char *_Nonnull str);
  int32_t (*_Nonnull cmp)(const char *_Nonnull c1, const char *_Nonnull c2);
  void (*_Nullable teardown)(void *_Nonnull val);
} symtab;

// Tiny initial size (4) keeps footprint minimal for the majority of tables
// that never grow beyond a handful of entries (many internal maps are <3). Growth
// doubles capacity so amortized insertion is still O(1). Load factor 0.75 strikes
// balance: higher factors increase probe length variance; lower wastes memory.
#define SYMTAB_INIT_SIZE 4
#define SYMTAB_LOAD_FACTOR .75

cql_noexport symtab *_Nonnull symtab_new_case_sens(void);
cql_noexport symtab *_Nonnull symtab_new(void);
cql_noexport void symtab_delete(symtab *_Nonnull syms);

// symtab_add returns false if symbol existed (no overwrite) so callers can cheaply
// detect duplicates without extra lookup. Overwrite semantics are intentionally absent
// to surface logical duplication early.
cql_noexport bool_t symtab_add(symtab *_Nonnull syms, const char *_Nonnull sym_new, void *_Nullable val_new);

// symtab_find returns entry pointer not value so caller may mutate payload in place
// (e.g., fill struct lazily) without re-insertion bookkeeping.
cql_noexport symtab_entry *_Nullable symtab_find(symtab *_Nullable syms, const char *_Nonnull sym_needed);

// Special case support for symbol table of byte buffers, char buffers, nested symbol tables
// these are commmon.
cql_noexport bytebuf *_Nonnull symtab_ensure_bytebuf(symtab *_Nonnull syms, const char *_Nonnull sym_new);
cql_noexport void symtab_append_bytes(symtab *_Nonnull syms, const char *_Nonnull sym_new, const void *_Nullable bytes, size_t count);
cql_noexport symtab *_Nonnull symtab_ensure_symtab(symtab *_Nonnull syms, const char *_Nonnull name);
cql_noexport bool_t symtab_add_symtab(symtab *_Nonnull syms, CSTR _Nonnull name, symtab *_Nonnull data);
cql_noexport charbuf *_Nonnull symtab_ensure_charbuf(symtab *_Nonnull syms, const char *_Nonnull sym_new);

cql_noexport int default_symtab_comparator(symtab_entry *_Nonnull entry1, symtab_entry *_Nonnull entry2);

// Copy-then-sort avoids in-place reordering which would break probing invariants.
// Sorting creates deterministic output (e.g., header generation) without altering live table.
cql_noexport symtab_entry *_Nonnull symtab_copy_sorted_payload(symtab *_Nonnull syms, int (*_Nonnull comparator)(symtab_entry *_Nonnull entry1, symtab_entry *_Nonnull entry2));

#define SYMTAB_CLEANUP(x)  if (x) { symtab_delete(x); x = NULL; }
