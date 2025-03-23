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

// This is used to validate if an imcoming argument
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

  return cql_blob_ref_new(blob, sqlite3_value_bytes(value));
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

  if (meta->columnOffsets == NULL) {
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
      // Not supported yet — See https://www.sqlite.org/bindptr.html
      cql_object_ref obj_ref = cql_result_set_get_object_col(result_set, row, column);
      cql_retain((cql_type_ref)obj_ref);
      sqlite3_result_int64(context, (int64_t)obj_ref);
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
