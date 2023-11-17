#include <stdio.h>
#include "cqlhelp.h"

// It will finalize the actual SQLite statement.  i.e. this is a destructor/finalizer
static void cql_file_finalize(void *_Nonnull data) {
  // note that we use cql_finalize_stmt because it can be and often is
  // intercepted to allow for cql statement pooling.
  FILE *f = (FILE *)data;
  if (f) {
    fclose(f);
  }
}

static FILE *_Nullable cql_file_get(cql_object_ref _Nonnull file_ref) {
  return (FILE *)_cql_generic_object_get_data(file_ref);
}

cql_object_ref cql_fopen(cql_string_ref _Nonnull name, cql_string_ref mode) {
  cql_alloc_cstr(n, name);
  cql_alloc_cstr(m, mode);

  FILE *f = fopen(n, m);

  cql_free_cstr(m, mode);
  cql_free_cstr(n, name);
  if (f) {
    return _cql_generic_object_create(f, cql_file_finalize);
  }
  else {
    return NULL;
  }
}

cql_string_ref readline_object_file(cql_object_ref file_ref) {
  FILE *f = cql_file_get(file_ref);
  char buf[4096];
  if (fgets(buf, sizeof(buf), f)) {
     int len = strlen(buf);
     if (len) buf[len-1] = 0;
     return cql_string_ref_new(buf);
  }
  else {
     return NULL;
  }
}

cql_string_ref after_text(cql_string_ref text, cql_int32 index) {
  cql_string_ref result = NULL;
  if (text) {
    cql_alloc_cstr(t, text);
    result = cql_string_ref_new(t + index);
    cql_free_cstr(t, text);
  }

  return result;
}

cql_object_ref create_arglist(int argc, char **argv) {
  cql_object_ref arglist = create_cql_string_list();

  for (int i = 0; i < argc; i++) {
    cql_string_ref str_ref = cql_string_ref_new(argv[i]);
    add_object_cql_string_list(arglist, str_ref);
    // ownership transfered to the list
    cql_string_release(str_ref);
  }

  return arglist;
}

cql_int32 atoi_at_text(cql_string_ref text, cql_int32 index) {
  cql_int32 result = 0;
  if (text) {
    cql_alloc_cstr(t, text);
    result = atoi(t + index);
    cql_free_cstr(t, text);
  }
  return result;
}

cql_int32 len_text(cql_string_ref text) {
  cql_int32 result = 0;
  if (text) {
    cql_alloc_cstr(t, text);
    result = strlen(t);
    cql_free_cstr(t, text);
  }
  return result;
}

cql_int32 octet_text(cql_string_ref text, cql_int32 index) {
  cql_int32 result = 0;
  if (text) {
    cql_alloc_cstr(t, text);
    result = t[index];
    cql_free_cstr(t, text);
  }
  return result;
}

cql_bool starts_with_text(cql_string_ref _Nonnull haystack, cql_string_ref _Nonnull needle) {
  cql_alloc_cstr(h, haystack);
  cql_alloc_cstr(n, needle);

  int len = strlen(n);
  cql_bool result = strncmp(h, n, len) == 0;

  cql_free_cstr(n, needle);
  cql_free_cstr(h, haystack);

  return result;
}

cql_int32 index_of_text(cql_string_ref _Nonnull haystack, cql_string_ref _Nonnull needle) {
  cql_int32 result = -1;

  cql_alloc_cstr(h, haystack);
  cql_alloc_cstr(n, needle);

  const char *loc = strstr(h, n);

  if (loc) {
    result = loc - h;
  }

  cql_free_cstr(n, needle);
  cql_free_cstr(h, haystack);

  return result;
}

cql_bool contains_at_text(cql_string_ref _Nonnull haystack, cql_string_ref _Nonnull needle, cql_int32 index) {
  cql_alloc_cstr(h, haystack);
  cql_alloc_cstr(n, needle);

  int len = strlen(n);
  cql_bool result = strncmp(h + index, n, len) == 0;

  cql_free_cstr(n, needle);
  cql_free_cstr(h, haystack);

  return result;
}
