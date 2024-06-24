/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

// !!! THIS FILE IS NOT AUTO GENERATED, only the .h file is !!!

#include "cqlrt.h"
#include <string.h>

cql_int64 openDb() {
  sqlite3 *db;
  if (sqlite3_open(":memory:", &db) == SQLITE_OK) {
    return (cql_int64)db;
  }
  return 0;
}

void closeDb(cql_int64 db) {
  sqlite3_close((sqlite3 *)db);
}

void close(cql_int64 rs) {
  cql_result_set_ref ref = (cql_result_set_ref)(rs);
  cql_result_set_release(ref);
}

cql_bool getBoolean(cql_int64 rs, cql_int32 row, cql_int32 col) {
  cql_result_set_ref ref = (cql_result_set_ref)(rs);

  return cql_result_set_get_bool_col(ref, row, col);
}

cql_int32 getInteger(cql_int64 rs, cql_int32 row, cql_int32 col) {
  cql_result_set_ref ref = (cql_result_set_ref)(rs);

  return cql_result_set_get_int32_col(ref, row, col);
}

cql_int64 getLong(cql_int64 rs, cql_int32 row, cql_int32 col) {
  cql_result_set_ref ref = (cql_result_set_ref)(rs);

  return cql_result_set_get_int64_col(ref, row, col);
}

const char *getString(cql_int64 rs, cql_int32 row, cql_int32 col) {
  cql_result_set_ref ref = (cql_result_set_ref)(rs);

  cql_string_ref str = cql_result_set_get_string_col(ref, row, col);
  cql_alloc_cstr(c_str, str);
  const char *result = strdup(c_str);
  cql_free_cstr(c_str, str);
  return result;
}

double getDouble(cql_int64 rs, cql_int32 row, cql_int32 col) {
  cql_result_set_ref ref = (cql_result_set_ref)(rs);

  return cql_result_set_get_double_col(ref, row, col);
}

void* getBlob(cql_int64 rs, cql_int32 row, cql_int32 col, cql_int32 *size_out) {
  cql_result_set_ref ref = (cql_result_set_ref)(rs);

  cql_blob_ref blob = cql_result_set_get_blob_col(ref, row, col);
  cql_uint32 size = cql_get_blob_size(blob);
  const void *bytes = cql_get_blob_bytes(blob);
  void *ret = malloc(size);
  memcpy(ret, bytes, size);
  *size_out = (cql_int32)size;
  return ret;
}

cql_int64 copyChildResultSet(cql_int64 rs, cql_int32 row, cql_int32 col) {

  cql_result_set_ref ref = (cql_result_set_ref)(rs);

  cql_object_ref refNew = cql_result_set_get_object_col(ref, row, col);
  cql_retain((cql_type_ref)refNew);

  return (cql_int64)refNew;
}

cql_bool isNull(cql_int64 rs, cql_int32 row, cql_int32 col) {
  cql_result_set_ref ref = (cql_result_set_ref)(rs);

  return cql_result_set_get_is_null_col(ref, row, col);
}

cql_int32 getCount(cql_int64 rs) {
  cql_result_set_ref ref = (cql_result_set_ref)(rs);

  return cql_result_set_get_count(ref);
}

cql_int64 rowHashCode(cql_int64 rs, cql_int32 row) {
  cql_result_set_ref ref = (cql_result_set_ref)(rs);

  return cql_row_hash(ref, row);
}

cql_bool rowsEqual(cql_int64 rs1, cql_int32 row1, cql_int64 rs2, cql_int32 row2) {

  cql_result_set_ref ref1 = (cql_result_set_ref)(rs1);
  cql_result_set_ref ref2 = (cql_result_set_ref)(rs2);

  return cql_rows_equal(ref1, row1, ref2, row2);
}

cql_bool rowsSame(cql_int64 rs1, cql_int32 row1, cql_int64 rs2, cql_int32 row2) {

  cql_result_set_ref ref1 = (cql_result_set_ref)(rs1);
  cql_result_set_ref ref2 = (cql_result_set_ref)(rs2);

  return cql_rows_same(ref1, row1, ref2, row2);
}

cql_int64 copy(cql_int64 rs, cql_int32 row, cql_int32 count) {
  cql_result_set_ref ref = (cql_result_set_ref)(rs);
  cql_result_set_ref refNew = NULL;
  cql_rowset_copy(ref, &refNew, row, count);
  return (cql_int64)refNew;
}

cql_bool getIsEncoded(cql_int64 rs, cql_int32 col) {
  cql_result_set_ref ref = (cql_result_set_ref)(rs);
  return cql_result_set_get_is_encoded_col(ref, col);
}
