#include <sqlite3ext.h>
#include "cqlrt.h"

cql_bool is_sqlite3_type_compatible_with_cql_core_type(int sqlite_type, int8_t cql_core_type, cql_bool is_nullable);

void set_sqlite3_result_from_result_set(sqlite3_context *_Nonnull context, cql_result_set_ref _Nonnull result_set);

cql_nullable_double resolve_nullable_real_from_sqlite3_value(sqlite3_value *_Nonnull value);
cql_nullable_int32 resolve_nullable_integer_from_sqlite3_value(sqlite3_value *_Nonnull value);
cql_nullable_int64 resolve_nullable_long_from_sqlite3_value(sqlite3_value *_Nonnull value);
cql_nullable_bool resolve_nullable_bool_from_sqlite3_value(sqlite3_value *_Nonnull value);
cql_string_ref _Nullable resolve_text_from_sqlite3_value(sqlite3_value *_Nonnull value);
cql_blob_ref _Nullable resolve_blob_from_sqlite3_value(sqlite3_value *_Nonnull value);
cql_object_ref _Nullable resolve_object_from_sqlite3_value(sqlite3_value *_Nonnull value);

#define RESOLVE_NOTNULL_BOOL_FROM_SQLITE3_VALUE(arg)    (cql_bool)sqlite3_value_int(arg);
#define RESOLVE_NOTNULL_REAL_FROM_SQLITE3_VALUE(arg)    (cql_double)sqlite3_value_double(arg);
#define RESOLVE_NOTNULL_INTEGER_FROM_SQLITE3_VALUE(arg) (cql_int32)sqlite3_value_int(arg);
#define RESOLVE_NOTNULL_LONG_FROM_SQLITE3_VALUE(arg)    (cql_int64)sqlite3_value_int64(arg);

#define SQLITE3_RESULT_CQL_NULLABLE_INT(context, nullable_output)    do { if ((nullable_output).is_null) { sqlite3_result_null(context); } else { sqlite3_result_int(context, (nullable_output).value); } } while (0)
#define SQLITE3_RESULT_CQL_NULLABLE_INT64(context, nullable_output)  do { if ((nullable_output).is_null) { sqlite3_result_null(context); } else { sqlite3_result_int64(context, (nullable_output).value); } } while (0)
#define SQLITE3_RESULT_CQL_NULLABLE_DOUBLE(context, nullable_output) do { if ((nullable_output).is_null) { sqlite3_result_null(context); } else { sqlite3_result_double(context, (nullable_output).value); } } while (0)
#define SQLITE3_RESULT_CQL_POINTER(context, nullable_output)         do { /* Not implemented yet */ } while (0)
#define SQLITE3_RESULT_CQL_BLOB(context, output)   \
  do { \
    if (!(output)) { \
      sqlite3_result_null(context); \
      break; \
    } \
    const void *bytes_##output = cql_get_blob_bytes(output); \
    cql_uint32 size_##output = cql_get_blob_size(output); \
    sqlite3_result_blob(context, bytes_##output, size_##output, SQLITE_TRANSIENT); \
  } while (0)
#define SQLITE3_RESULT_CQL_TEXT(context, output)   \
  do { \
    if (!(output)) { \
      sqlite3_result_null(context); \
      break; \
    } \
    cql_alloc_cstr(c_str_##output, output); \
    sqlite3_result_text(context, c_str_##output, -1, SQLITE_TRANSIENT); \
    cql_free_cstr(c_str_##output, output); \
  } while (0)
