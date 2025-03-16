#ifndef NO_SQLITE_EXT
#include <sqlite3ext.h>
#endif

#include "cqlrt.h"

cql_bool is_sqlite3_type_compatible_with_cql_core_type(int sqlite_type, int8_t cql_core_type, cql_bool is_nullable);
cql_bool resolve_not_null_bool_from_sqlite3_value(sqlite3_value *_Nonnull value);
cql_double resolve_not_null_real_from_sqlite3_value(sqlite3_value *_Nonnull value);
cql_int32 resolve_not_null_integer_from_sqlite3_value(sqlite3_value *_Nonnull value);
cql_int64 resolve_not_null_long_from_sqlite3_value(sqlite3_value *_Nonnull value);
cql_nullable_double resolve_nullable_real_from_sqlite3_value(sqlite3_value *_Nonnull value);
cql_nullable_int32 resolve_nullable_integer_from_sqlite3_value(sqlite3_value *_Nonnull value);
cql_nullable_int64 resolve_nullable_long_from_sqlite3_value(sqlite3_value *_Nonnull value);
cql_nullable_bool resolve_nullable_bool_from_sqlite3_value(sqlite3_value *_Nonnull value);
cql_string_ref _Nullable resolve_text_from_sqlite3_value(sqlite3_value *_Nonnull value);
cql_blob_ref _Nullable resolve_blob_from_sqlite3_value(sqlite3_value *_Nonnull value);
cql_object_ref _Nullable resolve_object_from_sqlite3_value(sqlite3_value *_Nonnull value);

void sqlite3_result_cql_nullable_bool(sqlite3_context *_Nonnull context, cql_nullable_bool value);
void sqlite3_result_cql_nullable_int(sqlite3_context *_Nonnull context, cql_nullable_int32 value);
void sqlite3_result_cql_nullable_int64(sqlite3_context *_Nonnull context, cql_nullable_int64 value);
void sqlite3_result_cql_nullable_double(sqlite3_context *_Nonnull context, cql_nullable_double value);
void sqlite3_result_cql_pointer(sqlite3_context *_Nonnull context, void *_Nonnull value);
void sqlite3_result_cql_blob(sqlite3_context *_Nonnull context, _Nullable cql_blob_ref value);
void sqlite3_result_cql_text(sqlite3_context *_Nonnull context, _Nullable cql_string_ref value);

typedef void (*cql_rowset_func)(sqlite3 *db, int32_t argc, sqlite3_value *_Nonnull *_Nonnull argv, cql_result_set_ref *result);

typedef struct {
    const char *table_decl;
    cql_rowset_func func;
} cql_rowset_aux_init;

int register_cql_rowset_tvf(sqlite3 *db, cql_rowset_aux_init *aux, const char *name);

typedef struct {
    sqlite3_vtab base;
    cql_result_set_ref result_set;
    cql_rowset_func func;
    sqlite3 *db;
} cql_rowset_table;

typedef struct {
  sqlite3_vtab_cursor base;
  sqlite3 *db;
  cql_rowset_func func;
  cql_result_set_ref result_set;
  int row_count;
  int column_count;
  int current_row;
} cql_rowset_cursor;

cql_rowset_aux_init *cql_rowset_create_aux_init(cql_rowset_func func, const char *create_table_str);
void cql_rowset_create_aux_destroy(void *pAux);
