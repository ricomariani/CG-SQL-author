#include <sqlite3ext.h>
extern const sqlite3_api_routines *sqlite3_api;

#include "cql_sqlite_extension.h"
#include "cqlrt.h"

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

/*
void set_sqlite3_result_from_result_set(sqlite3_context *_Nonnull context, cql_result_set_ref _Nonnull result_set) {
  const cql_int32 row = 0;
  const cql_int32 column = 0;

  if (row >= cql_result_set_get_count(result_set)) goto silent_error;

  cql_result_set_meta *meta = cql_result_set_get_meta(result_set);

  if (meta->columnOffsets == NULL || column >= meta->columnCount) goto silent_error;
  if (cql_result_set_get_is_null_col(result_set, row, column)) goto silent_error;

  switch (CQL_CORE_DATA_TYPE_OF(meta->dataTypes[column])) {
    case CQL_DATA_TYPE_INT32:
      sqlite3_result_int(context, cql_result_set_get_int32_col(result_set, row, column));
      return;
    case CQL_DATA_TYPE_INT64:
      sqlite3_result_int64(context, cql_result_set_get_int64_col(result_set, row, column));
      return;
    case CQL_DATA_TYPE_DOUBLE:
      sqlite3_result_double(context, cql_result_set_get_double_col(result_set, row, column));
      return;
    case CQL_DATA_TYPE_BOOL:
      sqlite3_result_int(context, cql_result_set_get_bool_col(result_set, row, column));
      return;
    case CQL_DATA_TYPE_STRING: {
      cql_string_ref str_ref = cql_result_set_get_string_col(result_set, row, column);
      cql_alloc_cstr(c_str, str_ref);
      sqlite3_result_text(context, c_str, -1, SQLITE_TRANSIENT);
      cql_free_cstr(c_str, str_ref);
      return;
    }
    case CQL_DATA_TYPE_BLOB: {
      cql_blob_ref blob_ref = cql_result_set_get_blob_col(result_set, row, column);
      const void *bytes = cql_get_blob_bytes(blob_ref);
      cql_uint32 size = cql_get_blob_size(blob_ref);
      sqlite3_result_blob(context, bytes, size, SQLITE_TRANSIENT);
      return;
    }
    case CQL_DATA_TYPE_OBJECT: {
      // Not supported yet — See https://www.sqlite.org/bindptr.html
      cql_object_ref obj_ref = cql_result_set_get_object_col(result_set, row, column);
      cql_retain((cql_type_ref)obj_ref);
      sqlite3_result_int64(context, (int64_t)obj_ref);
      return;
    }
  }

  silent_error:
    sqlite3_result_null(context);
}
*/

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

static int cql_rowset_connect(
  sqlite3 *db, 
  void *pAux,
  int argc,
  const char *const *argv,
  sqlite3_vtab **ppVtab,
  char **pzErr)
{
  cql_rowset_table *pNew = sqlite3_malloc(sizeof(cql_rowset_table));
  if (!pNew) return SQLITE_NOMEM;

  memset(pNew, 0, sizeof(cql_rowset_table));
  strncpy(pNew->function_name, argv[0], sizeof(pNew->function_name) - 1);
  
  // Store arguments
  pNew->argc = argc - 3;
  if (pNew->argc > 0) {
      pNew->argv = sqlite3_malloc(sizeof(char*) * pNew->argc);
      for (int i = 0; i < pNew->argc; i++) {
          pNew->argv[i] = sqlite3_mprintf("%s", argv[i + 3]); // Store a copy of the arguments
      }
  } else {
      pNew->argv = NULL;
  }

  *ppVtab = (sqlite3_vtab *)pNew;
  return SQLITE_OK;
}

static int cql_rowset_open_stub(sqlite3_vtab *pVtab, sqlite3_vtab_cursor **ppCursor) {
  cql_rowset_cursor *pCur = sqlite3_malloc(sizeof(cql_rowset_cursor));
  if (!pCur) return SQLITE_NOMEM;
  
  cql_rowset_table *pTab = (cql_rowset_table *)pVtab;
  pCur->result_set = 0; // get_rowset_handle_by_name(pTab->function_name, pTab->argc, pTab->argv);
  
  if (!pCur->result_set) {
      sqlite3_free(pCur);
      return SQLITE_ERROR;
  }

  // Check to make sure the meta data has column data
  cql_result_set_meta *meta = cql_result_set_get_meta(pCur->result_set);
  cql_contract(meta->columnOffsets != NULL);

  pCur->column_count =  meta->columnCount;
  pCur->row_count = cql_result_set_get_count(pCur->result_set); 
  pCur->current_row = 0;
  
  *ppCursor = (sqlite3_vtab_cursor *)pCur;
  return SQLITE_OK;
}


static int cql_rowset_disconnect(sqlite3_vtab *pVtab) {
  cql_rowset_table *pTab = (cql_rowset_table *)pVtab;
  if (pTab->argv) {
      for (int i = 0; i < pTab->argc; i++) {
          sqlite3_free(pTab->argv[i]);
      }
      sqlite3_free(pTab->argv);
  }
  sqlite3_free(pTab);
  return SQLITE_OK;
}

/* Close Cursor */
static int cql_rowset_close(sqlite3_vtab_cursor *cur) {
  cql_rowset_cursor *pCur = (cql_rowset_cursor *)cur;
  cql_result_set_release(pCur->result_set);
  sqlite3_free(cur);
  return SQLITE_OK;
}

/* Move to Next Row */
static int cql_rowset_next(sqlite3_vtab_cursor *cur) {
  cql_rowset_cursor *pCur = (cql_rowset_cursor *)cur;
  pCur->current_row++;
  return SQLITE_OK;
}

/* Check if Cursor is at End */
static int cql_rowset_eof(sqlite3_vtab_cursor *cur) {
  cql_rowset_cursor *pCur = (cql_rowset_cursor *)cur;
  return pCur->current_row >= pCur->row_count;
}

/* Retrieve Column Data */
static int cql_rowset_column(sqlite3_vtab_cursor *cur, sqlite3_context *context, int column) {
  cql_rowset_cursor *pCur = (cql_rowset_cursor *)cur;

  cql_result_set_ref result_set = pCur->result_set;
  if (result_set == NULL) {
    sqlite3_result_text(context, "nil result set", -1, SQLITE_TRANSIENT);
    return SQLITE_ERROR;
  }

  if (column >= pCur->column_count) {
    sqlite3_result_text(context, "column out of range", -1, SQLITE_TRANSIENT);
    return SQLITE_ERROR;
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
   
/* Return Row ID */
static int cql_rowset_rowid(sqlite3_vtab_cursor *cur, sqlite_int64 *pRowid) {
  cql_rowset_cursor *pCur = (cql_rowset_cursor *)cur;
  *pRowid = pCur->current_row;
  return SQLITE_OK;
}

/* xBestIndex - No filtering, full table scan */
static int cql_rowset_best_index(sqlite3_vtab *pVtab, sqlite3_index_info *pIdxInfo) {
  pIdxInfo->estimatedCost = 100.0;
  return SQLITE_OK;
}

int register_rowset_tvf(sqlite3 *db, cql_rowset_func func, const char *name) {
  static sqlite3_module rowsetModule = {
      .iVersion = 0,
      .xCreate = cql_rowset_connect,
      .xConnect = cql_rowset_connect,
      .xDisconnect = cql_rowset_disconnect,
      .xOpen = cql_rowset_open_stub,
      .xClose = cql_rowset_close,
      .xBestIndex = cql_rowset_best_index,
      .xNext = cql_rowset_next,
      .xEof = cql_rowset_eof,
      .xColumn = cql_rowset_column,
      .xRowid = cql_rowset_rowid
  };
  
  return sqlite3_create_module_v2(db, name, &rowsetModule, NULL, NULL);
}


