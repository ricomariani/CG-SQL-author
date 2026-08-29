/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#include "cqlrt.h"
#include "cqlrt_common.h"
#include <string.h>

// This binary is compiled with NDEBUG so that ordinary assert calls disappear.
// The Python driver first runs it with no arguments to verify valid operations,
// then runs each named contract violation in a separate process.  A working
// cql_contract or cql_invariant aborts that child process.  If a check is
// accidentally implemented with assert, the named operation returns normally
// under NDEBUG and the Python driver reports the zero exit status as a failure.

// The fixture is deliberately the smallest useful result set: one row with one
// nullable integer column.  This makes -1 and 1 the exact invalid boundaries
// for both row and column indexes.
typedef struct contract_test_row {
  cql_nullable_int32 value;
} contract_test_row;

// Result-set offset arrays begin with the column count, followed by one offset
// for each column.  The runtime uses these values for generic column access.
static cql_uint16 contract_test_offsets[] = {
  1,
  offsetof(contract_test_row, value),
};

// The fixture column is nullable so the same row can exercise ordinary reads,
// writes, set-to-null, and is-null accessors.
static uint8_t contract_test_types[] = {
  CQL_DATA_TYPE_INT32,
};

typedef struct hostile_cursor_test_row {
  cql_bool has_row;
  cql_bool value;
  cql_bool canary;
} hostile_cursor_test_row;

// Generated C normally supplies this builtin declaration.  This standalone
// runtime test needs the same prototype to exercise hostile blob input.
extern CQL_WARN_UNUSED cql_code cql_cursor_from_blob(
  sqlite3 *_Nonnull db,
  cql_dynamic_cursor *_Nonnull dyn_cursor,
  cql_blob_ref _Nullable b);

static cql_result_set_ref make_result_set(void) {
  // Ownership of this allocation transfers to the result set.  calloc also
  // clears the nullable flag, making the assigned value initially non-null.
  contract_test_row *row = calloc(1, sizeof(contract_test_row));
  row->value.value = 42;

  cql_result_set_meta meta = {
    .teardown = cql_result_set_teardown,
    .columnOffsets = contract_test_offsets,
    .rowsize = sizeof(contract_test_row),
    .columnCount = 1,
    .dataTypes = contract_test_types,
  };

  return cql_result_set_create(row, 1, meta);
}

static int run_valid_tests(void) {
  // These operations prove that the new checks preserve valid boundary indexes
  // and nullable-column behavior.
  cql_result_set_ref result_set = make_result_set();
  if (cql_result_set_get_int32_col(result_set, 0, 0) != 42) {
    return 1;
  }
  cql_result_set_set_int32_col(result_set, 0, 0, 0);
  if (cql_result_set_get_int32_col(result_set, 0, 0) != 0) {
    return 1;
  }
  cql_result_set_set_to_null_col(result_set, 0, 0);
  if (!cql_result_set_get_is_null_col(result_set, 0, 0)) {
    return 1;
  }
  cql_result_set_release(result_set);

  // Each list has exactly one element.  Besides checking index zero, these
  // cases ensure setters still accept legitimate zero-equivalent values.
  cql_string_ref one = cql_string_ref_new("one");
  cql_string_ref two = cql_string_ref_new("two");
  cql_object_ref strings = cql_string_list_create();
  cql_string_list_add(strings, one);
  cql_string_list_set_at(strings, 0, two);
  if (cql_string_compare(cql_string_list_get_at(strings, 0), two)) {
    return 1;
  }
  cql_object_release(strings);
  cql_string_release(one);
  cql_string_release(two);

  cql_object_ref longs = cql_long_list_create();
  cql_long_list_add(longs, 1);
  cql_long_list_set_at(longs, 0, 0);
  if (cql_long_list_get_at(longs, 0) != 0) {
    return 1;
  }
  cql_object_release(longs);

  cql_object_ref reals = cql_real_list_create();
  cql_real_list_add(reals, 1.0);
  cql_real_list_set_at(reals, 0, 0.0);
  if (cql_real_list_get_at(reals, 0) != 0.0) {
    return 1;
  }
  cql_object_release(reals);

  // A hostile type header used to wrap the 16-bit field counters at 65,536
  // entries.  The wrap made the one required boolean look absent, so the
  // nullable-bool layout overwrote both the value and its adjacent canary.
  enum { hostile_type_count = 65536 };
  uint8_t *hostile_bytes = malloc(hostile_type_count + 1);
  memset(hostile_bytes, 'F', hostile_type_count);
  hostile_bytes[hostile_type_count] = 0;
  cql_blob_ref hostile_blob =
    cql_blob_ref_new(hostile_bytes, hostile_type_count + 1);
  free(hostile_bytes);

  hostile_cursor_test_row hostile_row = {
    .value = 0x5a,
    .canary = 0xa5,
  };
  cql_uint16 hostile_offsets[] = {
    1,
    offsetof(hostile_cursor_test_row, value),
  };
  uint8_t hostile_types[] = {
    CQL_DATA_TYPE_BOOL | CQL_DATA_TYPE_NOT_NULL,
    CQL_DATA_TYPE_BOOL | CQL_DATA_TYPE_NOT_NULL,
  };
  const char *hostile_fields[] = { "value" };
  cql_dynamic_cursor hostile_cursor = {
    .cursor_data = &hostile_row,
    .cursor_has_row = &hostile_row.has_row,
    .cursor_col_offsets = hostile_offsets,
    .cursor_data_types = hostile_types,
    .cursor_fields = hostile_fields,
    .cursor_size = sizeof(hostile_row),
  };

  if (cql_cursor_from_blob(NULL, &hostile_cursor, hostile_blob) != SQLITE_ERROR ||
      hostile_row.has_row ||
      hostile_row.value != 0x5a ||
      hostile_row.canary != 0xa5) {
    return 1;
  }
  cql_blob_release(hostile_blob);
  return 0;
}

static void run_failure_test(const char *name) {
  // Test the macros directly so this suite detects a future regression back to
  // NDEBUG-sensitive assert definitions independently of any runtime accessor.
  if (!strcmp(name, "contract_failure")) {
    cql_contract(cql_false);
    return;
  }

  if (!strcmp(name, "invariant_failure")) {
    cql_invariant(cql_false);
    return;
  }

  // Row hashing performs pointer arithmetic from the selected row.  A negative
  // row must be rejected before its signed value is converted to size_t.
  if (!strcmp(name, "row_hash_negative")) {
    cql_result_set_ref result_set = make_result_set();
    cql_row_hash(result_set, -1);
    return;
  }

  // Check each result-set operand separately.  Testing only row1 could leave an
  // unchecked negative row2 in the second data-pointer calculation.  The shape
  // case verifies that equality does not use the first result set's row size
  // to read a differently sized second result set.  Optional logical
  // column descriptors are intentionally irrelevant to bytewise equality.
  if (!strncmp(name, "rows_equal_", 11)) {
    cql_result_set_ref result_set = make_result_set();
    if (!strcmp(name, "rows_equal_row_size_mismatch")) {
      cql_result_set_ref other_result_set = make_result_set();
      cql_result_set_get_meta(other_result_set)->rowsize++;
      cql_rows_equal(result_set, 0, other_result_set, 0);
      return;
    }
    cql_int32 row1 = !strcmp(name, "rows_equal_first_negative") ? -1 : 0;
    cql_int32 row2 = !strcmp(name, "rows_equal_second_negative") ? -1 : 0;
    cql_rows_equal(result_set, row1, result_set, row2);
    return;
  }

  // Identity comparison has the same two independent row inputs as strict
  // equality, so both lower-bound checks need their own subprocess.
  if (!strncmp(name, "rows_same_", 10)) {
    cql_result_set_ref result_set = make_result_set();
    cql_int32 row1 = !strcmp(name, "rows_same_first_negative") ? -1 : 0;
    cql_int32 row2 = !strcmp(name, "rows_same_second_negative") ? -1 : 0;
    cql_rows_same(result_set, row1, result_set, row2);
    return;
  }

  // Exercise every invalid slice dimension.  The INT32_MAX case specifically
  // guards against restoring the old "from + count" check, whose signed
  // addition could overflow before the range comparison.
  if (!strncmp(name, "rowset_copy_", 12)) {
    cql_result_set_ref result_set = make_result_set();
    cql_result_set_ref copy = NULL;
    cql_int32 from = !strcmp(name, "rowset_copy_from_high") ? 2 : 0;
    cql_int32 count = !strcmp(name, "rowset_copy_count_negative") ? -1 : 0;
    if (!strcmp(name, "rowset_copy_count_high")) {
      from = 1;
      count = INT32_MAX;
    }
    cql_rowset_copy(result_set, &copy, from, count);
    return;
  }

  // Most typed result-set getters and setters share cql_address_of_col, while
  // the generic null helpers perform their own indexing.  These cases cover
  // lower and upper bounds through both paths.
  if (!strncmp(name, "result_", 7)) {
    cql_result_set_ref result_set = make_result_set();
    if (!strcmp(name, "result_get_row_negative")) {
      cql_result_set_get_int32_col(result_set, -1, 0);
    }
    else if (!strcmp(name, "result_get_row_high")) {
      cql_result_set_get_int32_col(result_set, 1, 0);
    }
    else if (!strcmp(name, "result_get_col_negative")) {
      cql_result_set_get_int32_col(result_set, 0, -1);
    }
    else if (!strcmp(name, "result_get_col_high")) {
      cql_result_set_get_int32_col(result_set, 0, 1);
    }
    else if (!strcmp(name, "result_set_row_negative")) {
      cql_result_set_set_int32_col(result_set, -1, 0, 1);
    }
    else if (!strcmp(name, "result_set_col_high")) {
      cql_result_set_set_int32_col(result_set, 0, 1, 1);
    }
    else if (!strcmp(name, "result_is_null_row_negative")) {
      cql_result_set_get_is_null_col(result_set, -1, 0);
    }
    else if (!strcmp(name, "result_set_null_col_high")) {
      cql_result_set_set_to_null_col(result_set, 0, 1);
    }
    return;
  }

  // Each list below contains one element, so -1 tests the signed lower bound
  // and 1 tests the first index beyond the current element count.
  if (!strncmp(name, "string_", 7)) {
    cql_string_ref value = cql_string_ref_new("value");
    cql_object_ref list = cql_string_list_create();
    cql_string_list_add(list, value);
    if (!strcmp(name, "string_get_negative")) {
      cql_string_list_get_at(list, -1);
    }
    else {
      cql_string_list_set_at(list, 1, value);
    }
    return;
  }

  // Integer and real setters must accept zero values; only their indexes are
  // contracts.  The valid tests above cover zero, and these cases cover the
  // invalid boundaries.
  if (!strncmp(name, "long_", 5)) {
    cql_object_ref list = cql_long_list_create();
    cql_long_list_add(list, 1);
    if (!strcmp(name, "long_get_negative")) {
      cql_long_list_get_at(list, -1);
    }
    else {
      cql_long_list_set_at(list, 1, 2);
    }
    return;
  }

  // The Python driver invokes this final branch only with the two real-list
  // case names, so reaching the end normally always represents a failed check.
  cql_object_ref list = cql_real_list_create();
  cql_real_list_add(list, 1.0);
  if (!strcmp(name, "real_get_negative")) {
    cql_real_list_get_at(list, -1);
  }
  else {
    cql_real_list_set_at(list, 1, 2.0);
  }
}

int main(int argc, char **argv) {
  // No argument is the valid-operation smoke test and must return zero.
  if (argc == 1) {
    return run_valid_tests();
  }

  // Every named operation is expected to terminate inside its contract.  This
  // zero return is intentionally reachable only when a contract is missing;
  // the Python parent treats that outcome as a test failure.
  run_failure_test(argv[1]);
  return 0;
}
