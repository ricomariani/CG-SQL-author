/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#pragma once

#include "bytebuf.h"
#include "charbuf.h"

// each symbol table entry is a key/value pair
// the key is always a char *, the value can be anything
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
  void (*_Nullable teardown)(CqlState* CS, void *_Nonnull val);
} symtab;

#define SYMTAB_INIT_SIZE 4
#define SYMTAB_LOAD_FACTOR .75

cql_noexport symtab *_Nonnull symtab_new_case_sens(void);
cql_noexport symtab *_Nonnull symtab_new(void);
cql_noexport void symtab_delete(CqlState* CS, symtab *_Nonnull syms);
cql_noexport bool_t symtab_add(CqlState* CS, symtab *_Nonnull syms, const char *_Nonnull sym_new, void *_Nullable val_new);
cql_noexport symtab_entry *_Nullable symtab_find(symtab *_Nullable syms, const char *_Nonnull sym_needed);

// Special case support for symbol table of byte buffers, char buffers, nested symbol tables
// these are commmon.
cql_noexport bytebuf *_Nonnull symtab_ensure_bytebuf(CqlState* CS, symtab *_Nonnull syms, const char *_Nonnull sym_new);
cql_noexport void symtab_append_bytes(CqlState* CS, symtab *_Nonnull syms, const char *_Nonnull sym_new, const void *_Nullable bytes, size_t count);
cql_noexport symtab *_Nonnull symtab_ensure_symtab(CqlState* CS, symtab *_Nonnull syms, const char *_Nonnull name);
cql_noexport bool_t symtab_add_symtab(CqlState* CS, symtab *_Nonnull syms, CSTR _Nonnull name, symtab *_Nonnull data);
cql_noexport charbuf *_Nonnull symtab_ensure_charbuf(CqlState* CS, symtab *_Nonnull syms, const char *_Nonnull sym_new);

// patternlint-disable-next-line prefer-sized-ints-in-msys
cql_noexport int default_symtab_comparator(symtab_entry *_Nonnull entry1, symtab_entry *_Nonnull entry2);

// patternlint-disable-next-line prefer-sized-ints-in-msys
cql_noexport symtab_entry *_Nonnull symtab_copy_sorted_payload(symtab *_Nonnull syms, int (*_Nonnull comparator)(symtab_entry *_Nonnull entry1, symtab_entry *_Nonnull entry2));

#define SYMTAB_CLEANUP(x)  if (x) { symtab_delete(CS, x); x = NULL; }
