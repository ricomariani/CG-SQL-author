/*
 * Copyright (c) Joris Garonian and Rico Mariani
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

// This file contains the implementation of the CQL SQLite extension
// helper functions. These functions are used to convert SQLite values
// to CQL types and vice versa so that CQL procedures can be called
// from SQLite queries using the virtual table (and hence table-valued
// function) mechanism.

#include "cql_sqlite_extension.h"
#include "cqlrt.h"

#ifdef CQL_SQLITE_EXT
extern const sqlite3_api_routines *sqlite3_api;
#endif

#define trace_printf(x, ...)
// #define trace_printf printf

// This is used to validate if an incoming argument
// is compatible with the required CQL type.  If the
// argument is not compatible then an error is ultimately
// generated for this call. If you're using CQL to call
// the procedures via declare select function then this
// check happens at compile time but the code can't assume
// this. In fact that is not the normal use case at all
// if you are already in CQL you could just call the proc
// directly, so we have to assume a hostile, or at least
// error-prone caller.
cql_bool is_sqlite3_type_compatible_with_cql_core_type(
  int sqlite_type,
  int8_t cql_core_type,
  cql_bool is_nullable)
{
  if (sqlite_type == SQLITE_NULL && is_nullable) return true;
  if (sqlite_type == SQLITE_NULL && !is_nullable) return false;

  switch (cql_core_type) {
    case CQL_DATA_TYPE_INT32:
    case CQL_DATA_TYPE_INT64:
    case CQL_DATA_TYPE_BOOL:
    case CQL_DATA_TYPE_OBJECT:
      if (sqlite_type == SQLITE_INTEGER) return true;
      break;

    case CQL_DATA_TYPE_DOUBLE:
      if (sqlite_type == SQLITE_FLOAT || sqlite_type == SQLITE_INTEGER) return true;
      break;

    case CQL_DATA_TYPE_STRING:
      if (sqlite_type == SQLITE_TEXT) return true;
      break;

    case CQL_DATA_TYPE_BLOB:
      if (sqlite_type == SQLITE_BLOB) return true;
      break;
  }

  return false;
}

// Below are the conversion functions for getting a cql native type from a sqlite_value

cql_bool resolve_not_null_bool_from_sqlite3_value(sqlite3_value *_Nonnull value) {
  return (cql_bool)sqlite3_value_int(value);
}

cql_double resolve_not_null_real_from_sqlite3_value(sqlite3_value *_Nonnull value) {
  return (cql_double)sqlite3_value_double(value);
}

cql_int32 resolve_not_null_integer_from_sqlite3_value(sqlite3_value *_Nonnull value) {
  return (cql_int32)sqlite3_value_int(value);
}

cql_int64 resolve_not_null_long_from_sqlite3_value(sqlite3_value *_Nonnull value) {
  return (cql_int64)sqlite3_value_int64(value);
}

cql_nullable_double resolve_nullable_real_from_sqlite3_value(sqlite3_value *_Nonnull value) {
  if (sqlite3_value_type(value) == SQLITE_NULL) return (cql_nullable_double){ .is_null = true, .value = 0 };
  return (cql_nullable_double){ .is_null = false, .value = (cql_double)sqlite3_value_double(value) };
}

cql_nullable_int32 resolve_nullable_integer_from_sqlite3_value(sqlite3_value *_Nonnull value) {
  if (sqlite3_value_type(value) == SQLITE_NULL) return (cql_nullable_int32){ .is_null = true, .value = 0 };
  return (cql_nullable_int32){ .is_null = false, .value = (cql_int32)sqlite3_value_int(value) };
}

cql_nullable_int64 resolve_nullable_long_from_sqlite3_value(sqlite3_value *_Nonnull value) {
  if (sqlite3_value_type(value) == SQLITE_NULL) return (cql_nullable_int64){ .is_null = true, .value = 0 };
  return (cql_nullable_int64){ .is_null = false, .value = (cql_int64)sqlite3_value_int64(value) };
}

cql_nullable_bool resolve_nullable_bool_from_sqlite3_value(sqlite3_value *_Nonnull value) {
  if (sqlite3_value_type(value) == SQLITE_NULL) return (cql_nullable_bool){ .is_null = true, .value = false };
  return (cql_nullable_bool){ .is_null = false, .value = (cql_bool)sqlite3_value_int(value) };
}

cql_string_ref _Nullable resolve_text_from_sqlite3_value(sqlite3_value *_Nonnull value) {
  if (sqlite3_value_type(value) == SQLITE_NULL) return NULL;

  const char *text = (const char *)sqlite3_value_text(value);

  if (!text) return NULL;

  return cql_string_ref_new(text);
}

cql_blob_ref _Nullable resolve_blob_from_sqlite3_value(sqlite3_value *_Nonnull value) {
  if (sqlite3_value_type(value) == SQLITE_NULL) return NULL;

  const void *blob = sqlite3_value_blob(value);

  if (!blob) return NULL;

  return cql_blob_ref_new(blob, (cql_uint32)sqlite3_value_bytes(value));
}

cql_object_ref _Nullable resolve_object_from_sqlite3_value(sqlite3_value *_Nonnull value) {
  // Not supported yet — See https://www.sqlite.org/bindptr.html
  if (sqlite3_value_type(value) == SQLITE_NULL) return NULL;

  return (cql_object_ref)sqlite3_value_pointer(value, "pointer_type");
}

// below are the function for setting a SQlite result using a cql type

void sqlite3_result_cql_nullable_bool(sqlite3_context *_Nonnull context, cql_nullable_bool value) {
  if (value.is_null) {
    sqlite3_result_null(context);
    return;
  }

  sqlite3_result_int(context, value.value);
}

void sqlite3_result_cql_nullable_int(sqlite3_context *_Nonnull context, cql_nullable_int32 value) {
  if (value.is_null) {
    sqlite3_result_null(context);
    return;
  }

  sqlite3_result_int(context, value.value);
}

void sqlite3_result_cql_nullable_int64(sqlite3_context *_Nonnull context, cql_nullable_int64 value) {
  if (value.is_null) {
    sqlite3_result_null(context);
    return;
  }

  sqlite3_result_int64(context, value.value);
}

void sqlite3_result_cql_nullable_double(sqlite3_context *_Nonnull context, cql_nullable_double value) {
  if (value.is_null) {
    sqlite3_result_null(context);
    return;
  }

  sqlite3_result_double(context, value.value);
}

void sqlite3_result_cql_pointer(sqlite3_context *_Nonnull context, void *value) {
  // Not supported yet — See https://www.sqlite.org/bindptr.html
  sqlite3_result_null(context);
}

void sqlite3_result_cql_blob(sqlite3_context *_Nonnull context, cql_blob_ref value) {
  if (!value) {
    sqlite3_result_null(context);
    return;
  }

  const void *bytes = cql_get_blob_bytes(value);
  cql_uint32 size = cql_get_blob_size(value);
  sqlite3_result_blob(context, bytes, size, SQLITE_TRANSIENT);
}

void sqlite3_result_cql_text(sqlite3_context *_Nonnull context, cql_string_ref value) {
  if (!value) {
    sqlite3_result_null(context);
    return;
  }

  cql_alloc_cstr(c_str, value);
  sqlite3_result_text(context, c_str, -1, SQLITE_TRANSIENT);
  cql_free_cstr(c_str, value);
}

// This is the function that SQLite calls to create the virtual table.
// We give it the table declaration provided to us and store the function
// pointer in the vtab structure.  We will use the function pointer
// later to actually get the result set we need so provide values.
static int cql_rowset_connect(
  sqlite3 *db,
  void *aux,
  int argc,
  const char *const *argv,
  sqlite3_vtab **ppVtab,
  char **pzErr)
{
  trace_printf("connect\n");
  cql_rowset_aux_init *pAux = (cql_rowset_aux_init *)aux;

  const char *table_decl = pAux->table_decl;
  if (!table_decl) {
    *pzErr = sqlite3_mprintf("Missing table declaration");
    return SQLITE_ERROR;
  }

  // Declare the table structure (column names)
  if (sqlite3_declare_vtab(db, table_decl) != SQLITE_OK) {
    *pzErr = sqlite3_mprintf("Unable to declare vtab: %s", sqlite3_errmsg(db));
    return SQLITE_ERROR;
  }

  cql_rowset_table *pTab = sqlite3_malloc(sizeof(cql_rowset_table));
  if (!pTab) return SQLITE_NOMEM;
  memset(pTab, 0, sizeof(cql_rowset_table));

  pTab->func = pAux->func;
  pTab->db = db;
  *ppVtab = (sqlite3_vtab *)pTab;
  return SQLITE_OK;
}

// Here we can only allocate the cursor structure and fill in the db pointer
// Everything else will need to wait until xFilter is called.  The call sequence
// is xConnect
//   -> xBestIndex -> xOpen -> xFilter
//   -> xEof -> xColumn -> xNext
//   -> xEof -> xColumn -> xNext
//   -> xEof -> xClose
// -> xDisconnect
static int cql_rowset_open(sqlite3_vtab *pVtab, sqlite3_vtab_cursor **ppCursor) {
  trace_printf("open\n");
  cql_rowset_cursor *pCur = sqlite3_malloc(sizeof(cql_rowset_cursor));
  if (!pCur) return SQLITE_NOMEM;
  memset(pCur, 0, sizeof(cql_rowset_cursor));

  cql_rowset_table *pTab = (cql_rowset_table *)pVtab;
  pCur->db = pTab->db;

  *ppCursor = (sqlite3_vtab_cursor *)pCur;
  return SQLITE_OK;
}

// Filter the result set based on the arguments passed to the function
// This is where we actually call the function to get the result set
// and set up the cursor to iterate over the result set.
// The arguments are passed in as sqlite3_value pointers.  The function
// pointer we got in the aux structure is called to get the result set.
// It does the work of cracking the args out of argc and argv and it will
// give errors if they don't match the function signature.  We don't do any
// of that here, we just pass the args to the function and get the result
// set back.  The function is expected to return a result set that is
// compatible with the table declaration we passed in when we created
// the virtual table.  If the arguments match, it uses them to call the
// stored procedure it is wrapping which in turn yields the result set.
static int cql_rowset_filter(
  sqlite3_vtab_cursor *cur,
  int idxNum,
  const char *idxStr,
  int argc,
  sqlite3_value **argv)
{
  trace_printf("filter\n");
  cql_rowset_cursor *pCur = (cql_rowset_cursor *)cur;
  cql_rowset_table *pTab = (cql_rowset_table *)pCur->base.pVtab;
  pCur->func = pTab->func;

  // Release any previous result set before calling the function.
  //
  // WHY THIS IS NECESSARY — the xFilter re-entrancy problem:
  //
  // SQLite's virtual table xFilter callback is not called exactly once per
  // query.  It is called once per scan of the virtual table, and a single
  // SQL query can scan the same virtual table cursor multiple times.  The
  // most common case is a nested-loop join: if this TVF appears on the inner
  // side of a join, xFilter is re-invoked for every row of the outer table.
  // For example:
  //
  //   SELECT * FROM some_regular_table t
  //   JOIN my_cql_tvf(t.id) tvf ON tvf.key = t.key;
  //
  // SQLite will call xFilter on the TVF cursor once per row in
  // some_regular_table, passing a fresh t.id each time.  Each call produces
  // a brand-new result set.  Without this release, each new result set would
  // silently overwrite pCur->result_set, and the previous one's ref count
  // would never reach zero — a memory leak proportional to the row count of
  // the outer table.
  //
  // Setting result_set to NULL before the call is also important: if func()
  // fails and leaves result_set unchanged (or sets it to NULL), the contract
  // check below will fire cleanly rather than operating on stale data from a
  // previous invocation.
  //
  // cql_result_set_release is NULL-safe, so this pattern is correct on the
  // very first xFilter call when result_set has never been set.
  cql_result_set_release(pCur->result_set);
  pCur->result_set = NULL;

  // Call the function to get the result set
  cql_rowset_func func = pCur->func;
  func(pCur->db, argc, argv, &pCur->result_set);

  // Check to make sure the meta data has column data
  cql_result_set_meta *meta = cql_result_set_get_meta(pCur->result_set);
  cql_contract(meta->columnOffsets != NULL);

  pCur->column_count =  meta->columnCount;
  pCur->row_count = cql_result_set_get_count(pCur->result_set);
  pCur->current_row = 0;

  return SQLITE_OK;
}

// Disconnect from the virtual table, this is called when the
// virtual table is no longer needed.  We just free our
// vtab structure here.  It has nothing in it to free.
static int cql_rowset_disconnect(sqlite3_vtab *pVtab) {
  trace_printf("disconnect\n");
  cql_rowset_table *pTab = (cql_rowset_table *)pVtab;
  sqlite3_free(pTab);
  return SQLITE_OK;
}

// Close Cursor, release the result set here
static int cql_rowset_close(sqlite3_vtab_cursor *cur) {
  trace_printf("close\n");
  cql_rowset_cursor *pCur = (cql_rowset_cursor *)cur;
  cql_result_set_release(pCur->result_set);
  pCur->result_set = NULL;
  sqlite3_free(cur);
  return SQLITE_OK;
}

// Move to Next Row
static int cql_rowset_next(sqlite3_vtab_cursor *cur) {
  trace_printf("next\n");
  cql_rowset_cursor *pCur = (cql_rowset_cursor *)cur;
  pCur->current_row++;
  return SQLITE_OK;
}

// Check if Cursor is at End
static int cql_rowset_eof(sqlite3_vtab_cursor *cur) {
  trace_printf("eof\n");
  cql_rowset_cursor *pCur = (cql_rowset_cursor *)cur;
  return pCur->current_row >= pCur->row_count;
}

// Retrieve Column Data
static int cql_rowset_column(sqlite3_vtab_cursor *cur, sqlite3_context *context, int column) {
  trace_printf("column %d\n", column);
  cql_rowset_cursor *pCur = (cql_rowset_cursor *)cur;

  // SQLite's vtab architecture guarantees column >= 0: the VM routes negative
  // iCol values (e.g. ROWID requests) to xRowid, never to xColumn.  The
  // contract below documents that invariant and will fire in debug builds if
  // it is ever violated by a future SQLite change or a direct call from tests.
  cql_contract(column >= 0);

  cql_result_set_ref result_set = pCur->result_set;
  if (result_set == NULL) {
    sqlite3_result_text(context, "nil result set", -1, SQLITE_TRANSIENT);
    return SQLITE_ERROR;
  }

  if (column >= pCur->column_count) {
    // These are the hidden columns, any attempt to read these indicates
    // that we likely have too many arguments.  The best index function
    // is supposed to ensure that we omit all columns but the normal data
    // columns but it can only do so for the first 16 columns.  So either
    // we have a bug where .omit is not being set or we have more than 16.
    // Check out the cql_rowset_best_index function.
    sqlite3_result_text(context, "column out of range (maybe >16 args?)", -1, SQLITE_TRANSIENT);
    return SQLITE_OK;
  }
  const cql_int32 row = pCur->current_row;
  if (row >= pCur->row_count) {
    sqlite3_result_text(context, "row out of range", -1, SQLITE_TRANSIENT);
    return SQLITE_ERROR;
  }

  cql_result_set_meta *meta = cql_result_set_get_meta(result_set);

  if (meta->columnOffsets == NULL || meta->dataTypes == NULL) {
    sqlite3_result_text(context, "rowset metadata null", -1, SQLITE_TRANSIENT);
    return SQLITE_ERROR;
  }

  if (cql_result_set_get_is_null_col(result_set, row, column)) {
    sqlite3_result_null(context);
    return SQLITE_OK;
  }

  switch (CQL_CORE_DATA_TYPE_OF(meta->dataTypes[column])) {
    case CQL_DATA_TYPE_INT32:
      sqlite3_result_int(context, cql_result_set_get_int32_col(result_set, row, column));
      break;
    case CQL_DATA_TYPE_INT64:
      sqlite3_result_int64(context, cql_result_set_get_int64_col(result_set, row, column));
      break;
    case CQL_DATA_TYPE_DOUBLE:
      sqlite3_result_double(context, cql_result_set_get_double_col(result_set, row, column));
      break;
    case CQL_DATA_TYPE_BOOL:
      sqlite3_result_int(context, cql_result_set_get_bool_col(result_set, row, column));
      break;
    case CQL_DATA_TYPE_STRING: {
      cql_string_ref str_ref = cql_result_set_get_string_col(result_set, row, column);
      cql_alloc_cstr(c_str, str_ref);
      sqlite3_result_text(context, c_str, -1, SQLITE_TRANSIENT);
      cql_free_cstr(c_str, str_ref);
      break;
    }
    case CQL_DATA_TYPE_BLOB: {
      cql_blob_ref blob_ref = cql_result_set_get_blob_col(result_set, row, column);
      const void *bytes = cql_get_blob_bytes(blob_ref);
      cql_uint32 size = cql_get_blob_size(blob_ref);
      sqlite3_result_blob(context, bytes, size, SQLITE_TRANSIENT);
      break;
    }
    case CQL_DATA_TYPE_OBJECT: {
      // Objects cannot be meaningfully represented as a SQLite column value.
      // We return NULL here rather than crash or leak.
      //
      // Why this is fundamentally hard:
      //
      // 1. LIFETIME / REFERENCE COUNTING
      //    CQL objects are ref-counted.  sqlite3_result_pointer() (see
      //    https://www.sqlite.org/bindptr.html) can smuggle a raw pointer
      //    through a result column, and it accepts a destructor callback, so
      //    lifetime *could* be managed that way for a single consumer reading
      //    the value exactly once.  But SQLite may copy or cache the value,
      //    and the calling SQL expression may read the column multiple times.
      //    The ref-count discipline becomes very difficult to reason about.
      //
      // 2. TYPE IDENTITY
      //    sqlite3_result_pointer() tags the pointer with a caller-supplied
      //    string ("type name"), but that is just a convention, not enforced
      //    by SQLite.  There is no way to express the full CQL type — the
      //    consumer must already know what it is getting and cast accordingly.
      //    Any mismatch is a silent memory-safety bug.
      //
      // 3. NESTED RESULT SETS (the really crazy case)
      //    A common CQL object column type is a child result set — a full
      //    cql_result_set_ref representing a one-to-many relationship.  If we
      //    tried to expose that through this TVF bridge, each row of the parent
      //    TVF would need to somehow return a child *table* as a single column
      //    value.  SQLite has no concept of a table-valued column; the only
      //    options are:
      //      a) Serialize the child rows into a blob — lossy, requires a
      //         schema agreement, and loses all type information.
      //      b) Return a raw pointer via sqlite3_result_pointer() and let the
      //         caller invoke a second TVF over it — but now the child result
      //         set must stay alive across an unbounded query lifetime, the
      //         caller must know the child schema out-of-band, and joining the
      //         two TVFs in SQL produces a cross-product unless the query
      //         planner is very clever.
      //      c) Flatten the parent+child into a single wide TVF — possible but
      //         requires custom code per schema; this generic bridge cannot do
      //         it automatically.
      //    None of these are something a generic bridge layer can handle safely.
      //
      // 4. THE RECOMMENDED PATTERN FOR CHILD RESULT SETS
      //    If you genuinely need to expose a child result set to SQL callers,
      //    the best approach is a dedicated helper procedure with a contract
      //    that is explicitly designed for it — e.g. a stored proc that accepts
      //    a parent key, runs the child query directly, and returns those rows
      //    as its own result set.  The caller then joins or correlates the two
      //    result sets in application code rather than in SQL.
      //    Trying to do it inside a TVF is highly problematic: the TVF can
      //    appear in arbitrary JOIN expressions, meaning the child result set
      //    pointer could be evaluated in any join order, duplicated across
      //    multiple rows of a cross product, or held alive across a long-running
      //    query with no predictable release point.  A purpose-built helper
      //    procedure sidesteps all of that by having clear call/return
      //    ownership semantics.
      //
      // Bottom line: if you need object columns exposed to SQL, you need a
      // hand-written TVF that knows the specific object type and has a clear
      // ownership contract.  This generic bridge deliberately returns NULL.
      sqlite3_result_null(context);
      break;
    }
  }
  return SQLITE_OK;
}

// Return Row ID, it's just the row number
static int cql_rowset_rowid(sqlite3_vtab_cursor *cur, sqlite_int64 *pRowid) {
  trace_printf("rowid\n");
  cql_rowset_cursor *pCur = (cql_rowset_cursor *)cur;
  *pRowid = pCur->current_row;
  return SQLITE_OK;
}

// We tell SQLite that "we got it" we'll use the "index" to get the
// results it doesn't need to filter for us.  This is a lie, we don't
// actually have an index, we just want to be able to use the
// arguments as parameters to the function.  We don't want it to apply
// any where clause to the data in the table.  We are not a table, we
// are a function.  We'll get the actual arguments in cql_rowset_filter
static int cql_rowset_best_index(sqlite3_vtab *pVtab, sqlite3_index_info *pIdxInfo) {
  trace_printf("best index\n");
  // Loop through each constraint
  for (int i = 0; i < pIdxInfo->nConstraint; i++) {
    // Make sure every constraint is marked as usable
    pIdxInfo->aConstraint[i].usable = 1;

    // We want each constraint to come to us as a parameter
    // so give it a number (they are 1 based as 0 indicates we don't want it)
    // they won't be one based when they come back to us in argc/argv
    pIdxInfo->aConstraintUsage[i].argvIndex = i + 1;

    // We do not want SQLite to try to apply a where clause
    // on our table data for us and "fetch" the argument columns
    // the fact that they are hidden columns at all is a lie for
    // us, there are no such columns, they are func args only.
    // Note that nConstaint above is limited to 16 so if there are
    // ever more than 16 args this stops working.  We'll generate
    // a runtime error below with a hint that this happened.
    pIdxInfo->aConstraintUsage[i].omit = 1;
  }

  // You can optionally tell SQLite to not use any specific index
  // if you don't want it to make optimizations based on the index
  pIdxInfo->idxNum = 1; // No specific index to use
  pIdxInfo->idxFlags = SQLITE_INDEX_SCAN_UNIQUE;

  return SQLITE_OK;
}

// the standard helper to register a named tvf for wrapping a CQL proc and
// access its result set as a virtual table function.
//
// OWNERSHIP CONTRACT FOR `aux`:
//   `aux` MUST be allocated via `cql_rowset_create_aux_init()`, which uses
//   `sqlite3_malloc` internally.  Once passed here, ownership transfers to
//   SQLite: `sqlite3_create_module_v2` will call `cql_rowset_create_aux_destroy`
//   (which calls `sqlite3_free`) when the module is no longer needed.
//
//   Do NOT pass:
//     - a stack-allocated struct  (sqlite3_free on stack memory → crash)
//     - a libc malloc'd pointer   (sqlite3_free may use a different heap → corruption)
//     - a pointer you intend to free yourself (double-free)
//
//   The correct pattern is always:
//     cql_rowset_aux_init *aux = cql_rowset_create_aux_init(my_func, my_decl);
//     register_cql_rowset_tvf(db, aux, "my_tvf_name");
//     // do not free aux — SQLite owns it now
int register_cql_rowset_tvf(sqlite3 *db, cql_rowset_aux_init *aux, const char *name) {
  trace_printf("register %s\n", name);

  // all of the tvfs we create use the same helper functions, it always just decodes
  // a result set.  The only difference is what helper function we call to get the
  // result set and that flows to us in the aux pointer.  The aux pointer is
  // passed to us in the xCreate and xConnect functions.  We use it to get the
  // function to call to get the result set and the virtual table declaration.
  static sqlite3_module rowsetModule = {
      .iVersion = 0,
      .xCreate = cql_rowset_connect,
      .xConnect = cql_rowset_connect,
      .xDisconnect = cql_rowset_disconnect,
      .xOpen = cql_rowset_open,
      .xClose = cql_rowset_close,
      .xBestIndex = cql_rowset_best_index,
      .xNext = cql_rowset_next,
      .xEof = cql_rowset_eof,
      .xColumn = cql_rowset_column,
      .xRowid = cql_rowset_rowid,
      .xFilter = cql_rowset_filter,
  };

  // we use the aux pointer as our client data, that will tell us what function to call to
  // get the result set and what the table declaration is.
  return sqlite3_create_module_v2(db, name, &rowsetModule, aux, cql_rowset_create_aux_destroy);
}

// Make the new aux init structure from the pieces
cql_rowset_aux_init *cql_rowset_create_aux_init(
  cql_rowset_func func,
  const char *table_decl)
{
  cql_rowset_aux_init *pAux = sqlite3_malloc(sizeof(cql_rowset_aux_init));
  if (!pAux) return NULL;
  pAux->func = func;
  pAux->table_decl = table_decl;
  return pAux;
}

// release the aux structure
// this is called when the virtual table is no longer needed
void cql_rowset_create_aux_destroy(void *pv) {
  cql_rowset_aux_init *aux = (cql_rowset_aux_init *)pv;
  if (aux) {
    // there are no fields we need to free inside of aux at this time
    // but some day their might be so this is here to give us access
    // to those fields.
    sqlite3_free(aux);
  }
}
