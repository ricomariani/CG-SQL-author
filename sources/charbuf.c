/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#include "cql.h"
#include "charbuf.h"

cql_data_defn( int32_t charbuf_open_count );
cql_data_defn( pending_charbuf *__charbufs_in_flight; )

//
cql_noexport void release_open_charbufs() {
  while (__charbufs_in_flight) {
    bclose(__charbufs_in_flight->buf);
    __charbufs_in_flight = __charbufs_in_flight->prev;
  }
}

// Initialize the buffer, it will be empty and have no memory allocated. It
// points to the internal buffer.  We track open and closes so we can detect
// leaks.
cql_noexport void bopen(charbuf* b) {
  b->max = CHARBUF_INTERNAL_SIZE;
  b->ptr = &b->internal[0];
  bclear(b);
  charbuf_open_count++;
}

// Free the buffer if it was allocated.  Note that we assume that
// the charbuf itself s on the stack or some such.  The caller
// is responsible for ensuring that the charbuf is released.
cql_noexport void bclose(charbuf *b) {
  if (b->ptr != &b->internal[0]) {
    free(b->ptr);
  }
  b->ptr = NULL;
  b->max = 0;
  b->used = 0;
  charbuf_open_count--;
}

// Clear the buffer, it will be empty but the memory will still be allocated.
cql_noexport void bclear(charbuf *b) {
  // an empty buffer has the null terminator
  b->used = 1;
  b->ptr[0] = 0;
}

// Append a string to the buffer.  The buffer will grow as needed.
// We have to do two passes because we need to know how much space
// to allocate for what we are going to append and the format and arg
// count is arbitrary. We use vsnprintf twice to get the size and then
// to do the actual append.
cql_noexport void vbprintf(charbuf *b, const char *format, va_list args) {
  va_list pass1, pass2;
  va_copy(pass1, args);
  va_copy(pass2, args);

  // invariant is that there is already a null in the buffer
  // we can re-use that one.
  uint32_t avail = b->max - b->used;

  // does not include the trailing null
  uint32_t needed = (uint32_t)vsnprintf(NULL, 0, format, pass1);

  if (needed > avail) {
    b->max += needed + CHARBUF_GROWTH_SIZE;
    char *newptr = _new_array(char, b->max);

    // note that b->used includes the current null terminator
    memcpy(newptr, b->ptr, b->used);
    if (b->ptr != &b->internal[0]) {
      free(b->ptr);
    }
    avail = b->max - b->used;
    b->ptr = newptr;
  }

  // clobber starting from the current null, there is one more byte
  // than avail available to vsnprintf because we're backing off to
  // globber the old null.  The result is always null terminated.
  vsnprintf(b->ptr + b->used - 1, avail + 1, format, pass2);
  b->used += needed;

  va_end(pass1);
  va_end(pass2);
}

// this wraps the above with a va_list, this is the normal entry point
cql_noexport void bprintf(charbuf *b, const char *format, ...) {
  va_list args;
  va_start(args, format);
  vbprintf(b, format, args);
  va_end(args);
}

// this uses a temporary buffer to format the string and then
// duplicates it onto the heap with Strdup.  Note that this
// particular Strdup uses our allocation pools that are bulk
// deallocated at the end of the run. This string is durable.
cql_noexport CSTR dup_printf(const char *format, ...) {
  CSTR result;
  va_list args;
  va_start(args, format);
  CHARBUF_OPEN(tmp);
  vbprintf(&tmp, format, args);
  result = Strdup(tmp.ptr);
  CHARBUF_CLOSE(tmp);
  va_end(args);
  return result;
}

// Writes one character into the buffer, the buffer will grow as needed.
cql_noexport void bputc(charbuf *b, char c) {
  // invariant is that there is already a null in the buffer
  // we can re-use that one.
  uint32_t avail = b->max - b->used;

  if (avail < 1) {
    b->max += CHARBUF_GROWTH_SIZE;
    char *newptr = _new_array(char, b->max);

    // note that b->used includes the current null terminator
    memcpy(newptr, b->ptr, b->used);
    if (b->ptr != &b->internal[0]) {
      free(b->ptr);
    }
    avail = b->max - b->used;
    b->ptr = newptr;
  }

  b->ptr[b->used-1] = c; // clobber the previous null
  b->ptr[b->used++] = 0; // put a new null in place, for sure room for this
}

// Indents the input buffer by the specified number of spaces
// and puts the result into the output buffer.  This is used to format
// source code with unindented fragments getting indended after they are
// created and put into the main buffer.  For instance a statement list
// might get formatted with no indentation, once the whole list is done
// it can be indented as a block and inserted into the main buffer.
cql_noexport void bindent(charbuf *output, charbuf *input, int32_t indent) {
  if (indent == 0) {
    bprintf(output, "%s", input->ptr);
    return;
  }

  CHARBUF_OPEN(spaces);
  for (int32_t i = 0; i < indent; i++) bputc(&spaces, ' ');

  const char *p = input->ptr;

  for (;;) {
    if (!*p) break;

    // skip indenting blank lines
    if (*p != '\n') {
      bprintf(output, "%s", spaces.ptr);
    }

    while (*p) {
      char ch = *p++;
      bputc(output, ch);
      if (ch == '\n') break;
    }
  }

  CHARBUF_CLOSE(spaces);
}

// "Reads" a line from the incoming CSTR modifying it to the
// point to the start of the next line. The output buffer
// is cleared first and ends with a copy of the one line.
cql_noexport bool_t breadline(charbuf *output, CSTR *data) {
  // clean buffer
  bclear(output);

  CSTR p = *data;

  // no more lines
  if (p[0] == '\0') {
    return false;
  }

  // emit up to the next linefeed or end of the buffer, whichever comes first
  for (; *p != '\n' && *p != '\0'; p++) {
    bputc(output, *p);
  }

  // if we ended at a linefeed, skip over that
  if (p[0] == '\n') {
    p++;
  }

  *data = p;
  return true;
}
