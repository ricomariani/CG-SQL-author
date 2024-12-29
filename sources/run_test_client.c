/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#include <setjmp.h>

#include "cqlrt.h"
#include "run_test.h"
#include "alloca.h"

cql_code test_c_rowsets(sqlite3 *db);
cql_code test_rowset_same(sqlite3 *db);
cql_code test_bytebuf_growth(sqlite3 *db);
cql_code test_cql_finalize_on_error(sqlite3 *db);
cql_code test_blob_rowsets(sqlite3 *db);
cql_code test_sparse_blob_rowsets(sqlite3 *db);
cql_code test_c_one_row_result(sqlite3 *db);
cql_code test_ref_comparisons(sqlite3 *db);
cql_code test_all_column_fetchers(sqlite3 *db);
cql_code test_error_case_rowset(sqlite3 *db);
cql_code test_one_row_result(sqlite3 *db);
cql_code test_cql_bytebuf_open(sqlite3 *db);
cql_code test_cql_bytebuf_format(sqlite3 *db);
cql_code test_cql_bytebuf_alloc_within_bytebuf_exp_growth_cap(sqlite3 *db);
cql_code test_cql_bytebuf_alloc_over_bytebuf_exp_growth_cap(sqlite3 *db);
cql_code test_cql_contract_argument_notnull_tripwires(sqlite3 *db);
cql_code test_cql_rebuild_recreate_group(sqlite3 *db);
cql_code test_cql_parent_child(sqlite3 *db);

void take_bool(cql_nullable_bool x, cql_nullable_bool y);
void take_bool_not_null(cql_bool x, cql_bool y);

cql_string_ref _Nullable string_create(void);
cql_blob_ref _Nonnull blob_from_string(cql_string_ref str);

static int32_t steps_until_fail = 0;
static int32_t trace_received = 0;

#undef sqlite3_step

#define _VA_ARG_COUNT__(_0, _1, _2, _3, _4, _5, _6, _7, _8, _9, _10, _11, _12, _13, _14, _15, _count, ...) _count
#define _VA_ARG_COUNT_(...) _VA_ARG_COUNT__(__VA_ARGS__, 15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0)
#define _VA_ARG_COUNT(...) _VA_ARG_COUNT_(0, ##__VA_ARGS__)
#define _VA_ARG_FIRST(_first, ...) _first

#define _E(cond_, rc_, ...) { \
  expectations++; \
  if (!(cond_)) { \
    fails++; \
    if (_VA_ARG_COUNT(__VA_ARGS__) != 0 && (_VA_ARG_FIRST(__VA_ARGS__)) != NULL) { \
      printf(__VA_ARGS__); \
    } \
    printf("failed at %s:%d rc=%d\n", __FILE__, __LINE__, rc_); \
    return rc_; \
  } \
}

#define E(cond_, ...) _E(cond_, SQLITE_ERROR, __VA_ARGS__)

#define SQL_E(rc_) { \
  cql_code __saved_rc_ = (rc_); \
  _E(SQLITE_OK == __saved_rc_, __saved_rc_, "failed return code %s:%d %s\n", __FILE__, __LINE__, #rc_); \
}

#define _EXPECT(cond_,...) { \
  expectations++; \
  if (!(cond_)) { \
    fails++; \
    if (_VA_ARG_COUNT(__VA_ARGS__) != 0 && (_VA_ARG_FIRST(__VA_ARGS__)) != NULL) { \
      printf(__VA_ARGS__); \
    } \
  } \
}

cql_code mockable_sqlite3_step(sqlite3_stmt *stmt) {
  if (steps_until_fail) {
    if (0 == --steps_until_fail) {
      return SQLITE_ERROR;
    }
  }
  return sqlite3_step(stmt);
}


cql_code run_client(sqlite3 *db) {

  E(longs__one == 1L, "long_enum case 1");
  E(longs__big == 0x100000000L, "long_enum case 2");
  E(floats__one == 1.0, "float_enum case 1");
  E(floats__two == 2.0, "float_enum case 2");

  // ensure special case long const round trips to C
  int64_t min_long_ref = _64(-9223372036854775807);
  E(long_const_1 == min_long_ref, "round trip safe negative const");
  E(long_const_2 == min_long_ref - 1, "round trip min_long explicit long");
  E(long_const_3 == min_long_ref - 1, "round trip min_long implicit long");

  E(trace_received == 0, "failure: proc should not trigger trace yet\n");
  E(fails_because_bogus_table(db) != SQLITE_OK, "procedure should have returned an error\n");
  E(trace_received == 2, "failure: proc did not trigger a trace for both the sql error and rethrow\n");
  E(!cql_outstanding_refs, "outstanding refs in fails_because_bogus_table: %d\n", cql_outstanding_refs);

  SQL_E(test_c_rowsets(db));
  E(!cql_outstanding_refs, "outstanding refs in test_c_rowsets: %d\n", cql_outstanding_refs);

  SQL_E(test_rowset_same(db));
  E(!cql_outstanding_refs, "outstanding refs in test_rowset_same: %d\n", cql_outstanding_refs);

  SQL_E(test_blob_rowsets(db));
  E(!cql_outstanding_refs, "outstanding refs in test_blob_rowsets: %d\n", cql_outstanding_refs);

  SQL_E(test_ref_comparisons(db));
  E(!cql_outstanding_refs, "outstanding refs in test_ref_comparisons: %d\n", cql_outstanding_refs);

  SQL_E(test_sparse_blob_rowsets(db));
  E(!cql_outstanding_refs, "outstanding refs in test_sparse_blob_rowsets: %d\n", cql_outstanding_refs);

  SQL_E(test_bytebuf_growth(db));
  E(!cql_outstanding_refs, "outstanding refs in test bytebuf growth: %d\n", cql_outstanding_refs);

  SQL_E(test_cql_finalize_on_error(db));
  E(!cql_outstanding_refs, "outstanding refs in test finalize on error: %d\n", cql_outstanding_refs);

  SQL_E(test_c_one_row_result(db));
  E(!cql_outstanding_refs, "outstanding refs in test_c_one_row_result: %d\n", cql_outstanding_refs);

  SQL_E(test_all_column_fetchers(db));
  E(!cql_outstanding_refs, "outstanding refs in test_all_column_fetchers: %d\n", cql_outstanding_refs);

  SQL_E(test_error_case_rowset(db));
  E(!cql_outstanding_refs, "outstanding refs in test_error_case_rowset: %d\n", cql_outstanding_refs);

  SQL_E(test_one_row_result(db));
  E(!cql_outstanding_refs, "outstanding refs in one_row_result: %d\n", cql_outstanding_refs);

  SQL_E(test_cql_bytebuf_open(db));
  E(!cql_outstanding_refs, "outstanding refs in test_cql_bytebuf_open: %d\n", cql_outstanding_refs);

  SQL_E(test_cql_bytebuf_format(db));
  E(!cql_outstanding_refs, "outstanding refs in test_cql_bytebuf_format: %d\n", cql_outstanding_refs);

  SQL_E(test_cql_bytebuf_alloc_within_bytebuf_exp_growth_cap(db));
  E(!cql_outstanding_refs,
    "outstanding refs in test_cql_bytebuf_alloc_within_bytebuf_exp_growth_cap: %d\n",
    cql_outstanding_refs);

  SQL_E(test_cql_bytebuf_alloc_over_bytebuf_exp_growth_cap(db));
  E(!cql_outstanding_refs,
    "outstanding refs in test_cql_bytebuf_alloc_over_bytebuf_exp_growth_cap: %d\n",
    cql_outstanding_refs);

  SQL_E(test_cql_contract_argument_notnull_tripwires(db));
  E(!cql_outstanding_refs,
    "outstanding refs in test_cql_contract_argument_notnull_tripwires: %d\n",
    cql_outstanding_refs);

  SQL_E(test_cql_rebuild_recreate_group(db));
  E(!cql_outstanding_refs,
    "outstanding refs in test_cql_rebuild_recreate_group: %d\n",
    cql_outstanding_refs);

  SQL_E(test_cql_parent_child(db));
  E(!cql_outstanding_refs,
    "outstanding refs in test_cql_parent_child: %d\n",
    cql_outstanding_refs);

  return SQLITE_OK;
}

void run_test_trace_callback(const char *proc, const char *file, int32_t line) {
  if (strcmp(proc, "fails_because_bogus_table"))  {
    printf("failure trace not recieved on correct proc\n");
    return;
  }

  if (!file || strlen(file) < 8) {
    printf("callback file not a reasonable value\n");
    return;
  }

  if (line < 1000) {
    printf("line number in callback not a reasonable value\n");
    return;
  }

  trace_received++;
}

cql_code test_c_rowsets(sqlite3 *db) {
  printf("Running C client test\n");
  tests++;

  // we haven't created the table yet
  SQL_E(drop_mixed(db));
  get_mixed_result_set_ref result_set;
  E(SQLITE_OK != get_mixed_fetch_results(db, &result_set, 100), "table didn't exist, yet there was data...\n");

  SQL_E(make_mixed(db));
  SQL_E(load_mixed_with_nulls(db));
  SQL_E(get_mixed_fetch_results(db, &result_set, 100));

  cql_int32 count = get_mixed_result_count(result_set);
  E(count == 4, "expected 4 rows from mixed\n");

  cql_bool b_is_null;
  cql_bool b;
  cql_bool code_is_null;
  cql_int64 code;
  cql_string_ref name;

  b_is_null = get_mixed_get_flag_is_null(result_set, 0);
  b = get_mixed_get_flag_value(result_set, 0);
  code_is_null = get_mixed_get_code_is_null(result_set, 0);
  code = get_mixed_get_code_value(result_set, 0);
  name = get_mixed_get_name(result_set, 0);

  E(b_is_null == 0, "first mixed row has unexpected b_is_null value\n");
  E(b == 1, "first mixed row has unexpected b value\n");
  E(code_is_null == 0, "first mixed row has unexpected code_is_null value\n");
  E(code == 12, "first mixed row has unexpected code value\n");
  E(strcmp("a name", name->ptr) == 0, "first mixed row has unexpected name value\n");

  b_is_null = get_mixed_get_flag_is_null(result_set, 1);
  b = get_mixed_get_flag_value(result_set, 1);
  code_is_null = get_mixed_get_code_is_null(result_set, 1);
  code = get_mixed_get_code_value(result_set, 1);
  name = get_mixed_get_name(result_set, 1);

  E(b_is_null == 0, "second mixed row has unexpected b_is_null value\n");
  E(b == 1, "second mixed row has unexpected b value\n");
  E(code_is_null == 0, "second mixed row has unexpected code_is_null value\n");
  E(code == 14, "second mixed row has unexpected code value\n");
  E(strcmp("another name", name->ptr) == 0, "second mixed row has unexpected name value\n");

  // don't get b_value and code_value, as that will assert, since they are NULL
  b_is_null = get_mixed_get_flag_is_null(result_set, 2);
  code_is_null = get_mixed_get_code_is_null(result_set, 2);
  name = get_mixed_get_name(result_set, 2);

  E(b_is_null == 1, "third mixed row has unexpected b_is_null value\n");
  E(code_is_null == 1, "third mixed row has unexpected code_is_null value\n");
  E(name == NULL, "third mixed row has unexpected name value\n");

  b_is_null = get_mixed_get_flag_is_null(result_set, 3);
  b = get_mixed_get_flag_value(result_set, 3);
  code_is_null = get_mixed_get_code_is_null(result_set, 3);
  code = get_mixed_get_code_value(result_set, 3);
  name = get_mixed_get_name(result_set, 3);

  E(b_is_null == 0, "fourth mixed row has unexpected b_is_null value\n");
  E(b == 0, "fourth mixed row has unexpected b value\n");
  E(code_is_null == 0, "fourth mixed row has unexpected code_is_null value\n");
  E(code == 16, "fourth mixed row has unexpected code value\n");
  E(strcmp("last name", name->ptr) == 0, "fourth mixed row has unexpected name value\n");

  cql_int32 copy_index = 1;
  cql_int32 copy_count = 2;
  get_mixed_result_set_ref result_set_copy;
  get_mixed_copy(result_set, &result_set_copy, copy_index, copy_count);

  for (cql_int32 i = 0; i < copy_count; ++i) {
    // Check that the row hashes are equal from the source to the copy
    E(get_mixed_row_hash(result_set, i + copy_index) == get_mixed_row_hash(result_set_copy, i),
      "copied row %d hash not equal to the expected source row %d\n", i, i + copy_index);

    // Check that the rows are equal from the source to the copy
    E(get_mixed_row_equal(result_set, i + copy_index, result_set_copy, i),
      "copied row %d not equal to the expected source row %d\n", i, i + copy_index);
  }

  for (cql_int32 i = 0; i < count - 1; ++i) {
    // Check that the wrong rows are not equal
    E(!get_mixed_row_equal(result_set, i, result_set, i + 1), "row %d should not be equal to row %d\n", i, i + 1);

    // Check that strings are not equal
    E(!cql_string_equal(get_mixed_get_name(result_set, i), get_mixed_get_name(result_set, i + 1)),
      "row %d name should not be equal to row %d name\n", i, i + 1);
  }

  cql_result_set_release(result_set);
  cql_result_set_release(result_set_copy);

  tests_passed++;
  return SQLITE_OK;
}

static cql_nullable_int64 make_nullable_code(cql_bool is_null, cql_int64 value) {
  cql_nullable_int64 code;
  cql_set_nullable(code, is_null, value);
  return code;
}

static cql_nullable_int64 get_nullable_code(get_mixed_result_set_ref result_set, int32_t row) {
  return make_nullable_code(get_mixed_get_code_is_null(result_set, row), get_mixed_get_code_value(result_set, row));
}

cql_code test_rowset_same(sqlite3 *db) {
  printf("Running cql_row_same client test\n");
  tests++;

  get_mixed_result_set_ref result_set;
  get_mixed_result_set_ref result_set_updated;

  cql_string_ref updated_name = string_create();
  cql_blob_ref updated_bl = blob_from_string(updated_name);

  SQL_E(drop_mixed(db));
  SQL_E(make_mixed(db));
  SQL_E(load_mixed_with_nulls(db));
  SQL_E(get_mixed_fetch_results(db, &result_set, 100));

  // Update row 0 with just a new name, so the identity columns should still match the previous result set
  SQL_E(update_mixed(db,
                     get_mixed_get_id(result_set, 0),
                     updated_name,
                     get_nullable_code(result_set, 0),
                     get_mixed_get_bl(result_set, 0)));


  // Update row 1 with just a new code, so only 1 of the identity columns should not match the previous result set
  SQL_E(update_mixed(db,
                     get_mixed_get_id(result_set, 1),
                     get_mixed_get_name(result_set, 1),
                     make_nullable_code(0, 1234),
                     get_mixed_get_bl(result_set, 1)));

  // Update row 2 with just a new bl, so a ref type identity column should not match the previous result set
  // This also is testing that the last column in the identity columns is properly tested.
  SQL_E(update_mixed(db,
                     get_mixed_get_id(result_set, 2),
                     get_mixed_get_name(result_set, 2),
                     get_nullable_code(result_set, 2),
                     updated_bl));

  // Get the updated result set
  SQL_E(get_mixed_fetch_results(db, &result_set_updated, 100));

  E(get_mixed_row_same(result_set, 0, result_set_updated, 0),
    "updated row 0 should be the same as original row 0 (identity column check)\n");
  E(!get_mixed_row_same(result_set, 1, result_set_updated, 1),
    "updated row 1 should NOT be the same as original row 1 (identity column check)\n");
  E(!get_mixed_row_same(result_set, 2, result_set_updated, 2),
    "updated row 2 should NOT be the same as original row 2 (identity column check)\n");
  E(!get_mixed_row_same(result_set, 0, result_set_updated, 1),
    "updated row 1 should NOT be the same as original row 0 (identity column check)\n");

  cql_result_set_release(result_set);
  cql_result_set_release(result_set_updated);
  cql_string_release(updated_name);
  cql_blob_release(updated_bl);

  tests_passed++;
  return SQLITE_OK;
}

cql_code test_ref_comparisons(sqlite3 *db) {
  printf("Running ref comparison test\n");
  tests++;

  // we haven't created the table yet
  get_mixed_result_set_ref result_set;
  SQL_E(load_mixed_dupes(db));

  SQL_E(get_mixed_fetch_results(db, &result_set, 100));
  E(get_mixed_result_count(result_set) == 6, "expected 6 rows from mixed\n");

  // Check that the row hashes are equal from the source to the copy
  E(get_mixed_row_hash(result_set, 0) == get_mixed_row_hash(result_set, 1), "row %d hash not equal to row %d\n", 0, 1);
  E(get_mixed_row_hash(result_set, 2) == get_mixed_row_hash(result_set, 3), "row %d hash not equal to row %d\n", 2, 3);

  E(get_mixed_row_equal(result_set, 0, result_set, 1), "row %d should be equal to row %d\n", 0, 1);
  E(get_mixed_row_equal(result_set, 2, result_set, 3), "row %d should be equal to row %d\n", 2, 3);
  E(!get_mixed_row_equal(result_set, 0, result_set, 2), "row %d should be not equal to row %d\n", 0, 2);
  E(!get_mixed_row_equal(result_set, 1, result_set, 3), "row %d should not be equal to row %d\n", 1, 3);
  E(!get_mixed_row_equal(result_set, 0, result_set, 4), "row %d should not be equal to row %d\n", 0, 4);
  E(!get_mixed_row_equal(result_set, 1, result_set, 5), "row %d should not be equal to row %d\n", 0, 4);

  cql_result_set_release(result_set);

  tests_passed++;
  return SQLITE_OK;
}

cql_code test_bytebuf_growth(sqlite3 *db) {
  tests++;
  printf("Running C client test with huge number of rows\n");

  SQL_E(bulk_load_mixed(db, 10000));

  get_mixed_result_set_ref result_set;
  SQL_E(get_mixed_fetch_results(db, &result_set, 100000));
  E(get_mixed_result_count(result_set) == 10000, "expected 10000 rows from mixed\n");

  cql_result_set_release(result_set);

  tests_passed++;
  return SQLITE_OK;
}

cql_code test_cql_finalize_on_error(sqlite3 *db) {
  printf("Running cql finalize on error test\n");
  tests++;

  expectations++;
  SQL_E(load_mixed(db));

  sqlite3_stmt *stmt = NULL;
  SQL_E(sqlite3_prepare_v2(db, "select * from sqlite_master", -1, &stmt, NULL));

  cql_finalize_on_error(SQLITE_ERROR,&stmt);
  E(stmt == NULL, "expected statement to be finalized\n");

  tests_passed++;
  return SQLITE_OK;
}

cql_string_ref _Nullable string_create()
{
  return cql_string_ref_new("Hello, world.");
}

cql_int32 run_test_math(cql_int32 int1, cql_nullable_int32 *_Nonnull int2)
{
   int2->is_null = 0;
   int2->value = int1 * 5;
   return int1 * 7;
}

// dumbest set ever
#define MAX_STRINGS 16
typedef struct set_payload
{
  int count;
  cql_string_ref strings[MAX_STRINGS];
} set_payload;

static void set_finalize(cql_type_ref _Nonnull ref)
{
  cql_object_ref obj = (cql_object_ref)ref;
  set_payload *payload = (set_payload *)obj->ptr;
  for (int i = 0; i < payload->count; i++) {
    cql_set_string_ref(&payload->strings[i], NULL);
  }
  free(payload);
  obj->ptr = NULL;
}

cql_object_ref _Nonnull set_create()
{
  cql_object_ref obj = (cql_object_ref)calloc(sizeof(cql_object), 1);
  obj->base.type = CQL_C_TYPE_OBJECT;
  obj->base.ref_count = 1;
  obj->base.finalize = set_finalize;
  obj->ptr = calloc(sizeof(set_payload), 1);
  cql_outstanding_refs++;
  return obj;
}

cql_bool set_contains(cql_object_ref _Nonnull _set, cql_string_ref _Nonnull _key)
{
  set_payload *payload = (set_payload *)_set->ptr;

  for (int i = 0; i < payload->count; i++) {
    if (!strcmp(_key->ptr, payload->strings[i]->ptr)) {
      return cql_true;
    }
  }
  return cql_false;
}

cql_bool set_add(cql_object_ref _Nonnull _set, cql_string_ref _Nonnull _key)
{
  if (set_contains(_set, _key)) {
    return cql_false;
  }

  set_payload *payload = (set_payload *)_set->ptr;
  if (payload->count >= MAX_STRINGS) {
    return cql_false;
  }

  cql_set_string_ref(&payload->strings[payload->count], _key);
  payload->count++;

  return cql_true;
}

int get_outstanding_refs()
{
  return cql_outstanding_refs;
}

cql_blob_ref _Nonnull blob_from_string(cql_string_ref str)
{
  if (str) {
    return cql_blob_ref_new(str->ptr, strlen(str->ptr));
  }
  else {
    return cql_blob_ref_new("", 1);
  }
}

cql_string_ref _Nonnull string_from_blob(cql_blob_ref b)
{
  if (b) {
    char *buf = alloca(b->size+1);
    memcpy(buf, b->ptr, b->size);
    buf[b->size] = 0;
    return cql_string_ref_new(buf);
  }
  else {
    return cql_string_ref_new("");
  }
}

cql_code test_blob_rowsets(sqlite3 *db) {
  printf("Running blob rowset test\n");
  tests++;

  SQL_E(load_blobs(db));

  get_blob_table_result_set_ref result_set;
  SQL_E(get_blob_table_fetch_results(db, &result_set));

  E(get_blob_table_result_count(result_set) == 20, "expected 20 rows from blob table\n");

  cql_int32 id;
  cql_blob_ref b1;
  cql_blob_ref b2;

  for (cql_int32 i = 0; i < 20; i++) {
    id = get_blob_table_get_id(result_set, i);
    b1 = get_blob_table_get_b1(result_set, i);
    b2 = get_blob_table_get_b2(result_set, i);

    E(i == id, "id %d did not match %d\n", id, i);

    char buf1[100];
    char buf2[100];

    sprintf(buf1, "nullable blob %d", i);
    sprintf(buf2, "not nullable blob %d", i);

    cql_string_ref b1_ref = string_from_blob(b1);
    cql_string_ref b2_ref = string_from_blob(b2);
    E(strcmp(buf1, b1_ref->ptr) == 0, "nullable blob %d did not match %s\n", i, buf1);
    E(strcmp(buf2, b2_ref->ptr) == 0, "nullable blob %d did not match %s\n", i, buf2);
    cql_string_release(b1_ref);
    cql_string_release(b2_ref);
  }

  cql_result_set_release(result_set);

  cql_string_ref str_ref = cql_string_ref_new("123");
  cql_blob_ref blob_ref = blob_from_string(str_ref);
  cql_string_ref str_ref_1 = string_from_blob(blob_ref);
  cql_blob_ref blob_ref_1 = blob_from_string(str_ref_1);
  E(cql_string_equal(str_ref, str_ref_1), "string \"%s\" should equal to \"%s\"", str_ref->ptr, str_ref_1->ptr);
  E(cql_blob_equal(blob_ref, blob_ref_1), "blob \"%d\" should be equal to \"%d\"", blob_ref->size, blob_ref_1->size);

  cql_string_release(str_ref);
  cql_string_release(str_ref_1);
  cql_blob_release(blob_ref);
  cql_blob_release(blob_ref_1);

  tests_passed++;
  return SQLITE_OK;
}

cql_code test_sparse_blob_rowsets(sqlite3 *db) {
  printf("Running sparse blob rowset test\n");
  tests++;

  SQL_E(load_sparse_blobs(db));

  get_blob_table_result_set_ref result_set;
  SQL_E(get_blob_table_fetch_results(db, &result_set));

  E(get_blob_table_result_count(result_set) == 20, "expected 20 rows from blob table\n");

  cql_int32 id;
  cql_blob_ref b1;
  cql_blob_ref b2;

  cql_hash_code prev = -1;

  for (cql_int32 i = 0; i < 20; i++) {
    id = get_blob_table_get_id(result_set, i);
    b1 = get_blob_table_get_b1(result_set, i);
    b2 = get_blob_table_get_b2(result_set, i);

    cql_hash_code h = get_blob_table_row_hash(result_set, i);

    E(h != prev, "hash codes really shouldn't collide so easily (row %d)\n", i);
    prev = h;

    E(i == id, "id %d did not match %d\n", id, i);

    char buf1[100];
    char buf2[100];

    sprintf(buf1, "nullable blob %d", i);
    sprintf(buf2, "not nullable blob %d", i);

    cql_string_ref b1_ref = string_from_blob(b1);
    if (i % 2 == 0) {
      E(strcmp(buf1, b1_ref->ptr) == 0, "nullable blob %d did not match %s\n", i, buf1);
    }
    else {
      E(!b1, "nullable blob %d should have been null\n", i);
    }

    cql_string_ref b2_ref = string_from_blob(b2);
    E(strcmp(buf2, b2_ref->ptr) == 0, "nullable blob %d did not match %s\n", i, buf2);

    cql_string_release(b1_ref);
    cql_string_release(b2_ref);
  }

  cql_result_set_release(result_set);

  tests_passed++;
  return SQLITE_OK;
}

cql_code test_c_one_row_result(sqlite3 *db) {
  printf("Running C one row result set test\n");
  tests++;

  SQL_E(drop_mixed(db));

  // we haven't created the table yet
  get_one_from_mixed_result_set_ref result_set;
  E(SQLITE_OK != get_one_from_mixed_fetch_results(db, &result_set, 1), "table didn't exist, yet there was data...\n");
  SQL_E(make_mixed(db));
  SQL_E(load_mixed_with_nulls(db));

  SQL_E(get_one_from_mixed_fetch_results(db, &result_set, 1));
  E(get_one_from_mixed_result_count(result_set) == 1, "expected 1 rows from mixed\n");

  cql_bool b_is_null;
  cql_bool b;
  cql_bool code_is_null;
  cql_int64 code;
  cql_string_ref name;

  b_is_null = get_one_from_mixed_get_flag_is_null(result_set);
  b = get_one_from_mixed_get_flag_value(result_set);
  code_is_null = get_one_from_mixed_get_code_is_null(result_set);
  code = get_one_from_mixed_get_code_value(result_set);
  name = get_one_from_mixed_get_name(result_set);

  E(b_is_null == 0, "mixed row has unexpected b_is_null value\n");
  E(b == 1, "mixed row has unexpected b value\n");
  E(code_is_null == 0, "mixed row has unexpected code_is_null value\n");
  E(code == 12, "mixed row has unexpected code value\n");
  E(strcmp("a name", name->ptr) == 0, "mixed row has unexpected name value\n");

  // Compare to a result from a row with different values
  get_one_from_mixed_result_set_ref result_set2;
  SQL_E(get_one_from_mixed_fetch_results(db, &result_set2, 2));
  E(get_one_from_mixed_result_count(result_set2) == 1, "expected 1 rows from mixed\n");

  cql_bool b_is_null2;
  cql_bool b2;
  cql_bool code_is_null2;
  cql_int64 code2;
  cql_string_ref name2;

  b_is_null2 = get_one_from_mixed_get_flag_is_null(result_set2);
  b2 = get_one_from_mixed_get_flag_value(result_set2);
  code_is_null2 = get_one_from_mixed_get_code_is_null(result_set2);
  code2 = get_one_from_mixed_get_code_value(result_set2);
  name2 = get_one_from_mixed_get_name(result_set2);

  E(b_is_null2 == 0, "mixed row 2 has unexpected b_is_null value\n");
  E(b2 == 1, "mixed row 2 has unexpected b value\n");
  E(code_is_null2 == 0, "mixed row 2 has unexpected code_is_null value\n");
  E(code2 == 14, "mixed row 2 has unexpected code value\n");
  E(strcmp("another name", name2->ptr) == 0, "mixed row 2 has unexpected name value\n");

  E(!get_one_from_mixed_equal(result_set, result_set2), "mismatched result sets are equal\n");
  E(get_one_from_mixed_hash(result_set) != get_one_from_mixed_hash(result_set2),
    "mismatched result sets have the same hashes\n");

  cql_result_set_release(result_set2);

  // Exercise single-row copy and compare copied results
  get_one_from_mixed_copy(result_set, &result_set2);

  E(get_one_from_mixed_equal(result_set, result_set2), "result set copies are not equal\n");
  E(get_one_from_mixed_hash(result_set) == get_one_from_mixed_hash(result_set2),
    "result set copies do not have the same hashes\n");

  cql_result_set_release(result_set2);

  // Compare results fetched from the same row
  SQL_E(get_one_from_mixed_fetch_results(db, &result_set2, 1));

  E(get_one_from_mixed_equal(result_set, result_set2), "result sets for same row are not equal\n");
  E(get_one_from_mixed_hash(result_set) == get_one_from_mixed_hash(result_set2),
    "result sets for same row do not have the same hashes\n");

  cql_result_set_release(result_set);
  cql_result_set_release(result_set2);

  SQL_E(get_one_from_mixed_fetch_results(db, &result_set, 999));
  E(get_one_from_mixed_result_count(result_set) == 0, "expected 0 rows from mixed\n");

  cql_result_set_release(result_set);

  tests_passed++;
  return SQLITE_OK;
}

cql_code test_all_column_fetchers(sqlite3 *db) {
  printf("Running column fetchers test\n");
  tests++;

  // test object
  cql_object_ref set = set_create();
  emit_object_result_set_result_set_ref object_result_set;
  emit_object_result_set_fetch_results(&object_result_set, set);
  E(emit_object_result_set_result_count(object_result_set) == 2, "expected 2 rows from the object union\n");
  for (int32_t row = 0; row <= 1; row++) {
    for (int32_t col = 0; col < 1; col++) {
      cql_bool is_null = cql_result_set_get_is_null_col((cql_result_set_ref)object_result_set, row, col);
      cql_bool is_null_expected = (row == 1) && col == 0;
      E(is_null == is_null_expected, "expected is_null did not match seed data, row %d, col %d\n", row, col);
    }
  }

  cql_object_ref _Nullable object = cql_result_set_get_object_col((cql_result_set_ref)object_result_set, 1, 0);
  E(!object, "expected object to be null\n");
  cql_object_ref new_set = set_create();
  cql_result_set_set_object_col((cql_result_set_ref)object_result_set, 1, 0, new_set);
  object = cql_result_set_get_object_col((cql_result_set_ref)object_result_set, 1, 0);
  E(object, "expected not null object\n");
  cql_result_set_set_object_col((cql_result_set_ref)object_result_set, 1, 0, NULL);

  cql_object_release(set);
  cql_object_release(new_set);
  cql_result_set_release(object_result_set);

  load_all_types_table_result_set_ref result_set;
  SQL_E(load_all_types_table_fetch_results(db, &result_set));
  E(load_all_types_table_result_count(result_set) == 2, "expected 2 rows from result table\n");
  E(cql_result_set_get_meta(result_set)->columnCount == 12, "expected 12 columns from result table\n");
  cql_result_set_ref rs = (cql_result_set_ref)result_set;

  for (int32_t row = 0; row <= 1; row++) {
    for (int32_t col = 0; col < 12; col++) {
      cql_bool is_null = cql_result_set_get_is_null_col(rs, row, col);
      cql_bool is_null_expected = (row == 0) && col < 6;
      E(is_null == is_null_expected, "expected is_null did not match seed data, row %d, col %d\n", row, col);
    }
  }
  for (int32_t row = 0; row <= 1; row++) {
    for (int32_t col = 0; col < 12; col++) {
      cql_bool is_null_expected = (row == 0) && col < 6;
      if (is_null_expected) {
        continue;
      }
      switch (col % 6) {
        case 0:  {
          // bool
          E(cql_result_set_get_bool_col(rs, row, col) == row,
            "expected bool did not match seed data, row %d, col %d\n", row, col);
          cql_result_set_set_bool_col(rs, row, col, row);
          E(cql_result_set_get_bool_col(rs, row, col) == row,
            "expected bool did not match seed data, row %d, col %d\n", row, col);
          break;
        }
        case 1: {
          // int32
          E(cql_result_set_get_int32_col(rs, row, col) == row,
            "expected int32 did not match seed data, row %d, col %d\n", row, col);
          cql_result_set_set_int32_col(rs, row, col, row + 20);
          E(cql_result_set_get_int32_col(rs, row, col) == row + 20,
            "expected int32 did not match seed data, row %d, col %d\n", row + 20, col);
          break;
        }
        case 2: {
          // int64
          E(cql_result_set_get_int64_col(rs, row, col) == row,
            "expected int64 did not match seed data, row %d, col %d\n", row, col);
          cql_result_set_set_int64_col(rs, row, col, row + 30);
          E(cql_result_set_get_int64_col(rs, row, col) == row + 30,
            "expected int64 did not match seed data, row %d, col %d\n", row + 30, col);
          break;
        }
        case 3: {
          // double
          E(cql_result_set_get_double_col(rs, row, col) == row,
            "expected double did not match seed data, row %d, col %d\n", row, col);
          cql_result_set_set_double_col(rs, row, col, row + 40);
          E(cql_result_set_get_double_col(rs, row, col) == row + 40,
            "expected double did not match seed data, row %d, col %d\n", row + 40, col);
          break;
        }
        case 4: {
          // string
          // expected results:
          // s1_0  (row 0)  (s0 will be null)
          // s0_1  (row 1)
          // s1_1  (row 1)
          cql_string_ref str = cql_result_set_get_string_col(rs, row, col);
          const char *expected = row == 0 ? "s1_0" : col < 6 ? "s0_1" : "s1_1";
          E(strcmp(str->ptr, expected) == 0, "expected string did not match seed data, row %d, col %d\n", row, col);

          cql_string_ref updated = string_create();
          cql_result_set_set_string_col(rs, row, col, updated);
          str = cql_result_set_get_string_col(rs, row, col);
          E(strcmp(str->ptr, updated->ptr) == 0, "expected string did not match seed data, row %d, col %d\n", row, col);
          cql_string_release(updated);

          cql_result_set_set_string_col(rs, row, col, NULL);
          cql_string_ref _Nullable nullable_str = cql_result_set_get_string_col(rs, row, col);
          E(nullable_str == NULL, "expected string to be nil");
          break;
        }
        case 5: {
          // blob
          // expected results (size, data)
          // 5, bl1_0
          // 5, bl0_1
          // 5, bl1_1
          cql_blob_ref bl = cql_result_set_get_blob_col(rs, row, col);
          const char *expected = row == 0 ? "bl1_0" : col < 6 ? "bl0_1" : "bl1_1";
          E(bl->size == 5 && memcmp(bl->ptr, expected, 5) == 0,
            "expected blob did not match seed data, row %d, col %d\n", row, col);

          cql_string_ref str_blob = string_create();
          cql_blob_ref updated_bl = blob_from_string(str_blob);
          cql_result_set_set_blob_col(rs, row, col, updated_bl);
          bl = cql_result_set_get_blob_col(rs, row, col);
          E(bl->size == 13 && memcmp(bl->ptr, "Hello, world.", 13) == 0,
            "expected blob did not match seed data, row %d, col %d\n", row, col);
          cql_string_release(str_blob);
          cql_blob_release(updated_bl);
          break;
        }
      }
    }
  }

  // check nullability setters
  cql_int32 row = 0;
  // bool
  E(load_all_types_table_get_b0_is_null(result_set, row) == true, "b0 expected to be null at 0\n");
  load_all_types_table_set_b0_value(result_set, row, true);
  E(load_all_types_table_get_b0_is_null(result_set, row) == false, "b0 expected not to be null at 0\n");
  load_all_types_table_set_b0_to_null(result_set, row);
  E(load_all_types_table_get_b0_is_null(result_set, row) == true, "b0 expected to be null after _to_null\n");

  // int32
  cql_int32 new_int32 = 10;
  E(load_all_types_table_get_i0_is_null(result_set, row) == true, "i0 expected to be null at 0\n");
  load_all_types_table_set_i0_value(result_set, row, new_int32);
  E(load_all_types_table_get_i0_is_null(result_set, row) == false, "i0 expected not to be null at 0\n");
  load_all_types_table_set_i0_to_null(result_set, row);
  E(load_all_types_table_get_i0_is_null(result_set, row) == true, "i0 expected to be null after _to_null\n");

  // int64
  cql_int64 new_int64 = 99;
  E(load_all_types_table_get_l0_is_null(result_set, row) == true, "l0 expected to be null at 0\n");
  load_all_types_table_set_l0_value(result_set, row, new_int64);
  E(load_all_types_table_get_l0_is_null(result_set, row) == false, "l0 expected not to be null at 0\n");
  load_all_types_table_set_l0_to_null(result_set, row);
  E(load_all_types_table_get_l0_is_null(result_set, row) == true, "l0 expected to be null after _to_null\n");

  // double
  cql_double new_double = 200;
  E(load_all_types_table_get_d0_is_null(result_set, row) == true, "d0 expected to be null at 0\n");
  load_all_types_table_set_d0_value(result_set, row, new_double);
  E(load_all_types_table_get_d0_is_null(result_set, row) == false, "d0 expected not to be null at 0\n");
  load_all_types_table_set_d0_to_null(result_set, row);
  E(load_all_types_table_get_d0_is_null(result_set, row) == true, "d0 expected to be null after _to_null\n");

  cql_result_set_release(result_set);

  tests_passed++;
  return SQLITE_OK;
}

cql_code test_error_case_rowset(sqlite3 *db) {
  printf("Running error case rowset test\n");
  tests++;

  SQL_E(load_sparse_blobs(db));

  steps_until_fail = 5;

  get_blob_table_result_set_ref result_set;
  E(SQLITE_OK != get_blob_table_fetch_results(db, &result_set), "blob table error case failed\n");
  E(!result_set, "expected null result set for blob table");

  tests_passed++;
  return SQLITE_OK;
}

cql_code test_one_row_result(sqlite3 *db) {
  tests++;

  simple_cursor_proc_result_set_ref result_set;
  simple_cursor_proc_fetch_results(&result_set);
  int32_t id = simple_cursor_proc_get_id(result_set);

  E(1 == id, "id %d did not match %d\n", id, 1);

  cql_result_set_release(result_set);

  tests_passed++;
  return SQLITE_OK;
}

cql_code test_cql_bytebuf_open(sqlite3 *db) {
  printf("Running cql_bytebuf_open test\n");
  tests++;

  cql_bytebuf b;
  cql_bytebuf_open(&b);
  int32_t max = b.max;
  int32_t used = b.used;
  cql_bytebuf_close(&b);
  E(max == BYTEBUF_GROWTH_SIZE,
    "max %d did not match expected value %d\n",
    max,
    BYTEBUF_GROWTH_SIZE);
  E(used == 0, "used %d did not match expected value %d\n", used, 0);

  tests_passed++;
  return SQLITE_OK;
}

cql_code test_cql_bytebuf_format(sqlite3 *db) {
  tests++;
  printf("Running C client test for bytebuf formatting\n");

  cql_bytebuf b;
  cql_bytebuf_open(&b);
  cql_bprintf(&b, "Hello, world %s:%d", "foo%1", 12);
  cql_bytebuf_append_null(&b);

  const char *expected = "Hello, world foo%1:12";

  cql_bool matches = !strcmp(b.ptr, expected);

  if (!matches) {
    printf("expected: %s\nactual: %s\n", expected, b.ptr);
  }

  E(matches, "string format check -- failed");

  E(b.used == strlen(expected) + 1, "extra characters in buffer");

  cql_bytebuf_close(&b);

  tests_passed++;
  return SQLITE_OK;
}


cql_code test_cql_bytebuf_alloc_within_bytebuf_exp_growth_cap(sqlite3 *db) {
  printf("Running cql_bytebuf_alloc_within_bytebuf_exp_growth_cap test\n");
  tests++;

  cql_bytebuf b;
  cql_bytebuf_open(&b);
  int32_t init_size = b.max;
  int32_t init_used = b.used;
  int32_t needed = init_size + 10;
  cql_bytebuf_alloc(&b, needed);
  int32_t max = b.max;
  int32_t used = b.used;
  cql_bytebuf_close(&b);
  E(max == 2 * init_size + needed,
    "max %d did not match expected value %d\n",
    max,
    2 * init_size + needed);
  E(used == init_used + needed,
    "used %d did not match expected value %d\n",
    used,
    init_used + needed);

  tests_passed++;
  return SQLITE_OK;
}

cql_code test_cql_bytebuf_alloc_over_bytebuf_exp_growth_cap(sqlite3 *db) {
  printf("Running cql_bytebuf_alloc_over_bytebuf_exp_growth_cap test\n");
  tests++;

  cql_bytebuf b;
  cql_bytebuf_open(&b);
  int32_t init_size = b.max;
  int32_t init_used = b.used;
  int32_t needed = BYTEBUF_EXP_GROWTH_CAP;
  cql_bytebuf_alloc(&b, needed);
  E(b.max == needed + 2 * init_size,
    "max %d did not match expected value %d\n",
    b.max,
    needed + 2 * init_size);
  E(b.used == init_used + needed,
    "used %d did not match expected value %d\n",
    b.used,
    init_used + needed);
  init_size = b.max;
  init_used = b.used;
  needed = 2 * BYTEBUF_GROWTH_SIZE + 10;
  cql_bytebuf_alloc(&b, needed);
  int32_t max = b.max;
  int32_t used = b.used;
  cql_bytebuf_close(&b);
  E(max == init_size + needed + BYTEBUF_GROWTH_SIZE_AFTER_CAP,
    "max %d did not match expected value %d\n",
    max,
    init_size + needed + BYTEBUF_GROWTH_SIZE_AFTER_CAP);
  E(used == init_used + needed,
    "used %d did not match expected value %d\n",
    used,
    init_used + needed);

  tests_passed++;
  return SQLITE_OK;
}

// Verify that we hit a tripwire in all of the appropriate cases and avoid them
// otherwise.
cql_code test_cql_contract_argument_notnull_tripwires(sqlite3 *db) {
  printf("Running cql_contract_argument_notnull_tripwires test\n");
  tests++;

  jmp_buf tripwire_jmp_buf;

  // This causes `cql_contract_argument_notnull` (and its `_when_dereferenced`
  // variant) to longjmp instead of calling `cql_tripwire`.
  cql_contract_argument_notnull_tripwire_jmp_buf = &tripwire_jmp_buf;

  // Used for IN TEXT NOT NULL and INOUT TEXT NOT NULL arguments.
  cql_string_ref string = string_create();

  // Used for OUT NOT NULL arguments and bogus INOUT NOT NULL arguments.
  cql_string_ref null_string = NULL;

  // Test passing NULL when we're not supposed to. We do this one argument at a
  // time to exercise all possible code paths.
  for (int32_t position = 1; position <= 12; position++) {
    // `position_failed` will hold the position of the argument that failed,
    // counting from 1.
    int position_failed = 0;
    if (!(position_failed = setjmp(tripwire_jmp_buf))) {
      proc_with_notnull_args(
        // Arguments 1-8 have dedicated contract functions. Each case gets
        // tested twice just to pad us out to the 9-or-greater case. INOUT can
        // fail two different ways so we test both.
        position ==  1 ? NULL         : string,       // IN
        position ==  2 ? NULL         : string,       // IN
        position ==  3 ? NULL         : &null_string, // OUT
        position ==  4 ? NULL         : &null_string, // OUT
        position ==  5 ? NULL         : &string,      // INOUT
        position ==  6 ? NULL         : &string,      // INOUT
        position ==  7 ? &null_string : &string,      // INOUT
        position ==  8 ? &null_string : &string,      // INOUT
        position ==  9 ? NULL         : string,       // IN
        position == 10 ? NULL         : &null_string, // OUT
        position == 11 ? NULL         : &string,      // INOUT
        position == 12 ? &null_string : &string       // INOUT
      );
    }
    E(position != 0, "expected tripwire but did not hit one\n");
    E(position == position_failed,
      "expected tripwire for position %d but hit one for %d\n",
      position,
      position_failed);
  }

  // Allow `cql_contract_argument_notnull` to call `cql_tripwire` again.
  cql_contract_argument_notnull_tripwire_jmp_buf = NULL;

  cql_string_release(string);

  tests_passed++;
  return SQLITE_OK;
}

cql_code some_integers_fetch(
    sqlite3 *_Nonnull _db_,
    cql_object_ref _Nullable *_Nonnull rs,
    cql_int32 start,
    cql_int32 stop) {
  return some_integers_fetch_results(_db_, (some_integers_result_set_ref _Nullable *_Nonnull)rs, start, stop);
}

// for making buffers that are broken
cql_blob_ref create_truncated_blob(cql_blob_ref b, cql_int32 new_size) {
  cql_int32 existing_size = cql_get_blob_size(b);
  cql_contract(new_size <= existing_size);
  return cql_blob_ref_new(cql_get_blob_bytes(b), new_size);
}

static int32_t rand_state = 0;

// to ensure we can get the same series again (this is public)
void rand_reset() {
  rand_state = 0;
}

// This random number generator doesn't have to be very good
// but I can't use anything that looks standard because of who
// knows what copyright issues I might face for daring to use the same
// integers in linear congruence math. So for this lame thing I picked my
// own constants out of thin air and I have no idea if they are any good
// but they are my own and really we just don't care that much.
static int32_t seriously_lousy_rand() {
  rand_state = (rand_state * 1302475243 + 21493) & 0x7fffffff;
  return rand_state;
}

// We are about to break all the rules to corrupt this blob
// mutating the blob in place because we know how.
cql_blob_ref corrupt_blob_with_invalid_shenanigans(cql_blob_ref b) {

  cql_int32 size = cql_get_blob_size(b);
  uint8_t *bytes = (uint8_t *)cql_get_blob_bytes(b);

  for (int32_t i = 0; i < 20; i++) {
     uint32_t index = seriously_lousy_rand() % size;
     uint8_t byte = seriously_lousy_rand() & 0xff;

     // smash
     bytes[index] = byte;
  }
  cql_blob_retain(b);
  return b;
}

// This test first creates a sample recreate group with twp dependent tables
// one table with interesting string literals, and an index that will exist in sqlite_master.
// We will make sure the function succesfully drops and recreates with SQLITE_OK.
cql_code test_cql_rebuild_recreate_group(sqlite3 *db) {
  cql_string_ref tables = cql_string_ref_new(" CREATE TABLE g1( id INTEGER PRIMARY KEY, name TEXT ); "
                                            "CREATE TABLE [use g1]( id INTEGER PRIMARY KEY REFERENCES g1 (id), name2 TEXT); "
                                            "CREATE TABLE foo(y text DEFAULT 'it''s, ('); "
                                            "CREATE TABLE g2( id INTEGER PRIMARY KEY ); "
                                            "CREATE TABLE use_g2( id INTEGER PRIMARY KEY REFERENCES g2 (id)); ");
  cql_string_ref indices = cql_string_ref_new("CREATE INDEX extra_index ON g1 (id); ");
  cql_string_ref deletes = cql_string_ref_new("DROP TABLE IF EXISTS g2; DROP TABLE IF EXISTS use_g2; ");
  cql_code rc;
  cql_bool result = false;
  rc = cql_exec_internal(db, tables);
  E(rc == SQLITE_OK, "expected succesful table creates\n");
  rc = cql_exec_internal(db, indices);
  E(rc == SQLITE_OK, "expected succesful index create\n");
  rc = cql_rebuild_recreate_group(db, tables, indices, deletes, &result);
  E(rc == SQLITE_OK, "expected succesful recreate group upgrade\n");
  cql_string_release(tables);
  cql_string_release(indices);
  cql_string_release(deletes);
  return rc;
}

void take_bool(cql_nullable_bool x, cql_nullable_bool y)
{
  _EXPECT(x.is_null == y.is_null, "nullable bool is_null normalization error\n");
  _EXPECT(x.value == y.value, "nullable bool value normalization error\n");
}

void take_bool_not_null(cql_bool x, cql_bool y)
{
  _EXPECT(x == y, "not nullable bool normalization error\n");
}

cql_code test_cql_parent_child(sqlite3 *db) {
  printf("Running parent/child rowset test\n");
  tests++;

  cql_code rc = TestParentChildInit(db);
  E(rc == SQLITE_OK, "expected successful table init\n");

  TestParentChild_result_set_ref parent;

  rc = TestParentChild_fetch_results(db, &parent);
  E(rc == SQLITE_OK, "expected to fetch results from tables succesfully\n");

  cql_int32 count = TestParentChild_result_count(parent);
  E(count == 2, "expected two rows\n");

  for (int i = 0; i < count; i++) {
    cql_int32 roomID = TestParentChild_get_roomID(parent, i);
     cql_string_ref name_ref = TestParentChild_get_name(parent, i);

     cql_alloc_cstr(cstr, name_ref);

     if (roomID == 1) {
       E(!strcmp(cstr, "foo"), "expected room to be 'foo'");
     }
     else {
       E(!strcmp(cstr, "bar"), "expected room to be 'bar'");
     }

     cql_free_cstr(cstr, name_ref);

     // note that the shape of the result set from the Parent/Child will be
     // slightly different than the shape of child if you call it directly
     // because the partitioning logic will add the columns `has_row`,
     // `refs_count` and `refs_offset`.  But this is supposed to be no problem.
     // We verify the accessors work in this case with the code below

     TestChild_result_set_ref child = TestParentChild_get_test_tasks(parent, i);
     cql_int32 children = TestChild_result_count(child);

     for (int j = 0; j < children; j++) {
       cql_int32 child_room = TestChild_get_roomID(child, j);
       cql_int32 child_task = TestChild_get_thisIsATask(child, j);

       E(child_room == roomID, "expected matching parent and child room id\n");
       E(child_task == 100*roomID + j, "child task did not match expected formula\n");
     }
  }
  cql_result_set_release(parent);

  tests_passed++;
  return SQLITE_OK;
}
