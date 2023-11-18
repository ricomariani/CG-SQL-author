/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

/*
 * Note this file is set up to verify the .h file rather than the .c file in test.sh
 */

create table foo (
  f1 integer not null,
  f2 text not null,
  f3 real not null,
  f4 bool not null,
  f5 long not null,
  f6 blob not null,

  g1 integer,
  g2 text,
  g3 real,
  g4 bool,
  g5 long,
  g6 blob
);

-- TEST: try the inline getters form for a a simple procedure
-- not null types
-- +1 static inline cql_int32 selector_get_f1(selector_result_set_ref _Nonnull result_set, cql_int32 row) {
-- +1   return cql_result_set_get_int32_col((cql_result_set_ref)result_set, row, 0);
-- +1 static inline cql_string_ref _Nonnull selector_get_f2(selector_result_set_ref _Nonnull result_set, cql_int32 row) {
-- +1   return cql_result_set_get_string_col((cql_result_set_ref)result_set, row, 1);
-- +1 static inline cql_double selector_get_f3(selector_result_set_ref _Nonnull result_set, cql_int32 row) {
-- +1   return cql_result_set_get_double_col((cql_result_set_ref)result_set, row, 2);
-- +1 static inline cql_bool selector_get_f4(selector_result_set_ref _Nonnull result_set, cql_int32 row) {
-- +1   return cql_result_set_get_bool_col((cql_result_set_ref)result_set, row, 3);
-- +1 static inline cql_int64 selector_get_f5(selector_result_set_ref _Nonnull result_set, cql_int32 row) {
-- +1   return cql_result_set_get_int64_col((cql_result_set_ref)result_set, row, 4);
-- +1 static inline cql_blob_ref _Nonnull selector_get_f6(selector_result_set_ref _Nonnull result_set, cql_int32 row) {
-- +1   return cql_result_set_get_blob_col((cql_result_set_ref)result_set, row, 5);
--
-- nullable int
-- +1 static inline cql_bool selector_get_g1_is_null(selector_result_set_ref _Nonnull result_set, cql_int32 row) {
-- +1   return cql_result_set_get_is_null_col((cql_result_set_ref)result_set, row, 6);
-- +1 static inline cql_int32 selector_get_g1_value(selector_result_set_ref _Nonnull result_set, cql_int32 row) {
-- +1   return cql_result_set_get_int32_col((cql_result_set_ref)result_set, row, 6);
--
-- nullable text
-- +1 static inline cql_string_ref _Nullable selector_get_g2(selector_result_set_ref _Nonnull result_set, cql_int32 row) {
-- +1   return cql_result_set_get_is_null_col((cql_result_set_ref)result_set, row, 7) ? NULL : cql_result_set_get_string_col((cql_result_set_ref)result_set, row, 7);
--
-- nullable real
-- +1 static inline cql_bool selector_get_g3_is_null(selector_result_set_ref _Nonnull result_set, cql_int32 row) {
-- +1   return cql_result_set_get_is_null_col((cql_result_set_ref)result_set, row, 8);
-- +1 static inline cql_double selector_get_g3_value(selector_result_set_ref _Nonnull result_set, cql_int32 row) {
-- +1   return cql_result_set_get_double_col((cql_result_set_ref)result_set, row, 8);
--
-- nullable bool
-- +1 static inline cql_bool selector_get_g4_is_null(selector_result_set_ref _Nonnull result_set, cql_int32 row) {
-- +1   return cql_result_set_get_is_null_col((cql_result_set_ref)result_set, row, 9);
-- +1 static inline cql_bool selector_get_g4_value(selector_result_set_ref _Nonnull result_set, cql_int32 row) {
-- +1   return cql_result_set_get_bool_col((cql_result_set_ref)result_set, row, 9);
--
-- nullable long
-- +1 static inline cql_bool selector_get_g5_is_null(selector_result_set_ref _Nonnull result_set, cql_int32 row) {
-- +1   return cql_result_set_get_is_null_col((cql_result_set_ref)result_set, row, 10);
-- +1 static inline cql_int64 selector_get_g5_value(selector_result_set_ref _Nonnull result_set, cql_int32 row) {
-- +1   return cql_result_set_get_int64_col((cql_result_set_ref)result_set, row, 10);
-- +1 static inline cql_blob_ref _Nullable selector_get_g6(selector_result_set_ref _Nonnull result_set, cql_int32 row) {
--
-- nullable blob
-- +1   return cql_result_set_get_is_null_col((cql_result_set_ref)result_set, row, 11) ? NULL : cql_result_set_get_blob_col((cql_result_set_ref)result_set, row, 11);
create proc selector()
begin
  select * from foo;
end;

-- TEST: emit an object result set with type getters
-- + static inline cql_object_ref _Nonnull emit_object_result_set_get_o(emit_object_result_set_result_set_ref _Nonnull result_set, cql_int32 row) {
-- +   return cql_result_set_get_object_col((cql_result_set_ref)result_set, row, 0);
create proc emit_object_result_set(o object not null)
begin
   declare C cursor like emit_object_result_set arguments;
   fetch C from arguments;
   out union C;
end;

-- TEST: a copy function will be generated
-- + #define sproc_copy_func_copy(result_set, result_set_to, from, count)
@attribute(cql:generate_copy)
create proc sproc_copy_func()
begin
  select * from foo;
end;
-- TEST: emit an object result set with type setters
-- + static inline cql_object_ref _Nonnull emit_object_with_setters_get_o(emit_object_with_setters_result_set_ref _Nonnull result_set) {
-- +  return cql_result_set_get_object_col((cql_result_set_ref)result_set, 0, 0);
-- + static inline void emit_object_with_setters_set_o(emit_object_with_setters_result_set_ref _Nonnull result_set, cql_object_ref _Nonnull new_value) {
-- +  cql_result_set_set_object_col((cql_result_set_ref)result_set, 0, 0, new_value);
@attribute(cql:emit_setters)
create proc emit_object_with_setters(o object not null)
begin
  declare C cursor like emit_object_with_setters arguments;
  fetch C from arguments;
  out C;
end;

create proc simple_child_proc()
begin
  select 1 x, 2 y;
end;

-- TEST: emit getters and setters for a simple result set set type
-- + static inline cql_bool simple_container_proc_get_a_is_null(simple_container_proc_result_set_ref _Nonnull result_set, cql_int32 row) {
-- +   return cql_result_set_get_is_null_col((cql_result_set_ref)result_set, row, 0);
-- + static inline cql_int32 simple_container_proc_get_a_value(simple_container_proc_result_set_ref _Nonnull result_set, cql_int32 row) {
-- +   return cql_result_set_get_int32_col((cql_result_set_ref)result_set, row, 0);
-- + static inline void simple_container_proc_set_a_value(simple_container_proc_result_set_ref _Nonnull result_set, cql_int32 row, cql_int32 new_value) {
-- +   cql_result_set_set_int32_col((cql_result_set_ref)result_set, row, 0, new_value);
-- + static inline void simple_container_proc_set_a_to_null(simple_container_proc_result_set_ref _Nonnull result_set, cql_int32 row) {
-- +   cql_result_set_set_to_null_col((cql_result_set_ref)result_set, row, 0);
-- + static inline cql_int32 simple_container_proc_get_b(simple_container_proc_result_set_ref _Nonnull result_set, cql_int32 row) {
-- +   return cql_result_set_get_int32_col((cql_result_set_ref)result_set, row, 1);
-- + static inline void simple_container_proc_set_b(simple_container_proc_result_set_ref _Nonnull result_set, cql_int32 row, cql_int32 new_value) {
-- +   cql_result_set_set_int32_col((cql_result_set_ref)result_set, row, 1, new_value);
-- + static inline simple_child_proc_result_set_ref _Nullable simple_container_proc_get_c(simple_container_proc_result_set_ref _Nonnull result_set, cql_int32 row) {
-- +   return (simple_child_proc_result_set_ref _Nullable )(cql_result_set_get_is_null_col((cql_result_set_ref)result_set, row, 2) ? NULL : cql_result_set_get_object_col((cql_result_set_ref)result_set, row, 2));
-- + static inline void simple_container_proc_set_c(simple_container_proc_result_set_ref _Nonnull result_set, cql_int32 row, simple_child_proc_result_set_ref _Nullable new_value) {
-- +   cql_result_set_set_object_col((cql_result_set_ref)result_set, row, 2, (cql_object_ref)new_value);
@attribute(cql:emit_setters)
create proc simple_container_proc()
begin
  declare C cursor like (a integer, b integer not null, c object<simple_child_proc set>);
  fetch C using
     1 a,
     2 b,
     simple_child_proc() c;

  out union C;
end;


