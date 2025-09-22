/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#include "cql.h"
#include "symtab.h"
#include "bytebuf.h"
#include "charbuf.h"

static void symtab_rehash(symtab *syms);

static void set_payload(symtab *syms) {
  // Zeroed allocation ensures empty-slot test is just pointer NULL check; no
  // explicit 'in_use' bit needed. calloc used over malloc+memset for clarity.
  syms->payload = (symtab_entry *)calloc(syms->capacity, sizeof(symtab_entry));
}


// Standard hash and comparison functions for strings

static uint32_t hash_case_insens(const char *sym) {
  const unsigned char *bytes = (const unsigned char *)sym;
  uint64_t hash = 0;
  while (*bytes) {
    unsigned char byte = *bytes | 0x20;
    hash = ((hash << 5) | (hash >> 27)) ^ byte;
    bytes++;
  }
  return (uint32_t)(hash ^ (hash >>32));
}

static int32_t cmp_case_insens(const char *s1, const char *s2) {
  return (int32_t)StrCaseCmp(s1, s2);
}

static int32_t cmp_case_sens(const char *s1, const char *s2) {
  return (int32_t)strcmp(s1, s2);
}

static uint32_t hash_case_sens(const char *sym) {
  const unsigned char *bytes = (const unsigned char *)sym;
  uint64_t hash = 0;
  while (*bytes) {
    unsigned char byte = *bytes;
    hash = ((hash << 5) | (hash >> 27)) ^ byte;
    bytes++;
  }
  return (uint32_t)(hash ^ (hash >>32));
}

// The most normal confuguration of the symbol table is case insensitive
// the hash and comparison function are created for that case.  The
// normal teardown function is no-teardown as all items are borrowed.
// The most common case is that the names are strings in the AST
// and the values are AST pointer, all of which are durable from
// the perspective of the symbol table.
cql_noexport symtab *symtab_new() {
  symtab *syms = _new(symtab);
  syms->count = 0;
  syms->capacity = SYMTAB_INIT_SIZE;
  syms->hash = hash_case_insens;
  syms->cmp = cmp_case_insens;
  syms->teardown = NULL;
  set_payload(syms);
  return syms;
}

// This is the case sensitive version of the symbol table
// The default is case insensitive because nearly every
// lookup is case insensitive.
cql_noexport symtab *symtab_new_case_sens() {
  symtab *syms = symtab_new();
  syms->hash = hash_case_sens;
  syms->cmp = cmp_case_sens;
  return syms;
}

// If there is a teardown function, it is called for each payload.
// Specifically the *values* of each payload.  The strings are
// assumed to be long-lived and owned by something else.
cql_noexport void symtab_delete(symtab *syms) {
  if (syms->teardown) {
    for (uint32_t i = 0; i < syms->capacity; i++) {
      void *val = syms->payload[i].val;
      if (val) {
        syms->teardown(val);
      }
    }
  }
  free(syms->payload);
  free(syms);
}

// Adding a new symbol to the table is a simple matter of finding an empty slot
// and populating it.  If the table is too full we rehash in a bigger table.
// We a least have room to add the new symbol.  The hashing algorithm is
// the usual close hash table form with linear probing.  The comparison
// and hashing functions can be changed at the time the table is created.
// But if you change them after inserting anything you will have to rehash the table.
// Generally, this is a really bad idea.

// We avoid tombstones and deletions altogether—symbol tables are append-only for the
// compiler's lifetime. This simplifies rehash (no skip logic) and keeps probe chains
// short/predictable. Rehash threshold uses load factor to keep worst-case probe small.
cql_noexport bool_t symtab_add(symtab *syms, const char *sym_new, void *val_new) {
  uint32_t hash = syms->hash(sym_new);
  uint32_t offset = hash % syms->capacity;
  symtab_entry *payload = syms->payload;

  for (;;) {
    // We search until we find an empty slot or a matching symbol
    // one of the two will happen for sure because the table is never full.
    const char *sym = payload[offset].sym;
    if (!sym) {
      payload[offset].sym = sym_new;
      payload[offset].val = val_new;

      syms->count++;
      if (syms->count > syms->capacity * SYMTAB_LOAD_FACTOR) {
        symtab_rehash(syms);
      }

      // did not find the symbol, return true indicating we added it
      return true;
    }

    // found the symbol, return false indicated we did not add
    if (!syms->cmp(sym, sym_new)) {
      return false;
    }

    // wrap the offset around, we don't use modulus because it
    // isn't a power of two necessarily.  This form can compile
    // into a conditional store.
    offset++;
    if (offset >= syms->capacity) {
      offset = 0;
    }
  }
}

// The find operation is a simple matter of hashing the symbol and then
// doing a linear probe until we find the symbol or an empty slot.
// We return the payload  which allows us to modify the stored value
// if we want to.
cql_noexport symtab_entry *symtab_find(symtab *syms, const char *sym_needed) {
  if (!syms) {
    return NULL;
  }

  uint32_t hash = syms->hash(sym_needed);
  uint32_t offset = hash % syms->capacity;
  symtab_entry *payload = syms->payload;

  for (;;) {
    const char *sym = syms->payload[offset].sym;
    if (!sym) {
      return NULL;
    }

    if (!syms->cmp(sym, sym_needed)) {
      return &payload[offset];
    }

    offset++;
    if (offset >= syms->capacity) {
      offset = 0;
    }
  }
}

// When the table is too full we rehash in a bigger table.
// To do this extract the guts of the table and then load
// it with new, bigger guts, that are empty.  Then we
// insert the values from the old guts.  This is a liner
// time operation and it's the simplest way spread the
// values to the new table.  When this is done we
// can delete the old guts.
static void symtab_rehash(symtab *syms) {
  uint32_t old_capacity = syms->capacity;
  symtab_entry *old_payload = syms->payload;

  syms->count = 0;
  syms->capacity *= 2;
  set_payload(syms);

  for (uint32_t i = 0; i < old_capacity; i++) {
    const char *sym = old_payload[i].sym;
    if (!sym) {
      continue;
    }

    symtab_add(syms, old_payload[i].sym, old_payload[i].val);
  }

  free(old_payload);
}

cql_noexport int default_symtab_comparator(symtab_entry *entry1, symtab_entry *entry2) {
  return strcmp(entry1->sym, entry2->sym);
}

// This helper function makes a copy of the payload entries and then sorts them
// according to the provided comparator. Any nulls in the payload array are
// skipped.
//
// Many generated artifacts (e.g., schema dumps) need stable ordering
// independent of hash table capacity evolution; copying only live entries then
// qsort yields reproducible output.
cql_noexport symtab_entry *symtab_copy_sorted_payload(
  symtab *syms,
  int (*comparator)(symtab_entry *entry1, symtab_entry *entry2))
{
  uint32_t count = syms->count;
  size_t size = sizeof(symtab_entry);
  symtab_entry *sorted = calloc(count, size);
  int32_t found = 0;
  for (uint32_t i = 0; i < syms->capacity; i++) {
    // skip the null syms in our copy
    if (syms->payload[i].sym) {
      sorted[found++] = syms->payload[i];
    }
  }

  // now sort the nonnull values
  qsort(sorted, count, size, (int (*)(const void *, const void *))comparator);
  return sorted;
}

// first special case teardown
//  * a symbol table with payload of symbol tables
static void symtab_teardown(void *val) {
  // Delegated teardown allows arbitary cleanup. For instance nested symbol
  // tables to own their children while preserving generic symtab_delete logic.
  symtab_delete(val);
}

// second special case teardown
//  * a symbol table with payload of bytebuffers
static void bytebuf_teardown(void *val) {
  // Ensure bytebuf_close runs before freeing raw struct (ordering matters for internal invariants).
  bytebuf_close((bytebuf*)val);
  free(val);
}

// third special case teardown
//  * a symbol table with payload of character buffers
static void charbuf_teardown(void *val) {
  // bclose handles any internal allocations; then struct freed.
  bclose((charbuf*)val);
  free(val);
}


// This helper is just for making a symbol table that holds symbol tables.
// It sets the cleanup function to be one that deletes symbol tables in the payload.
// This flavor create the table at the named slot for you to use.
cql_noexport symtab *_Nonnull symtab_ensure_symtab(symtab *syms, const char *name) {
  syms->teardown = symtab_teardown;
  symtab_entry *entry = symtab_find(syms, name);

  symtab *value = entry ? (symtab *)entry->val : NULL;
  if (entry == NULL) {
    value = symtab_new();
    symtab_add(syms, name, value);
  }
  return value;
}

// This helper is just for making a symbol table that holds symbol tables
// we don't have to do anything special except set the cleanup function
// to one that deletes symbol tables in the payload.
cql_noexport bool_t symtab_add_symtab(symtab *syms, CSTR name, symtab *data) {
  syms->teardown = symtab_teardown;
  return symtab_add(syms, name, (void*)data);
}

// This helper ensures that a byte buffer is present for the given symbol and
// returns it.  If the symbol value is not present it creates a new byte buffer
// for that slot. The teardown function is changed to free the byte buffers.
// Mixing different value types in the same symbol table is a bad idea.
cql_noexport bytebuf *_Nonnull symtab_ensure_bytebuf(symtab *syms, const char *sym_new) {
  syms->teardown = bytebuf_teardown;
  symtab_entry *entry = symtab_find(syms, sym_new);

  bytebuf *buf = entry ? (bytebuf *)entry->val : NULL;
  if (entry == NULL) {
    buf = _new(bytebuf);
    bytebuf_open(buf);
    symtab_add(syms, sym_new, buf);
  }
  return buf;
}

// This helper uses the above to create a byte buffer for the given symbol
// and then appends the given bytes to that  buffer.
cql_noexport void symtab_append_bytes(symtab *syms, const char *sym_new, const void *bytes, size_t count) {
  bytebuf *buf = symtab_ensure_bytebuf(syms, sym_new);
  bytebuf_append(buf, bytes, (uint32_t)count);
}

// This is similar to the byte buffer case but for character buffers.  These can
// be written to with charbuf helpers like bprintf and so forth.  Once you do this
// the teardown function is changed to free the char buffers.  Mixing different
// value types in the same symbol table is a bad idea.
cql_noexport charbuf *_Nonnull symtab_ensure_charbuf(symtab *syms, const char *sym_new) {
  syms->teardown = charbuf_teardown;
  symtab_entry *entry = symtab_find(syms, sym_new);
  charbuf *output = entry ? (charbuf *)entry->val : NULL;
  if (!output) {
    // None found, create one
    output = _new(charbuf);
    bopen(output);
    // This buffer doesn't participate in the normal stack of charbufs
    // it will be freed when the symbol table is torn down
    charbuf_open_count--;
    symtab_add(syms, sym_new, output);
  }
  return output;
}
