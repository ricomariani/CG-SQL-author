/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#include "cqlrt.h"
#include "cqlrt_common.h"
#include <string.h>

typedef struct contract_test_row {
  cql_nullable_int32 value;
} contract_test_row;

static cql_uint16 contract_test_offsets[] = {
  1,
  offsetof(contract_test_row, value),
};

static uint8_t contract_test_types[] = {
  CQL_DATA_TYPE_INT32,
};

static cql_result_set_ref make_result_set(void) {
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
  return 0;
}

static void run_failure_test(const char *name) {
  if (!strcmp(name, "contract_failure")) {
    cql_contract(cql_false);
    return;
  }

  if (!strcmp(name, "invariant_failure")) {
    cql_invariant(cql_false);
    return;
  }

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
  if (argc == 1) {
    return run_valid_tests();
  }

  run_failure_test(argv[1]);
  return 0;
}
