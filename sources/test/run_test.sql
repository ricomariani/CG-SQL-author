/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

declare tests int!;
declare tests_passed int!;
declare fails int!;
declare expectations int!;
declare function get_outstanding_refs() int!;
declare start_refs int!;
declare end_refs int!;
declare proc printf no check;
declare proc exit no check;

@MACRO(stmt_list) EXPECT!(pred! expr)
begin
  call errcheck(pred!, @TEXT(pred!), @MACRO_LINE);
end;

-- use this for both normal eval and SQLite eval
@MACRO(stmt_list) EXPECT_SQL_TOO!(pred! expr)
begin
  EXPECT!(pred!);
  EXPECT!((select pred!));
end;

proc lua_gated(out gated int!)
begin

  @ifdef __rt__lua
    gated := true;
  @else
    gated := false;
  @endif

end;

@MACRO(stmt_list) TEST_GATED!(x! expr, pred! expr, body! stmt_list)
begin
  proc @ID("test_", x!)()
  begin
    try
      tests := tests + 1;
      declare starting_fails int!;
      starting_fails := fails;
      body!;
    catch
      call printf("%s had an unexpected CQL exception (usually a db error)\n", @TEXT(x!));
      fails := fails + 1;
      throw;
    end;
    if starting_fails != fails then
      call printf("%s failed.\n", @TEXT(x!));
    else
      tests_passed := tests_passed + 1;
    end if;
  end;

  if not pred! then
    start_refs := get_outstanding_refs();
    call @ID(@TEXT("test_", x!))();
    end_refs := get_outstanding_refs();
    if start_refs != end_refs then
      call printf("Test %s unbalanced refs.", @TEXT(x!));
      call printf("  Starting refs %d, ending refs %d.\n", start_refs, end_refs);
      fails := fails + 1;
    end if;
  end if;
end;

@MACRO(stmt_list) TEST!(x! expr, body! stmt_list)
begin
  TEST_GATED!(x!, false, body!);
end;

@MACRO(stmt_list) BEGIN_SUITE!()
begin
  declare zero int!;
  declare one int!;
  declare two int!;

  zero := 0;
  one := 1;
  two := 2;
end;

@MACRO(stmt_list) END_SUITE!()
begin
  call end_suite();
end;

proc errcheck(passed bool @sensitive, message text, line int!)
begin
  expectations := expectations + 1;
  if not coalesce(passed, 0) then
    call printf("test: %s: FAIL on line %d\n", message, line);
    fails := fails + 1;
  end if;
end;

proc end_suite()
begin
  call printf("%d tests executed. %d passed, %d failed.  %d expectations failed of %d.\n",
    tests, tests_passed, tests - tests_passed, fails, expectations);
  call exit(fails);
end;

/* Enable this code if you want to get verbose errors from the run tests

@echo c, '

#undef cql_error_trace
#define cql_error_trace()
  fprintf(stderr, "Error at %s:%d in %s: %d %s\n", __FILE__, __LINE__, _PROC_, _rc_, sqlite3_errmsg(_db_))
';
*/

-- for the test cases, all the blob function will be offset based rather than hash based
-- this makes the dumb test implementation of these b* functions easier
@blob_get_key_type bgetkey_type;
@blob_get_val_type bgetval_type;
@blob_get_key bgetkey offset;
@blob_get_val bgetval offset;
@blob_create_key bcreatekey offset;
@blob_create_val bcreateval offset;
@blob_update_key bupdatekey offset;
@blob_update_val bupdateval offset;


declare const group blob_types (
  CQL_BLOB_TYPE_BOOL   = 0,
  CQL_BLOB_TYPE_INT32  = 1,
  CQL_BLOB_TYPE_INT64  = 2,
  CQL_BLOB_TYPE_FLOAT  = 3,
  CQL_BLOB_TYPE_STRING = 4,
  CQL_BLOB_TYPE_BLOB   = 5
);

declare select function bgetkey_type(b blob) long;
declare select function bgetval_type(b blob) long;
declare select function bgetkey(b blob, iarg int) long;
declare select function bgetval(b blob, iarg long) long;
declare select function bcreateval no check blob;
declare select function bcreatekey no check blob;
declare select function bupdateval no check blob;
declare select function bupdatekey no check blob;

declare function get_blob_byte(b blob!, i int!) int!;
declare function get_blob_size(b blob!) int!;
declare function create_truncated_blob(b blob!, truncated_size int!) create blob!;

declare function blob_from_string(str text @sensitive) create blob!;
declare function string_from_blob(b blob @sensitive) create text!;
declare procedure _cql_init_extensions() using transaction;

declare enum floats real (
  one = 1.0,
  two = 2.0
);

declare enum longs long (
  one = 1,
  big = 0x100000000,
  neg = -1
);

proc make_schema()
begin
  @attribute(cql:backing_table)
  create table backing(
    `the key` blob primary key,
    `the value` blob!
  );
end;

@attribute(cql:backed_by=backing)
create table backed (
  id int primary key,
  `value one` int!,
  `value two` int!
);

@attribute(cql:backed_by=backing)
create table backed2 (
  id int primary key,
  `value one` int
);

call make_schema();
call _cql_init_extensions();

BEGIN_SUITE!();

TEST!(vers,
BEGIN
  call printf("SQLite Verison: %s\n", (select sqlite_version()));
END);

TEST!(arithmetic,
BEGIN
  EXPECT_SQL_TOO!((1 + 2) * 3 == 9);
  EXPECT_SQL_TOO!(1 + 2 * 3 == 7);
  EXPECT_SQL_TOO!(6 / 3 == 2);
  EXPECT_SQL_TOO!(7 - 5 == 2);
  EXPECT_SQL_TOO!(6 % 5 == 1);
  EXPECT_SQL_TOO!(5 / 2.5 == 2);
  EXPECT_SQL_TOO!(-(1+3) == -4);
  EXPECT_SQL_TOO!(-1+3 == 2);
  EXPECT_SQL_TOO!(1+-3 == -2);
  EXPECT_SQL_TOO!(longs.neg == -1);
  EXPECT_SQL_TOO!(-longs.neg == 1);
  EXPECT_SQL_TOO!(- -longs.neg == -1);
  EXPECT_SQL_TOO!(-3 / 2 == -1);
  EXPECT_SQL_TOO!(3 / -2 == -1);
  EXPECT_SQL_TOO!(-3 / -2 == 1);
  EXPECT_SQL_TOO!(-3 % 2 == -1);
  EXPECT_SQL_TOO!(3 % -2 == 1);
  EXPECT_SQL_TOO!(-3 % -2 == -1);
END);

declare side_effect_0_count int!;
declare side_effect_1_count int!;
declare side_effect_null_count int!;

proc side_effect_0(out result int)
begin
  result := 0;
  side_effect_0_count := side_effect_0_count + 1;
end;

proc side_effect_1(out result int)
begin
  result := 1;
  side_effect_1_count := side_effect_1_count + 1;
end;

proc side_effect_null(out result int)
begin
  result := null;
  side_effect_null_count := side_effect_null_count + 1;
end;

proc reset_counts()
begin
  side_effect_0_count := 0;
  side_effect_1_count := 0;
  side_effect_null_count := 0;
end;

TEST!(logical_operations,
BEGIN
  EXPECT_SQL_TOO!((NULL AND 0) = 0);
  EXPECT_SQL_TOO!((NULL AND 0) = 0);
  EXPECT_SQL_TOO!((0 AND NULL) = 0);
  EXPECT_SQL_TOO!((1 AND NULL) IS NULL);
  EXPECT_SQL_TOO!((NULL AND 1) IS NULL);
  EXPECT_SQL_TOO!((NULL OR 1) = 1);
  EXPECT_SQL_TOO!((1 OR NULL) = 1);
  EXPECT_SQL_TOO!((0 OR NULL) IS NULL);
  EXPECT_SQL_TOO!((NULL OR 0) IS NULL);
  EXPECT_SQL_TOO!((0 OR 1) AND (1 OR 0));
  EXPECT_SQL_TOO!(NOT 1 + 2 = 0);
  EXPECT_SQL_TOO!((NOT 1) + 2 = 2);

  EXPECT!((side_effect_0() and side_effect_0()) == 0);
  EXPECT!(side_effect_0_count == 1);
  call reset_counts();

  EXPECT!((side_effect_0() and side_effect_1()) == 0);
  EXPECT!(side_effect_0_count == 1);
  EXPECT!(side_effect_1_count == 0);
  call reset_counts();

  EXPECT!((side_effect_0() and side_effect_null()) == 0);
  EXPECT!(side_effect_0_count == 1);
  EXPECT!(side_effect_null_count == 0);
  call reset_counts();

  EXPECT!((side_effect_1() and side_effect_0()) == 0);
  EXPECT!(side_effect_0_count == 1);
  EXPECT!(side_effect_1_count == 1);
  call reset_counts();

  EXPECT!((side_effect_1() and side_effect_1()) == 1);
  EXPECT!(side_effect_1_count == 2);
  call reset_counts();

  EXPECT!((side_effect_1() and side_effect_null()) is null);
  EXPECT!(side_effect_1_count == 1);
  EXPECT!(side_effect_null_count == 1);
  call reset_counts();

  EXPECT!((side_effect_null() and side_effect_0()) == 0);
  EXPECT!(side_effect_null_count == 1);
  EXPECT!(side_effect_0_count == 1);
  call reset_counts();

  EXPECT!((side_effect_null() and side_effect_1()) is null);
  EXPECT!(side_effect_null_count == 1);
  EXPECT!(side_effect_1_count == 1);
  call reset_counts();

  EXPECT!((side_effect_null() and side_effect_null()) is null);
  EXPECT!(side_effect_null_count == 2);
  call reset_counts();

  EXPECT!((side_effect_0() or side_effect_0()) == 0);
  EXPECT!(side_effect_0_count == 2);
  EXPECT!(side_effect_1_count == 0);
  call reset_counts();

  EXPECT!((side_effect_0() or side_effect_1()) == 1);
  EXPECT!(side_effect_0_count == 1);
  EXPECT!(side_effect_1_count == 1);
  call reset_counts();

  EXPECT!((side_effect_0() or side_effect_null()) is null);
  EXPECT!(side_effect_0_count == 1);
  EXPECT!(side_effect_null_count == 1);
  call reset_counts();

  EXPECT!((side_effect_1() or side_effect_0()) == 1);
  EXPECT!(side_effect_0_count == 0);
  EXPECT!(side_effect_1_count == 1);
  call reset_counts();

  EXPECT!((side_effect_1() or side_effect_1()) == 1);
  EXPECT!(side_effect_1_count == 1);
  call reset_counts();

  EXPECT!((side_effect_1() or side_effect_null()) == 1);
  EXPECT!(side_effect_null_count == 0);
  EXPECT!(side_effect_1_count == 1);
  call reset_counts();

  EXPECT!((side_effect_null() or side_effect_0()) is null);
  EXPECT!(side_effect_0_count == 1);
  EXPECT!(side_effect_null_count == 1);
  call reset_counts();

  EXPECT!((side_effect_null() or side_effect_1()) == 1);
  EXPECT!(side_effect_null_count == 1);
  EXPECT!(side_effect_1_count == 1);
  call reset_counts();

  EXPECT!((side_effect_null() or side_effect_null()) is null);
  EXPECT!(side_effect_null_count == 2);
  call reset_counts();

  -- even though this looks like all non nulls we do not eval side_effect_1
  -- we can't use the simple && form because there is statement output
  -- requred to evaluate the coalesce.

  EXPECT!((0 and coalesce(side_effect_1(), 1)) == 0);
  EXPECT!(side_effect_1_count == 0);
  call reset_counts();

  EXPECT!((1 and coalesce(side_effect_1(), 1)) == 1);
  EXPECT!(side_effect_1_count == 1);
  call reset_counts();

  EXPECT!((1 or coalesce(side_effect_1(), 1)) == 1);
  EXPECT!(side_effect_1_count == 0);
  call reset_counts();

  EXPECT!((0 or coalesce(side_effect_1(), 1)) == 1);
  EXPECT!(side_effect_1_count == 1);
  call reset_counts();

  -- this is the same as NOT (0 < 0) rather than (NOT 0) < 0
  -- do not move NOT around or you will break stuff
  -- I have broken this many times now do not change this expectation
  -- it will save your life.
  EXPECT_SQL_TOO!(NOT 0 < 0);
END);

-- logical and short-circuit verify 1/0 not evaluated
TEST!(local_operations_early_out,
BEGIN
  EXPECT_SQL_TOO!(not (0 and 1/zero));
  EXPECT_SQL_TOO!(1 or 1/zero);
END);

-- assorted between combinations
TEST!(between_operations,
BEGIN
  EXPECT_SQL_TOO!(1 BETWEEN 0 AND 2);
  EXPECT_SQL_TOO!(NOT 3 BETWEEN 0 AND 2);
  EXPECT_SQL_TOO!(NOT 3 BETWEEN 0 AND 2);
  EXPECT_SQL_TOO!(NULL BETWEEN 0 AND 2 IS NULL);
  EXPECT_SQL_TOO!(1 BETWEEN NULL AND 2 IS NULL);
  EXPECT_SQL_TOO!(1 BETWEEN 0 AND NULL IS NULL);

  EXPECT!((-1 between side_effect_0() and side_effect_1()) == 0);
  EXPECT!(side_effect_0_count == 1);
  EXPECT!(side_effect_1_count == 0);
  call reset_counts();

  EXPECT!((0 between side_effect_0() and side_effect_1()) == 1);
  EXPECT!(side_effect_0_count == 1);
  EXPECT!(side_effect_1_count == 1);
  call reset_counts();

  EXPECT!((2 between side_effect_0() and side_effect_1()) == 0);
  EXPECT!(side_effect_0_count == 1);
  EXPECT!(side_effect_1_count == 1);
  call reset_counts();

  EXPECT!((-1 not between side_effect_0() and side_effect_1()) == 1);
  EXPECT!(side_effect_0_count == 1);
  EXPECT!(side_effect_1_count == 0);
  call reset_counts();

  EXPECT!((0 not between side_effect_0() and side_effect_1()) == 0);
  EXPECT!(side_effect_0_count == 1);
  EXPECT!(side_effect_1_count == 1);
  call reset_counts();

  EXPECT!((2 not between side_effect_0() and side_effect_1()) == 1);
  EXPECT!(side_effect_0_count == 1);
  EXPECT!(side_effect_1_count == 1);
  call reset_counts();
END);

-- assorted not between combinations
TEST!(not_between_operations,
BEGIN
  EXPECT_SQL_TOO!(3 NOT BETWEEN 0 AND 2);
  EXPECT_SQL_TOO!(NOT 1 NOT BETWEEN 0 AND 2);
  EXPECT_SQL_TOO!(NOT 1 NOT BETWEEN 0 AND 2);
  EXPECT_SQL_TOO!((NOT 1) NOT BETWEEN 0 AND 2 = 0);
  EXPECT_SQL_TOO!(1 NOT BETWEEN 2 AND 0);
  EXPECT_SQL_TOO!(0 = (NOT 7 NOT BETWEEN 5 AND 6));
  EXPECT_SQL_TOO!(1 = (NOT 7) NOT BETWEEN 5 AND 6);
  EXPECT_SQL_TOO!(NULL NOT BETWEEN 0 AND 2 IS NULL);
  EXPECT_SQL_TOO!(1 NOT BETWEEN NULL AND 2 IS NULL);
  EXPECT_SQL_TOO!(1 NOT BETWEEN 0 AND NULL IS NULL);
END);

-- assorted comparisons
TEST!(numeric_comparisons,
BEGIN
  EXPECT_SQL_TOO!(0 = zero);
  EXPECT_SQL_TOO!(1 = one);
  EXPECT_SQL_TOO!(2 = two);
  EXPECT_SQL_TOO!(NOT two = zero);
  EXPECT_SQL_TOO!(two <> zero);
  EXPECT_SQL_TOO!(NOT zero <> 0);
  EXPECT_SQL_TOO!(NOT zero == two);
  EXPECT_SQL_TOO!((NOT two) == 0);
  EXPECT_SQL_TOO!((NOT two) <> 1);
  EXPECT_SQL_TOO!(one > zero);
  EXPECT_SQL_TOO!(zero < one);
  EXPECT_SQL_TOO!(one >= zero);
  EXPECT_SQL_TOO!(zero <= one);
  EXPECT_SQL_TOO!(one >= 1);
  EXPECT_SQL_TOO!(one <= 1);
END);

TEST!(simple_funcs,
BEGIN
  EXPECT_SQL_TOO!(abs(-2) = 2);
  EXPECT_SQL_TOO!(abs(2) = 2);
  EXPECT_SQL_TOO!(abs(-2.0) = 2);
  EXPECT_SQL_TOO!(abs(2.0) = 2);

  LET t := 3L;
  EXPECT_SQL_TOO!(abs(t) = t);
  EXPECT_SQL_TOO!(abs(-t) = t);

  t := -4;
  EXPECT_SQL_TOO!(abs(t) = -t);
  EXPECT_SQL_TOO!(abs(-t) = -t);

  EXPECT!(sign(5) = 1);
  EXPECT!(sign(0.1) = 1);
  EXPECT!(sign(7L) = 1);
  EXPECT!(sign(-5) = -1);
  EXPECT!(sign(-0.1) = -1);
  EXPECT!(sign(-7L) = -1);
  EXPECT!(sign(0) = 0);
  EXPECT!(sign(0.0) = 0);
  EXPECT!(sign(0L) = 0);
END);

-- verify that out parameter is set in proc call
proc echo ( in arg1 int!, out arg2 int!)
begin
  arg2 := arg1;
end;

TEST!(out_arguments,
BEGIN
  declare scratch int!;
  call echo(12, scratch);
  EXPECT_SQL_TOO!(scratch == 12);
END);

-- test simple recursive function
proc fib (in arg int!, out result int!)
begin
  if (arg <= 2) then
    result := 1;
  else
    declare t int!;
    call fib(arg - 1,  result);
    call fib(arg - 2,  t);
    result := t + result;
  end if;
end;

TEST!(simple_recursion,
BEGIN
  EXPECT!(fib(1) == 1);
  EXPECT!(fib(2) == 1);
  EXPECT!(fib(3) == 2);
  EXPECT!(fib(4) == 3);
  EXPECT!(fib(5) == 5);
  EXPECT!(fib(6) == 8);
END);

-- test elementary cursor on select with no tables, still round trips through sqlite
TEST!(cursor_basics,
BEGIN
  declare col1 int;
  declare col2 real!;
  declare basic_cursor cursor for select 1, 2.5;
  fetch basic_cursor into col1, col2;
  EXPECT!(basic_cursor);
  EXPECT!(col1 == 1);
  EXPECT!(col2 == 2.5);
  fetch basic_cursor into col1, col2;
  EXPECT!(not basic_cursor);
END);

-- the most expensive way to swap two variables ever :)
TEST!(exchange_with_cursor,
BEGIN
  let arg1 := 7;
  let arg2 := 11;
  declare exchange_cursor cursor for select arg2, arg1;
  fetch exchange_cursor into arg1, arg2;
  EXPECT!(exchange_cursor);
  EXPECT!(arg1 == 11);
  EXPECT!(arg2 == 7);
END);

proc make_mixed()
begin
  create table mixed(
    id int!,
    name text,
    code long int,   -- these are nullable to make the cg harder
    flag bool,
    rate real,
    bl blob
  );
end;

proc drop_mixed()
begin
  drop table if exists mixed;
end;

call make_mixed();

proc load_mixed()
begin
  delete from mixed;
  insert into mixed values (1, "a name", 12, 1, 5.0, cast("blob1" as blob));
  insert into mixed values (2, "another name", 14, 3, 7.0, cast("blob2" as blob));
end;

proc load_mixed_dupes()
begin
  delete from mixed;
  insert into mixed values (1, "a name", 12, 1, 5.0, NULL);
  insert into mixed values (1, "a name", 12, 1, 5.0, NULL);
  insert into mixed values (2, "another name", 14, 3, 7.0, cast("blob2" as blob));
  insert into mixed values (2, "another name", 14, 3, 7.0, cast("blob2" as blob));
  insert into mixed values (1, "a name", 12, 1, 5.0, cast("blob1" as blob));
  insert into mixed values (1, NULL, 12, 1, 5.0, NULL);
end;

proc load_mixed_dupe_identities()
begin
  delete from mixed;
  insert into mixed values (1, "a name", 12, 1, 5.0, NULL);
  insert into mixed values (1, "another name", 12, 1, 5.0, NULL);
  insert into mixed values (1, "another name", 12, 0, 5.0, NULL);
  insert into mixed values (1, "another name", 12, 0, 5.0, cast("blob1" as blob));
  insert into mixed values (1, "another name", 14, 0, 7.0, cast("blob1" as blob));
end;

proc load_mixed_with_nulls()
begin
  call load_mixed();
  insert into mixed values (3, NULL, NULL, NULL, NULL, NULL);
  insert into mixed values (4, "last name", 16, 0, 9.0, cast("blob3" as blob));
end;

proc update_mixed(id_ int!, name_ text, code_ long int, bl_ blob)
begin
  update mixed set code = code_, bl = bl_ where id = id_;
end;

-- test readback of two rows
TEST!(read_mixed,
BEGIN
  declare id_ int!;
  declare name_ text;
  declare code_ long int;
  declare flag_ bool;
  declare rate_ real;
  declare bl_ blob;

  call load_mixed();

  declare read_cursor cursor for select * from mixed;

  fetch read_cursor into id_, name_, code_, flag_, rate_, bl_;
  EXPECT!(read_cursor);
  EXPECT!(id_ == 1);
  EXPECT!(name_ == "a name");
  EXPECT!(code_ == 12);
  EXPECT!(flag_ == 1);
  EXPECT!(rate_ == 5);
  EXPECT!(string_from_blob(bl_) == "blob1");

  fetch read_cursor into id_, name_, code_, flag_, rate_, bl_;
  EXPECT!(read_cursor);
  EXPECT!(id_ == 2);
  EXPECT!(name_ == "another name");
  EXPECT!(code_ == 14);
  EXPECT!(flag_ == 1);
  EXPECT!(rate_ == 7);
  EXPECT!(string_from_blob(bl_) == "blob2");

  fetch read_cursor into id_, name_, code_, flag_, rate_, bl_;
  EXPECT!(not read_cursor);
  close read_cursor;
END);

-- now attempt a mutation
TEST!(mutate_mixed,
BEGIN
  declare new_code long;
  declare code_ long;
  new_code := 88;
  declare id_ int;
  id_ := 2;  -- either works

  call load_mixed();

  update mixed set code = new_code where id = id_;
  declare updated_cursor cursor for select code from mixed where id = id_;
  fetch updated_cursor into code_;
  close updated_cursor;
  EXPECT!(code_ == new_code);
END);

TEST!(nested_select_expressions,
BEGIN
  -- use nested expression select
  let temp_1 := (select zero * 5 + one * 11);
  EXPECT!(temp_1 == 11);

  call load_mixed();

  temp_1 := (select id from mixed where id > 1 order by id limit 1);
  EXPECT!(temp_1 == 2);

  temp_1 := (select count(*) from mixed);
  EXPECT!(temp_1 == 2);

  let temp_2 := (select avg(id) from mixed);
  EXPECT!(temp_2 == 1.5);

  EXPECT!((select longs.neg) == -1);
  EXPECT!((select -longs.neg) == 1);
  EXPECT!((select - -longs.neg) == -1);
END);

proc make_bools()
begin
  select true x
  union all
  select false x;
end;

TEST!(bool_round_trip,
BEGIN
  declare b bool;

  -- coerce from integer
  b := (select 0);
  EXPECT!(NOT b);

  b := (select 1);
  EXPECT!(b);

  cursor C for call make_bools();
  fetch C;
  EXPECT!(C.x);
  fetch C;
  EXPECT!(not C.x);
  fetch C;
  EXPECT!(not C);

  -- capture the result set (i.e. use fetch_results)
  let result := make_bools();
  declare C2 cursor for result;
  fetch C2;
  EXPECT!(C2.x);
  fetch C2;
  EXPECT!(NOT C2.x);
  fetch C2;
  EXPECT!(not C2);
END);

-- complex delete pattern

proc delete_one_from_mixed(out _id int!)
begin
  _id := (select id from mixed order by id limit 1);
  delete from mixed where id = _id;
end;

TEST!(delete_several,
BEGIN
  call load_mixed();
  EXPECT!(2 == (select count(*) from mixed));

  declare id_ int!;
  call delete_one_from_mixed(id_);
  EXPECT!(1 == id_);
  EXPECT!(0 == (select count(*) from mixed where id = id_));
  EXPECT!(1 == (select count(*) from mixed where id != id_));

  call delete_one_from_mixed(id_);
  EXPECT!(2 == id_);
  EXPECT!(0 == (select count(*) from mixed));
END);

-- some basic string stuff using sqlite for string helpers
proc string_copy(in input text!, out output text!)
begin
  -- extra shuffling for refcount testing
  declare t text!;
  t := input;
  output := t;
end;

-- some basic string stuff using sqlite for string helpers
proc string_equal(in t1 text!, in t2 text!, out result bool!)
begin
  result := (select t1 == t2);
end;

-- try out some string lifetime functions
TEST!(string_ref_test,
BEGIN
  declare a_string text!;
  call string_copy("Hello", a_string);
  declare result bool!;
  call string_equal(a_string, "Hello", result);
  EXPECT!(result);
END);

-- try out some string comparisons
TEST!(string_comparisons,
BEGIN
  let t1 := "a";
  let t2 := "b";
  let t3 := "a";

  EXPECT_SQL_TOO!("a" == "a");
  EXPECT_SQL_TOO!("a" IS "a");
  EXPECT_SQL_TOO!("a" != "b");
  EXPECT_SQL_TOO!("a" IS NOT "b");
  EXPECT_SQL_TOO!(t1 < t2);
  EXPECT_SQL_TOO!(t2 > t1);
  EXPECT_SQL_TOO!(t1 <= t2);
  EXPECT_SQL_TOO!(t2 >= t1);
  EXPECT_SQL_TOO!(t1 <= t3);
  EXPECT_SQL_TOO!(t3 >= t1);
  EXPECT_SQL_TOO!(t1 == t3);
  EXPECT_SQL_TOO!(t1 != t2);
END);

-- string comparison nullability checks
TEST!(string_comparisons_nullability,
BEGIN
  declare null_ text;
  let x := "x";
  EXPECT_SQL_TOO!((nullable(x) < nullable(x)) is not null);
  EXPECT_SQL_TOO!((nullable(x) > nullable("x")) is not null);
  EXPECT_SQL_TOO!((null_ > x) is null);
  EXPECT_SQL_TOO!((x > null_) is null);
  EXPECT_SQL_TOO!((null_ > null_) is null);
  EXPECT_SQL_TOO!((null_ == null_) is null);
END);

-- string is null and is not null tests
TEST!(string_is_null_or_not,
BEGIN
  declare null_ text;
  let x := "x";
  let y := nullable("y");

  EXPECT_SQL_TOO!(null_ is null);
  EXPECT_SQL_TOO!(nullable(x) is not null);
  EXPECT_SQL_TOO!(y is not null);
  EXPECT_SQL_TOO!(not (null_ is not null));
  EXPECT_SQL_TOO!(not (nullable(x) is null));
  EXPECT_SQL_TOO!(not (y is null));

END);

-- binding tests for not null types
TEST!(bind_not_nullables,
BEGIN
  let b := true;
  let i := 2;
  let l := 3L;
  let r := 4.5;
  let t := "foo";

  EXPECT!(b == (select b)); -- binding not null bool
  EXPECT!(i == (select i)); -- binding not null int
  EXPECT!(l == (select l)); -- binding not null long
  EXPECT!(r == (select r)); -- binding not null real
  EXPECT!(t == (select t)); -- binding not null text

  EXPECT!(b != (select not b)); -- binding not null bool
  EXPECT!(i != (select 1 + i)); -- binding not null int
  EXPECT!(l != (select 1 + l)); -- binding not null long
  EXPECT!(r != (select 1 + r)); -- binding not null real
END);

-- binding tests for nullable types
TEST!(bind_nullables_not_null,
BEGIN
  let b := true:nullable;
  let i := 2:nullable;
  let l := 3L:nullable;
  let r := 4.5:nullable;
  let t := "foo":nullable;

  EXPECT!(b == (select b)); -- binding nullable not null bool
  EXPECT!(i == (select i)); -- binding nullable not null int
  EXPECT!(l == (select l)); -- binding nullable not null long
  EXPECT!(r == (select r)); -- binding nullable not null real
  EXPECT!(t == (select t)); -- binding nullable not null text

  EXPECT!(b != (select not b)); -- binding nullable not null bool
  EXPECT!(i != (select 1 + i)); -- binding nullable not null int
  EXPECT!(l != (select 1 + l)); -- binding nullable not null long
  EXPECT!(r != (select 1 + r)); -- binding nullable not null real
END);

-- binding tests for nullable types values null
TEST!(bind_nullables_null,
BEGIN
  declare b bool;
  declare i int;
  declare l long;
  declare r real;
  declare t text;

  b := null;
  i := null;
  l := null;
  r := null;
  t := null;

  EXPECT!((select b) is null); -- binding null bool
  EXPECT!((select i) is null); -- binding null int
  EXPECT!((select l) is null); -- binding null long
  EXPECT!((select r) is null); -- binding null real
  EXPECT!((select t) is null); -- binding null text

END);

TEST!(loop_fetch,
BEGIN
  declare id_ int!;
  declare name_ text;
  declare code_ long int;
  declare flag_  bool;
  declare rate_ real;
  declare bl_ blob;
  declare count, sum int!;

  call load_mixed();

  declare read_cursor cursor for select * from mixed;

  count := 0;
  sum := 0;
  loop fetch read_cursor into id_, name_, code_, flag_, rate_, bl_
  begin
    count += 1;
    sum := sum + id_;
  end;

  EXPECT!(count == 2);  -- there should be two rows
  EXPECT!(sum  == 3);   -- some math along the way
END);

proc load_more_mixed()
begin
  delete from mixed;
  insert into mixed values (1, "a name", 12, 1, 5.0, NULL);
  insert into mixed values (2, "some name", 14, 3, 7.0, NULL);
  insert into mixed values (3, "yet another name", 15, 3, 17.4, NULL);
  insert into mixed values (4, "some name", 19, 4, 9.1, NULL);
  insert into mixed values (5, "what name", 21, 8, 12.3, NULL);
end;

TEST!(loop_control_flow,
BEGIN
  call load_more_mixed();

  cursor C for select * from mixed;

  let count := 0;
  loop fetch C
  begin
    -- skip number two
    if C.id == 2 continue;
    count += 1;

    -- should break on number 4
    if C.name == "some name" leave;
  end;

  EXPECT!(count == 3); -- there should be three rows tested
  EXPECT!(C.id  == 4);  -- the match goes with id #4
END);

-- basic test of while loop plus leave and continue
TEST!(while_control_flow,
BEGIN
  let i := 0;
  let sum := 0;
  while i < 5
  begin
    i += 1;
    sum += i;
  end;

  EXPECT!(i == 5);  -- loop ended on time
  EXPECT!(sum == 15); -- correct sum computed: 1+2+3+4+5

  i := 0;
  sum := 0;
  while i < 5
  begin
    i += 1;
    if i == 2 continue;

    if i == 4 leave;
    sum += i;
  end;

  EXPECT!(i == 4);  -- loop ended on time
  EXPECT!(sum == 4);  -- correct sum computed: 1+3
END);

-- same test but the control variable is nullable making the expression nullable
TEST!(while_control_flow_with_nullables,
BEGIN
  let i := 0;
  let sum := 0;
  while i < 5
  begin
    i += 1;
    sum += i;
  end;

  EXPECT!(i == 5); -- loop ended on time
  EXPECT!(sum == 15);  -- correct sum computed: 1+2+3+4+5
END);

-- like predicate test
TEST!(like_predicate,
BEGIN
  EXPECT_SQL_TOO!("this is a test" like "%is a%");
  EXPECT_SQL_TOO!(not ("this is a test" like "is a"));

  declare txt text;
  EXPECT_SQL_TOO!(("" like txt) is null);
  EXPECT_SQL_TOO!((txt like "%") is null);
  EXPECT_SQL_TOO!((txt like txt) is null);
END);

-- error handling with try catch throw
proc throws(out did_throw bool!)
begin
  did_throw := false;
  try
    -- this fails, there is no such row
    let x := (select id from mixed where id = 999);
  catch
    did_throw := true;
    -- and rethrow!
    throw;
  end;
  -- test fails if this runs, it should not
  let divide_by_zero := one / zero;  -- this does not run
end;

TEST!(throw_and_catch,
BEGIN
  let did_throw := false;
  let did_continue := false;
  try
    call throws(did_throw);
    let divide_by_zero := one / zero;  -- this does not run
  catch
    did_continue := true;
  end;
  EXPECT!(did_throw);  -- exception was caught
  EXPECT!(did_continue);  -- execution continued
END);

-- the catch block should not run if no errors
TEST!(throw_and_not_catch,
BEGIN
  declare did_catch int!;
  try
    did_catch := 0;
  catch
    did_catch := 1;
  end;
  EXPECT!(did_catch == 0); -- catch did not run
END);

TEST!(cql_throw,
BEGIN
   let result := -1;
   try
     cql_throw(12345);
   catch
     result := @rc;
   end;
   EXPECT!(result = 12345);
END);

proc case_tester1(value int!, out result int)
begin
  result := CASE value
    WHEN 1 THEN 100
    WHEN 2 THEN 200
    WHEN 3 THEN 300
    ELSE 400
  END;
end;

proc case_tester2(value int!, out result int)
begin
  result := CASE value
    WHEN 1 THEN 100
    WHEN 2 THEN 200
    WHEN 3 THEN 300
  END;
end;

TEST!(simple_case_test,
BEGIN
  declare result int;

  call case_tester1(1, result);
  EXPECT!(result == 100);
  call case_tester1(2, result);
  EXPECT!(result == 200);
  call case_tester1(3, result);
  EXPECT!(result == 300);
  call case_tester1(5, result);
  EXPECT!(result == 400);

  call case_tester2(1, result);
  EXPECT!(result == 100);
  call case_tester2(2, result);
  EXPECT!(result == 200);
  call case_tester2(3, result);
  EXPECT!(result == 300);
  call case_tester2(5, result);
  EXPECT!(result is null);
END);

proc string_case_tester1(value text, out result text)
begin
  result := CASE value
    WHEN "1" THEN "100"
    WHEN "2" THEN "200"
    WHEN "3" THEN "300"
  END;
end;

TEST!(string_case_test,
BEGIN
  let result := string_case_tester1("1");
  EXPECT!(result == "100");

  result := string_case_tester1("2");
  EXPECT!(result == "200");

  result := string_case_tester1("3");
  EXPECT!(result == "300");

  result := string_case_tester1("5");
  EXPECT!(result is null);
END);

proc in_tester1(value int!, out result bool!)
begin
  result := value in (1, 2, 3);
end;

TEST!(in_test_not_null,
BEGIN
  declare result bool!;
  call in_tester1(1, result);
  EXPECT!(result);
  call in_tester1(2, result);
  EXPECT!(result);
  call in_tester1(3, result);
  EXPECT!(result);
  call in_tester1(4, result);
  EXPECT!(not result);
END);

proc in_tester2(value int, out result bool)
begin
  declare two int;
  two := 2;
  result := value in (1, two, 3);
end;

TEST!(in_test_nullables,
BEGIN
  declare result bool;
  call in_tester2(1, result);
  EXPECT!(result);
  call in_tester2(2, result);
  EXPECT!(result);
  call in_tester2(3, result);
  EXPECT!(result);
  call in_tester2(4, result);
  EXPECT!(not result);
  call in_tester2(null, result);
  EXPECT!(result is null);
END);

proc nullables_case_tester(value int, out result int!)
begin
  -- this is a very weird way to get a bool
  result := case 1 when value then 1 else 0 end;
end;

TEST!(nullable_when_test,
BEGIN
  declare result int!;
  call nullables_case_tester(1, result);
  EXPECT!(result == 1);
  call nullables_case_tester(0, result);
  EXPECT!(result == 0);
END);

proc nullables_case_tester2(value int, out result int!)
begin
  -- this is a very weird way to get a bool
  result := case when value then 1 else 0 end;
end;

TEST!(nullable_when_pred_test,
BEGIN
  declare result int!;
  call nullables_case_tester(1, result);
  EXPECT!(result == 1);
  call nullables_case_tester(0, result);
  EXPECT!(result == 0);
  call nullables_case_tester(null, result);
  EXPECT!(result == 0);
END);

proc in_string_tester(value text, out result bool)
begin
  result := value in ("this", "that");
end;

TEST!(string_in_test,
BEGIN
  declare result bool;
  call in_string_tester("this", result);
  EXPECT!(result);
  call in_string_tester("that", result);
  EXPECT!(result);
  call in_string_tester("at", result);
  EXPECT!(not result);
  call in_string_tester(null, result);
  EXPECT!(result is null);
END);

TEST!(string_between_test,
BEGIN
  declare n1, n2, n3 text;
  declare s1, s2, s3 text!;

  n1 := "1";
  n2 := "2";
  n3 := "3";
  s1 := "1";
  s2 := "2";
  s3 := "3";

  EXPECT_SQL_TOO!(s2 between s1 and s3);
  EXPECT_SQL_TOO!(not (s2 between s3 and s1));
  EXPECT_SQL_TOO!(1 + (s2 between s1 and s3) == 2);

  EXPECT_SQL_TOO!(n2 between n1 and n3);
  EXPECT_SQL_TOO!(not (n2 between n3 and n1));

  n2 := null;
  EXPECT_SQL_TOO!((n2 between n1 and n3) is null);
  n2 := "2";

  n1 := null;
  EXPECT_SQL_TOO!((n2 between n1 and n3) is null);
  n1 := "1";

  n3 := null;
  EXPECT_SQL_TOO!((n2 between n1 and n3) is null);
  n3 := "3";
END);

TEST!(string_not_between_test,
BEGIN
  declare n1, n2, n3 text;
  declare s1, s2, s3 text!;

  n1 := "1";
  n2 := "2";
  n3 := "3";
  s1 := "1";
  s2 := "2";
  s3 := "3";

  EXPECT_SQL_TOO!(not (s2 not between s1 and s3));
  EXPECT_SQL_TOO!(s2 not between s3 and s1);
  EXPECT_SQL_TOO!(1 + (s2 not between s1 and s3) == 1);

  EXPECT_SQL_TOO!(not (n2 not between n1 and n3));
  EXPECT_SQL_TOO!(n2 not between n3 and n1);

  n2 := null;
  EXPECT_SQL_TOO!((n2 not between n1 and n3) is null);
  n2 := "2";

  n1 := null;
  EXPECT_SQL_TOO!((n2 not between n1 and n3) is null);
  n1 := "1";

  n3 := null;
  EXPECT_SQL_TOO!((n2 not between n1 and n3) is null);
  n3 := "3";
END);

proc maybe_commit(do_commit bool!)
begin
  call load_mixed();
  begin transaction;
  delete from mixed where id = 1;
  EXPECT!(1 == (select count(*) from mixed)); -- delete successful
  if do_commit then
    commit transaction;
  else
    rollback transaction;
  end if;
end;

TEST!(transaction_mechanics,
BEGIN
  call maybe_commit(1);
  EXPECT!(1 == (select count(*) from mixed)); -- commit successful
  call maybe_commit(0);
  EXPECT!(2 == (select count(*) from mixed)); -- rollback successful
END);

@attribute(cql:identity=(id, code, bl))
@attribute(cql:generate_copy)
proc get_mixed(lim int!)
begin
  select * from mixed limit lim;
end;

@attribute(cql:generate_copy)
proc get_one_from_mixed(id_ int!)
begin
  cursor C for select * from mixed where id = id_;
  fetch C;
  out C;
end;

TEST!(proc_loop_fetch,
BEGIN
  call load_mixed();

  declare read_cursor cursor for call get_mixed(200);

  let count := 0;
  loop fetch read_cursor
  begin
    count += 1;
  end;

  EXPECT!(count == 2); -- there should be two rows
END);

proc savepoint_maybe_commit(do_commit bool!)
begin
  call load_mixed();
  savepoint foo;
  delete from mixed where id = 1;
  EXPECT!(1 == (select count(*) from mixed));  -- delete successful
  if do_commit then
    release savepoint foo;
  else
    rollback transaction to savepoint foo;
  end if;
end;

TEST!(savepoint_mechanics,
BEGIN
  call savepoint_maybe_commit(1);
  EXPECT!(1 == (select count(*) from mixed));  -- savepoint commit successful
  call savepoint_maybe_commit(0);
  EXPECT!(2 == (select count(*) from mixed));  -- savepoint rollback successful
END);

TEST!(exists_test,
BEGIN
  call load_mixed();
  EXPECT!((select EXISTS(select * from mixed)));  -- exists found rows
  delete from mixed;
  EXPECT!((select NOT EXISTS(select * from mixed)));  -- not exists found no rows
END);

proc bulk_load_mixed(rows_ int!)
begin
  delete from mixed;

  let i := 0;
  while i < rows_
  begin
    insert into mixed values (i, "a name", 12, 1, 5.0, cast(i as blob));
    i += 1;
  end;
end;

TEST!(complex_nested_selects,
BEGIN
  create table vals(id int, val int);
  create table codes(id int, code int);

  insert into vals values(1, 100);
  insert into vals values(2, 200);
  insert into vals values(3, 300);

  insert into codes values(1, 1000);
  insert into codes values(1, 1001);
  insert into codes values(1, 1002);
  insert into codes values(2, 2000);
  insert into codes values(2, 2001);
  insert into codes values(3, 3000);

  declare c1 cursor for select id from vals as T1 where exists (select * from codes as T2 where T1.id == T2.id and T2.code % 1000 == 1);

  declare id_ int;
  declare count_ int;
  loop fetch c1 into id_
  begin
    EXPECT!(case id_ when 1 then 1 when 2 then 1 else 0 end);
  end;

  declare c2 cursor for
    select id, (select count(*) from codes T2 where T2.id = T1.id) as code_count
    from vals T1
    where val >= 7;
  loop fetch c2 into id_, count_
  begin
    EXPECT!(count_ == case id_ when 1 then 3 when 2 then 2 when 3 then 1 else 0 end);
  end;
END);

TEST!(proc_loop_auto_fetch,
BEGIN
  declare count, sum int!;

  call load_mixed();

  declare read_cursor cursor for call get_mixed(200);

  count := 0;
  sum := 0;
  loop fetch read_cursor
  begin
    count += 1;
    sum := sum + read_cursor.id;
  end;

  EXPECT!(count == 2);  -- there should be two rows
  EXPECT!(sum  == 3);  -- id checksum
END);

TEST!(coalesce,
BEGIN
  let i := null ~int~;
  EXPECT_SQL_TOO!(coalesce(i, i, 2) == 2); -- grab the not null last value
  EXPECT_SQL_TOO!(ifnull(i, 2) == 2); -- grab the not null last value

  i := nullable(3);
  EXPECT_SQL_TOO!(coalesce(i, i, 2) == 3); -- grab the not null first value
  EXPECT_SQL_TOO!(ifnull(i, 2) == 3); -- grab the not null first value
END);

TEST!(printf_expression,
BEGIN
  EXPECT!(printf("%d and %d", 12, 7) == "12 and 7"); -- loose printf ok
  EXPECT!((select printf("%d and %d", 12, 7)) == "12 and 7"); -- sql printf ok
END);

TEST!(case_with_null,
BEGIN
  let x := null ~int~;
  x := case x when 0 then 1 else 2 end;
  EXPECT!(x == 2); --null only matches the else
END);

TEST!(group_concat,
BEGIN
  create table conc_test(id int, name text);
  insert into conc_test values (1,"x");
  insert into conc_test values (1,"y");
  insert into conc_test values (2,"z");
  cursor C for select id, group_concat(name) as vals from conc_test group by id;
  fetch C;
  EXPECT!(C.id = 1);
  EXPECT!(C.vals = "x,y");
  fetch C;
  EXPECT!(C.id = 2);
  EXPECT!(C.vals = "z");
END);

TEST!(strftime,
BEGIN
  var _null text;

  -- sql strftime ok
  EXPECT!((select strftime("%s", "1970-01-01T00:00:03")) == "3");

 -- strftime null format ok
  EXPECT!((select strftime(_null, "1970-01-01T00:00:03")) is null);

  -- strftime null timestring ok
  EXPECT!((select strftime("%s", _null)) is null);

 -- strftime null timestring ok
  EXPECT!((select strftime("%s", "1970-01-01T00:00:03", "+1 day")) == "86403");

 -- strftime with multiple modifiers on now ok
  EXPECT!((select strftime("%W", "now", "+1 month", "start of month", "-3 minutes", "weekday 4")) is not null);
END);

TEST!(cast_expr,
BEGIN
  EXPECT!((select cast(1.3 as int)) == 1); -- cast expression
END);

let uuux := 5;

TEST!(type_check_,
BEGIN
  let int_val := type_check(1 as int!);
  EXPECT!(int_val == 1);

  let int_cast_val := type_check(1 ~int<foo>~ as int<foo> not null);
  EXPECT!(int_cast_val == 1);
END);

TEST!(union_all_test,
BEGIN
  cursor C for
    select 1 as A, 2 as B
    union all
    select 3 as A, 4 as B;
  fetch C;
  EXPECT!(C.A = 1);
  EXPECT!(C.B = 2);
  fetch C;
  EXPECT!(C.A = 3);
  EXPECT!(C.B = 4);
END);

TEST!(union_test,
BEGIN
  cursor C for
    select 1 as A, 2 as B
    union
    select 1 as A, 2 as B;
  fetch C;
  EXPECT!(C.A = 1);
  EXPECT!(C.B = 2);
  fetch C;
  EXPECT!(NOT C); -- no more rows
END);

TEST!(union_test_with_nullable,
BEGIN
  cursor C for
    select nullable(121) as A, 212 as B
    union
    select nullable(121) as A, 212 as B;
  fetch C;
  EXPECT!(C.A = 121);
  EXPECT!(C.B = 212);
  fetch C;
  EXPECT!(NOT C);
END);

TEST!(with_test,
BEGIN
  cursor C for
    with X(A,B) as ( select 1,2)
    select * from X;

  fetch C;
  EXPECT!(C.A = 1);
  EXPECT!(C.B = 2);
  fetch C;
  EXPECT!(NOT C);
END);

TEST!(with_recursive_test,
BEGIN
cursor C for
  with recursive
    c1(current) as (
      select 1
      union all
      select current+1 from c1
      limit 5
    ),
    c2(current) as (
      select 6
      union all
      select current+1 from c2
      limit 5
    )
  select current as X from c1
  union all
  select current as X from c2;

  declare i int!;
  i := 1;

  loop fetch C
  begin
    EXPECT!(C.X == i); -- iterating over the recursive result
    i += 1;
  end;
  EXPECT!(i == 11); -- 10 results matched, 11th did not match
END);

proc outint(out int1 int, out int2 int!)
begin
  declare C1 cursor for select 1;
  fetch C1 into int1;
  declare C2 cursor for select 2;
  fetch C2 into int2;
END;

TEST!(fetch_output_param,
BEGIN
  declare out call outint(int1, int2);
  EXPECT!(int1 == 1); -- bind output nullable
  EXPECT!(int2 == 2); -- bind output not nullable
END);

declare function run_test_math(int1 int!, out int2 int) int!;
declare function string_create() create text;
declare function string_ref_count(str text) int!;

TEST!(external_functions,
BEGIN
  declare int_out int;

  let int_result := run_test_math(100, int_out);
  EXPECT!(int_out == 500);
  EXPECT!(int_result == 700);

  let text_result := string_create();

  EXPECT!(text_result like "%Hello%");
END);

TEST!(rev_appl_operator,
BEGIN
  declare int_out int;

  let int_result := 100:run_test_math(int_out);
  EXPECT_SQL_TOO!(int_out == 500);
  EXPECT_SQL_TOO!(int_result == 700);

  declare int_out2 int;
  declare int_out3 int;
  declare int_result2 int!;

  -- test left associativity, given that this does not raise any errors, we know this is left associative
  int_result2 := 10:run_test_math(int_out2):run_test_math(int_out3);
  EXPECT_SQL_TOO!(int_out2 == 50);
  EXPECT_SQL_TOO!(int_out3 == 350);
  EXPECT_SQL_TOO!(int_result2 == 490);
END);

declare function set_create() create object!;
declare function set_add(_set object!, _key text!) bool!;
declare function set_contains(_set object!, _key text!) bool!;

TEST!(external_set,
BEGIN
  -- stress the create and copy semantics
  declare _set object!;
  _set := set_create();
  declare _set2 object!;
  _set2 := set_create();
  _set := _set2; -- this is a copy

  EXPECT!(nullable(_set) is not null);  -- successful create
  EXPECT!(not set_contains(_set, "garbonzo")); -- initially empty
  EXPECT!(set_add(_set, "garbonzo")); -- successful addition
  EXPECT!(set_contains(_set, "garbonzo")); -- key added
  EXPECT!(not set_add(_set, "garbonzo")); -- duplicate addition
END);

TEST!(object_notnull,
BEGIN
  declare _setNN object!;
  declare _set object;
  _set := nullable(set_create());
  _setNN := ifnull_crash(_set);
  EXPECT!(_set == _setNN); -- should be the same pointer
END);

TEST!(dummy_values,
BEGIN
  delete from mixed;
  let i := 0;
  while (i < 20)
  begin
    insert into mixed (bl) values (cast(i as blob)) @dummy_seed(i) @dummy_nullables @dummy_defaults;
    i += 1;
  end;

  cursor C for select * from mixed;
  i := 0;
  while (i < 20)
  begin
    fetch C;
    EXPECT!(C.id == i);
    EXPECT!(C.name == printf("name_%d", i));
    EXPECT!(C.code == i);
    EXPECT!(not C.flag == not i);
    EXPECT!(C.rate == i);
    i += 1;
  end;
END);

TEST!(blob_basics,
BEGIN
  let s := "a string";
  let b := blob_from_string(s);
  let s2 := string_from_blob(b);
  EXPECT!(s == s2); -- blob conversion failed
  EXPECT!(b == blob_from_string("a string"));
  EXPECT!(b IS blob_from_string("a string"));
  EXPECT!(b <> blob_from_string("a strings"));
  EXPECT!(b IS NOT blob_from_string("a strings"));

  declare b_null blob;
  b_null := null;
  declare s_null text;
  s_null := null;
  EXPECT!(b_null IS b_null);
  EXPECT!(s_null IS s_null);
  EXPECT!(b_null IS NOT b);
  EXPECT!(s_null IS NOT s);
  EXPECT!(b_null IS NULL);
  EXPECT!(s_null IS NULL);
END);

proc blob_table_maker()
begin
  create table if not exists blob_table(
    id int!,
    b1 blob,
    b2 blob!
  );
  delete from blob_table;
end;

proc load_blobs()
begin
  call blob_table_maker();

  let i := 0;
  let count := 20;

  declare b1 blob;
  declare b2 blob!;

  while (i < count)
  begin
    let s := printf("nullable blob %d", i);
    b1 := blob_from_string(s);
    s := printf("not nullable blob %d", i);
    b2 := blob_from_string(s);
    insert into blob_table(id, b1, b2) values (i, b1, b2);
    i += 1;
  end;
end;

TEST!(blob_data_manip,
BEGIN
  call load_blobs();

  cursor C for select * from blob_table order by id;
  let i := 0;
  let count := 20;

  loop fetch C
  begin
    declare s1, s2 text;
    EXPECT!(i == C.id);

    s1 := string_from_blob(c.b1);
    EXPECT!(s1 == printf("nullable blob %d", i)); -- nullable blob failed to round trip

    s2 := string_from_blob(c.b2);
    EXPECT!(s2 == printf("not nullable blob %d", i)); -- not nullable blob failed to round trip

    i += 1;
  end;

  EXPECT!(i == count); -- wrong number of rows
END);

proc get_blob_table()
begin
  select * from blob_table;
end;

proc load_sparse_blobs()
begin
  call blob_table_maker();

  declare s text!;
  declare b1 blob;
  declare b2 blob!;

  let i := 0;
  let count := 20;

  while (i < count)
  begin
    s := printf("nullable blob %d", i);
    b1 := case when i % 2 == 0 then blob_from_string(s) else null end;
    s := printf("not nullable blob %d", i);
    b2 := blob_from_string(s);
    insert into blob_table(id, b1, b2) values (i, b1, b2);
    i += 1;
  end;
end;

TEST!(blob_data_manip_nullables,
BEGIN
  cursor C for select * from blob_table order by id;
  let i := 0;
  let count := 20;

  call load_sparse_blobs();

  loop fetch C
  begin
    declare s1, s2 text;
    s1 := string_from_blob(C.b1);
    EXPECT!(i == C.id);
    if i % 2 == 0 then
      s1 := string_from_blob(C.b1);
      EXPECT!(s1 == printf("nullable blob %d", i)); -- nullable blob failed to round trip
    else
      EXPECT!(C.b1 is null);
    end if;
    s2 := string_from_blob(C.b2);
    EXPECT!(s2 == printf("not nullable blob %d", i)); -- not nullable blob failed to round trip
    i += 1;
  end;

  EXPECT!(i == count); -- wrong number of rows
END);

proc row_getter(x int!, y real!, z text)
begin
  cursor C for select x X, y Y, z Z;
  fetch C;
  out C;
end;

TEST!(data_reader,
BEGIN
  cursor C fetch from call row_getter(1, 2.5, "xyzzy");
  EXPECT!(C.X == 1);
  EXPECT!(C.Y == 2.5);
  EXPECT!(C.Z == "xyzzy");
END);

-- test simple recursive function -- using func syntax!
proc fib2 (in arg int!, out result int!)
begin
  if (arg <= 2) then
    result := 1;
  else
    result := fib2(arg-1) + fib2(arg-2);
  end if;
end;

TEST!(recurse_with_proc,
BEGIN
  EXPECT!(fib2(1) == 1);
  EXPECT!(fib2(2) == 1);
  EXPECT!(fib2(3) == 2);
  EXPECT!(fib2(4) == 3);
  EXPECT!(fib2(5) == 5);
  EXPECT!(fib2(6) == 8);
END);

-- test simple recursive function -- using func syntax!
proc fib3 (in arg int!, out result int!)
begin
  if (arg <= 2) then
    result := (select 1); -- for this to be a dml proc
  else
    result := fib3(arg-1) + fib3(arg-2);
  end if;
end;

TEST!(recurse_with_dml_proc,
BEGIN
  -- we force all the error handling code to run with this flavor
  EXPECT!(fib3(1) == 1);
  EXPECT!(fib3(2) == 1);
  EXPECT!(fib3(3) == 2);
  EXPECT!(fib3(4) == 3);
  EXPECT!(fib3(5) == 5);
  EXPECT!(fib3(6) == 8);
END);

TEST!(row_id_test,
BEGIN
  call load_mixed();
  cursor C for select rowid from mixed;
  declare r int!;
  r := 1;

  loop fetch C
  begin
    EXPECT!(C.rowid == r);
    r := r + 1;
  end;
END);


TEST!(bind_and_fetch_all_types,
BEGIN
  let i := 10;
  let l := 1234567890156789L;
  let r := 1234.45;
  let b := 1;
  let s := "string";
  let bl := blob_from_string("blob text");

  EXPECT!(13*i == (select 13*i));
  EXPECT!(13*l == (select 13*l));
  EXPECT!(13*r == (select 13*r));
  EXPECT!(not b == (select not b));
  EXPECT!(printf("foo %s", s) == (select printf("foo %s", s)));
  EXPECT!("blob text" == string_from_blob((select bl)));
END);

TEST!(bind_and_fetch_all_types_nullable,
BEGIN
  declare i int;
  declare l long;
  declare r real;
  declare b bool;
  declare s text;
  declare bl blob;

  i := nullable(10);
  l := nullable(1234567890156789L);
  r := nullable(1234.45);
  b := nullable(1);
  s := nullable("string");
  bl := nullable(blob_from_string("blob text"));

  EXPECT!(13*i == (select 13*i));
  EXPECT!(13*l == (select 13*l));
  EXPECT!(13*r == (select 13*r));
  EXPECT!(not b == (select not b));
  EXPECT!(printf("foo %s", s) == (select printf("foo %s", s)));
  EXPECT!("blob text" == string_from_blob((select bl)));
END);

TEST!(fetch_all_types_cursor,
BEGIN
  declare i int!;
  declare l long!;
  declare r real!;
  declare b bool!;
  declare s text!;
  declare bl blob!;

  i := 10;
  l := 1234567890156789L;
  r := 1234.45;
  b := 1;
  s := "string";
  bl := blob_from_string("blob text");

  cursor C for select i*13 i, l*13 l, r*13 r, not b b, printf("foo %s",s) s, bl bl;
  fetch C;
  EXPECT!(13*i == C.i);
  EXPECT!(13*l == C.l);
  EXPECT!(13*r == C.r);
  EXPECT!(not b == C.b);
  EXPECT!(printf("foo %s", s) == C.s);
  EXPECT!("blob text" == string_from_blob(C.bl));

  fetch C;
  EXPECT!(not C);
  EXPECT!(C.i ==  0);
  EXPECT!(C.l ==  0);
  EXPECT!(C.r ==  0);
  EXPECT!(C.b ==  0);
  EXPECT!(nullable(C.s) is null); -- even though s is not null, it is null... sigh
  EXPECT!(nullable(c.bl) is null); -- even though bl is not null, it is null... sigh
END);

TEST!(fetch_all_types_cursor_nullable,
BEGIN
  declare i int;
  declare l long;
  declare r real;
  declare b bool;
  declare s text;
  declare bl blob;

  i := nullable(10);
  l := nullable(1234567890156789L);
  r := nullable(1234.45);
  b := nullable(1);
  s := nullable("string");
  bl := nullable(blob_from_string("blob text"));

  cursor C for select i*13 i, l*13 l, r*13 r, not b b, printf("foo %s",s) s, bl bl;
  fetch C;
  EXPECT!(C);
  EXPECT!(13*i == C.i);
  EXPECT!(13*l == C.l);
  EXPECT!(13*r == C.r);
  EXPECT!(not b == C.b);
  EXPECT!(printf("foo %s", s) == C.s);
  EXPECT!("blob text" == string_from_blob(C.bl));

  fetch C;
  EXPECT!(not C);
  EXPECT!(C.i is null);
  EXPECT!(C.l is null);
  EXPECT!(C.r is null);
  EXPECT!(C.b is null);
  EXPECT!(nullable(C.s) is null);
  EXPECT!(nullable(c.bl) is null);
END);

TEST!(concat_pri,
BEGIN
  -- concat is weaker than ~
  EXPECT!('-22' == (SELECT ~1||2));
  EXPECT!('-22' == (SELECT (~1)||2));

  -- if the order was otherwise we'd get a different result...
  -- a semantic error actually
  EXPECT!(-13 == (SELECT ~CAST(1||2 as INTEGER)));

  --- negation is stronger than CONCAT
  EXPECT!('01' == (select -0||1));
  EXPECT!('01' == (select (-0)||1));

  -- if the order was otherwise we'd get a different result...
  -- a semantic error actually
  EXPECT!(-1 == (select -CAST(0||1 as INTEGER)));

END);

-- Test precedence of multiply with (* / %) with add (+ -)
TEST!(multiply_pri,
BEGIN
  EXPECT_SQL_TOO!(1+2*3 == 7);
  EXPECT_SQL_TOO!(1+2*3+4*5 == 27);
  EXPECT_SQL_TOO!(1+2/2 == 2);
  EXPECT_SQL_TOO!(1+2/2*4 == 5);
  EXPECT_SQL_TOO!(1+2/2*4 == 5);
  EXPECT_SQL_TOO!(1*2+3 == 5);
  EXPECT_SQL_TOO!(1*2+6/3 == 4);
  EXPECT_SQL_TOO!(1*2+6/3 == 4);
  EXPECT_SQL_TOO!(2*3*4+3/3 == 25);
  EXPECT_SQL_TOO!(-5*5 == -25);
  EXPECT_SQL_TOO!(5-5*5 == -20);
  EXPECT_SQL_TOO!(4+5*5 == 29);
  EXPECT_SQL_TOO!(4*5+5 == 25);
  EXPECT_SQL_TOO!(4*4-1 == 15);
  EXPECT_SQL_TOO!(10-4*2 == 2);
  EXPECT_SQL_TOO!(25%3/2 == 0);
  EXPECT_SQL_TOO!(25/5%2 == 1);
  EXPECT_SQL_TOO!(25*5%2 == 1);
  EXPECT_SQL_TOO!(25*5%4%2 == 1);
  EXPECT_SQL_TOO!(25-5%2 == 24);
  EXPECT_SQL_TOO!(15%3-2 == -2);
  EXPECT_SQL_TOO!(15-30%4 == 13);
  EXPECT_SQL_TOO!(15-30/2 == 0);
  EXPECT_SQL_TOO!(15/5-3 == 0);
  EXPECT_SQL_TOO!(15*5-3 == 72);
  EXPECT_SQL_TOO!(5*5-3 == 22);
  EXPECT_SQL_TOO!(25+5%2 == 26);
  EXPECT_SQL_TOO!(15%3+2 == 2);
  EXPECT_SQL_TOO!(15+30%4 == 17);
  EXPECT_SQL_TOO!(15+30/2 == 30);
  EXPECT_SQL_TOO!(15/5+3 == 6);
  EXPECT_SQL_TOO!(15*5+3 == 78);
  EXPECT_SQL_TOO!(5*5+3 == 28);
  EXPECT_SQL_TOO!(5*12/3 == 20);
  EXPECT_SQL_TOO!(5*12/3%7 == 6);
  EXPECT_SQL_TOO!(9%12/3*7 == 21);
END);

-- Test precedence of binary (<< >> & |) with add (+ -)
TEST!(shift_pri,
BEGIN
  EXPECT_SQL_TOO!(10<<1+1 == 40);
  EXPECT_SQL_TOO!(1+10<<1 == 22);
  EXPECT_SQL_TOO!(10<<1-1 == 10);
  EXPECT_SQL_TOO!(10<<4-1 == 80);
  EXPECT_SQL_TOO!(10-1<<1 == 18);

  EXPECT_SQL_TOO!(10>>3-1 == 2);
  EXPECT_SQL_TOO!(11-1>>1 == 5);
  EXPECT_SQL_TOO!(10>>1+1 == 2);
  EXPECT_SQL_TOO!(1+10>>1 == 5);

  EXPECT_SQL_TOO!(10&1+1 == 2);
  EXPECT_SQL_TOO!(1+10&1 == 1);
  EXPECT_SQL_TOO!(1+10&7 == 3);
  EXPECT_SQL_TOO!(10-1&7 == 1);
  EXPECT_SQL_TOO!(10-4&7 == 6);

  EXPECT_SQL_TOO!(10|1+1 == 10);
  EXPECT_SQL_TOO!(10|4 == 14);
  EXPECT_SQL_TOO!(1+10|4 == 15);
  EXPECT_SQL_TOO!(10-1|7 == 15);
  EXPECT_SQL_TOO!(10-3|7 == 7);

  EXPECT_SQL_TOO!(6&4 == 4);
  EXPECT_SQL_TOO!(6&4|12 == 12);
  EXPECT_SQL_TOO!(6&4|12|2 == 14);
  EXPECT_SQL_TOO!(6&4|12|2|2 == 14);
  EXPECT_SQL_TOO!(6&4|12|2|2<<3 == 112);
  EXPECT_SQL_TOO!(6&4|12|2|2<<3>>3<<2 == 56);
END);

-- Test precedence of inequality (< <= > >=) with binary (<< >> & |)
TEST!(inequality_pri,
BEGIN
  EXPECT_SQL_TOO!(10 < 10<<1);
  EXPECT_SQL_TOO!(10 <= 10<<1);
  EXPECT_SQL_TOO!(10 > 10>>1);
  EXPECT_SQL_TOO!(10 >= 10>>1);
  EXPECT_SQL_TOO!(0 >= 0>>1);
  EXPECT_SQL_TOO!(0 <= 0<<1);
  EXPECT_SQL_TOO!(5 >= 0<<31);
  EXPECT_SQL_TOO!(5 > 0<<31);
  EXPECT_SQL_TOO!(16>>1 >= 4<<1);
  EXPECT_SQL_TOO!(4<<1 <= 16>>1);
  EXPECT_SQL_TOO!(16>>1 > 3<<1);
  EXPECT_SQL_TOO!(16>>1 >= 3<<1);
  EXPECT_SQL_TOO!(16>>1 <= 4<<1);

  EXPECT_SQL_TOO!(16&8 <= 4|8);
  EXPECT_SQL_TOO!(16&8 < 15);
  EXPECT_SQL_TOO!(16&8 <= 15);
  EXPECT_SQL_TOO!(16&17 > 4);
  EXPECT_SQL_TOO!(16&17 >= 4);
  EXPECT_SQL_TOO!(6 > 4&5);
  EXPECT_SQL_TOO!(6 >= 4&5);
  EXPECT_SQL_TOO!(6 > 4|5);
  EXPECT_SQL_TOO!(6 >= 4|5);

  EXPECT_SQL_TOO!(3|8 >= 4&5);
  EXPECT_SQL_TOO!(3|8 > 4&5);
  EXPECT_SQL_TOO!(3|4 >= 4&5);
  EXPECT_SQL_TOO!(3|4 > 4&5);
  EXPECT_SQL_TOO!(4&5 <= 3|8);
  EXPECT_SQL_TOO!(4&5 < 3|8);
  EXPECT_SQL_TOO!(4&5 <= 3|4);
  EXPECT_SQL_TOO!(4&5 < 3|4);
  EXPECT_SQL_TOO!(4|3 <= 3|4);
  EXPECT_SQL_TOO!(4&5 <= 5&4);
  EXPECT_SQL_TOO!(4&5 >= 5&4);

  EXPECT_SQL_TOO!(4&5 >= 5&4 > 0);
  EXPECT_SQL_TOO!(4&5 >= 5&4 <= 1);
  EXPECT_SQL_TOO!(4&5 >= 5&4 >= 1);
  EXPECT_SQL_TOO!(3&10 <= 100 <= 3&2);
  EXPECT_SQL_TOO!((3&10 <= 100) <= 3&2 == 3&10 <= 100 <= 3&2);
  EXPECT_SQL_TOO!(5 > 3 > -1 > 0);
END);

-- Test precedence of equality (= == != <> LIKE GLOB MATCH IN NOT IN IS_NOT_NULL IS_NULL) with binary (< <= > >=)
TEST!(equality_pri,
BEGIN
  declare null_ int;

  EXPECT_SQL_TOO!(5 == 5);
  EXPECT_SQL_TOO!(5 < 6 == 6 > 5);
  EXPECT_SQL_TOO!(5 <= 6 == 6 >= 5);
  EXPECT_SQL_TOO!(5 < 6 == 6 >= 5);
  EXPECT_SQL_TOO!(5 <= 6 == 6 > 5);
  EXPECT_SQL_TOO!(5 <= 6 == 1);
  EXPECT_SQL_TOO!(1 == 5 < 6);
  EXPECT_SQL_TOO!(1 == 5 <= 6);
  EXPECT_SQL_TOO!(1 == 0 + 1);
  EXPECT_SQL_TOO!(1 == 1 + 0 * 1);
  EXPECT_SQL_TOO!(1 == 0 * 1 + 1);
  EXPECT_SQL_TOO!(1 == 0 * -1 + 1);
  EXPECT_SQL_TOO!(1 + 1 == 3 - 1 == 1);
  EXPECT_SQL_TOO!(1 + 1 == 3 - 1 != 0);
  EXPECT_SQL_TOO!(1 + 1 == 3 - 1 != 30);

  EXPECT_SQL_TOO!(5 = 5);
  EXPECT_SQL_TOO!(5 < 6 = 6 > 5);
  EXPECT_SQL_TOO!(5 <= 6 = 6 >= 5);
  EXPECT_SQL_TOO!(5 < 6 = 6 >= 5);
  EXPECT_SQL_TOO!(5 <= 6 = 6 > 5);
  EXPECT_SQL_TOO!(5 <= 6 = 1);
  EXPECT_SQL_TOO!(1 = 5 < 6);
  EXPECT_SQL_TOO!(1 = 5 <= 6);
  EXPECT_SQL_TOO!(1 = 0 + 1);
  EXPECT_SQL_TOO!(1 = 1 + 0 * 1);
  EXPECT_SQL_TOO!(1 = 0 * 1 + 1);
  EXPECT_SQL_TOO!(1 = 0 * -1 + 1);
  EXPECT_SQL_TOO!(1 + 1 = 3 - 1 = 1);
  EXPECT_SQL_TOO!(1 + 1 = 3 - 1 <> 0);
  EXPECT_SQL_TOO!(1 + 1 == 3 - 1 <> 0);
  EXPECT_SQL_TOO!(1 + 1 = 3 - 1 <> 30);
  EXPECT_SQL_TOO!(1 + 1 == 3 - 1 <> 30);

  EXPECT_SQL_TOO!(1 == 1 <> 0 == 1 = 1 != 0 = 1 == 1);

  -- CQL requires both operands of binary_like to be text, so there is no way to test
  -- order of operations with <, <=, etc. When concat (||) is implemented, it is
  -- possible to write a test case.

  -- CQL requires both operands of binary_like to be text, so there is no way to test
  -- order of operations with <, <=, etc. When concat (||) is implemented, it is
  -- possible to write a test case.

  -- GLOB must be inside a select statement so it also cannot be tested
  -- MATCH can only be in a select statement, no test necessary

  -- Test IS_NOT and IS
  EXPECT_SQL_TOO!(nullable(1) + nullable(1) IS NULL == 0);
  EXPECT_SQL_TOO!(nullable(1) + nullable(1) IS NOT NULL == 1);
  EXPECT_SQL_TOO!(nullable(1) + nullable(1) IS NULL + 1 == 0); -- Evaluated as: (1 + 1) IS (NULL + 1) == 0;
  EXPECT_SQL_TOO!(nullable(1) + nullable(1) IS NOT NULL);
  EXPECT_SQL_TOO!((nullable(1) + nullable(1) IS NOT NULL) + 1 == 2);
  EXPECT_SQL_TOO!(1 + 1 IS NOT NULL + 1 == 1);
  EXPECT_SQL_TOO!(1 + NULL IS NULL);
  EXPECT_SQL_TOO!(NULL + 1 IS NULL);
  EXPECT_SQL_TOO!(NULL * 1 IS NULL);
  EXPECT_SQL_TOO!(NULL * 0 IS NULL);
  EXPECT_SQL_TOO!(0 * NULL * 0 IS NULL);
  EXPECT_SQL_TOO!(NULL > 0 IS NULL);
  EXPECT_SQL_TOO!(NULL >= 1 IS NULL);
  EXPECT_SQL_TOO!(NULL < 2 IS NULL);
  EXPECT_SQL_TOO!(NULL <= 3 IS NULL);
  EXPECT_SQL_TOO!(1 + NULL == 3 IS NULL);
  EXPECT_SQL_TOO!(1 + NULL != 3 IS NULL);
  EXPECT_SQL_TOO!(1 + NULL <> 3 IS NULL);
  EXPECT_SQL_TOO!(1 = NULL * 1 + 1 IS NULL);
  EXPECT_SQL_TOO!(1 = NULL * -1 + 1 IS NULL);
  EXPECT_SQL_TOO!(1 + NULL = 3 - 1 = 1 IS NULL);
  EXPECT_SQL_TOO!(1 + NULL = 3 - 1 <> 0 IS NULL);
  EXPECT_SQL_TOO!(1 + NULL == 3 - 1 <> 0 IS NULL);
  EXPECT_SQL_TOO!(1 + NULL = 3 - 1 <> 30 IS NULL);
  EXPECT_SQL_TOO!(1 + NULL == 3 - 1 <> 30 IS NULL);
  EXPECT_SQL_TOO!((NULL IS NOT NULL) == 0);
  EXPECT_SQL_TOO!(nullable(1) + nullable(1) IS NOT NULL);
  EXPECT_SQL_TOO!(null_ == 3 IS NULL);
  EXPECT_SQL_TOO!(((null_ == 3) IS NULL) == 1);
  EXPECT_SQL_TOO!((null_ == 3 IS NULL) == 1);
  EXPECT_SQL_TOO!((null_ == 3 IS NULL) == 1);
  EXPECT_SQL_TOO!(nullable(null_ == 3 IS NULL) IS NOT NULL);
  EXPECT_SQL_TOO!((1 + NULL == 3 IS NOT NULL) == 0);
  EXPECT_SQL_TOO!((1 + NULL = 3 - 1 <> 0 IS NOT NULL) == 0);
  EXPECT_SQL_TOO!((1 + NULL == 3 - 1 <> 0 IS NOT NULL) == 0);
  EXPECT_SQL_TOO!((1 + NULL = 3 - 1 <> 30 IS NOT NULL) == 0);

  -- Basic IS tests, all non null
  EXPECT_SQL_TOO!(2 * 3 IS 4 + 2);
  EXPECT_SQL_TOO!(2 * 3 IS 4 + 2);
  EXPECT_SQL_TOO!(10-4*2 IS 2);
  EXPECT_SQL_TOO!(25%3/2 IS 0);
  EXPECT_SQL_TOO!(25/5%2 IS 1);
  EXPECT_SQL_TOO!(25*5%2 IS 1);
  EXPECT_SQL_TOO!(25*5%4%2 IS 1);
  EXPECT_SQL_TOO!(25-5%2 IS 24);
  EXPECT_SQL_TOO!(15%3-2 IS -2);
  EXPECT_SQL_TOO!(15-30%4 IS 13);
  EXPECT_SQL_TOO!(15-30/2 IS 0);
  EXPECT_SQL_TOO!(15/5-3 IS 0);
  EXPECT_SQL_TOO!(15*5-3 IS 72);
  EXPECT_SQL_TOO!(5*5-3 IS 22);
  EXPECT_SQL_TOO!(25+5%2 IS 26);
  EXPECT_SQL_TOO!(15%3+2 IS 2);
  EXPECT_SQL_TOO!(15+30%4 IS 17);
  EXPECT_SQL_TOO!(15+30/2 IS 30);
  EXPECT_SQL_TOO!(15/5+3 IS 6);
  EXPECT_SQL_TOO!(15*5+3 IS 78);
  EXPECT_SQL_TOO!(5*5+3 IS 28);
  EXPECT_SQL_TOO!(5*12/3 IS 20);
  EXPECT_SQL_TOO!(5*12/3%7 IS 6);
  EXPECT_SQL_TOO!(9%12/3*7 IS 21);

  -- IS tests with null
  EXPECT_SQL_TOO!(1 IS 1 == 1 IS 1 == 1);
  EXPECT_SQL_TOO!(5 > 6 IS 2 < 1);
  EXPECT_SQL_TOO!(5 <= 6 IS 2 > 1);
  EXPECT_SQL_TOO!(5 == 5 IS 2 > 1);
  EXPECT_SQL_TOO!("1" IS "2" == 0);
  EXPECT_SQL_TOO!(nullable("1") IS NULL == 0);
  EXPECT_SQL_TOO!(NULL IS "1" == 0);
  EXPECT_SQL_TOO!(NULL IS NULL);
  EXPECT_SQL_TOO!(null_ == 0 IS NULL);
  EXPECT_SQL_TOO!(NULL IS NULL == 1 != 0);
  EXPECT_SQL_TOO!(NULL IS NULL = 1 <> 0);
  EXPECT_SQL_TOO!(null_ == null_ IS NULL);
  EXPECT_SQL_TOO!(NULL IS (null_ == 0));
  EXPECT_SQL_TOO!(NULL IS NOT NULL == 0);
  EXPECT_SQL_TOO!((NULL IS NOT NULL) == 0);
  EXPECT_SQL_TOO!(nullable(5) > nullable(2) IS NOT NULL);
  EXPECT_SQL_TOO!(NULL IS NOT 2 < 3);
  EXPECT_SQL_TOO!(nullable(NULL IS 2 < 3) IS NOT NULL);
  EXPECT_SQL_TOO!(NULL IS NULL + 1);
  EXPECT_SQL_TOO!(NULL IS 1 + NULL);
  EXPECT_SQL_TOO!(NULL IS 1 << NULL);

  -- Test IN
  EXPECT_SQL_TOO!(3 IN (1, 2) == 0);
  EXPECT_SQL_TOO!(3 + 2 IN (1, 5));
  EXPECT_SQL_TOO!(3 / 3 IN (1, 2));
  EXPECT_SQL_TOO!(3 / 3 IN (1, 2) IN (1));
  EXPECT_SQL_TOO!(1 IN (NULL, 1));
  EXPECT!(NOT (1 IN (NULL, 5)));
  EXPECT!((SELECT NULL IS (NOT (1 IN (NULL, 5))))); -- known sqlite and CQL IN difference for NULL
  EXPECT_SQL_TOO!(NULL IS (NULL IN (1)));

  -- Test NOT IN
  EXPECT_SQL_TOO!(3 NOT IN (1, 2) == 1);
  EXPECT_SQL_TOO!(1 NOT IN (1, 2) == 0);
  EXPECT_SQL_TOO!(3 + 1 NOT IN (1, 5));
  EXPECT_SQL_TOO!(3 / 1 NOT IN (1, 2));
  EXPECT_SQL_TOO!(3 / 1 NOT IN (1, 2) NOT IN (0));
  EXPECT_SQL_TOO!(NOT (1 NOT IN (NULL, 1)));
  EXPECT!(1 NOT IN (NULL, 5));
  EXPECT!((SELECT NULL IS (1 NOT IN (NULL, 5))));  -- known sqlite and CQL IN difference for NULL
  EXPECT_SQL_TOO!(NULL IS (NULL NOT IN (1)));

  declare x text;
  x := NULL;

  EXPECT_SQL_TOO!((x IN ("foo", "goo")) IS NULL);
  EXPECT_SQL_TOO!((x NOT IN ("foo", "goo")) IS NULL);

  -- Test IS TRUE and IS FALSE
  EXPECT_SQL_TOO!(1 is true);
  EXPECT_SQL_TOO!(0 is false);
  EXPECT_SQL_TOO!(not 0 is true);
  EXPECT_SQL_TOO!(not 1 is false);
  EXPECT_SQL_TOO!(not null is false);
  EXPECT_SQL_TOO!(not null is true);

  -- Test IS NOT TRUE and IS NOT FALSE
  EXPECT_SQL_TOO!(not 1 is not true);
  EXPECT_SQL_TOO!(not 0 is not false);
  EXPECT_SQL_TOO!(0 is not true);
  EXPECT_SQL_TOO!(1 is not false);
  EXPECT_SQL_TOO!(null is not false);
  EXPECT_SQL_TOO!(null is not true);

  -- priority of same
  EXPECT_SQL_TOO!(not (1>=0 is false));
  EXPECT_SQL_TOO!(not ((1>=0) is false));
  EXPECT_SQL_TOO!(1 >= (0 is false));

  EXPECT_SQL_TOO!(-1 > -2 is not false);
  EXPECT_SQL_TOO!((-1 > -2) is not false);
  EXPECT_SQL_TOO!(not -1 > (-2 is not false));

  EXPECT_SQL_TOO!(-1 > -2 is true);
  EXPECT_SQL_TOO!((-1 > -2) is true);
  EXPECT_SQL_TOO!(not -1 > (-2 is true));

  EXPECT_SQL_TOO!(-5 > -2 is not true);
  EXPECT_SQL_TOO!((-5 > -2) is not true);
  EXPECT_SQL_TOO!(not -5 > (-2 is not true));

  -- https://sqlite.org/forum/forumpost/70e78ad16a
  --
  -- sqlite> select false is true < false;
  -- 1
  -- sqlite> select sqlite_version();
  -- 3.32.3
  --
  -- vs.
  --
  -- PostgreSQL> select false is true < false;
  -- false
  --
  -- When CQL emits this operator, it naturally adds parens around (false is true)
  -- because is true binds weaker than < which ensures the "correct" eval order even
  -- though SQLite would do it the other way.  CQL is like other SQL systems in that "is true"
  -- is an operator.  In SQLite the way it works is that if the right operator of "IS" happens
  -- to the the literal "true" then you get "is true" behavior.
  -- This is wrong.  And hard to emulate.   CQL forces it the normal way with parens.
  -- SQLite will see "not ((false is true) < false)";
  --
  -- This may be fixed in future SQLites, but even if that happens the below will still pass.
  --
  EXPECT_SQL_TOO!(not(false is true < false));

END);

TEST!(between_pri,
BEGIN
  -- between is the same as = but binds left to right

  EXPECT_SQL_TOO!(0 == (1=2 between 2 and 2));
  EXPECT_SQL_TOO!(1 == (1=(2 between 2 and 2)));
  EXPECT_SQL_TOO!(0 == ((1=2) between 2 and 2));

  LET four := 4;

  -- verifying binding when = is on the right, still left to right
  EXPECT_SQL_TOO!(0 == (0 between -2 and -1 = four));
  EXPECT_SQL_TOO!(0 == ((0 between -2 and -1) = four));
  EXPECT_SQL_TOO!(1 == (0 between -2 and (-1 = four)));

  -- not is weaker than between
  let neg := -1;

  EXPECT_SQL_TOO!(0 == (not 0 between neg and 2));
  EXPECT_SQL_TOO!(1 == ((not 0) between neg and 2));
  EXPECT_SQL_TOO!(0 == (not (0 between neg and 2)));

  -- between binds left to right
  EXPECT_SQL_TOO!(0 == (0 between 0 and 3 between 2 and 3));
  EXPECT_SQL_TOO!(0 == ((0 between 0 and 3) between 2 and 3));
  EXPECT_SQL_TOO!(1 == (0 between 0 and (3 between 2 and 3)));

  -- nested betweens are actually not ambiguous
  EXPECT_SQL_TOO!(1 == (0 between 1 between 3 and 4 and (3 between 2 and 3)));
  EXPECT_SQL_TOO!(1 == (0 between (1 between 3 and 4) and (3 between 2 and 3)));

END);

-- AND tests with = == != <> IS IS_NOT IN NOT IN
TEST!(and_pri,
BEGIN
  declare null_ int;

  EXPECT_SQL_TOO!(3 + 3 AND 5);
  EXPECT_SQL_TOO!((3 + 3 AND 0) == 0);
  EXPECT_SQL_TOO!((NULL AND true) IS NULL);
  EXPECT_SQL_TOO!((NULL AND true = null_) IS NULL);
  EXPECT_SQL_TOO!(NOT (NULL AND nullable(true) IS NULL));
  EXPECT_SQL_TOO!((NULL AND false) == 0);
  EXPECT_SQL_TOO!(NOT (NULL AND false));
  EXPECT_SQL_TOO!(1 AND false == false);
  EXPECT_SQL_TOO!(1 AND false = false);
  EXPECT_SQL_TOO!(1 AND true != false);
  EXPECT_SQL_TOO!(1 AND true <> false);
  EXPECT_SQL_TOO!(5 IS 5 AND 2 IS 2);
  EXPECT_SQL_TOO!(nullable(5) IS NOT NULL AND 2 IS 2);
  EXPECT_SQL_TOO!(nullable(5) IS NOT NULL AND 2 IS 2);
  EXPECT_SQL_TOO!(5 AND false + 1);
  EXPECT_SQL_TOO!(5 AND false * 1 + 1);
  EXPECT_SQL_TOO!(5 AND false >> 4 >= -1);
  EXPECT_SQL_TOO!(5 AND false | 4 & 12);
  EXPECT_SQL_TOO!(5 AND 6 / 3);
  EXPECT_SQL_TOO!((5 AND 25 % 5) == false);
  EXPECT_SQL_TOO!(5 AND false IN (0));
  EXPECT_SQL_TOO!(5 AND true NOT IN (false));
  EXPECT_SQL_TOO!(NOT(5 AND false NOT IN (false)));
END);

-- Test AND with OR
TEST!(or_pri,
BEGIN
  -- The following tests show that if AND and OR were evaluated from
  -- left to right, then the output would be different
  EXPECT_SQL_TOO!((0 OR 1 OR 1 AND 0 OR 0) != ((((0 OR 1) OR 1) AND 0) OR 0));
  EXPECT_SQL_TOO!((1 OR 1 AND 0 AND 1 AND 0) != ((((1 OR 1) AND 0) AND 1) AND 0));
  EXPECT_SQL_TOO!((0 OR 1 OR 1 AND 0 AND 1) != ((((0 OR 1) OR 1) AND 0) AND 1));
  EXPECT_SQL_TOO!((1 OR 1 OR 1 AND 0 AND 0) != ((((1 OR 1) OR 1) AND 0) AND 0));
  EXPECT_SQL_TOO!((1 OR 1 OR 1 AND 0 OR 0) != ((((1 OR 1) OR 1) AND 0) OR 0));
  EXPECT_SQL_TOO!((1 AND 1 AND 1 OR 1 AND 0) != ((((1 AND 1) AND 1) OR 1) AND 0));
  EXPECT_SQL_TOO!((1 OR 0 AND 0 AND 1 OR 0) != ((((1 OR 0) AND 0) AND 1) OR 0));
  EXPECT_SQL_TOO!((1 AND 1 OR 0 AND 0 AND 1) != ((((1 AND 1) OR 0) AND 0) AND 1));
  EXPECT_SQL_TOO!((1 OR 0 OR 0 OR 0 AND 0) != ((((1 OR 0) OR 0) OR 0) AND 0));
  EXPECT_SQL_TOO!((1 OR 0 AND 0 OR 1 AND 0) != ((((1 OR 0) AND 0) OR 1) AND 0));
  EXPECT_SQL_TOO!((1 OR 1 AND 1 AND 1 AND 0) != ((((1 OR 1) AND 1) AND 1) AND 0));
  EXPECT_SQL_TOO!((0 AND 0 OR 1 OR 0 AND 0) != ((((0 AND 0) OR 1) OR 0) AND 0));
  EXPECT_SQL_TOO!((0 OR 1 OR 1 AND 0 AND 0) != ((((0 OR 1) OR 1) AND 0) AND 0));
  EXPECT_SQL_TOO!((1 AND 1 AND 1 OR 0 AND 0) != ((((1 AND 1) AND 1) OR 0) AND 0));
  EXPECT_SQL_TOO!((1 OR 1 OR 1 AND 0 AND 1) != ((((1 OR 1) OR 1) AND 0) AND 1));
  EXPECT_SQL_TOO!((1 OR 0 OR 0 OR 0 AND 0) != ((((1 OR 0) OR 0) OR 0) AND 0));
END);

-- Take some priority tests and replace constants with nullable variables
TEST!(nullable_test,
BEGIN
  let x0 := nullable(0);
  let x1 := nullable(1);
  let x2 := nullable(2);
  let x3 := nullable(3);
  let x4 := nullable(4);
  let x5 := nullable(5);
  let x6 := nullable(6);
  let x7 := nullable(7);
  let x8 := nullable(8);
  let x9 := nullable(9);

  let temp0 := nullable(27);
  EXPECT_SQL_TOO!(x1+x2*x3+x4*x5 == temp0);
  EXPECT_SQL_TOO!(x1+x2/x2 == x2);
  EXPECT_SQL_TOO!(x1+x2/x2*x4 == x5);
  EXPECT_SQL_TOO!(x1+x2/x2*x4 == x5);
  EXPECT_SQL_TOO!(x1*x2+x3 == x5);
  EXPECT_SQL_TOO!(x1*x2+x6/x3 == x4);
  EXPECT_SQL_TOO!(x1*x2+x6/x3 == x4);
  temp0 := nullable(25);
  EXPECT_SQL_TOO!(x2*x3*x4+x3/x3 == temp0);
  temp0 := nullable(-25);
  EXPECT_SQL_TOO!(-x5*x5 == temp0);
  temp0 := nullable(-20);
  EXPECT_SQL_TOO!(x5-x5*x5 == temp0);
  temp0 := nullable(29);
  EXPECT_SQL_TOO!(x4+x5*x5 == temp0);
  temp0 := nullable(25);
  EXPECT_SQL_TOO!(x4*x5+x5 == temp0);
  temp0 := nullable(15);
  EXPECT_SQL_TOO!(x4*x4-x1 == temp0);
  temp0 := nullable(10);
  EXPECT_SQL_TOO!(10-x4*x2 == x2);

  temp0 := nullable(10);

  let temp1 := nullable(40);
  EXPECT_SQL_TOO!(temp0<<x1+x1 == temp1);
  temp1 := nullable(22);
  EXPECT_SQL_TOO!(x1+temp0<<x1 == temp1);
  EXPECT_SQL_TOO!(temp0<<x1-x1 == temp0);
  temp1 := nullable(80);
  EXPECT_SQL_TOO!(temp0<<x4-x1 == temp1);
  temp1 := nullable(18);
  EXPECT_SQL_TOO!(temp0-x1<<x1 == temp1);

  EXPECT_SQL_TOO!(temp0>>x3-x1 == x2);
  temp1 := nullable(11);
  EXPECT_SQL_TOO!(temp1-x1>>x1 == x5);
  EXPECT_SQL_TOO!(temp0>>x1+x1 == x2);
  EXPECT_SQL_TOO!(x1+temp0>>x1 == x5);

  EXPECT_SQL_TOO!(temp0&x1+x1 == x2);
  EXPECT_SQL_TOO!(x1+temp0&x1 == x1);
  EXPECT_SQL_TOO!(x1+temp0&x7 == x3);
  EXPECT_SQL_TOO!(temp0-x1&x7 == x1);
  EXPECT_SQL_TOO!(temp0-x4&x7 == x6);

  EXPECT_SQL_TOO!(temp0|x1+x1 == temp0);
  temp1 := nullable(14);
  EXPECT_SQL_TOO!(temp0|x4 == temp1);
  temp1 := nullable(15);
  EXPECT_SQL_TOO!(x1+temp0|x4 == temp1);
  EXPECT_SQL_TOO!(temp0-x1|x7 == temp1);
  EXPECT_SQL_TOO!(temp0-x3|x7 == x7);

  temp1 := nullable(12);

  EXPECT_SQL_TOO!(x6&x4 == x4);
  EXPECT_SQL_TOO!(x6&x4|temp1 == temp1);
  let temp2 := nullable(14);
  EXPECT_SQL_TOO!(x6&x4|temp1|x2 == temp2);
  EXPECT_SQL_TOO!(x6&x4|temp1|x2|x2 == temp2);
  temp2 := nullable(112);
  EXPECT_SQL_TOO!(x6&x4|temp1|x2|x2<<x3 == temp2);
  temp2 := nullable(56);
  EXPECT_SQL_TOO!(x6&x4|temp1|x2|x2<<x3>>x3<<x2 == temp2);

  EXPECT_SQL_TOO!(temp0 < temp0<<x1);
  EXPECT_SQL_TOO!(temp0 <= temp0<<x1);
  temp1 := nullable(31);
  EXPECT_SQL_TOO!(x5 >= x0<<temp1);
  EXPECT_SQL_TOO!(x5 > x0<<temp1);
  temp1 := nullable(16);
  EXPECT_SQL_TOO!(temp1>>x1 >= x4<<x1);
  EXPECT_SQL_TOO!(x4<<x1 <= temp1>>x1);
  EXPECT_SQL_TOO!(temp1>>x1 > x3<<x1);
  EXPECT_SQL_TOO!(temp1>>x1 >= x3<<x1);
  EXPECT_SQL_TOO!(temp1>>x1 <= x4<<x1);

  EXPECT_SQL_TOO!(temp1&x8 <= x4|x8);
  temp2 := nullable(15);
  EXPECT_SQL_TOO!(temp1&8 < temp2);
  EXPECT_SQL_TOO!(x6 > x4|x5);
  EXPECT_SQL_TOO!(x6 >= x4|x5);

  EXPECT_SQL_TOO!(x4&x5 <= x3|x4);
  EXPECT_SQL_TOO!(x4&x5 < x3|x4);
  EXPECT_SQL_TOO!(x4|x3 <= x3|x4);
  EXPECT_SQL_TOO!(x4&x5 <= x5&x4);
  EXPECT_SQL_TOO!(x4&x5 >= x5&x4);

  EXPECT_SQL_TOO!(x4&x5 >= x5&x4 > x0);
  EXPECT_SQL_TOO!(x4&x5 >= x5&x4 <= x1);
  EXPECT_SQL_TOO!(x4&x5 >= x5&x4 >= x1);
  temp1 := nullable(100);
  EXPECT_SQL_TOO!(x3&temp0 <= temp1 <= x3&x2);
  EXPECT_SQL_TOO!((x3&temp0 <= temp1) <= x3&x2 == x3&temp0 <= temp1 <= x3&x2);
  EXPECT_SQL_TOO!(x5 > x3 > -x1 > x0);

  temp1 := nullable(30);
  EXPECT_SQL_TOO!(x5 == x5);
  EXPECT_SQL_TOO!(x5 < x6 == x6 > x5);
  EXPECT_SQL_TOO!(x5 <= x6 == x6 >= x5);
  EXPECT_SQL_TOO!(x5 < x6 == x6 >= x5);
  EXPECT_SQL_TOO!(x5 <= x6 == x6 > x5);
  EXPECT_SQL_TOO!(x5 <= x6 == x1);
  EXPECT_SQL_TOO!(x1 == x5 < x6);
  EXPECT_SQL_TOO!(x1 == x5 <= x6);
  EXPECT_SQL_TOO!(x1 == x0 + x1);
  EXPECT_SQL_TOO!(x1 == x1 + x0 * x1);
  EXPECT_SQL_TOO!(x1 == x0 * x1 + x1);
  EXPECT_SQL_TOO!(x1 == x0 * -x1 + x1);
  EXPECT_SQL_TOO!(x1 + x1 == x3 - x1 == x1);
  EXPECT_SQL_TOO!(x1 + x1 == x3 - x1 != x0);
  EXPECT_SQL_TOO!(x1 + x1 == x3 - x1 != temp1);

  EXPECT_SQL_TOO!(x5 = x5);
  EXPECT_SQL_TOO!(x5 < x6 = x6 > x5);
  EXPECT_SQL_TOO!(x5 <= x6 = x6 >= x5);
  EXPECT_SQL_TOO!(x5 < x6 = x6 >= x5);
  EXPECT_SQL_TOO!(x5 <= x6 = x6 > x5);
  EXPECT_SQL_TOO!(x5 <= x6 = x1);
  EXPECT_SQL_TOO!(x1 = x5 < x6);
  EXPECT_SQL_TOO!(x1 = x5 <= x6);
  EXPECT_SQL_TOO!(x1 = x0 + x1);
  EXPECT_SQL_TOO!(x1 = x1 + x0 * x1);
  EXPECT_SQL_TOO!(x1 = x0 * x1 + x1);
  EXPECT_SQL_TOO!(x1 = x0 * -x1 + x1);
  EXPECT_SQL_TOO!(x1 + x1 = x3 - x1 = x1);
  EXPECT_SQL_TOO!(x1 + x1 = x3 - x1 <> x0);
  EXPECT_SQL_TOO!(x1 + x1 == x3 - x1 <> x0);
  EXPECT_SQL_TOO!(x1 + x1 = x3 - x1 <> temp1);
  EXPECT_SQL_TOO!(x1 + x1 == x3 - x1 <> temp1);

  temp1 := nullable(30);
  declare temp_null int;
  temp_null := NULL;

  EXPECT_SQL_TOO!(x1 + x1 IS NULL == x0);
  EXPECT_SQL_TOO!(x1 + x1 IS NOT NULL == x1);
  EXPECT_SQL_TOO!(x1 + x1 IS NULL + x1 == x0);
  EXPECT_SQL_TOO!(x1 + x1 IS NOT NULL);
  EXPECT_SQL_TOO!((x1 + x1 IS NOT NULL) + x1 == x2);
  EXPECT_SQL_TOO!(x1 + x1 IS NOT NULL + x1 == x1);
  EXPECT_SQL_TOO!(x1 + NULL IS NULL);
  EXPECT_SQL_TOO!(NULL + x1 IS NULL);
  EXPECT_SQL_TOO!(NULL * x1 IS NULL);
  EXPECT_SQL_TOO!(NULL * x0 IS NULL);
  EXPECT_SQL_TOO!(x0 * NULL * x0 IS NULL);
  EXPECT_SQL_TOO!(NULL > x0 IS NULL);
  EXPECT_SQL_TOO!(NULL >= x1 IS NULL);
  EXPECT_SQL_TOO!(NULL < x2 IS NULL);
  EXPECT_SQL_TOO!(NULL <= x3 IS NULL);
  EXPECT_SQL_TOO!(x1 + NULL == x3 IS NULL);
  EXPECT_SQL_TOO!(x1 + NULL != x3 IS NULL);
  EXPECT_SQL_TOO!(x1 + NULL <> x3 IS NULL);
  EXPECT_SQL_TOO!(x1 = temp_null * x1 + x1 IS temp_null);
  EXPECT_SQL_TOO!(x1 = temp_null * -x1 + x1 IS temp_null);
  EXPECT_SQL_TOO!(x1 + temp_null = x3 - x1 = x1 IS temp_null);
  EXPECT_SQL_TOO!(x1 + temp_null = x3 - x1 <> x0 IS temp_null);
  EXPECT_SQL_TOO!(x1 + temp_null == x3 - x1 <> x0 IS temp_null);
  EXPECT_SQL_TOO!(x1 + temp_null = x3 - x1 <> temp1 IS temp_null);
  EXPECT_SQL_TOO!(x1 + temp_null == x3 - x1 <> temp1 IS temp_null);
  EXPECT_SQL_TOO!((temp_null IS NOT temp_null) == x0);
  EXPECT_SQL_TOO!(x1 + x1 IS NOT temp_null);
  EXPECT_SQL_TOO!(temp_null == x3 IS temp_null);
  EXPECT_SQL_TOO!(((temp_null == x3) IS temp_null) == x1);
  EXPECT_SQL_TOO!((temp_null == x3 IS temp_null) == x1);
  EXPECT_SQL_TOO!((temp_null == x3 IS temp_null) == x1);
  EXPECT_SQL_TOO!((temp_null == x3 IS temp_null) IS NOT temp_null);
  EXPECT_SQL_TOO!((x1 + temp_null == x3 IS NOT temp_null) == x0);
  EXPECT_SQL_TOO!((x1 + temp_null = x3 - x1 <> x0 IS NOT temp_null) == x0);
  EXPECT_SQL_TOO!((x1 + temp_null == x3 - x1 <> x0 IS NOT temp_null) == x0);
  EXPECT_SQL_TOO!((x1 + temp_null = x3 - x1 <> temp1 IS NOT temp_null) == x0);

  temp0 := nullable(25);

  EXPECT_SQL_TOO!(x2 * x3 IS x4 + x2);
  EXPECT_SQL_TOO!(x2 * x3 IS x4 + x2);
  temp1 := nullable(10);
  EXPECT_SQL_TOO!(temp1-x4*x2 IS x2);
  EXPECT_SQL_TOO!(temp0%x3/x2 IS x0);
  EXPECT_SQL_TOO!(temp0/x5%x2 IS x1);
  EXPECT_SQL_TOO!(temp0*x5%x2 IS x1);
  EXPECT_SQL_TOO!(temp0*x5%x4%x2 IS x1);
  temp1 := nullable(24);
  EXPECT_SQL_TOO!(temp0-x5%x2 IS temp1);
  temp1 := nullable(15);
  EXPECT_SQL_TOO!(temp1%x3-x2 IS -x2);
  temp2 := nullable(30);
  let temp3 := nullable(13);
  EXPECT_SQL_TOO!(temp1-temp2%x4 IS temp3);
  EXPECT_SQL_TOO!(temp1-temp2/x2 IS x0);
  EXPECT_SQL_TOO!(temp1/x5-x3 IS x0);
  temp3 := nullable(72);
  EXPECT_SQL_TOO!(temp1*x5-x3 IS temp3);
  temp3 := nullable(22);
  EXPECT_SQL_TOO!(x5*x5-x3 IS temp3);
  temp3 := 26;
  EXPECT_SQL_TOO!(temp0+x5%x2 IS temp3);
  EXPECT_SQL_TOO!(temp1%x3+x2 IS x2);
  temp1 := nullable(17);
  temp2 := nullable(30);
  temp3 := nullable(15);
  EXPECT_SQL_TOO!(temp3+temp2%x4 IS temp1);
  temp1 := nullable(30);
  EXPECT_SQL_TOO!(temp3+temp1/x2 IS temp1);
  EXPECT_SQL_TOO!(temp3/x5+x3 IS x6);
  temp1 := nullable(78);
  EXPECT_SQL_TOO!(temp3*x5+x3 IS temp1);
  temp1 := nullable(28);
  EXPECT_SQL_TOO!(x5*x5+x3 IS temp1);
  temp1 := nullable(20);
  temp2 := nullable(12);
  EXPECT_SQL_TOO!(x5*temp2/x3 IS temp1);
  EXPECT_SQL_TOO!(x5*temp2/x3%x7 IS x6);
  temp1 := nullable(21);
  temp2 := nullable(12);
  EXPECT_SQL_TOO!(x9%temp2/x3*x7 IS temp1);

  EXPECT_SQL_TOO!(x1 IS x1 == x1 IS x1 == x1);
  EXPECT_SQL_TOO!(x5 > x6 IS x2 < x1);
  EXPECT_SQL_TOO!(x5 <= x6 IS x2 > x1);
  EXPECT_SQL_TOO!(x5 == x5 IS x2 > x1);
  EXPECT_SQL_TOO!(NULL IS NULL);
  EXPECT_SQL_TOO!(temp_null == x0 IS NULL);
  EXPECT_SQL_TOO!(NULL IS NULL == x1 != x0);
  EXPECT_SQL_TOO!(NULL IS NULL = x1 <> x0);
  EXPECT_SQL_TOO!(temp_null == temp_null IS NULL);
  EXPECT_SQL_TOO!(NULL IS (temp_null == x0));
  EXPECT_SQL_TOO!(NULL IS NOT NULL == x0);
  EXPECT_SQL_TOO!((NULL IS NOT NULL) == x0);
  EXPECT_SQL_TOO!(x5 > x2 IS NOT NULL);
  EXPECT_SQL_TOO!(NULL IS NOT x2 < x3);
  EXPECT_SQL_TOO!(NULL IS NULL + x1);
  EXPECT_SQL_TOO!(NULL IS x1 + NULL);
  EXPECT_SQL_TOO!(NULL IS x1 << NULL);

  let one := nullable("1");
  let two := nullable("2");
  EXPECT_SQL_TOO!(one IS two == x0);
  EXPECT_SQL_TOO!(one IS NULL == x0);
  EXPECT_SQL_TOO!(NULL IS one == x0);

  -- Test IN
  EXPECT_SQL_TOO!(x3 IN (x1, x2) == x0);
  EXPECT_SQL_TOO!(x3 + x2 IN (x1, x5));
  EXPECT_SQL_TOO!(x3 / x3 IN (x1, x2));
  EXPECT_SQL_TOO!(x3 / x3 IN (x1, x2) IN (x1));
  EXPECT_SQL_TOO!(x1 IN (NULL, x1));
  EXPECT!(NOT (x1 IN (NULL, x5))); -- known difference between CQL and SQLite in IN
  EXPECT_SQL_TOO!(NULL IS (NULL IN (x1)));

  -- Test NOT IN
  EXPECT_SQL_TOO!(x1 NOT IN (x1, x2) == x0);
  EXPECT_SQL_TOO!(x3 NOT IN (x1, x2) == x1);
  EXPECT_SQL_TOO!(x3 + x2 NOT IN (x1, x2));
  EXPECT_SQL_TOO!(x3 / x1 NOT IN (x1, x2));
  EXPECT_SQL_TOO!(x3 / x1 NOT IN (x1, x2) IN (x1));
  EXPECT_SQL_TOO!(NOT (x1 NOT IN (NULL, x1)));
  EXPECT!(x1 NOT IN (NULL, x5)); -- known difference between CQL and SQLite in IN
  EXPECT_SQL_TOO!(NULL IS (NULL NOT IN (x1)));

  declare x text;
  x := NULL;
  EXPECT_SQL_TOO!((x IN ("foo", "goo")) IS NULL);
  EXPECT_SQL_TOO!((x NOT IN ("foo", "goo")) IS NULL);

  EXPECT_SQL_TOO!(x3 + x3 AND x5);
  EXPECT_SQL_TOO!((x3 + x3 AND x0) == x0);
  EXPECT_SQL_TOO!((NULL AND x1) IS NULL);
  EXPECT_SQL_TOO!((NULL AND x1 = temp_null) IS NULL);
  EXPECT_SQL_TOO!(NOT (NULL AND x1 IS NULL));
  EXPECT_SQL_TOO!((NULL AND x0) == x0);
  EXPECT_SQL_TOO!(NOT (NULL AND x0));
  EXPECT_SQL_TOO!(x1 AND x0 == x0);
  EXPECT_SQL_TOO!(x1 AND x0 = x0);
  EXPECT_SQL_TOO!(x1 AND x1 != x0);
  EXPECT_SQL_TOO!(x1 AND x1 <> x0);
  EXPECT_SQL_TOO!(x5 IS x5 AND x2 IS x2);
  EXPECT_SQL_TOO!(x5 IS NOT NULL AND x2 IS x2);
  EXPECT_SQL_TOO!(x5 IS NOT NULL AND x2 IS x2);
  EXPECT_SQL_TOO!(x5 AND x0 + x1);
  EXPECT_SQL_TOO!(x5 AND x0 * x1 + x1);
  EXPECT_SQL_TOO!(x5 AND x0 >> x4 >= -x1);
  temp1 := nullable(12);
  EXPECT_SQL_TOO!(x5 AND x0 | x4 & temp1);
  EXPECT_SQL_TOO!(x5 AND x6 / x3);
  temp1 := nullable(25);
  EXPECT_SQL_TOO!((x5 AND temp1 % x5) == x0);
  EXPECT_SQL_TOO!(x5 AND x0 IN (x0));

  EXPECT_SQL_TOO!((x0 OR x1 OR x1 AND x0 OR x0) != ((((x0 OR x1) OR x1) AND x0) OR x0));
  EXPECT_SQL_TOO!((x1 OR x1 AND x0 AND x1 AND x0) != ((((x1 OR x1) AND x0) AND x1) AND x0));
  EXPECT_SQL_TOO!((x0 OR x1 OR x1 AND x0 AND x1) != ((((x0 OR x1) OR x1) AND x0) AND x1));
  EXPECT_SQL_TOO!((x1 OR x1 OR x1 AND x0 AND x0) != ((((x1 OR x1) OR x1) AND x0) AND x0));
  EXPECT_SQL_TOO!((x1 OR x1 OR x1 AND x0 OR x0) != ((((x1 OR x1) OR x1) AND x0) OR x0));
  EXPECT_SQL_TOO!((x1 AND x1 AND x1 OR x1 AND x0) != ((((x1 AND x1) AND x1) OR x1) AND x0));
  EXPECT_SQL_TOO!((x1 OR x0 AND x0 AND x1 OR x0) != ((((x1 OR x0) AND x0) AND x1) OR x0));
  EXPECT_SQL_TOO!((x1 AND x1 OR x0 AND x0 AND x1) != ((((x1 AND x1) OR x0) AND x0) AND x1));
  EXPECT_SQL_TOO!((x1 OR x0 OR x0 OR x0 AND x0) != ((((x1 OR x0) OR x0) OR x0) AND x0));
  EXPECT_SQL_TOO!((x1 OR x0 AND x0 OR x1 AND x0) != ((((x1 OR x0) AND x0) OR x1) AND x0));
  EXPECT_SQL_TOO!((x1 OR x1 AND x1 AND x1 AND x0) != ((((x1 OR x1) AND x1) AND x1) AND x0));
  EXPECT_SQL_TOO!((x0 AND x0 OR x1 OR x0 AND x0) != ((((x0 AND x0) OR x1) OR x0) AND x0));
  EXPECT_SQL_TOO!((x0 OR x1 OR x1 AND x0 AND x0) != ((((x0 OR x1) OR x1) AND x0) AND x0));
  EXPECT_SQL_TOO!((x1 AND x1 AND x1 OR x0 AND x0) != ((((x1 AND x1) AND x1) OR x0) AND x0));
  EXPECT_SQL_TOO!((x1 OR x1 OR x1 AND x0 AND x1) != ((((x1 OR x1) OR x1) AND x0) AND x1));
  EXPECT_SQL_TOO!((x1 OR x0 OR x0 OR x0 AND x0) != ((((x1 OR x0) OR x0) OR x0) AND x0));

END);

@attribute(cql:vault_sensitive)
proc load_encoded_table()
begin
  create table all_types_encoded_table(
    b0 bool @sensitive,
    i0 int @sensitive,
    l0 long @sensitive,
    d0 real @sensitive,
    s0 text @sensitive,
    bl0 blob @sensitive,

    b1 bool! @sensitive,
    i1 int! @sensitive,
    l1 long! @sensitive,
    d1 real! @sensitive,
    s1 text! @sensitive,
    bl1 blob! @sensitive
  );

  insert into all_types_encoded_table values (
    FALSE, 0, 0, 0.0, "0", "0" ~blob~,
    TRUE, 1, 1, 1.1, "1", "1" ~blob~
  );

  select * from all_types_encoded_table;
end;

@attribute(cql:vault_sensitive=(context, (b0, i0, l0, d0, s0, bl0, b1, i1, l1, d1, s1, bl1)))
proc load_encoded_with_context_table()
begin
  create table all_types_encoded_with_context_table(
    b0 bool @sensitive,
    i0 int @sensitive,
    l0 long @sensitive,
    d0 real @sensitive,
    s0 text @sensitive,
    bl0 blob @sensitive,

    b1 bool! @sensitive,
    i1 int! @sensitive,
    l1 long! @sensitive,
    d1 real! @sensitive,
    s1 text! @sensitive,
    bl1 blob! @sensitive,

    context text!
  );

  insert into all_types_encoded_with_context_table values (
    FALSE, 0, 0, 0.0, "0", cast("0" as blob),
    TRUE, 1, 1, 1.1, "1", cast("1" as blob), "cxt"
  );

  select * from all_types_encoded_with_context_table;
end;

@attribute(cql:vault_sensitive)
proc load_encoded_cursor()
begin
  cursor C for select * from all_types_encoded_table;
  fetch C;
  out C;
end;

@attribute(cql:vault_sensitive)
proc out_union_dml()
begin
  declare x cursor for select * from all_types_encoded_table;
  fetch x;
  out union x;
end;

@attribute(cql:vault_sensitive)
proc out_union_not_dml()
begin
  declare bogus cursor for select 1; -- just to make the proc dml to test a non dml cursor x with vault.

  declare x cursor like all_types_encoded_table;
  fetch x using
    0 b0,
    0 i0,
    0 l0,
    0.0 d0,
    "0" s0,
    blob_from_string("0") bl0,
    1 b1,
    1 i1,
    1 l1,
    1.1 d1,
    "1" s1,
    blob_from_string("1") bl1;

  out union x;
end;

@attribute(cql:vault_sensitive)
proc load_decoded_out_union()
begin
  cursor C for call out_union_dml();
  fetch C;
  out C;
end;

@attribute(cql:vault_sensitive)
proc load_decoded_multi_out_union()
begin
  cursor C for call out_union_dml();
  fetch C;
  out union C;

  declare C1 cursor for call out_union_not_dml();
  fetch C1;
  out union C1;
end;

@attribute(cql:vault_sensitive=(z, (y)))
proc out_union_dml_with_encode_context()
begin
  create table some_type_encoded_table(x int, y text @sensitive, z text);
  insert into some_type_encoded_table using 66 x, 'abc' y, 'xyz' z;
  declare x cursor for select * from some_type_encoded_table;
  fetch x;
  out union x;
end;

TEST!(decoded_value_with_encode_context,
BEGIN
  cursor C for call out_union_dml_with_encode_context();
  fetch C;

  EXPECT!(C.x IS 66);
  EXPECT!(C.y IS 'abc');
  EXPECT!(C.z IS 'xyz');
END);

TEST!(encoded_values,
BEGIN
  cursor C for call load_encoded_table();
  fetch C;
  EXPECT!(C.b0 IS 0);
  EXPECT!(C.i0 IS 0);
  EXPECT!(C.l0 IS 0);
  EXPECT!(C.d0 IS 0.0);
  EXPECT!(C.s0 IS "0");
  EXPECT!(string_from_blob(C.bl0) IS "0");
  EXPECT!(C.b1 IS 1);
  EXPECT!(C.i1 IS 1);
  EXPECT!(C.l1 IS 1);
  EXPECT!(C.d1 IS 1.1);
  EXPECT!(C.s1 IS "1");
  EXPECT!(string_from_blob(C.bl1) IS "1");

  declare C1 cursor for call out_union_dml();
  fetch C1;
  EXPECT!(cql_cursor_diff_val(C, C1) IS NULL);

  declare C2 cursor for call out_union_not_dml();
  fetch C2;
  EXPECT!(cql_cursor_diff_val(C, C2) IS NULL);

  declare C3 cursor fetch from call load_decoded_out_union();
  EXPECT!(cql_cursor_diff_val(C, C3) IS NULL);
END);

TEST!(encoded_null_values,
BEGIN
  create table encode_null_table(
      b0 bool @sensitive,
      i0 int @sensitive,
      l0 long @sensitive,
      d0 real @sensitive,
      s0 text @sensitive,
      bl0 blob @sensitive
  );
  insert into encode_null_table using
    null b0,
    null i0,
    null l0,
    null d0,
    null s0,
    null bl0;

  cursor C for select * from encode_null_table;
  fetch C;

  EXPECT!(C.b0 IS null);
  EXPECT!(C.i0 IS null);
  EXPECT!(C.l0 IS null);
  EXPECT!(C.d0 IS null);
  EXPECT!(C.s0 IS null);
  EXPECT!(C.bl0 IS null);
END);


declare proc obj_shape(set_ object) out union (o object);
declare proc not_null_obj_shape(set_ object!) out union (o object!);

proc emit_object_result_set(set_ object)
begin
  cursor C like obj_shape;
  fetch C using set_ o;
  out union C;

  fetch C using null o;
  out union C;
end;

proc emit_object_result_set_not_null(set_ object!)
begin
  cursor C like not_null_obj_shape;
  fetch C using set_ o;
  out union C;
end;

TEST!(object_result_set_value,
BEGIN
  let s := set_create();
  declare D cursor for call emit_object_result_set(s);
  fetch D;
  EXPECT!(D);
  EXPECT!(D.o is s);

  fetch D;
  EXPECT!(D);
  EXPECT!(D.o is null);

  declare E cursor for call emit_object_result_set_not_null(s);
  fetch E;
  EXPECT!(E);
  EXPECT!(E.o is s);
END);

@attribute(cql:vault_sensitive=(y))
proc load_some_encoded_field()
begin
  create table some_encoded_field_table(x int, y text @sensitive);
  insert into some_encoded_field_table using 66 x, 'bogus' y;

  cursor C for select * from some_encoded_field_table;
  fetch C;
  out C;
end;

TEST!(read_partially_vault_cursor,
BEGIN
  cursor C fetch from call load_some_encoded_field();

  EXPECT!(C.x IS 66);
  EXPECT!(C.y IS 'bogus');
END);

@attribute(cql:vault_sensitive=(z, (y)))
proc load_some_encoded_field_with_encode_context()
begin
  create table some_encoded_field_context_table(x int, y text @sensitive, z text);
  insert into some_encoded_field_context_table using 66 x, 'bogus' y, 'context' z;

  cursor C for select * from some_encoded_field_context_table;
  fetch C;
  out C;
end;

TEST!(read_partially_encode_with_encode_context_cursor,
BEGIN
  cursor C fetch from call load_some_encoded_field_with_encode_context();

  EXPECT!(C.x IS 66);
  EXPECT!(C.y IS 'bogus');
  EXPECT!(C.z IS 'context');
END);

@attribute(cql:emit_setters)
proc load_all_types_table()
begin
  create table all_types_table(
    b0 bool @sensitive,
    i0 int @sensitive,
    l0 long @sensitive,
    d0 real @sensitive,
    s0 text @sensitive,
    bl0 blob @sensitive,

    b1 bool!,
    i1 int!,
    l1 long!,
    d1 real!,
    s1 text!,
    bl1 blob!
  );

  -- all nullables null
  insert into all_types_table(bl1) values(cast("bl1_0" as blob)) @dummy_seed(0);

  -- all nullables not null
  insert into all_types_table(bl0, bl1) values(cast("bl0_1" as blob),  cast("bl1_1" as blob)) @dummy_seed(1) @dummy_nullables;
  select * from all_types_table;
end;

-- this proc will make the tables and also this serves as the table declarations
proc init_temp_tables()
begin
  create temp table temp_table_one(id int! @sensitive);
  create temp table temp_table_two(id int!);
  create temp table temp_table_three(id int!);

  insert into temp_table_one values(1);
  insert into temp_table_two values(2);
  insert into temp_table_three values(3);
end;

-- The run test client verifies that we can call this proc twice
-- having read the rowset out of it and it still succeeds because
-- the tables are dropped. Note simply calling the proc from CQL
-- will not do the job -- you have to use the result set helper
-- to get the auto-cleanup.  If you are using the statement
-- as with a direct CQL call, you are out of luck
@attribute(cql:autodrop=(temp_table_one, temp_table_two, temp_table_three))
proc read_three_tables_and_autodrop()
begin
  call init_temp_tables();

  select * from temp_table_one
  union all
  select * from temp_table_two
  union all
  select * from temp_table_three;
end;

-- This helper proc will be called by the client producing its one-row result
-- it has no DB pointer and that exercises and important case in the autodrop logic
-- where info.db is NULL.  There can be no autodrop tables here.
proc simple_cursor_proc()
begin
  cursor C like temp_table_one;
  fetch C (id) from values(1);
  out c;
end;

-- This is a simple proc we will use to create a result set that is a series of integers.
-- Below we will read and verify these results.

-- this table will never exist
create table dummy_table(id int);

proc some_integers(start int!, stop int!)
begin
  cursor C like select 1 v, 2 vsq, "xx" junk;
  declare i int!;
  i := start;
  while (i < stop)
  begin
    fetch C(v, vsq, junk) from values (i, i*i, printf("%d", i));
    out union C;
    i += 1;
  end;

  -- if the start was -1 then force an error, this ensures full cleanup
  -- do this after we have produced rows to make it hard
  if start == -1 then
    drop table dummy_table;
  end if;
end;

-- we need this helper to get a rowset out with type "object", all it does is call the above proc
-- we just need the cast that it does really, but there's no way to code that cast in CQL.

declare proc some_integers_fetch(out rs object!, start int!, stop int!) using transaction;

-- these are the helper functions we will be using to read the rowset, they are defined and registered elsewhere
-- See the "call cql_init_extensions();" above for registration.

declare select function rscount(rs long) long;
declare select function rscol(rs long, row int!, col int!) long;

-- This test is is going to create a rowset using a stored proc, then
-- using the helper proc some_integers_fetch() get access to the result set pointer
-- rather than the sqlite statement.  Then it iterates over the result set as though
-- that result set were a virtual table.  The point of all of this is to test
-- the virtual-table-like construct that we have created and in so doing
-- test the runtime binding facilities needed by ptr(x)

TEST!(rowset_reading,
BEGIN
  declare start, stop, cur int!;
  start := 10;
  stop := 20;
  declare rs object!;
  call some_integers_fetch(rs, start, stop);

  -- use a nullable version too to exercise both kinds of binding
  declare rs1 object;
  rs1 := rs;

  cursor C for
    with recursive
    C(i) as (select 0 i union all select i+1 i from C limit rscount(ptr(rs))),
    V(v,vsq) as (select rscol(ptr(rs), C.i, 0), rscol(ptr(rs1), C.i, 1) from C)
    select * from V;

  cur := start;
  loop fetch C
  begin
    EXPECT!(C.v == cur);
    EXPECT!(C.v * C.v == C.vsq);
    cur := cur + 1;
  end;

END);

TEST!(rowset_reading_language_support,
BEGIN
  declare cur int!;
  cur := 7;
  cursor C for call some_integers(7, 12);
  loop fetch C
  begin
    EXPECT!(C.v == cur);
    EXPECT!(c.vsq == cur * cur);
    cur := cur + 1;
  end;
END);

proc all_types_union()
begin
  cursor C like all_types_table;

  -- all nullables null
  fetch C(bl1) from values(blob_from_string("bl1_0")) @dummy_seed(0);
  out union C;

  -- all nullables not null
  fetch C(bl0, bl1) from values(blob_from_string("bl0_1"), blob_from_string("bl1_1")) @dummy_seed(1) @dummy_nullables;
  out union C;
end;

TEST!(read_all_types_rowset,
BEGIN
  cursor C for call all_types_union();
  fetch C;
  EXPECT!(C);

  EXPECT!(C.b0 IS NULL);
  EXPECT!(C.i0 IS NULL);
  EXPECT!(C.l0 IS NULL);
  EXPECT!(C.d0 IS NULL);
  EXPECT!(C.s0 IS NULL);
  EXPECT!(C.bl0 IS NULL);
  EXPECT!(C.b1 IS 0);
  EXPECT!(C.i1 IS 0);
  EXPECT!(C.l1 IS 0);
  EXPECT!(C.d1 IS 0);
  EXPECT!(C.s1 == "s1_0");
  EXPECT!(C.bl1 == blob_from_string("bl1_0"));

  fetch C;
  EXPECT!(C);

  EXPECT!(C.b0 IS 1);
  EXPECT!(C.i0 IS 1);
  EXPECT!(C.l0 IS 1);
  EXPECT!(C.d0 IS 1);
  EXPECT!(C.s0 IS "s0_1");
  EXPECT!(C.bl0 IS blob_from_string("bl0_1"));
  EXPECT!(C.b1 IS 1);
  EXPECT!(C.i1 IS 1);
  EXPECT!(C.l1 IS 1);
  EXPECT!(C.d1 IS 1);
  EXPECT!(C.s1 == "s1_1");
  EXPECT!(C.bl1 IS blob_from_string("bl1_1"));

  fetch C;
  EXPECT!(not C);
END);

TEST!(read_all_types_auto_fetcher,
BEGIN
  -- we want to force the auto fetcher to be called, so we capture the result set
  -- rather than cursoring over it.  Then we cursor over the captured result set

  let result_set := load_all_types_table();
  cursor C for result_set;
  fetch C;
  EXPECT!(C);

  EXPECT!(C.b0 IS NULL);
  EXPECT!(C.i0 IS NULL);
  EXPECT!(C.l0 IS NULL);
  EXPECT!(C.d0 IS NULL);
  EXPECT!(C.s0 IS NULL);
  EXPECT!(C.bl0 IS NULL);
  EXPECT!(C.b1 IS 0);
  EXPECT!(C.i1 IS 0);
  EXPECT!(C.l1 IS 0);
  EXPECT!(C.d1 IS 0);
  EXPECT!(C.s1 == "s1_0");
  EXPECT!(string_from_blob(C.bl1) == "bl1_0");

  fetch C;
  EXPECT!(C);

  EXPECT!(C.b0 IS 1);
  EXPECT!(C.i0 IS 1);
  EXPECT!(C.l0 IS 1);
  EXPECT!(C.d0 IS 1);
  EXPECT!(C.s0 IS "s0_1");
  EXPECT!(string_from_blob(C.bl0) == "bl0_1");
  EXPECT!(C.b1 IS 1);
  EXPECT!(C.i1 IS 1);
  EXPECT!(C.l1 IS 1);
  EXPECT!(C.d1 IS 1);
  EXPECT!(C.s1 == "s1_1");
  EXPECT!(string_from_blob(C.bl1) == "bl1_1");
  EXPECT!(cql_get_blob_size(C.bl1) == 5);

  fetch C;
  EXPECT!(not C);
END);

TEST!(rowset_via_union_failed,
BEGIN
  declare ok_after_all bool!;
  declare start, stop, cur int!;

  start := -1;
  stop := 1;
  declare rs object!;
  try
    call some_integers_fetch(rs, start, stop);
  catch
    ok_after_all := 1;
  end;

  -- throw happened and we're not gonna leak
  EXPECT!(ok_after_all);

END);

TEST!(boxing_cursors,
BEGIN
  let i := 0;
  while i < 5
  begin
    cursor C for
      with data(x,y) as (values (1,2), (3,4), (5,6))
      select * from data;

    declare box object<C cursor>;
    set box from cursor C;
    declare D cursor for box;

    fetch C;
    EXPECT!(C.x == 1);
    EXPECT!(C.y == 2);

    fetch D;
    -- C did not change
    EXPECT!(C.x == 1);
    EXPECT!(C.y == 2);
    EXPECT!(D.x == 3);
    EXPECT!(D.y == 4);

    fetch C;
    -- C advanced D values held
    EXPECT!(C.x == 5);
    EXPECT!(C.y == 6);
    EXPECT!(D.x == 3);
    EXPECT!(D.y == 4);

    i += 1;
  end;
END);

proc a_few_rows()
begin
  with data(x,y) as (values (1,2), (3,4), (5,6))
  select * from data;
end;

TEST!(boxing_from_call,
BEGIN
  let i := 0;
  while i < 5
  begin
    cursor C for call a_few_rows();

    declare box object<C cursor>;
    set box from cursor C;
    declare D cursor for box;

    fetch C;
    EXPECT!(C.x == 1);
    EXPECT!(C.y == 2);

    fetch D;
    -- C did not change
    EXPECT!(C.x == 1);
    EXPECT!(C.y == 2);
    EXPECT!(D.x == 3);
    EXPECT!(D.y == 4);

    fetch C;
    -- C advanced D values held
    EXPECT!(C.x == 5);
    EXPECT!(C.y == 6);
    EXPECT!(D.x == 3);
    EXPECT!(D.y == 4);

    i += 1;
  end;
END);

@enforce_normal cast;

TEST!(numeric_casts,
BEGIN
  declare b bool!;
  declare i int!;
  declare l long!;
  declare r real!;
  declare b0 bool;
  declare i0 int;
  declare l0 long;
  declare r0 real;

  -- force conversion (not null)
  b := cast(7.5 as bool);
  EXPECT!(b == 1);
  i := cast(1.9 as int);
  EXPECT!(i == 1);
  l := cast(12.9 as long);
  EXPECT!(l == 12);
  r := cast(12 as real);
  EXPECT!(r == 12.0);

  -- null cases
  EXPECT!(cast(b0 as bool) is null);
  EXPECT!(cast(b0 as int) is null);
  EXPECT!(cast(b0 as long) is null);
  EXPECT!(cast(b0 as real) is null);

  -- force conversion (nullable)
  declare x real;
  x := 7.5;
  b0 := cast(x as bool);
  EXPECT!(b0 == 1);
  x := 1.9;
  i0 := cast(x as int);
  EXPECT!(i0 == 1);
  x := 12.9;
  l0 := cast(x as long);
  EXPECT!(l0 == 12);
  x := 12.0;
  r0 := cast(x as real);
  EXPECT!(r0 == 12.0);
  l := 12;
  r0 := cast(l as real);
  EXPECT!(r0 == 12.0);

END);

@enforce_strict cast;

proc dummy(seed int!, i int!, r real!, b bool!)
begin
  EXPECT!(seed == i);
  EXPECT!(seed == r);
  EXPECT!(not seed == not b);
end;

TEST!(cursor_args,
BEGIN
  declare args cursor like dummy arguments;
  fetch args() from values() @dummy_seed(12);
  call dummy(from args);
END);

DECLARE PROCEDURE cql_exec_internal(sql TEXT!) USING TRANSACTION;
create table xyzzy(id int, name text, data blob);

TEST!(exec_internal,
BEGIN
  call cql_exec_internal("create table xyzzy(id integer, name text, data blob);");
  declare bl1 blob;
  bl1 := blob_from_string('z');
  declare bl2 blob;
  bl2 := blob_from_string('w');
  insert into xyzzy using 1 id, 'x' name, bl1 data;
  insert into xyzzy using 2 id, 'y' name, bl2 data;
  cursor C for select * from xyzzy;
  declare D cursor like C;
  fetch C;
  fetch D using 1 id, 'x' name, bl1 data;
  EXPECT!(cql_cursor_diff_val(C,D) is null);
  fetch C;
  fetch D using 2 id, 'y' name, bl2 data;
  EXPECT!(cql_cursor_diff_val(C,D) is null);
END);

TEST!(const_folding,
BEGIN
  EXPECT!(const(1 + 1) == 2);
  EXPECT!(const(1.0 + 1) == 2.0);
  EXPECT!(const(1 + 1L) == 2L);
  EXPECT!(const(1 + (1==1) ) == 2);
  EXPECT!(const(1.0 + 1L) == 2.0);
  EXPECT!(const(1.0 + (1 == 1)) == 2.0);
  EXPECT!(const((1==1) + 1L) == 2L);

  EXPECT!(2 == const(1 + 1));
  EXPECT!(2.0 == const(1.0 + 1));
  EXPECT!(2L == const(1 + 1L));
  EXPECT!(2 == const(1 + (1==1) ));

  EXPECT!(const(1 - 1) == 0);
  EXPECT!(const(1.0 - 1) == 0.0);
  EXPECT!(const(1 - 1L) == 0L);
  EXPECT!(const(1 - (1==1) ) == 0);

  EXPECT!(const(3 * 2) == 6);
  EXPECT!(const(3.0 * 2) == 6.0);
  EXPECT!(const(3 * 2L) == 6L);
  EXPECT!(const(3 * (1==1) ) == 3);

  EXPECT!(const(3 / 1) == 3);
  EXPECT!(const(3.0 / 1) == 3.0);
  EXPECT!(const(3 / 1L) == 3L);
  EXPECT!(const(3 / (1==1) ) == 3);

  EXPECT!(const(3 % 1) == 0);
  EXPECT!(const(3 % 1L) == 0L);
  EXPECT!(const(3 % (1==1) ) == 0);

  EXPECT!(const(8 | 1) == 9);
  EXPECT!(const(8 | 1L) == 9L);
  EXPECT!(const(8 | (1==1) ) == 9);

  EXPECT!(const(7 & 4) == 4);
  EXPECT!(const(7 & 4L) == 4L);
  EXPECT!(const(7 & (1==1) ) == 1);

  EXPECT!(const(16 << 1) == 32);
  EXPECT!(const(16 << 1L) == 32L);
  EXPECT!(const(16 << (1==1) ) == 32);

  EXPECT!(const(16 >> 1) == 8);
  EXPECT!(const(16 >> 1L) == 8L);
  EXPECT!(const(16 >> (1==1) ) == 8);

  EXPECT!(const(NULL) is null);

  EXPECT!(const( 1 or 1/0) == 1);
  EXPECT!(const( 0 or null) is null);
  EXPECT!(const( 0 or 0) == 0);
  EXPECT!(const( 0 or 1) == 1);
  EXPECT!(const( null or null) is null);
  EXPECT!(const( null or 0) is null);
  EXPECT!(const( null or 1) is 1);

  EXPECT!(const( 0 and 1/0) == 0);
  EXPECT!(const( 1 and null) is null);
  EXPECT!(const( 1 and 0) == 0);
  EXPECT!(const( 1 and 1) == 1);
  EXPECT!(const( null and null) is null);
  EXPECT!(const( null and 0) == 0);
  EXPECT!(const( null and 1) is null);

  EXPECT!(const(3 == 3));
  EXPECT!(const(3 == 3.0));
  EXPECT!(const(3 == 3L));
  EXPECT!(const((0 == 0) == (1 == 1)));

  EXPECT!(const(4 != 3));
  EXPECT!(const(4 != 3.0));
  EXPECT!(const(4 != 3L));
  EXPECT!(const((1 == 0) != (1 == 1)));

  EXPECT!(const(4 >= 3));
  EXPECT!(const(4 >= 3.0));
  EXPECT!(const(4 >= 3L));
  EXPECT!(const((1 == 1) >= (1 == 0)));

  EXPECT!(const(3 >= 3));
  EXPECT!(const(3 >= 3.0));
  EXPECT!(const(3 >= 3L));
  EXPECT!(const((1 == 1) >= (1 == 1)));

  EXPECT!(const(4 > 3));
  EXPECT!(const(4 > 3.0));
  EXPECT!(const(4 > 3L));
  EXPECT!(const((1 == 1) > (1 == 0)));

  EXPECT!(const(2 <= 3));
  EXPECT!(const(2 <= 3.0));
  EXPECT!(const(2 <= 3L));
  EXPECT!(const((1 == 0) <= (1 == 1)));

  EXPECT!(const(3 <= 3));
  EXPECT!(const(3 <= 3.0));
  EXPECT!(const(3 <= 3L));
  EXPECT!(const((1 == 1) <= (1 == 1)));

  EXPECT!(const(2 < 3));
  EXPECT!(const(2 < 3.0));
  EXPECT!(const(2 < 3L));
  EXPECT!(const((1 == 0) < (1 == 1)));

  EXPECT!((NULL + NULL) is NULL);
  EXPECT!((NULL - NULL) is NULL);
  EXPECT!((NULL * NULL) is NULL);
  EXPECT!((NULL / NULL) is NULL);
  EXPECT!((NULL % NULL) is NULL);
  EXPECT!((NULL | NULL) is NULL);
  EXPECT!((NULL & NULL) is NULL);
  EXPECT!((NULL << NULL) is NULL);
  EXPECT!((NULL >> NULL) is NULL);

  EXPECT!(const(NULL + NULL) is NULL);
  EXPECT!(const(NULL - NULL) is NULL);
  EXPECT!(const(NULL * NULL) is NULL);
  EXPECT!(const(NULL / NULL) is NULL);
  EXPECT!(const(NULL % NULL) is NULL);
  EXPECT!(const(NULL | NULL) is NULL);
  EXPECT!(const(NULL & NULL) is NULL);
  EXPECT!(const(NULL << NULL) is NULL);
  EXPECT!(const(NULL >> NULL) is NULL);

  EXPECT!(const((NULL + NULL) is NULL));
  EXPECT!(const((NULL - NULL) is NULL));
  EXPECT!(const((NULL * NULL) is NULL));
  EXPECT!(const((NULL / NULL) is NULL));
  EXPECT!(const((NULL % NULL) is NULL));
  EXPECT!(const((NULL | NULL) is NULL));
  EXPECT!(const((NULL & NULL) is NULL));
  EXPECT!(const((NULL << NULL) is NULL));
  EXPECT!(const((NULL >> NULL) is NULL));

  EXPECT!(const(NULL IS NOT NULL) == 0);
  EXPECT!(const(NULL IS NOT 1));
  EXPECT!(const((1 OR NULL) IS NOT NULL));

  EXPECT!(const(1 IS 1));
  EXPECT!(const(1L IS 1L));
  EXPECT!(const(1.0 IS 1.0));
  EXPECT!(const((1==1) is (2==2)));

  EXPECT!(const(cast(3.2 as int) == 3));
  EXPECT!(const(cast(3.2 as long) == 3L));
  EXPECT!(const(cast(3.2 as bool) == 1));
  EXPECT!(const(cast(0.0 as bool) == 0));
  EXPECT!(const(cast(null+0 as bool) is null));
  EXPECT!(const(cast(3L as real) == 3.0));
  EXPECT!(const(cast(3L as int) == 3));
  EXPECT!(const(cast(3L as bool) == 1));
  EXPECT!(const(cast(0L as bool) == 0));

  EXPECT!(const(not 0) == 1);
  EXPECT!(const(not 1) == 0);
  EXPECT!(const(not 2) == 0);
  EXPECT!(const(not 0L) == 1);
  EXPECT!(const(not 1L) == 0);
  EXPECT!(const(not 2L) == 0);
  EXPECT!(const(not 2.0) == 0);
  EXPECT!(const(not 0.0) == 1);
  EXPECT!(const(not not 2) == 1);
  EXPECT!(const(not NULL) is NULL);

  EXPECT!(const(~0) == -1);
  EXPECT!(const(~0L) == -1L);
  EXPECT!(const(~ ~0L) == 0L);
  EXPECT!(const(~NULL) is NULL);
  EXPECT!(const(~(0==0)) == -2);
  EXPECT!(const(~(0==1)) == -1);

  EXPECT!(const(-1) == -1);
  EXPECT!(const(-2) == -2);
  EXPECT!(const(-1.0) == -1.0);
  EXPECT!(const(-2.0) == -2.0);
  EXPECT!(const((0 + -2)) == -2);
  EXPECT!(const(-(1 + 1)) == -2);
  EXPECT!(const(-1L) == -1L);
  EXPECT!(const(- -1L) == 1L);
  EXPECT!(const(-NULL) is NULL);
  EXPECT!(const(-(0==0)) == -1);
  EXPECT!(const(-(0==1)) == 0);

  -- IIF gets rewritten to case/when so we use that here for convenience
  EXPECT!(const(iif(1, 3, 5)) == 3);
  EXPECT!(const(iif(0, 3, 5)) == 5);
  EXPECT!(const(iif(1L, 3, 5)) == 3);
  EXPECT!(const(iif(0L, 3, 5)) == 5);
  EXPECT!(const(iif(1.0, 3, 5)) == 3);
  EXPECT!(const(iif(0.0, 3, 5)) == 5);
  EXPECT!(const(iif((1==1), 3, 5)) == 3);
  EXPECT!(const(iif((1==0), 3, 5)) == 5);

  EXPECT!(const(case 1 when 2 then 20 else 10 end) == 10);
  EXPECT!(const(case 2 when 2 then 20 else 10 end) == 20);
  EXPECT!(const(case 2 when 1 then 10 when 2 then 20 else 40 end) == 20);
  EXPECT!(const(case 1 when 1 then 10 when 2 then 20 else 40 end) == 10);
  EXPECT!(const(case 5 when 1 then 10 when 2 then 20 else 40 end) == 40);
  EXPECT!(const(case null when 1 then 10 when 2 then 20 else 40 end) == 40);

  EXPECT!(const(case 1.0 when 2 then 20 else 10 end) == 10);
  EXPECT!(const(case 2.0 when 2 then 20 else 10 end) == 20);
  EXPECT!(const(case 2.0 when 1 then 10 when 2 then 20 else 40 end) == 20);
  EXPECT!(const(case 1.0 when 1 then 10 when 2 then 20 else 40 end) == 10);
  EXPECT!(const(case 5.0 when 1 then 10 when 2 then 20 else 40 end) == 40);

  EXPECT!(const(case 1L when 2 then 20 else 10 end) == 10);
  EXPECT!(const(case 2L when 2 then 20 else 10 end) == 20);
  EXPECT!(const(case 2L when 1 then 10 when 2 then 20 else 40 end) == 20);
  EXPECT!(const(case 1L when 1 then 10 when 2 then 20 else 40 end) == 10);
  EXPECT!(const(case 5L when 1 then 10 when 2 then 20 else 40 end) == 40);

  EXPECT!(const(case (1==1) when (1==1) then 10 else 20 end) == 10);
  EXPECT!(const(case (1==0) when (1==1) then 10 else 20 end) == 20);
  EXPECT!(const(case (1==1) when (0==1) then 10 else 20 end) == 20);
  EXPECT!(const(case (1==0) when (0==1) then 10 else 20 end) == 10);

  EXPECT!(const(case 5L when 1 then 10 when 2 then 20 end) is NULL);

  EXPECT!(const(0x10) == 16);
  EXPECT!(const(0x10 + 0xf) == 31);
  EXPECT!(const(0x100100100) == 0x100100100);
  EXPECT!(const(0x100100100L) == 0x100100100);
  EXPECT!(const(0x100100100) == 0x100100100L);
  EXPECT!(const(0x100100100L) == 0x100100100L);

END);

TEST!(long_literals,
BEGIN
  declare x long!;
  declare z long;

  x := 1L;
  EXPECT!(x == 1);

  x := 10000000000;
  EXPECT!(x = 10000000000);
  EXPECT!(x != const(cast(10000000000L as int)));
  EXPECT!(x > 0x7fffffff);

  x := 10000000000L;
  EXPECT!(x = 10000000000L);
  EXPECT!(x != const(cast(10000000000L as int)));
  EXPECT!(x > 0x7fffffff);

  x := 0x1000000000L;
  EXPECT!(x = 0x1000000000L);
  EXPECT!(x != const(cast(0x10000000000L as int)));
  EXPECT!(x > 0x7fffffff);

  x := 0x1000000000;
  EXPECT!(x = 0x1000000000L);
  EXPECT!(x != const(cast(0x10000000000L as int)));
  EXPECT!(x > 0x7fffffff);

  x := const(0x1000000000);
  EXPECT!(x = 0x1000000000L);
  EXPECT!(x != const(cast(0x1000000000L as int)));
  EXPECT!(x > 0x7fffffff);

  x := 1000L * 1000 * 1000 * 1000;
  EXPECT!(x = 1000000000000);
  EXPECT!(x != const(cast(1000000000000 as int)));
  x := const(1000L * 1000 * 1000 * 1000);

  z := 1L;
  EXPECT!(z == 1);

  z := 10000000000;
  EXPECT!(z = 10000000000);
  EXPECT!(z != const(cast(10000000000L as int)));
  EXPECT!(z > 0x7fffffff);

  z := 10000000000L;
  EXPECT!(z = 10000000000L);
  EXPECT!(z != const(cast(10000000000L as int)));
  EXPECT!(z > 0x7fffffff);

  z := 0x1000000000L;
  EXPECT!(z = 0x1000000000L);
  EXPECT!(z != const(cast(0x1000000000L as int)));
  EXPECT!(z > 0x7fffffff);

  z := 0x1000000000;
  EXPECT!(z = 0x1000000000L);
  EXPECT!(z != const(cast(0x1000000000L as int)));
  EXPECT!(z > 0x7fffffff);

  z := const(0x1000000000);
  EXPECT!(z = 0x1000000000L);
  EXPECT!(z != const(cast(0x1000000000L as int)));
  EXPECT!(z > 0x7fffffff);

  z := 1000L * 1000 * 1000 * 1000;
  EXPECT!(z = 1000000000000);
  EXPECT!(z != const(cast(1000000000000 as int)));
  z := const(1000L * 1000 * 1000 * 1000);

END);

proc no_statement_really(x int)
begin
  if x then
    select 1 x;
  end if;
end;

TEST!(null_statement,
BEGIN
  cursor C for call no_statement_really(0);
  let x := 0;
  loop fetch C
  begin
    x := x + 1;
  end;
  EXPECT!(x == 0);
END);

TEST!(if_nothing_forms,
BEGIN
  create table tdata (
    id int,
    v int,
    t text);

  declare t1 text;
  t1 := (select t from tdata if nothing then "nothing");
  EXPECT!(t1 == "nothing");

  declare `value one` int;
  set `value one` := (select v from tdata if nothing then -1);
  EXPECT!(`value one` == -1);

  insert into tdata values(1, 2, null);
  t1 := (select t from tdata if nothing then "nothing");
  EXPECT!(t1 is null);

  set `value one` := (select v from tdata if nothing then -1);
  EXPECT!(`value one` == 2);

  t1 := (select t from tdata if nothing or null then "still nothing");
  EXPECT!(t1 == "still nothing");

  insert into tdata values(2, null, "x");
  set `value one` := (select v from tdata where id == 2 if nothing or null then -1);
  EXPECT!(`value one` == -1);

END);

proc simple_select()
begin
  select 1 x;
end;

TEST!(call_in_loop,
BEGIN
  let i := 0;
  while i < 5
  begin
    i += 1;
    cursor C for call simple_select();
    fetch C;
    EXPECT!(C.x == 1);
  end;
END);

TEST!(call_in_loop_boxed,
BEGIN
  let i := 0;
  while i < 5
  begin
    i += 1;
    cursor C for call simple_select();
    declare box object<C cursor>;
    set box from cursor C;
    declare D cursor for box;
    fetch D;
    EXPECT!(D.x == 1);
  end;
END);

proc out_union_helper()
begin
  cursor C like select 1 x;
  fetch C using 1 x;
  out union C;
end;

TEST!(call_out_union_in_loop,
BEGIN
  let i := 0;
  while i < 5
  begin
    i += 1;
    cursor C for call out_union_helper();
    fetch C;
    EXPECT!(C.x == 1);
  end;
END);

create table simple_rc_table(id int, foo text);
proc simple_insert()
begin
  insert into simple_rc_table(id, foo) values(1, "foo");
end;

proc select_if_nothing(id_ int!)
begin
  declare bar text;
  bar := (select foo from simple_rc_table where id == id_ if nothing then "bar");
end;

proc select_if_nothing_throw(id_ int!)
begin
  declare bar text;
  bar := (select foo from simple_rc_table where id == id_ if nothing then throw);
end;

TEST!(rc_simple_select,
BEGIN
  cursor C for call simple_select();
  EXPECT!(@rc == 0);
END);

TEST!(rc_simple_insert_and_select,
BEGIN
  create table simple_rc_table(id int, foo text);

  call simple_insert();
  EXPECT!(@rc == 0);

  call select_if_nothing(1);
  EXPECT!(@rc == 0);

  call select_if_nothing(2);
  EXPECT!(@rc == 0);

  try
    call select_if_nothing_throw(2);
  catch
    EXPECT!(@rc != 0);
  end;
END);

proc out_union()
begin
  cursor C like select 1 x;
  fetch C using 1 x;
  out union C;
end;

-- claims to be an out-union proc but isn't really going to produce anything
-- non dml path
proc out_union_nil_result()
begin
  if 0 then
    call out_union();
  end if;
end;

-- claims to be an out-union proc but isn't really going to produce anything
-- dml path
proc out_union_nil_result_dml()
begin
  if 0 then
    call out_union_dml();
  end if;
end;

TEST!(empty_out_union,
BEGIN
  cursor C for call out_union_nil_result();
  fetch C;
  EXPECT!(NOT C); -- cursor empty but not null

  declare D cursor for call out_union_nil_result_dml();
  fetch D;
  EXPECT!(NOT D); -- cursor empty but not null
END);

TEST!(nested_rc_values,
BEGIN
  let e0 := @rc;
  EXPECT!(e0 = 0); -- SQLITE_OK
  try
    -- force duplicate table error
    create table foo(id int primary key);
    create table foo(id int primary key);
  catch
    let e1 := @rc;
    EXPECT!(e1 == 1); -- SQLITE_ERROR
    try
      let e2 := @rc;
      EXPECT!(e2 == 1); -- SQLITE_ERROR
      -- force constraint error
      insert into foo using 1 id;
      insert into foo using 1 id;
    catch
      let e3 := @rc;
      EXPECT!(e3 == 19); -- SQLITE_CONSTRAINT
    end;
    let e4 := @rc;
    EXPECT!(e4 == 1); -- back to SQLITE_ERROR
  end;
  let e7 := @rc;
  EXPECT!(e7 = 0); -- back to SQLITE_OK
END);

-- facet helper functions, used by the schema upgrader
DECLARE facet_data TYPE OBJECT<facet_data>;
DECLARE FUNCTION cql_facets_create() create facet_data!;
DECLARE FUNCTION cql_facet_add(facets facet_data, facet TEXT!, crc LONG NOT NULL) BOOL NOT NULL;
DECLARE FUNCTION cql_facet_find(facets facet_data, facet TEXT!) LONG NOT NULL;

TEST!(facet_helpers,
BEGIN
  let facets := cql_facets_create();

  -- add some facets
  let i := 0;
  while i < 1000
  begin
    EXPECT!(cql_facet_add(facets, printf('fake facet %d', i), i*i));
    i += 1;
  end;

  -- all duplicates, all the adds should return false
  i := 0;
  while i < 1000
  begin
    EXPECT!(NOT cql_facet_add(facets, printf('fake facet %d', i), i*i));
    i += 1;
  end;

  -- we should be able to find all of these
  i := 0;
  while i < 1000
  begin
    EXPECT!(i*i == cql_facet_find(facets, printf('fake facet %d', i)));
    i += 1;
  end;

  -- we should be able to find none of these
  i := 0;
  while i < 1000
  begin
    EXPECT!(-1 == cql_facet_find(facets, printf('fake_facet %d', i)));
    i += 1;
  end;

  -- NOTE the test infra is counting refs so that if we fail
  -- to clean up the test fails; no expectation is required
END);

-- not null result
proc f(x int!, out y int!)
begin
  y := x;
end;

-- nullable version (not null arg)
proc fn(x int!, out y int)
begin
  y := x;
end;

-- nullable arg and result version (forces boxing)
proc fnn(x int, out y int)
begin
  y := x;
end;

-- the point of this is to force the temporaries from previous calls to
-- survive into the next expression, the final expression should be
-- something like t1+t2+t3+t4+t5+t6 with no sharing
TEST!(verify_temp_non_reuse,
BEGIN
  EXPECT!(f(1)+f(2)+f(4)+f(8)+f(16)+f(32)==63);
  EXPECT!(fn(1)+fn(2)+fn(4)+fn(8)+fn(16)+fn(32)==63);
  EXPECT!(f(1)+fn(2)+f(4)+fn(8)+f(16)+fn(32)==63);
  EXPECT!(fn(1)+f(2)+fn(4)+f(8)+fn(16)+f(32)==63);

  EXPECT!(fnn(1)+fnn(2)+fnn(4)+fnn(8)+fnn(16)+fnn(32)==63);
  EXPECT!(fn(1)+fnn(2)+fn(4)+fnn(8)+fn(16)+fnn(32)==63);
  EXPECT!(f(1)+fn(2)+fnn(4)+fn(8)+fnn(16)+fn(32)==63);
  EXPECT!(fn(1)+fnn(2)+fn(4)+f(8)+fnn(16)+f(32)==63);
END);

TEST!(compressible_batch,
BEGIN
  -- nest the batch so that it doesn't conflict with the macro proc preamble
  IF 1 THEN
    drop table if exists foo;
    create table goo(id int);
    insert into goo values (1), (2), (3);
  END IF;
  EXPECT!((select sum(id) from goo) == 6);
  drop table goo;
END);

-- a simple proc that creates a result set with out union
-- this reference must be correctly managed
proc get_row()
begin
  declare D cursor like select 'x' facet;
  fetch D using 'x' facet;
  out union D;
end;

-- the test here is to ensure that when we call get_row we correctly
-- release the previous result set
proc get_row_thrice()
begin
  -- these are redundant but they force the previous pending result to be freed
  -- this still returns a single row
  call get_row();
  call get_row();
  call get_row();
end;

TEST!(out_union_refcounts,
BEGIN
  cursor C FOR CALL get_row();
  FETCH C;
  EXPECT!(C);
  EXPECT!(C.facet = 'x');
  FETCH C;
  EXPECT!(NOT C);

  DECLARE D CURSOR FOR CALL get_row_thrice();
  FETCH D;
  EXPECT!(D);
  EXPECT!(D.facet = 'x');
  FETCH D;
  EXPECT!(NOT D);
END);


@attribute(cql:shared_fragment)
proc f1(pattern text)
begin
  with source(*) LIKE (select 1 id, "x" t)
  select * from source where t like pattern;
end;

@attribute(cql:shared_fragment)
proc f2(pattern text, idstart int!, idend int!, lim int!)
begin
  with
  source(*) LIKE f1,
  data(*) as (call f1(pattern) using source as source)
  select * from data where data.id between idstart and idend
  limit lim;
end;

@attribute(cql:private)
proc shared_consumer()
begin
  with
    source1(id, t) as (values (1100, 'x_x'), (1101, 'zz')),
    source2(id, t) as (values (4500, 'y_y'), (4501, 'zz')),
    t1(*) as (call f2('x%', 1000, 2000, 10) using source1 as source),
    t2(*) as (call f2('y%', 4000, 5000, 20) using source2 as source)
  select * from t1
  union all
  select * from t2;
end;

TEST!(shared_fragments,
BEGIN
  cursor C for call shared_consumer();
  fetch C;
  EXPECT!(C.id = 1100);
  EXPECT!(C.t = 'x_x');
  fetch C;
  EXPECT!(C.id = 4500);
  EXPECT!(C.t = 'y_y');
  fetch C;
  EXPECT!(not C);
END);

@attribute(cql:shared_fragment)
proc select_nothing_user(flag bool!)
begin
  if flag then
    select flag as xyzzy;
  else
    select nothing;
  end if;
end;

TEST!(select_nothing,
BEGIN
  declare X cursor for select * from (call select_nothing_user(true));
  fetch X;
  EXPECT!(X);
  fetch X;
  EXPECT!(NOT X);

  declare Y cursor for select * from (call select_nothing_user(false));
  fetch Y;
  EXPECT!(NOT Y);
END);

@attribute(cql:shared_fragment)
proc get_values()
begin
  select 1 id, 'x' t
  union all
  select 2 id, 'y' t;
end;

create table x(id int, t text);

TEST!(shared_exec,
BEGIN
  drop table if exists x;
  create table x(id int, t text);
  with
    (call get_values())
  insert into x select * from get_values;

  cursor C for select * from x;
  fetch C;
  EXPECT!(C.id = 1);
  EXPECT!(C.t = 'x');
  fetch C;
  EXPECT!(C.id = 2);
  EXPECT!(C.t = 'y');
  fetch C;
  EXPECT!(not C);

  drop table x;
END);

@attribute(cql:shared_fragment)
proc conditional_values_base(x_ int)
begin
  if x_ == 2 then
    select x_ id, 'y' t;
  else
    select x_ id, 'u' t
    union all
    select x_+1 id, 'v' t;
  end if;
end;

@attribute(cql:shared_fragment)
proc conditional_values(x_ int!)
begin
  if x_ == 1 then
    select nullable(x_) id, 'x' t;
  else if x_ == 99 then  -- this branch won't run
    select nullable(99) id, 'x' t;
  else
    with result(*) as (call conditional_values_base(x_))
    select * from result;
  end if;
end;

TEST!(conditional_fragment,
BEGIN
  cursor C for
    with some_cte(*) as (call conditional_values(1))
    select * from some_cte;

  fetch C;

  EXPECT!(C.id = 1);
  EXPECT!(C.t = 'x');
  fetch C;
  EXPECT!(not C);

  declare D cursor for
    with some_cte(*) as (call conditional_values(2))
  select * from some_cte;

  fetch D;
  EXPECT!(D.id = 2);
  EXPECT!(D.t = 'y');
  fetch D;
  EXPECT!(not D);

  declare E cursor for
    with some_cte(*) as (call conditional_values(3))
  select * from some_cte;

  fetch E;
  EXPECT!(E.id = 3);
  EXPECT!(E.t = 'u');
  fetch E;
  EXPECT!(E.id = 4);
  EXPECT!(E.t = 'v');
  fetch E;
  EXPECT!(not E);
END);

TEST!(conditional_fragment_no_with,
BEGIN
  cursor C for select * from (call conditional_values(1));

  fetch C;
  EXPECT!(C.id = 1);
  EXPECT!(C.t = 'x');
  fetch C;
  EXPECT!(not C);

  declare D cursor for select * from (call conditional_values(2));

  fetch D;
  EXPECT!(D.id = 2);
  EXPECT!(D.t = 'y');
  fetch D;
  EXPECT!(not D);

  declare E cursor for select * from (call conditional_values(3));

  fetch E;
  EXPECT!(E.id = 3);
  EXPECT!(E.t = 'u');
  fetch E;
  EXPECT!(E.id = 4);
  EXPECT!(E.t = 'v');
  fetch E;
  EXPECT!(not E);
END);

@attribute(cql:shared_fragment)
proc skip_notnulls(a_ int!, b_ bool!, c_ long!, d_ real!, e_ text!, f_ blob!, g_ object!)
begin
  if a_ == 0 then
    select a_ - 100 result;
  else if a_ == 1 then
    select case when
      a_ == a_ and
      b_ == b_ and
      c_ == c_ and
      d_ == d_ and
      e_ == e_ and
      f_ == f_ and
      ptr(g_) == ptr(g_)
    then a_ + 100
    else a_ + 200
    end result;
  else
    select a_ result;
  end if;
end;

TEST!(skip_notnulls,
BEGIN
  declare _set object!;
  _set := set_create();
  declare _bl blob!;
  _bl := blob_from_string('hi');

  cursor C for
    with some_cte(*) as (call skip_notnulls(123, false, 1L, 2.3, 'x', _bl, _set))
    select * from some_cte;

  fetch C;
  EXPECT!(C.result == 123);
  fetch C;
  EXPECT!(not C);
END);

@attribute(cql:shared_fragment)
proc skip_nullables(
  a_ int,
  b_ bool,
  c_ long,
  d_ real,
  e_ text,
  f_ blob,
  g_ object)
begin
  if a_ == 0 then
    select a_ - 100 result;
  else if a_ == 1 then
    select case when
      a_ == a_ and
      b_ == b_ and
      c_ == c_ and
      d_ == d_ and
      e_ == e_ and
      f_ == f_ and
      ptr(g_) == ptr(g_)
    then a_ + 100
    else a_ + 200
    end result;
  else
    select a_ result;
  end if;
end;

TEST!(skip_nullables,
BEGIN
  declare _set object!;
  _set := set_create();
  declare _bl blob!;
  _bl := blob_from_string('hi');

  cursor C for
    with some_cte(*) as (call skip_nullables(456, false, 1L, 2.3, 'x', _bl, _set))
    select * from some_cte;

  fetch C;
  EXPECT!(C.result == 456);
  fetch C;
  EXPECT!(not C);
END);

@attribute(cql:shared_fragment)
proc abs_func(x int!)
begin
  select case
    when x < 0 then x * -1
    else x
  end x;
end;

@attribute(cql:shared_fragment)
proc max_func(x int!, y int!)
begin
  select case when x <= y then y else x end result;
end;

@attribute(cql:shared_fragment)
proc ten()
begin
  select 10 ten;
end;

@attribute(cql:shared_fragment)
proc numbers(lim int!)
begin
  with N(x) as (
    select 1 x
    union all
    select x+1 x from N
    limit lim)
  select x from N;
end;

TEST!(inline_proc,
BEGIN
  cursor C for
    select
      abs_func(x - ten()) s1,
      abs(x-10) s2,
      max_func(x - ten(), abs_func(x - ten())) m1,
      max(x - 10, abs(x - 10)) m2
    from
      (call numbers(20));

  loop fetch C
  begin
    EXPECT!(C.s1 == C.s2);
    EXPECT!(C.m1 == C.m2);
  end;

END);

proc make_xy()
begin
  create table xy (
    x int,
    y int
  );
end;

[[shared_fragment]]
proc transformer()
begin
  with
     source(*) like xy
     select source.x + 1 x, source.y + 20 y from source;
end;

TEST!(rename_tables_in_dot,
BEGIN
  call make_xy();
  insert into xy values (1,2), (2,3);

  cursor C for
    with T(*) as (call transformer() using xy as source)
    select T.* from T;

  fetch C;
  EXPECT!(C);
  EXPECT!(C.x == 2);
  EXPECT!(C.y == 22);
  fetch C;
  EXPECT!(C);
  EXPECT!(C.x == 3);
  EXPECT!(C.y == 23);
  fetch C;
  EXPECT!(NOT C);
END);

declare proc alltypes_nullable() (
  t bool,
  f bool,
  i int,
  l long,
  r real,
  bl blob,
  str text
);

declare proc alltypes_notnull() (
  `bool 1 notnull` bool!,
  `bool 2 notnull` bool!,
  i_nn int!,
  l_nn long!,
  r_nn real!,
  bl_nn blob!,
  str_nn text!
);

@attribute(cql:blob_storage)
create table storage_notnull(
  like alltypes_notnull
);

@attribute(cql:blob_storage)
create table storage_nullable(
  like alltypes_nullable
);

@attribute(cql:blob_storage)
create table storage_both(
  like alltypes_notnull,
  like alltypes_nullable
);

@attribute(cql:blob_storage)
create table storage_with_extras(
  like alltypes_notnull,
  x int!
);

@attribute(cql:blob_storage)
create table storage_one_int(
  x int!
);

@attribute(cql:blob_storage)
create table storage_one_long(
  x long!
);

TEST_GATED!(blob_serialization, lua_gated(),
BEGIN
  let a_blob := blob_from_string("a blob");
  let b_blob := blob_from_string("b blob");
  declare cursor_both cursor like storage_both;
  fetch cursor_both using
      false f, true t, 22 i, 33L l, 3.14 r, a_blob bl, "text" str,
      false `bool 2 notnull`, true `bool 1 notnull`, 88 i_nn, 66L l_nn, 6.28 r_nn, b_blob bl_nn, "text2" str_nn;

  -- note: using cursor_both and cursor_both ensures codegen is canonicalizing the name
  declare blob_both blob<storage_both>;
  set blob_both from cursor cursor_both;
  declare test_cursor_both cursor like cursor_both;
  fetch test_cursor_both from blob_both;

  EXPECT!(test_cursor_both);
  EXPECT!(test_cursor_both.`bool 1 notnull` == cursor_both.`bool 1 notnull`);
  EXPECT!(test_cursor_both.`bool 2 notnull` == cursor_both.`bool 2 notnull`);
  EXPECT!(test_cursor_both.i_nn == cursor_both.i_nn);
  EXPECT!(test_cursor_both.l_nn == cursor_both.l_nn);
  EXPECT!(test_cursor_both.r_nn == cursor_both.r_nn);
  EXPECT!(test_cursor_both.bl_nn == cursor_both.bl_nn);
  EXPECT!(test_cursor_both.str_nn == cursor_both.str_nn);
  EXPECT!(test_cursor_both.t == cursor_both.t);
  EXPECT!(test_cursor_both.f == cursor_both.f);
  EXPECT!(test_cursor_both.i == cursor_both.i);
  EXPECT!(test_cursor_both.l == cursor_both.l);
  EXPECT!(test_cursor_both.r == cursor_both.r);
  EXPECT!(test_cursor_both.bl == cursor_both.bl);
  EXPECT!(test_cursor_both.str == cursor_both.str);

  declare cursor_notnulls cursor like storage_notnull;
  fetch cursor_notnulls from cursor_both(like cursor_notnulls);
  declare blob_notnulls blob<storage_notnull>;
  set blob_notnulls from cursor cursor_notnulls;
  declare test_cursor_notnulls cursor like cursor_notnulls;
  fetch test_cursor_notnulls from blob_notnulls;

  EXPECT!(test_cursor_notnulls);
  EXPECT!(test_cursor_notnulls.`bool 1 notnull` == cursor_both.`bool 1 notnull`);
  EXPECT!(test_cursor_notnulls.`bool 2 notnull` == cursor_both.`bool 2 notnull`);
  EXPECT!(test_cursor_notnulls.i_nn == cursor_both.i_nn);
  EXPECT!(test_cursor_notnulls.l_nn == cursor_both.l_nn);
  EXPECT!(test_cursor_notnulls.r_nn == cursor_both.r_nn);
  EXPECT!(test_cursor_notnulls.bl_nn == cursor_both.bl_nn);
  EXPECT!(test_cursor_notnulls.str_nn == cursor_both.str_nn);

  -- deserializing should not screw up the reference counts
  set blob_notnulls from cursor cursor_notnulls;
  set blob_notnulls from cursor cursor_notnulls;
  set blob_notnulls from cursor cursor_notnulls;

  -- The next tests verify various things with blobs that are
  -- not directly the right type so we're cheesing the type system.
  -- We need to be able to handle different version sources
  -- as well as assorted corruptions without crashing hence
  -- we pass in blobs of dubious pedigree.

  -- There are missing nullable columns at the end
  -- this is ok and it is our versioning strategy.
  declare any_blob blob;
  let stash_both := blob_both;
  let stash_notnulls := blob_notnulls;
  any_blob := blob_notnulls;
  blob_both := any_blob;
  fetch test_cursor_both from blob_both;

  EXPECT!(test_cursor_both);
  EXPECT!(test_cursor_both.`bool 1 notnull` == cursor_both.`bool 1 notnull`);
  EXPECT!(test_cursor_both.`bool 2 notnull` == cursor_both.`bool 2 notnull`);
  EXPECT!(test_cursor_both.i_nn == cursor_both.i_nn);
  EXPECT!(test_cursor_both.l_nn == cursor_both.l_nn);
  EXPECT!(test_cursor_both.r_nn == cursor_both.r_nn);
  EXPECT!(test_cursor_both.bl_nn == cursor_both.bl_nn);
  EXPECT!(test_cursor_both.str_nn == cursor_both.str_nn);
  EXPECT!(test_cursor_both.t is null);
  EXPECT!(test_cursor_both.f is null);
  EXPECT!(test_cursor_both.i is null);
  EXPECT!(test_cursor_both.l is null);
  EXPECT!(test_cursor_both.r is null);
  EXPECT!(test_cursor_both.bl is null);
  EXPECT!(test_cursor_both.str is null);

  blob_both := null;

  -- null blob, throws exception
  let caught := false;
  try
    fetch test_cursor_both from blob_both;
  catch
    EXPECT!(not test_cursor_both);
    caught := true;
  end;
  EXPECT!(caught);

  -- big blob will have too many fields...
  caught := false;
  any_blob := stash_both;
  blob_notnulls := any_blob;
  fetch test_cursor_notnulls from blob_notnulls;

  -- we still expect to be able to read the fields we know without error
  EXPECT!(test_cursor_notnulls);
  EXPECT!(test_cursor_notnulls.`bool 1 notnull` == cursor_both.`bool 1 notnull`);
  EXPECT!(test_cursor_notnulls.`bool 2 notnull` == cursor_both.`bool 2 notnull`);
  EXPECT!(test_cursor_notnulls.i_nn == cursor_both.i_nn);
  EXPECT!(test_cursor_notnulls.l_nn == cursor_both.l_nn);
  EXPECT!(test_cursor_notnulls.r_nn == cursor_both.r_nn);
  EXPECT!(test_cursor_notnulls.bl_nn == cursor_both.bl_nn);
  EXPECT!(test_cursor_notnulls.str_nn == cursor_both.str_nn);

  -- we're missing fields and they aren't nullable, this will make errors
  declare cursor_with_extras cursor like storage_with_extras;
  caught := false;
  any_blob := stash_notnulls;
  declare blob_with_extras blob<storage_with_extras>;
  blob_with_extras := any_blob;
  try
    fetch cursor_with_extras from blob_with_extras;
  catch
    EXPECT!(not cursor_with_extras);
    caught := true;
  end;
  EXPECT!(caught);

  -- attempting to read from an empty cursor will throw
  EXPECT!(not cursor_with_extras);
  caught := false;
  try
    set blob_with_extras from cursor cursor_with_extras;
  catch
    EXPECT!(not cursor_with_extras);
    caught := true;
  end;
  EXPECT!(caught);

  -- the types are all wrong but they are simply not null values of the same types
  -- we can safely decode that
  declare blob_nullables blob<storage_nullable>;
  any_blob := stash_notnulls;
  blob_nullables := any_blob;
  declare cursor_nullables cursor like storage_nullable;
  fetch cursor_nullables from blob_nullables;

  -- note that we read the not null versions of the fields
  EXPECT!(cursor_nullables);
  EXPECT!(cursor_nullables.t == cursor_both.`bool 1 notnull`);
  EXPECT!(cursor_nullables.f == cursor_both.`bool 2 notnull`);
  EXPECT!(cursor_nullables.i == cursor_both.i_nn);
  EXPECT!(cursor_nullables.l == cursor_both.l_nn);
  EXPECT!(cursor_nullables.r == cursor_both.r_nn);
  EXPECT!(cursor_nullables.bl == cursor_both.bl_nn);
  EXPECT!(cursor_nullables.str == cursor_both.str_nn);

  -- now blob_nullables really does have nullable types
  set blob_nullables from cursor cursor_nullables;
  any_blob := blob_nullables;
  blob_notnulls := any_blob;

  -- we can't read possibly null types into not null types
  caught := false;
  try
    fetch test_cursor_notnulls from blob_notnulls;
  catch
    EXPECT!(not test_cursor_notnulls);
    caught := true;
  end;
  EXPECT!(caught);

  -- set up a totally different stored blob
  declare cursor_other cursor like storage_one_int;
  fetch cursor_other using 5 x;
  declare blob_other blob<storage_one_int>;
  set blob_other from cursor cursor_other;
  declare test_cursor_other cursor like cursor_other;
  fetch test_cursor_other from blob_other;
  EXPECT!(test_cursor_other);
  EXPECT!(test_cursor_other.x = cursor_other.x);

  any_blob := blob_other;
  blob_nullables := any_blob;

  -- the types in this blob do not match the cursor we're going to use it with
  caught := false;
  try
    fetch cursor_nullables from blob_nullables;
  catch
    EXPECT!(not cursor_nullables);
    caught := true;
  end;
  EXPECT!(caught);

END);


TEST_GATED!(blob_serialization_null_cases, lua_gated(),
BEGIN
  declare cursor_nulls cursor like storage_nullable;
  fetch cursor_nulls using
    null f, null t, null i, null l, null r, null bl, null str;

  declare blob_nulls blob<storage_nullable>;
  set blob_nulls from cursor cursor_nulls;
  declare test_cursor cursor like cursor_nulls;
  fetch test_cursor from blob_nulls;

  EXPECT!(test_cursor);
  EXPECT!(test_cursor.t is null);
  EXPECT!(test_cursor.f is null);
  EXPECT!(test_cursor.i is null);
  EXPECT!(test_cursor.l is null);
  EXPECT!(test_cursor.r is null);
  EXPECT!(test_cursor.bl is null);
  EXPECT!(test_cursor.str is null);

END);

TEST_GATED!(corrupt_blob_deserialization, lua_gated(),
BEGIN
  let a_blob := blob_from_string("a blob");
  let b_blob := blob_from_string("b blob");
  declare cursor_both cursor like storage_both;
  fetch cursor_both using
      false f, true t, 22 i, 33L l, 3.14 r, a_blob bl, "text" str,
      false `bool 2 notnull`, true `bool 1 notnull`, 88 i_nn, 66L l_nn, 6.28 r_nn, b_blob bl_nn, "text2" str_nn;

  declare blob_both blob<storage_both>;
  set blob_both from cursor cursor_both;
  if blob_both is null throw;

  -- sanity check the decode of the full blob
  declare test_cursor_both cursor like cursor_both;
  fetch test_cursor_both from blob_both;

  -- sanity check the blob size of the full encoding
  let full_size := get_blob_size(blob_both);
  EXPECT!(full_size > 50);
  EXPECT!(full_size < 100);

  -- try truncated blobs of every size
  let i := 0;
  while i < full_size
  begin
    declare blob_broken  blob<storage_both>;
    blob_broken := create_truncated_blob(blob_both, i);
    -- the types in this blob do not match the cursor we're going to use it with
    let caught := false;
    try
      -- this is gonna fail
      fetch cursor_both from blob_broken;
    catch
      EXPECT!(not cursor_both);
      caught := true;
    end;
    EXPECT!(caught);
    i += 1;
  end;

END);

TEST_GATED!(bogus_varint, lua_gated(),
BEGIN
  let control_blob := (select X'490001');  -- one byte zigzag encoding of -1
  declare test_blob blob<storage_one_int>;
  test_blob := control_blob;
  cursor C like storage_one_int;

  -- correctly encoded control case
  fetch C from test_blob;
  EXPECT!(C);
  EXPECT!(C.x == -1);

  -- this int has 6 bytes, 5 is the most you can need
  let bogus_int := (select X'4900818181818100');

  test_blob := bogus_int;

  let caught := false;
  try
    -- this is gonna fail
    fetch C from test_blob;
  catch
    EXPECT!(not C);
    caught := true;
  end;
  EXPECT!(caught);
END);

TEST_GATED!(bogus_varlong, lua_gated(),
BEGIN
  let control_blob := (select X'4C0001');  -- one byte zigzag encoding of -1
  declare test_blob blob<storage_one_long>;
  test_blob := control_blob;
  cursor C like storage_one_long;

  -- correctly encoded control case
  fetch C from test_blob;
  EXPECT!(C);
  EXPECT!(C.x == -1);

  -- this long has 11 bytes, 10 is the most you can need
  let bogus_long := (select X'4C008181818181818181818100');

  test_blob := bogus_long;

  let caught := false;
  try
    -- this is gonna fail
    fetch C from test_blob;
  catch
    EXPECT!(not C);
    caught := true;
  end;
  EXPECT!(caught);
END);

proc round_trip_int(value int!)
begin
  cursor C LIKE storage_one_int;
  FETCH C using value x;
  EXPECT!(C.x == value);
  declare int_blob blob<storage_one_int>;
  set int_blob from cursor C;
  DECLARE D cursor like C;
  fetch D from int_blob;
  EXPECT!(C.x == D.x);
end;

proc round_trip_long(value long!)
begin
  cursor C LIKE storage_one_long;
  FETCH C using value x;
  EXPECT!(C.x == value);
  declare int_blob blob<storage_one_long>;
  set int_blob from cursor C;
  DECLARE D cursor like C;
  fetch D from int_blob;
  EXPECT!(C.x == D.x);
end;

declare const group long_constants (
  long_const_1 = -9223372036854775807L,
  long_const_2 = -9223372036854775808L,
  long_const_3 = -9223372036854775808
);

@emit_constants long_constants;

TEST!(verify_long_constant_forms,
BEGIN
  let reference := long_const_1  - 1;

  EXPECT_SQL_TOO!(reference = -9223372036854775808L);
  EXPECT_SQL_TOO!(reference = -9223372036854775808);
  EXPECT_SQL_TOO!(reference = const(-9223372036854775808L));
  EXPECT_SQL_TOO!(reference = const(-9223372036854775808));
  EXPECT_SQL_TOO!(reference = long_const_2);
  EXPECT_SQL_TOO!(reference = long_const_3);

  LET x := -9223372036854775808L;
  EXPECT_SQL_TOO!(reference == x);

  x := -9223372036854775808;
  EXPECT_SQL_TOO!(reference == x);

  x := const(-9223372036854775808L);
  EXPECT_SQL_TOO!(reference == x);

  x := const(-9223372036854775808);
  EXPECT_SQL_TOO!(reference == x);

  x := long_const_2;
  EXPECT_SQL_TOO!(reference == x);

  x := long_const_3;
  EXPECT_SQL_TOO!(reference == x);

  DECLARE z real!;
  z := 9223372036854775807;

  -- this verifies that z was stored as a double
  -- hence adding 0.0 will make no difference
  EXPECT_SQL_TOO!(z - 1 == z + 0.0 - 1);

  -- ensure division does not convert to float
  EXPECT!(9223372036854775807 - 9223372036854775807 / 2 * 2 == 1);
  EXPECT!(const(9223372036854775807 - 9223372036854775807 / 2 * 2) == 1);
  EXPECT!(9223372036854775807 >> 1 == 9223372036854775807 / 2);
  EXPECT!(const(9223372036854775807 >> 1 == 9223372036854775807 / 2));

  cursor C for
    select 9223372036854775807 v
    union all
    select 9223372036854775807.0 v;

  -- this verifies that if we mean to fetch a float we get a float
  -- even if the value in the select is a long
  FETCH C;
  EXPECT!(z == C.v);
  FETCH C;
  EXPECT!(z == C.v);

END);

TEST_GATED!(serialization_tricky_values, lua_gated(),
BEGIN
  call round_trip_int(0);
  call round_trip_int(1);
  call round_trip_int(-1);
  call round_trip_int(129);
  call round_trip_int(32769);
  call round_trip_int(-129);
  call round_trip_int(-32769);
  call round_trip_int(0x7fffffff);
  call round_trip_int(-214783648);

  call round_trip_long(0);
  call round_trip_long(1);
  call round_trip_long(-1);
  call round_trip_long(129);
  call round_trip_long(32769);
  call round_trip_long(-129);
  call round_trip_long(-32769);
  call round_trip_long(0x7fffffffL);
  call round_trip_long(-214783648L);
  call round_trip_long(0x7fffffffffffffffL);  -- max int64
  call round_trip_long(0x8000000000000000L);  -- min int64

  -- these are actually testing constant handling rather than
  -- the blob but this is a convenient way to ensure that it was
  -- all on the up and up.  Especially since we already confirmed
  -- above that it works in hex.
  call round_trip_long(-9223372036854775808L); -- min int64 in decimal
  call round_trip_long(-9223372036854775808);  -- min int64 in decimal
  call round_trip_long(9223372036854775807L);  -- max int64 in decimal
  call round_trip_long(9223372036854775807);   -- max int64 in decimal
END);

declare proc rand_reset();
declare proc corrupt_blob_with_invalid_shenanigans(b blob!);

TEST_GATED!(clobber_blobs, lua_gated(),
BEGIN
  -- the point of the test is to ensure that we don't segv or get ASAN failures
  -- or leak memory when dealing with broken blobs.  Some of the blobs
  -- may still be valid since we corrupt them randomly.  But this will
  -- help us to be sure that nothing horrible happens if you corrupt blobs

  -- we're going to make a good blob with various data in it and then clobber it
  let a_blob := blob_from_string("a blob");
  let b_blob := blob_from_string("b blob");
  declare cursor_both cursor like storage_both;
  fetch cursor_both using
      false f, true t, 22 i, 33L l, 3.14 r, a_blob bl, "text" str,
      false `bool 2 notnull`, true `bool 1 notnull`, 88 i_nn, 66L l_nn, 6.28 r_nn, b_blob bl_nn, "text2" str_nn;

  -- storage both means nullable types and not null types
  declare my_blob blob<storage_both>;
  set my_blob from cursor cursor_both;

  -- sanity check the decode of the full blob
  declare test_cursor_both cursor like storage_both;
  fetch test_cursor_both from my_blob;

  call rand_reset();

  let good := 0;
  let bad := 0;

  -- if this test fails you can use this count to set a breakpoint
  -- on the attempt that crashed, check out this value in the debugger
  let attempt := 0;

  let i := 0;
  while i < 100
  begin
    i += 1;

    -- refresh the blob from the cursor, it's good now (again)
    set my_blob from cursor cursor_both;
    if my_blob is null throw;

    -- same buffer will be smashed 10 times
    let j := 0;
    while j < 10
    begin
      j += 1;

      -- invoke da smasher
      call corrupt_blob_with_invalid_shenanigans(my_blob);

      try
        -- almost certainly going to get an error, that's fine, but no segv, no leaks, etc.
        fetch test_cursor_both from my_blob;
        good := good + 1;
      catch
        bad := bad + 1;
      end;

      attempt := attempt + 1;
    end;
  end;

  -- use the no call syntax
  printf("blob corruption results: good: %d, bad: %d\n", good, bad);
  printf("1000 bad results is normal\n");
END);

proc change_arg(x text)
begin
  x := 'hi';
end;

TEST!(arg_mutation,
BEGIN
  call change_arg(null);
END);

declare proc lotsa_types() (
  i int!,
  l long!,
  b bool!,
  r real!,
  i0 int,
  l0 long,
  b0 bool,
  r0 real,
  t text!,
  t0 text
);

declare function cql_cursor_hash(C cursor) long!;

TEST!(cursor_hash,
BEGIN
  cursor C like lotsa_types;
  declare D cursor like C;

  -- empty cursor hashes to nothing
  EXPECT!(0 == cql_cursor_hash(C));

  let i := 0;
  while i < 5
  begin
    -- no explicit values, all dummy
    fetch C() from values () @DUMMY_SEED(i);
    fetch D() from values () @DUMMY_SEED(i);

    let hash0 := cql_cursor_hash(C);
    let hash1 := cql_cursor_hash(C);
    let hash2 := cql_cursor_hash(D);

    EXPECT!(hash0 == hash1);  -- control for sanity
    EXPECT!(hash1 == hash2);  -- equivalent data -> same hash (not strings are dynamic)

    fetch C() from values () @DUMMY_SEED(i) @DUMMY_NULLABLES;
    fetch D() from values () @DUMMY_SEED(i) @DUMMY_NULLABLES;

    hash0 := cql_cursor_hash(C);
    hash1 := cql_cursor_hash(C);
    hash2 := cql_cursor_hash(D);

    EXPECT!(hash0 == hash1);  -- control for sanity
    EXPECT!(hash1 == hash2);  -- equivalent data -> same hash (not strings are dynamic)

    ---------
    fetch D() from values () @DUMMY_SEED(i) @DUMMY_NULLABLES;

    update cursor D using
      not C.b as b;

    hash2 := cql_cursor_hash(D);
    EXPECT!(hash1 != hash2);  -- now different

    ---------
    fetch D() from values () @DUMMY_SEED(i) @DUMMY_NULLABLES;

    update cursor D using
      C.i + 1 as i;

    hash2 := cql_cursor_hash(D);
    EXPECT!(hash1 != hash2);  -- now different

    ---------
    fetch D() from values () @DUMMY_SEED(i) @DUMMY_NULLABLES;

    update cursor D using
      C.l + 1 as l;

    hash2 := cql_cursor_hash(D);
    EXPECT!(hash1 != hash2);  -- now different

    ---------
    fetch D() from values () @DUMMY_SEED(i) @DUMMY_NULLABLES;

    update cursor D using
      C.r + 1 as r;

    hash2 := cql_cursor_hash(D);
    EXPECT!(hash1 != hash2);  -- now different

    ---------
    fetch D() from values () @DUMMY_SEED(i) @DUMMY_NULLABLES;

    update cursor D using
      "different" as t;

    hash2 := cql_cursor_hash(D);
    EXPECT!(hash1 != hash2);  -- now different

    ---------
    fetch D() from values () @DUMMY_SEED(i) @DUMMY_NULLABLES;

    update cursor D using
      not C.b as b0;

    hash2 := cql_cursor_hash(D);
    EXPECT!(hash1 != hash2);  -- now different

    ---------
    fetch D() from values () @DUMMY_SEED(i) @DUMMY_NULLABLES;

    update cursor D using
      C.i + 1 as i0;

    hash2 := cql_cursor_hash(D);
    EXPECT!(hash1 != hash2);  -- now different

    ---------
    fetch D() from values () @DUMMY_SEED(i) @DUMMY_NULLABLES;

    update cursor D using
      C.l + 1 as l0;

    hash2 := cql_cursor_hash(D);
    EXPECT!(hash1 != hash2);  -- now different

    ---------
    fetch D() from values () @DUMMY_SEED(i) @DUMMY_NULLABLES;

    update cursor D using
      C.r + 1 as r0;

    hash2 := cql_cursor_hash(D);
    EXPECT!(hash1 != hash2);  -- now different

    ---------
    fetch D() from values () @DUMMY_SEED(i) @DUMMY_NULLABLES;

    update cursor D using
      "different" as t0;

    hash2 := cql_cursor_hash(D);
    EXPECT!(hash1 != hash2);  -- now different

    ---------
    fetch D() from values () @DUMMY_SEED(i) @DUMMY_NULLABLES;

    update cursor D using
      NULL as b0;

    hash2 := cql_cursor_hash(D);
    EXPECT!(hash1 != hash2);  -- now different

    ---------
    fetch D() from values () @DUMMY_SEED(i) @DUMMY_NULLABLES;

    update cursor D using
      NULL as i0;

    hash2 := cql_cursor_hash(D);
    EXPECT!(hash1 != hash2);  -- now different

    ---------
    fetch D() from values () @DUMMY_SEED(i) @DUMMY_NULLABLES;

    update cursor D using
      NULL as l0;

    hash2 := cql_cursor_hash(D);
    EXPECT!(hash1 != hash2);  -- now different

    ---------
    fetch D() from values () @DUMMY_SEED(i) @DUMMY_NULLABLES;

    update cursor D using
      NULL as r0;

    hash2 := cql_cursor_hash(D);
    EXPECT!(hash1 != hash2);  -- now different

    ---------
    fetch D() from values () @DUMMY_SEED(i) @DUMMY_NULLABLES;

    update cursor D using
      NULL as t0;

    hash2 := cql_cursor_hash(D);
    EXPECT!(hash1 != hash2);  -- now different

    i += 1;
  end;

END);

declare function cql_cursors_equal(C1 cursor, C2 cursor) bool!;

TEST!(cursor_equal,
BEGIN
  cursor C like lotsa_types;
  declare D cursor like C;

  -- empty cursor hashes to nothing
  EXPECT!(cql_cursors_equal(C, D));

  -- one cursor empty
  fetch C() from values () @DUMMY_SEED(0);
  EXPECT!(NOT cql_cursors_equal(C, D));
  EXPECT!(NOT cql_cursors_equal(D, C));

  let i := 0;
  while i < 5
  begin
    -- no explicit values, all dummy
    fetch C() from values () @DUMMY_SEED(i);
    fetch D() from values () @DUMMY_SEED(i);

    EXPECT!(cql_cursors_equal(C, C)); -- control for sanity
    EXPECT!(cql_cursors_equal(C, D)); -- control for sanity

    fetch C() from values () @DUMMY_SEED(i) @DUMMY_NULLABLES;
    fetch D() from values () @DUMMY_SEED(i) @DUMMY_NULLABLES;

    EXPECT!(cql_cursors_equal(C, C)); -- control for sanity
    EXPECT!(cql_cursors_equal(C, D)); -- control for sanity

    ---------
    fetch D() from values () @DUMMY_SEED(i) @DUMMY_NULLABLES;

    update cursor D using
      not C.b as b;

    EXPECT!(NOT cql_cursors_equal(C, D));

    ---------
    fetch D() from values () @DUMMY_SEED(i) @DUMMY_NULLABLES;

    update cursor D using
      C.i + 1 as i;

    EXPECT!(NOT cql_cursors_equal(C, D));

    ---------
    fetch D() from values () @DUMMY_SEED(i) @DUMMY_NULLABLES;

    update cursor D using
      C.l + 1 as l;

    EXPECT!(NOT cql_cursors_equal(C, D));

    ---------
    fetch D() from values () @DUMMY_SEED(i) @DUMMY_NULLABLES;

    update cursor D using
      C.r + 1 as r;

    EXPECT!(NOT cql_cursors_equal(C, D));

    ---------
    fetch D() from values () @DUMMY_SEED(i) @DUMMY_NULLABLES;

    update cursor D using
      "different" as t;

    EXPECT!(NOT cql_cursors_equal(C, D));

    ---------
    fetch D() from values () @DUMMY_SEED(i) @DUMMY_NULLABLES;

    update cursor D using
      not C.b as b0;

    EXPECT!(NOT cql_cursors_equal(C, D));

    ---------
    fetch D() from values () @DUMMY_SEED(i) @DUMMY_NULLABLES;

    update cursor D using
      C.i + 1 as i0;

    EXPECT!(NOT cql_cursors_equal(C, D));

    ---------
    fetch D() from values () @DUMMY_SEED(i) @DUMMY_NULLABLES;

    update cursor D using
      C.l + 1 as l0;

    EXPECT!(NOT cql_cursors_equal(C, D));

    ---------
    fetch D() from values () @DUMMY_SEED(i) @DUMMY_NULLABLES;

    update cursor D using
      C.r + 1 as r0;

    EXPECT!(NOT cql_cursors_equal(C, D));

    ---------
    fetch D() from values () @DUMMY_SEED(i) @DUMMY_NULLABLES;

    update cursor D using
      "different" as t0;

    EXPECT!(NOT cql_cursors_equal(C, D));

    ---------
    fetch D() from values () @DUMMY_SEED(i) @DUMMY_NULLABLES;

    update cursor D using
      NULL as b0;

    EXPECT!(NOT cql_cursors_equal(C, D));

    ---------
    fetch D() from values () @DUMMY_SEED(i) @DUMMY_NULLABLES;

    update cursor D using
      NULL as i0;

    EXPECT!(NOT cql_cursors_equal(C, D));

    ---------
    fetch D() from values () @DUMMY_SEED(i) @DUMMY_NULLABLES;

    update cursor D using
      NULL as l0;

    EXPECT!(NOT cql_cursors_equal(C, D));

    ---------
    fetch D() from values () @DUMMY_SEED(i) @DUMMY_NULLABLES;

    update cursor D using
      NULL as r0;

    EXPECT!(NOT cql_cursors_equal(C, D));

    ---------
    fetch D() from values () @DUMMY_SEED(i) @DUMMY_NULLABLES;

    update cursor D using
      NULL as t0;

    EXPECT!(NOT cql_cursors_equal(C, D));

    i += 1;
  end;

  -- different number of columns
  declare E cursor like select 1 x;
  EXPECT!(NOT cql_cursors_equal(C, E));

  -- different types (same offset)
  declare F cursor like select 1L x;
  EXPECT!(NOT cql_cursors_equal(E, F));

  -- different offsets (this is checked before types)
  declare G cursor like select 1L x, 1L y;
  declare H cursor like select 1 x, 1 y;
  EXPECT!(NOT cql_cursors_equal(G, H));

END);

DECLARE PROC get_rows(result object!) OUT UNION (x INT!, y TEXT!, z BOOL);

TEST!(child_results,
BEGIN
  let p := cql_partition_create();

  declare v cursor like (x int!, y text!, z bool);
  declare k cursor like v(x, y);

  -- empty cursors, not added to partition
  let added := cql_partition_cursor(p, k, v);
  EXPECT!(not added);

  let i := 0;

  while i < 10
  begin
    fetch v() from values() @DUMMY_SEED(i) @DUMMY_NULLABLES;
    fetch k from v(like k);
    added := cql_partition_cursor(p, k, v);
    EXPECT!(added);

    if (i % 3 == 0) THEN
      added := cql_partition_cursor(p, k, v);
      EXPECT!(added);
    end if;

    if (i % 6 == 0) THEN
      added := cql_partition_cursor(p, k, v);
      EXPECT!(added);
    end if;

    i += 1;
  end;

  i := -2;
  while i < 12
  begin
    /* don't join #6 to force cleanup */
    if i != 6 then
      fetch k() from values() @DUMMY_SEED(i) @DUMMY_NULLABLES;
      declare rs1 object<get_rows set>;
      rs1 := cql_extract_partition(p, k);
      let rs2 := cql_extract_partition(p, k);

      -- if we ask for the same key more than once, we should get the exact same result
      -- this is object identity we are checking here (i.e. it's the same pointer!)
      EXPECT!(rs1 == rs2);

      cursor C for rs1;

      let row_count := 0;
      loop fetch C
      begin
        EXPECT!(C.x == i);
        EXPECT!(C.y == printf("y_%d", i));
        EXPECT!(C.z == NOT NOT i);
        row_count := row_count + 1;
      end;

      switch i
        when -2, -1, 10, 11
          then EXPECT!(row_count == 0);
        when 1, 2, 4, 5, 7, 8
          then EXPECT!(row_count == 1);
        when 3, 9
          then EXPECT!(row_count == 2);
        when 0
          then EXPECT!(row_count == 3);
      end;
    end if;

    i += 1;
  end;
END);

proc ch1()
begin
  let i := 0;
  let base := 500;
  cursor C like (k1 int, k2 text, v1 bool, v2 text, v3 real);
  declare K cursor like C(k1,k2);
  while i < 10
  begin
    -- note that 1/3 of parents do not have this child
    if i % 3 != 2 then
      fetch K() from values() @dummy_seed(base+i) @dummy_nullables;
      fetch C(like K) from values(from K) @dummy_seed(base+i*2) @dummy_nullables;
      out union C;
      fetch C(like K) from values(from K) @dummy_seed(base+i*2+1) @dummy_nullables;
      out union C;
    end if;
    i += 1;
  end;
end;

proc ch2()
begin
  let i := 0;
  let base := 1000;
  cursor C like (k3 integer, k4 text, v1 bool, v2 text, v3 real);
  declare K cursor like C(k3, k4);
  while i < 10
  begin
    -- note that 1/3 of parents do not have this child
    if i % 3 != 1 then
      fetch K() from values() @dummy_seed(base+i) @dummy_nullables;
      fetch C(like K) from values(from K) @dummy_seed(base+i*2) @dummy_nullables;
      out union C;
      fetch C(like K) from values(from K) @dummy_seed(base+i*2+1) @dummy_nullables;
      out union C;
    end if;
    i += 1;
  end;
end;

proc ch1_filter(k1 int, k2 text)
begin
  cursor C for call ch1();
  loop fetch C
  begin
    if C.k1 == k1 and C.k2 == k2 then
      out union C;
    end if;
  end;
end;

proc ch2_filter(k3 int, k4 text)
begin
  cursor C for call ch2();
  loop fetch C
  begin
    if C.k3 == k3 and C.k4 == k4 then
      out union C;
    end if;
  end;
end;


proc parent()
begin
  let i := 0;
  cursor C like (k1 int, k2 text, k3 int, k4 text, v1 bool, v2 text, v3 real);
  declare D cursor like C;
  while i < 10
  begin
    fetch C() from values() @dummy_seed(i) @dummy_nullables;

    -- ch1 keys are +500
    fetch D() from values() @dummy_seed(i+500) @dummy_nullables;
    update cursor C using D.k1 k1, D.k2 k2;

    -- ch2 keys are +1000
    fetch D() from values() @dummy_seed(i+1000) @dummy_nullables;
    update cursor C using D.k3 k3, D.k4 k4;

    out union C;
    i += 1;
  end;
end;

proc parent_child()
begin
  OUT UNION CALL parent() JOIN
    call ch1() USING (k1, k2) AS ch1 AND
    call ch2() USING (k3, k4) AS ch2;
end;

proc parent_child_simple_pattern()
begin
  cursor C for call parent();
  loop fetch C
  begin
    declare result cursor like (like parent, ch1 object<ch1_filter set>, ch2 object<ch2_filter set>);
    fetch result from values (from C, ch1_filter(C.k1, C.k2), ch2_filter(C.k3, C.k4));
    out union result;
  end;
end;

proc verify_parent_child_results(results object<parent_child set>)
begin
  declare P cursor for results;
  let i := 0;

  loop fetch P
  begin
    EXPECT!(P.k1 == i+500);
    EXPECT!(P.k2 == printf("k2_%d", i+500));
    EXPECT!(P.k3 == i+1000);
    EXPECT!(P.k4 == printf("k4_%d", i+1000));
    EXPECT!(P.k4 == printf("k4_%d", i+1000));
    EXPECT!(P.v1 == not not i);
    EXPECT!(P.v2 == printf("v2_%d", i));
    EXPECT!(P.v3 == i);

    let count_rows := 0;
    declare C1 cursor for P.ch1;
    loop fetch C1
    begin
      EXPECT!(P.k1 == C1.k1);
      EXPECT!(P.k2 == C1.k2);
      EXPECT!(C1.v1 == not not 500 + i*2 + count_rows);
      EXPECT!(C1.v2 == printf("v2_%d", 500 + i*2 + count_rows));
      EXPECT!(C1.v3 == 500 + i*2 + count_rows);
      count_rows := count_rows + 1;
    end;

    EXPECT!(count_rows == case when i % 3 == 2 then 0 else 2 end);

    count_rows := 0;
    declare C2 cursor for P.ch2;
    loop fetch C2
    begin
      EXPECT!(P.k3 == C2.k3);
      EXPECT!(P.k4 == C2.k4);
      EXPECT!(C2.v1 == not not 1000 + i*2 + count_rows);
      EXPECT!(C2.v2 == printf("v2_%d", 1000 + i*2 + count_rows));
      EXPECT!(C2.v3 == 1000 + i*2 + count_rows);
      count_rows := count_rows + 1;
    end;

    EXPECT!(count_rows = case when i % 3 == 1 then 0 else 2 end);

    i += 1;
  end;
end;

TEST!(parent_child_results,
BEGIN
  let results := parent_child();
  call verify_parent_child_results(results);

  let alt_results := parent_child_simple_pattern();
  declare r object;
  r := alt_results;

  -- shape compatible, cast away ch1/ch2 vs. ch1_filter/ch2_filter
  -- this verifies that the manually created parent/child result is the same
  call verify_parent_child_results(r);

END);

TEST!(string_dictionary,
BEGIN

  let i := 1;
  while i <= 512
  begin
    let dict := cql_string_dictionary_create();

    let j := 0;
    while j < i
    begin
      -- set to bogus original value
      let added := dict:add(printf("%d", j), "0");
      EXPECT!(added);

      let bogus_val := dict:find(printf("%d", j));
      EXPECT!(bogus_val == "0");

      -- replace
      added := dict:add(printf("%d", j), printf("%d", j*100));
      EXPECT!(NOT added);
      j := j + 2;
    end;

    j := 0;
    while j < i
    begin
      let result := dict:find(printf("%d", j));
      EXPECT!(case when j % 2 then result IS NULL else result == printf("%d", j*100) end);
      j += 1;
    end;

    i := i * 2;
  end;

  -- test null lookup, always fails
  EXPECT!(dict:find(NULL) IS NULL);

END);

DECLARE FUNCTION _cql_contains_column_def(haystack TEXT, needle TEXT) BOOL NOT NULL;

-- _cql_contains_column_def is used by the upgrader to find string matches the indicate a column is present
-- it's the same as this expression: haystack GLOB printf('*[) ]%s*', needle)
-- any null arguments yield a false result
TEST!(cql_contains_column_def,
BEGIN

  -- trivial cases all fail, the "needle" has to be reasonable to even have a chance to match
  EXPECT!(NOT _cql_contains_column_def(null, 'x'));
  EXPECT!(NOT _cql_contains_column_def('x', NULL));
  EXPECT!(NOT _cql_contains_column_def('', 'bar'));
  EXPECT!(NOT _cql_contains_column_def('foo', ''));

  EXPECT!(_cql_contains_column_def("create table foo(x integer)", "x integer"));
  EXPECT!(NOT _cql_contains_column_def("create table foo(xx integer)", "x integer"));
  EXPECT!(_cql_contains_column_def("create table foo(id integer, x integer)", "x integer"));
  EXPECT!(NOT _cql_contains_column_def("create table foo(id integer, xx integer)", "x integer"));

  -- it's expecting normalized text so non-canonical matches don't count
  EXPECT!(NOT _cql_contains_column_def("create table foo(id integer, x Integer)", "x integer"));

  -- column name at the start isn't a match, there has to be a space or paren
  EXPECT!(NOT _cql_contains_column_def("x integer", "x integer"));

END);

-- cql utilities for making a basic string list
-- this is not a very functional list but schema helpers might need
-- generic lists of strings so we offer these based on bytebuf


TEST!(cql_string_list,
BEGIN
  let list := cql_string_list_create();
  EXPECT!(0 == cql_string_list_count(list));
  cql_string_list_add(list, "hello");
  cql_string_list_add(list, "goodbye");
  EXPECT!(2 == cql_string_list_count(list));
  EXPECT!("hello" == cql_string_list_get_at(list, 0));
  EXPECT!("goodbye" == cql_string_list_get_at(list, 1));
END);

TEST!(cql_string_list_as_array,
BEGIN
  let list := cql_string_list_create();
  EXPECT!(0 == list.count);
  list:add("hello"):add("goodbye");
  EXPECT!(2 == list.count);
  EXPECT!("hello" == list[0]);
  EXPECT!("goodbye" == list[1]);
  list[0] := "salut";
  EXPECT!("salut" == list[0]);
END);

TEST!(cursor_formatting,
BEGIN
  cursor C like (a_bool bool, an_int int, a_long long, a_real real, a_string text, a_blob blob);
  -- load all nulls
  fetch C() from values ();

  LET s1 := C:format;
  EXPECT!(s1 = "a_bool:null|an_int:null|a_long:null|a_real:null|a_string:null|a_blob:null");

  -- nullable values not null
  fetch C(a_blob, a_real) from values ((select cast('xyzzy' as blob)), 3.5) @dummy_seed(1) @dummy_nullables;
  LET s2 := C:format;
  EXPECT!(s2 = "a_bool:true|an_int:1|a_long:1|a_real:3.5|a_string:a_string_1|a_blob:length 5 blob");

  declare D cursor like (a_bool bool!, an_int int!, a_long long!, a_real real!, a_string text!, a_blob blob!);

  -- not null values
  fetch D(a_blob, a_real) from values ((select cast('xyzzy' as blob)), 3.5) @dummy_seed(1);
  LET s3 := cql_cursor_format(D);
  EXPECT!(s3 = "a_bool:true|an_int:1|a_long:1|a_real:3.5|a_string:a_string_1|a_blob:length 5 blob");
END);

TEST!(compressed_strings,
BEGIN

  let x := "hello hello hello hello";
  let y := cql_compressed("hello hello hello hello");
  EXPECT!(x == y);

  let empty1 := "";
  let empty2 := cql_compressed("");
  EXPECT!(empty1 == empty2);

END);

-- external implementation will test the exact value passed
declare proc take_bool_not_null(x bool!, y bool!);
declare proc take_bool(x bool, y bool);

TEST!(normalize_bool_on_call,
BEGIN
  call take_bool(10, true);
  call take_bool(0, false);

  call take_bool_not_null(10, true);
  call take_bool_not_null(0, false);
END);

TEST!(blob_key_funcs,
BEGIN
  let b := (select bcreatekey(112233, 1234, CQL_BLOB_TYPE_INT32, 5678, CQL_BLOB_TYPE_INT32));
  EXPECT!(112233 == (select bgetkey_type(b)));
  EXPECT!(1234 == (select bgetkey(b,0)));
  EXPECT!(5678 == (select bgetkey(b,1)));

  b := (select bupdatekey(b, 1, 3456));
  EXPECT!(1234 == (select bgetkey(b,0)));
  EXPECT!(3456 == (select bgetkey(b,1)));

  b := (select bupdatekey(b, 0, 2345));
  EXPECT!(2345 == (select bgetkey(b,0)));
  EXPECT!(3456 == (select bgetkey(b,1)));

  -- note that CQL thinks that we are going to be returning a integer value from bgetkey here
  -- ad hoc calls to these functions aren't the normal way they are used
  b := (select bcreatekey(112234, 2, CQL_BLOB_TYPE_BOOL, 5.5, CQL_BLOB_TYPE_FLOAT));
  EXPECT!(112234 == (select bgetkey_type(b)));
  EXPECT!((select bgetkey(b,0) == 1));
  EXPECT!((select bgetkey(b,1) == 5.5));

  b := (select bupdatekey(b, 0, 0));
  EXPECT!((select bgetkey(b,0) == 0));

  b := (select bupdatekey(b, 0, 1, 1, 3.25));
  EXPECT!((select bgetkey(b,0) == 1));
  EXPECT!((select bgetkey(b,1) == 3.25));

  -- note that CQL thinks that we are going to be returning a integer value from bgetkey here
  -- ad hoc calls to these functions aren't the normal way they are used
  b := (select bcreatekey(112235, 0x12345678912L, CQL_BLOB_TYPE_INT64, 0x87654321876L, CQL_BLOB_TYPE_INT64));
  EXPECT!(112235 == (select bgetkey_type(b)));
  EXPECT!((select bgetkey(b,0) == 0x12345678912L));
  EXPECT!((select bgetkey(b,1) == 0x87654321876L));

  b := (select bupdatekey(b, 0, 0xabcdef01234));
  EXPECT!((select bgetkey(b,0) == 0xabcdef01234));

  -- cheese the return type with casts to work around the fixed type of bgetkey
  b := (select bcreatekey(112236,  x'313233', CQL_BLOB_TYPE_BLOB, 'hello', CQL_BLOB_TYPE_STRING));
  EXPECT!(112236 == (select bgetkey_type(b)));
  EXPECT!((select cast(bgetkey(b,0) as blob) == x'313233'));
  EXPECT!((select cast(bgetkey(b,1) as text) == 'hello'));

  b := (select bupdatekey(b, 0, x'4546474849'));
  EXPECT!((select cast(bgetkey(b,0) as blob) == x'4546474849'));

  b := (select bupdatekey(b, 0, x'fe'));
  EXPECT!((select cast(bgetkey(b,0) as blob) == x'fe'));

  b := (select bupdatekey(b, 0, x''));
  EXPECT!((select cast(bgetkey(b,0) as blob) == x''));

  b := (select bupdatekey(b, 1, 'garbonzo'));
  EXPECT!((select cast(bgetkey(b,1) as text) == 'garbonzo'));
  EXPECT!((select cast(bgetkey(b,0) as blob) == x''));

  b := (select bupdatekey(b, 0, x'4546474849', 1, 'h'));
  EXPECT!((select cast(bgetkey(b,0) as blob) == x'4546474849'));
  EXPECT!((select cast(bgetkey(b,1) as text) == 'h'));
END);

TEST!(blob_createkey_func_errors,
BEGIN
  -- not enough args
  EXPECT!((select bcreatekey(112233) IS NULL));

  -- args have the wrong parity (it should be pairs)
  EXPECT!((select bcreatekey(112233, 1) IS NULL));

  -- the first arg should be an int64
  EXPECT!((select bcreatekey('112233', 1, 1) IS NULL));

  -- the arg type should be a small integer
  EXPECT!((select bcreatekey(112233, 1, 'error') IS NULL));

  -- the arg type should be a small integer
  EXPECT!((select bcreatekey(112233, 1000, 99) IS NULL));

  -- the value doesn't match the blob type -- int32
  EXPECT!((select bcreatekey(112233, 'xxx', CQL_BLOB_TYPE_BOOL) IS NULL));

  -- the value doesn't match the blob type -- int32
  EXPECT!((select bcreatekey(112233, 'xxx', CQL_BLOB_TYPE_INT32) IS NULL));

  -- the value doesn't match the blob type -- int64
  EXPECT!((select bcreatekey(112233, 'xxx', CQL_BLOB_TYPE_INT64) IS NULL));

  -- the value doesn't match the blob type -- float
  EXPECT!((select bcreatekey(112233, 'xxx', CQL_BLOB_TYPE_FLOAT) IS NULL));

  -- the value doesn't match the blob type -- string
  EXPECT!((select bcreatekey(112233, 1, CQL_BLOB_TYPE_STRING) IS NULL));

  -- the value doesn't match the blob type -- blob
  EXPECT!((select bcreatekey(112233, 1, CQL_BLOB_TYPE_BLOB) IS NULL));
END);

TEST!(blob_getkey_func_errors,
BEGIN
  -- a test blob
  let b := (select bcreatekey(112235, 0x12345678912L, CQL_BLOB_TYPE_INT64, 0x87654321876L, CQL_BLOB_TYPE_INT64));

  -- second arg is too big  only (0, 1) are valid
  EXPECT!((select bgetkey(b, 2) IS NULL));

  -- second arg is negative
  EXPECT!((select bgetkey(b, -1) IS NULL));

  -- the blob isn't a real encoded blob
  EXPECT!((select bgetkey(x'0000000000000000000000000000', 0) IS NULL));

  -- the blob isn't a real encoded blob
  EXPECT!((select bgetkey_type(x'0000000000000000000000000000') IS NULL));
END);

TEST!(blob_updatekey_func_errors,
BEGIN
  -- a test blob
  let b := (select bcreatekey(112235,
       false, CQL_BLOB_TYPE_BOOL,
       0x12345678912L, CQL_BLOB_TYPE_INT64,
       1.5, CQL_BLOB_TYPE_FLOAT,
       'abc', CQL_BLOB_TYPE_STRING,
       x'4546474849', CQL_BLOB_TYPE_BLOB
       ));

  -- not enough args
  EXPECT!((select bupdatekey(112233) IS NULL));

  -- args have the wrong parity (it should be pairs)
  EXPECT!((select bupdatekey(112233, 1) IS NULL));

  -- the first arg should be a blob
  EXPECT!((select bupdatekey(1234, 1, 1) IS NULL));

  -- the first arg should be a blob in the standard format
  EXPECT!((select bupdatekey(x'0000000000000000000000000000', 1, 1) IS NULL));

  -- the column index should be a small integer
  EXPECT!((select bupdatekey(b, 'error', 1) IS NULL));

  -- the column index must be in range
  EXPECT!((select bupdatekey(b, 5, 1234) IS NULL));

  -- the column index must be in range
  EXPECT!((select bupdatekey(b, -1, 1234) IS NULL));

  -- the value doesn't match the blob type
  EXPECT!((select bupdatekey(b, 0, 'xxx') IS NULL));
  EXPECT!((select bupdatekey(b, 1, 'xxx') IS NULL));
  EXPECT!((select bupdatekey(b, 2, 'xxx') IS NULL));
  EXPECT!((select bupdatekey(b, 3, 5.0) IS NULL));
  EXPECT!((select bupdatekey(b, 4, 5.0) IS NULL));

  -- can't update the same field twice (setting bool to false twice)
  EXPECT!((select bupdatekey(b, 0, 0, 0, 0) IS NULL));
END);

TEST!(blob_val_funcs,
BEGIN
  let k1 := 123412341234;
  let k2 := 123412341235;
  let b := (select bcreateval(112233, k1, 1234, CQL_BLOB_TYPE_INT32, k2, 5678, CQL_BLOB_TYPE_INT32));

  EXPECT!(112233 == (select bgetval_type(b)));
  EXPECT!(1234 == (select bgetval(b, k1)));
  EXPECT!(5678 == (select bgetval(b, k2)));

  b := (select bupdateval(b, k2, 3456, CQL_BLOB_TYPE_INT32));

  EXPECT!(b is not null);
  EXPECT!((select bgetval_type(b)) == 112233);
  EXPECT!((select bgetval(b, k1)) is not null);
  EXPECT!((select bgetval(b, k2)) is not null);

  EXPECT!(1234 == (select bgetval(b, k1)));
  EXPECT!(3456 == (select bgetval(b, k2)));

  b := (select bupdateval(b, k1, 2345, CQL_BLOB_TYPE_INT32));
  EXPECT!(2345 == (select bgetval(b, k1)));
  EXPECT!(3456 == (select bgetval(b, k2)));

  -- note that CQL thinks that we are going to be returning a integer value from bgetkey here
  -- ad hoc calls to these functions aren't the normal way they are used
  b := (select bcreateval(112234, k1, 2, CQL_BLOB_TYPE_BOOL, k2, 5.5, CQL_BLOB_TYPE_FLOAT));
  EXPECT!(112234 == (select bgetval_type(b)));
  EXPECT!((select bgetval(b, k1) == 1));
  EXPECT!((select bgetval(b, k2) == 5.5));

  b := (select bupdateval(b, k1, 0, CQL_BLOB_TYPE_BOOL));
  EXPECT!((select bgetval(b, k1) == 0));

  b := (select bupdateval(b, k1, 1, CQL_BLOB_TYPE_BOOL, k2, 3.25, CQL_BLOB_TYPE_FLOAT));
  EXPECT!((select bgetval(b, k1) == 1));
  EXPECT!((select bgetval(b, k2) == 3.25));

  -- note that CQL thinks that we are going to be returning a integer value from bgetval here
  -- ad hoc calls to these functions aren't the normal way they are used
  b := (select bcreateval(112235, k1, 0x12345678912L, CQL_BLOB_TYPE_INT64, k2, 0x87654321876L, CQL_BLOB_TYPE_INT64));
  EXPECT!(112235 == (select bgetval_type(b)));
  EXPECT!((select bgetval(b, k1) == 0x12345678912L));
  EXPECT!((select bgetval(b, k2) == 0x87654321876L));

  b := (select bupdateval(b, k1, 0xabcdef01234, CQL_BLOB_TYPE_INT64));
  EXPECT!((select bgetval(b, k1) == 0xabcdef01234));

  -- cheese the return type with casts to work around the fixed type of bgetval
  b := (select bcreateval(112236,  k1, x'313233', CQL_BLOB_TYPE_BLOB, k2, 'hello', CQL_BLOB_TYPE_STRING));
  EXPECT!(112236 == (select bgetval_type(b)));
  EXPECT!((select cast(bgetval(b, k1) as blob) == x'313233'));
  EXPECT!((select cast(bgetval(b, k2) as text) == 'hello'));

  b := (select bupdateval(b, k1, x'4546474849', CQL_BLOB_TYPE_BLOB));
  EXPECT!((select cast(bgetval(b, k1) as blob) == x'4546474849'));

  b := (select bupdateval(b, k1, x'fe', CQL_BLOB_TYPE_BLOB));
  EXPECT!((select cast(bgetval(b, k1) as blob) == x'fe'));

  b := (select bupdateval(b, k1, x'', CQL_BLOB_TYPE_BLOB));
  EXPECT!((select cast(bgetval(b, k1) as blob) == x''));

  b := (select bupdateval(b, k2, 'garbonzo', CQL_BLOB_TYPE_STRING));
  EXPECT!((select cast(bgetval(b, k2) as text) == 'garbonzo'));
  EXPECT!((select cast(bgetval(b, k1) as blob) == x''));

  b := (select bupdateval(b, k1, x'4546474849', CQL_BLOB_TYPE_BLOB, k2, 'h', CQL_BLOB_TYPE_STRING));
  EXPECT!((select cast(bgetval(b, k1) as blob) == x'4546474849'));
  EXPECT!((select cast(bgetval(b, k2) as text) == 'h'));

  b := (select bcreateval(112234, k1, NULL, CQL_BLOB_TYPE_BOOL, k2, 5.5, CQL_BLOB_TYPE_FLOAT));
  EXPECT!(112234 == (select bgetval_type(b)));
  EXPECT!((select bgetval(b, k1) IS NULL));  /* missing column */
  EXPECT!((select bgetval(b, k2) == 5.5));
END);

TEST!(blob_createval_func_errors,
BEGIN
  let k1 := 123412341234;

  -- not enough argsss
  EXPECT!((select bcreateval() IS NULL));

  -- args have the wrong parity (it should be triples)
  EXPECT!((select bcreateval(112233, 1) IS NULL));

  -- the first arg should be an int64
  EXPECT!((select bcreateval('112233', 1, 1, 1) IS NULL));

  -- the field id should be an integer
  EXPECT!((select bcreateval(112233, 'error', 1, CQL_BLOB_TYPE_BOOL) IS NULL));

  -- the arg type should be a small integer
  EXPECT!((select bcreateval(112233, k1, 1, 'error') IS NULL));

  -- the field id type should be a small integer
  EXPECT!((select bcreateval(112233, 'k1', 1, CQL_BLOB_TYPE_BOOL) IS NULL));

  -- the arg type should be a small integer
  EXPECT!((select bcreateval(112233, k1, 1000, 99) IS NULL));

  -- the value doesn't match the blob type -- int32
  EXPECT!((select bcreateval(112233, k1, 'xxx', CQL_BLOB_TYPE_BOOL) IS NULL));

  -- the value doesn't match the blob type -- int32
  EXPECT!((select bcreateval(112233, k1, 'xxx', CQL_BLOB_TYPE_INT32) IS NULL));

  -- the value doesn't match the blob type -- int64
  EXPECT!((select bcreateval(112233, k1, 'xxx', CQL_BLOB_TYPE_INT64) IS NULL));

  -- the value doesn't match the blob type -- float
  EXPECT!((select bcreateval(112233, k1, 'xxx', CQL_BLOB_TYPE_FLOAT) IS NULL));

  -- the value doesn't match the blob type -- string
  EXPECT!((select bcreateval(112233, k1, 1, CQL_BLOB_TYPE_STRING) IS NULL));

  -- the value doesn't match the blob type -- blob
  EXPECT!((select bcreateval(112233, k1, 1, CQL_BLOB_TYPE_BLOB) IS NULL));
END);

TEST!(blob_getval_func_errors,
BEGIN
  let k1 := 123412341234;
  let k2 := 123412341235;
  let b := (select bcreateval(112233, k1, 1234, CQL_BLOB_TYPE_INT32, k2, 5678, CQL_BLOB_TYPE_INT32));

  -- second arg is is not a valid key
  EXPECT!((select bgetval(b, 1111) IS NULL));
END);

TEST!(blob_updateval_null_cases,
BEGIN
  let k1 := 123412341234;
  let k2 := 123412341235;
  let k3 := 123412341236;
  let k4 := 123412341237;
  let k5 := 123412341238;
  let k6 := 123412341239;

  -- a test blob
  let b := (select bcreateval(
       112235,
       k1, false, CQL_BLOB_TYPE_BOOL,
       k2, 0x12345678912L, CQL_BLOB_TYPE_INT64,
       k3, 1.5, CQL_BLOB_TYPE_FLOAT,
       k4, 'abc', CQL_BLOB_TYPE_STRING,
       k5, x'4546474849', CQL_BLOB_TYPE_BLOB
       ));

  EXPECT!((select bgetval_type(b) == 112235));
  EXPECT!((select cast(bgetval(b, k1) as bool) == false));
  EXPECT!((select bgetval(b, k2) == 0x12345678912L));
  EXPECT!((select cast(bgetval(b, k3) as real) == 1.5));
  EXPECT!((select cast(bgetval(b, k4) as text) == 'abc'));
  EXPECT!((select cast(bgetval(b, k5) as blob) == x'4546474849'));
  EXPECT!((select bgetval(b, k6) IS NULL));

  -- adding a new field id adds a field...
  b := (select bupdateval(b, k6, 1.1, CQL_BLOB_TYPE_FLOAT));
  EXPECT!((select bgetval_type(b) == 112235));
  EXPECT!((select cast(bgetval(b, k6) as real) == 1.1));
  EXPECT!((select cast(bgetval(b, k1) as bool) == false));
  EXPECT!((select bgetval(b, k2) == 0x12345678912L));
  EXPECT!((select cast(bgetval(b, k3) as real) == 1.5));
  EXPECT!((select cast(bgetval(b, k4) as text) == 'abc'));
  EXPECT!((select cast(bgetval(b, k5) as blob) == x'4546474849'));

  -- remove the field k6
  b := (select bupdateval(b, k6, NULL, CQL_BLOB_TYPE_FLOAT));

  EXPECT!((select bgetval_type(b) == 112235));
  EXPECT!((select bgetval(b, k6) IS NULL));
  EXPECT!((select cast(bgetval(b, k1) as bool) == false));
  EXPECT!((select bgetval(b, k2) == 0x12345678912L));
  EXPECT!((select cast(bgetval(b, k3) as real) == 1.5));
  EXPECT!((select cast(bgetval(b, k4) as text) == 'abc'));
  EXPECT!((select cast(bgetval(b, k5) as blob) == x'4546474849'));

  -- remove the field k6 again (removing a not present field)
  b := (select bupdateval(b, k6, NULL, CQL_BLOB_TYPE_FLOAT));
  EXPECT!((select bgetval_type(b) == 112235));
  EXPECT!((select bgetval(b, k6) IS NULL));
  EXPECT!((select cast(bgetval(b, k1) as bool) == false));
  EXPECT!((select bgetval(b, k2) == 0x12345678912L));
  EXPECT!((select cast(bgetval(b, k3) as real) == 1.5));
  EXPECT!((select cast(bgetval(b, k4) as text) == 'abc'));
  EXPECT!((select cast(bgetval(b, k5) as blob) == x'4546474849'));

  -- remove several fields
  b := (select bupdateval(
       b,
       k1, NULL, CQL_BLOB_TYPE_BOOL,
       k2, 0x12345678912L, CQL_BLOB_TYPE_INT64,
       k3, NULL, CQL_BLOB_TYPE_FLOAT,
       k4, 'abc', CQL_BLOB_TYPE_STRING,
       k5, NULL, CQL_BLOB_TYPE_BLOB
       ));

  EXPECT!((select bgetval_type(b) == 112235));
  EXPECT!((select bgetval(b, k1) IS NULL));
  EXPECT!((select bgetval(b, k3) IS NULL));
  EXPECT!((select bgetval(b, k5) IS NULL));
  EXPECT!((select bgetval(b, k6) IS NULL));
  EXPECT!((select bgetval(b, k2) == 0x12345678912L));
  EXPECT!((select cast(bgetval(b, k4) as text) == 'abc'));

  -- remove all remaining fields
  b := (select bupdateval(
       b,
       k1, NULL, CQL_BLOB_TYPE_BOOL,
       k2, NULL, CQL_BLOB_TYPE_INT64,
       k4, NULL, CQL_BLOB_TYPE_STRING
       ));

  EXPECT!((select bgetval_type(b) == 112235));
  EXPECT!((select bgetval(b, k1) IS NULL));
  EXPECT!((select bgetval(b, k2) IS NULL));
  EXPECT!((select bgetval(b, k3) IS NULL));
  EXPECT!((select bgetval(b, k4) IS NULL));
  EXPECT!((select bgetval(b, k5) IS NULL));
  EXPECT!((select bgetval(b, k6) IS NULL));

  -- put some fields back
  b := (select bupdateval(
       b,
       k2, 0x12345678912L, CQL_BLOB_TYPE_INT64,
       k4, 'abc', CQL_BLOB_TYPE_STRING
       ));

  EXPECT!((select bgetval_type(b) == 112235));
  EXPECT!((select bgetval(b, k1) IS NULL));
  EXPECT!((select bgetval(b, k3) IS NULL));
  EXPECT!((select bgetval(b, k5) IS NULL));
  EXPECT!((select bgetval(b, k6) IS NULL));
  EXPECT!((select bgetval(b, k2) == 0x12345678912L));
  EXPECT!((select cast(bgetval(b, k4) as text) == 'abc'));

  -- the blob isn't a real encoded blob
  EXPECT!((select bgetval(x'0000000000000000000000000000', k1) IS NULL));

  -- the blob isn't a real encoded blob
  EXPECT!((select bgetval_type(x'0000000000000000000000000000') IS NULL));
END);

TEST!(blob_updateval_func_errors,
BEGIN
  -- a test blob
  let k1 := 123412341234;
  let k2 := 123412341235;
  let k3 := 123412341236;
  let k4 := 123412341237;
  let k5 := 123412341238;
  let k6 := 123412341239;

  let b := (select bcreateval(112235,
       k1, false, CQL_BLOB_TYPE_BOOL,
       k2, 0x12345678912L, CQL_BLOB_TYPE_INT64,
       k3, 1.5, CQL_BLOB_TYPE_FLOAT,
       k4, 'abc', CQL_BLOB_TYPE_STRING,
       k5, x'4546474849', CQL_BLOB_TYPE_BLOB
       ));

  -- not enough args
  EXPECT!((select bupdateval(112233) IS NULL));

  -- args have the wrong parity (it should be pairs)
  EXPECT!((select bupdateval(112233, 1) IS NULL));

  -- the first arg should be a blob
  EXPECT!((select bupdateval(1234, k1, 1, CQL_BLOB_TYPE_BOOL) IS NULL));

  -- the column index should be a small integer
  EXPECT!((select bupdateval(b, 'error', 1, CQL_BLOB_TYPE_BOOL) IS NULL));

  -- duplicate field id is an error
  EXPECT!((select bupdateval(b, k1, 1, CQL_BLOB_TYPE_BOOL, k1, 1, CQL_BLOB_TYPE_BOOL) IS NULL));

    -- the value doesn't match the blob type
  EXPECT!((select bupdateval(b, k1, 'xxx', CQL_BLOB_TYPE_BOOL) IS NULL));
  EXPECT!((select bupdateval(b, k2, 'xxx', CQL_BLOB_TYPE_INT64) IS NULL));
  EXPECT!((select bupdateval(b, k3, 'xxx', CQL_BLOB_TYPE_FLOAT) IS NULL));
  EXPECT!((select bupdateval(b, k4, 5.0, CQL_BLOB_TYPE_STRING) IS NULL));
  EXPECT!((select bupdateval(b, k5, 5.0, CQL_BLOB_TYPE_BLOB) IS NULL));

  -- adding a new column but the types are not compatible
  EXPECT!((select bupdateval(b, k1, 1, CQL_BLOB_TYPE_BOOL, k6, 'xxx', CQL_BLOB_TYPE_BOOL) IS NULL));

  -- the first arg should be a blob in the standard format
  EXPECT!((select bupdateval(x'0000000000000000000000000000', k1, 0, CQL_BLOB_TYPE_BOOL) IS NULL));
END);

TEST!(backed_tables,
BEGIN
  -- seed some data
  insert into backed values (1, 100, 101), (2, 200, 201);

  -- validate count and the math of the columns
  let r := 0;
  cursor C for select * from backed;
  loop fetch C
  begin
    EXPECT!(C.`value one` = 100*C.id);
    EXPECT!(C.`value two` = 100*C.id+1);
    r := r + 1;
  end;
  EXPECT!(r == 2);

  -- update some keys and values
  update backed set id=3, `value one`=300, `value two`=301 where id = 2;
  update backed set id=4, `value one`=400, `value two`=401 where `value one` = 100;

  -- reverify it still makes sense
  r := 0;
  declare D cursor for select * from backed;
  loop fetch D
  begin
    EXPECT!(D.`value one` = 100*D.id);
    EXPECT!(D.`value two` = 100*D.id+1);
    r := r + 1;
  end;
  EXPECT!(r == 2);

  -- delete one row
  delete from backed where `value two` = 401;

  -- validate again, use aggregate functions and nested select alternatives
  EXPECT!(1 == (select count(*) from backed));
  EXPECT!(300 == (select `value one` from backed where id = 3));

  -- update using the values already in the table
  update backed set id = id + 1, `value one` = `value one` + 100, `value two` = backed.`value two` + 100;

  EXPECT!(400 == (select `value one` from backed where id = 4));

  -- another swizzle using values to update keys and keys to update values
  update backed set id = (`value one` + 100)/100, `value one` = (id+1)*100, `value two` = `value two` + 100;

  EXPECT!(500 == (select `value one` from backed where id = 5));

  -- insert a row with only key and no value
  insert into backed2(id) values(1);
  EXPECT!(1 == (select id from backed2));
END);

@attribute(cql:backed_by=backing)
create table backed_table_with_defaults(
  pk1 int default 1000,
  pk2 int default 2000,
  x int default 3000,
  y int default 4000,
  z text default "foo",
  constraint pk primary key (pk1, pk2)
);

TEST!(backed_tables_default_values,
BEGIN
  insert into backed_table_with_defaults(pk1, x) values (1, 100), (2, 200);

  cursor C for select * from backed_table_with_defaults;

  -- verify default values inserted
  fetch C;
  EXPECT!(C);
  EXPECT!(C.pk1 = 1);
  EXPECT!(C.pk2 = 2000);
  EXPECT!(C.x = 100);
  EXPECT!(C.y = 4000);

  -- and second row
  fetch C;
  EXPECT!(C);
  EXPECT!(C.pk1 = 2);
  EXPECT!(C.pk2 = 2000);
  EXPECT!(C.x = 200);
  EXPECT!(C.y = 4000);

  -- and no third row
  fetch C;
  EXPECT!(NOT C);
END);


-- the backing table was defined above already
[[backed_by=backing]]
create table mixed_backed(
  id int! primary key,
  name text,
  code long int,
  flag bool,
  rate real,
  bl blob
);

proc load_mixed_backed()
begin
  delete from mixed_backed;
  insert into mixed_backed values (1, "a name", 12, 1, 5.0, cast("blob1" as blob));
  insert into mixed_backed values (2, "another name", 14, 3, 7.0, cast("blob2" as blob));
end;

-- test readback of two rows
TEST!(read_mixed_backed,
BEGIN
  call load_mixed_backed();

  cursor C for select * from mixed_backed;
  fetch C;
  EXPECT!(C);
  EXPECT!(C.id == 1);
  EXPECT!(C.name == "a name");
  EXPECT!(C.code == 12);
  EXPECT!(C.flag == 1);
  EXPECT!(C.rate == 5);
  EXPECT!(string_from_blob(C.bl) == "blob1");

  fetch C;
  EXPECT!(C);
  EXPECT!(C.id == 2);
  EXPECT!(C.name == "another name");
  EXPECT!(C.code == 14);
  EXPECT!(C.flag == 1);
  EXPECT!(C.rate == 7);
  EXPECT!(string_from_blob(C.bl) == "blob2");

  fetch C;
  EXPECT!(not C);
END);

-- now attempt a mutation
TEST!(mutate_mixed_backed,
BEGIN
  declare new_code long;
  declare code_ long;
  new_code := 88;
  declare id_ int;
  id_ := 2;  -- either works

  call load_mixed_backed();

  update mixed_backed set code = new_code where id = id_;
  declare updated_cursor cursor for select code from mixed_backed where id = id_;
  fetch updated_cursor into code_;
  close updated_cursor;
  EXPECT!(code_ == new_code);
END);

[[backed_by=backing]]
create table compound_backed(
  id1 text,
  id2 text,
  val real,
  primary key (id1, id2)
);

 -- We're going to make sure that the key blob stays in canonical form
 -- no matter how we update it.  This is a bit tricky for variable fields
 -- which have to stay in a fixed order so this test exercises that.
TEST!(mutate_compound_backed_key,
BEGIN
  insert into compound_backed values('foo', 'bar', 1);
  insert into compound_backed values('goo', 'bar', 2);
  insert into compound_backed values('foo', 'stew', 3);

  -- this should conflict (the net key blob must be the same as the one for val == 1)
  let caught := false;
  try
    update compound_backed set id1 = 'foo' where val = 2;
  catch
    caught := true;
  end;

  EXPECT!(caught);

  -- this should conflict (the net key blob must be the same as the one for val == 1)
  caught := false;
  try
    update compound_backed set id2 = 'bar' where val = 3;
  catch
    caught := true;
  end;

  EXPECT!(caught);

  -- these are safe
  update compound_backed set id1 = 'zoo' where val = 1;
  update compound_backed set id1 = 'foo' where val = 2;

  -- this should conflict (the net key blob must be the same as the one for val == 2)
  caught := false;
  try
    update compound_backed set id1 = 'foo' where val = 1;
  catch
    caught := true;
  end;

  cursor C for select * from compound_backed order by val;

  fetch C;
  EXPECT!(C);
  EXPECT!(C.id1 == 'zoo');
  EXPECT!(C.id2 == 'bar');
  EXPECT!(C.val == 1);

  fetch C;
  EXPECT!(C);
  EXPECT!(C.id1 == 'foo');
  EXPECT!(C.id2 == 'bar');
  EXPECT!(C.val == 2);

  fetch C;
  EXPECT!(C);
  EXPECT!(C.id1 == 'foo');
  EXPECT!(C.id2 == 'stew');
  EXPECT!(C.val == 3);

  fetch C;
  EXPECT!(NOT C);
END);

-- This a bogus proc but it makes an interesting test
-- it can be called directly or using proc as func
-- and we need both for this test.

var a_global int!;
proc mutator(new_val int!, out result int!)
begin
  result := new_val + 1;
  a_global := result;
end;

TEST!(expr_stmt_rewrite,
BEGIN
  a_global := 0;
  -- not a call
  case when 1 then mutator(1) end;
  EXPECT!(a_global == 2);
  case when 1 then mutator(100) end;
  EXPECT!(a_global == 101);
  var result int!;
  mutator(2, result);
  EXPECT!(a_global == 3);
  EXPECT!(result == 3);
  -- chained call, the last one is the proc form so it needs all the args
  -- we can actually do better on this by adding special logic to allow
  -- proc_as_func at the top level if the arg count is ok for that
  -- not yet implemented though
  20:mutator():mutator(result);
  EXPECT!(result == 22);
  EXPECT!(a_global == 22);
END);

@MACRO(stmt_list) box_test!(x! expr, t! expr, tval! expr)
begin
  -- make nullable variable and hold the given value to test
  var @ID(val_, t!) @ID(t!);
  @ID(val_, t!) := x!;

  -- now box and unbox
  let @ID(box_, t!) := @ID(val_, t!):box;
  let @ID(unboxed_, t!) := @ID(box_, t!):@ID('to_', t!);
  EXPECT!(@ID(unboxed_, t!) == @ID(val_, t!));
  EXPECT!(@ID(box_, t!):cql_box_get_type = tval!);

  -- test null value
  @ID(val_, t!) := NULL;

  -- now box and unbox
  set @ID(box_, t!) := @ID(val_, t!):box;
  set @ID(unboxed_, t!) := @ID(box_, t!):@ID('to_', t!);
  EXPECT!(@ID(unboxed_, t!) IS NULL);
end;

TEST!(boxing,
BEGIN
  let bl := (select 'a blob' ~blob~);

  box_test!(5, 'int', CQL_DATA_TYPE_INT32);
  box_test!(7.5, 'real', CQL_DATA_TYPE_DOUBLE);
  box_test!(true, 'bool', CQL_DATA_TYPE_BOOL);
  box_test!(1000L, 'long', CQL_DATA_TYPE_INT64);
  box_test!('abcde', 'text', CQL_DATA_TYPE_STRING);
  box_test!(bl, 'blob', CQL_DATA_TYPE_BLOB);
  box_test!(box_int, 'object', CQL_DATA_TYPE_OBJECT);

  -- now we store the wrong kind of stuff in the boxed object
  -- all the unboxing operations should fail.

  box_bool := 5:box;
  box_int := 5.0:box;
  box_long := 5:box;
  box_real := 5:box;
  box_text := 5:box;
  box_blob := 5:box;
  box_object := 5:box;

  -- they all have the wrong thing in them
  EXPECT!(box_int:cql_unbox_int IS NULL);
  EXPECT!(box_bool:cql_unbox_bool IS NULL);
  EXPECT!(box_real:cql_unbox_real IS NULL);
  EXPECT!(box_long:cql_unbox_long IS NULL);
  EXPECT!(box_text:cql_unbox_text IS NULL);
  EXPECT!(box_blob:cql_unbox_blob IS NULL);
  EXPECT!(box_object:cql_unbox_object IS NULL);

END);

TEST!(object_dictionary,
BEGIN
  let d := cql_object_dictionary_create();
  d:add("foo", 101:box);
  let v := d:find("foo")~object<cql_box>~:ifnull_throw:to_int;
  EXPECT!(v == 101);
END);

TEST!(cursor_accessors_notnull,
BEGIN
  cursor C for select true a, 1 b, 2L c, 3.0 d, "foo" e, "bar" ~blob~ f;
  fetch C;
  EXPECT!(6 == C:count);
  EXPECT!(CQL_DATA_TYPE_BOOL | CQL_DATA_TYPE_NOT_NULL == C:type(0));
  EXPECT!(CQL_DATA_TYPE_INT32 | CQL_DATA_TYPE_NOT_NULL == C:type(1));
  EXPECT!(CQL_DATA_TYPE_INT64 | CQL_DATA_TYPE_NOT_NULL == C:type(2));
  EXPECT!(CQL_DATA_TYPE_DOUBLE | CQL_DATA_TYPE_NOT_NULL == C:type(3));
  EXPECT!(CQL_DATA_TYPE_STRING | CQL_DATA_TYPE_NOT_NULL == C:type(4));
  EXPECT!(CQL_DATA_TYPE_BLOB | CQL_DATA_TYPE_NOT_NULL == C:type(5));

  EXPECT!(-1 == C:type(-1));
  EXPECT!(-1 == C:type(C:count));
  EXPECT!(true == C:to_bool(0));
  EXPECT!(1 == C:to_int(1));
  EXPECT!(2L == C:to_long(2));
  EXPECT!(3.0 == C:to_real(3));
  EXPECT!("foo" == C:to_text(4));
  EXPECT!(C:to_blob(5) IS NOT NULL);
END);

TEST!(cursor_accessors_nullable,
BEGIN
  cursor C for select true:nullable a, 1:nullable b,
         2L:nullable c, 3.0:nullable d, "foo":nullable e, "bar" ~blob~:nullable f;
  fetch C;

  EXPECT!(6 == C:count);
  EXPECT!(CQL_DATA_TYPE_BOOL == C:type(0));
  EXPECT!(CQL_DATA_TYPE_INT32 == C:type(1));
  EXPECT!(CQL_DATA_TYPE_INT64 == C:type(2));
  EXPECT!(CQL_DATA_TYPE_DOUBLE == C:type(3));
  EXPECT!(CQL_DATA_TYPE_STRING == C:type(4));
  EXPECT!(CQL_DATA_TYPE_BLOB == C:type(5));

  EXPECT!(true == C:to_bool(0));
  EXPECT!(1 == C:to_int(1));
  EXPECT!(2L == C:to_long(2));
  EXPECT!(3.0 == C:to_real(3));
  EXPECT!("foo" == C:to_text(4));
  EXPECT!(C:to_blob(5) IS NOT NULL);
END);


TEST!(cursor_accessors_object,
BEGIN
  let v := 1:box;
  cursor C like (obj object<cql_box>);
  fetch C from values(v);
  EXPECT!(C:to_object(0) IS NOT NULL);
  EXPECT!(C:to_object(-1) IS NULL);
  EXPECT!(C:to_object(1) IS NULL);
END);

TEST!(null_casting,
BEGIN
  let f1 := null ~bool~;
  let i1 := null ~int~;
  let l1 := null ~long~;
  let r1 := null ~real~;
  let t1 := null ~text~;
  let b1 := null ~blob~;
  let o1 := null ~object~;

  EXPECT!(f1 is null);
  EXPECT!(i1 is null);
  EXPECT!(l1 is null);
  EXPECT!(r1 is null);
  EXPECT!(t1 is null);
  EXPECT!(b1 is null);
  EXPECT!(o1 is null);

  -- make everything not null again
  f1 := true;
  i1 := 1;
  l1 := 1;
  r1 := 1;
  t1 := "dummy";
  b1 := randomblob(1);
  o1 := b1:box;

  EXPECT!(f1 :nullable is not null);
  EXPECT!(i1 :nullable is not null);
  EXPECT!(l1 :nullable is not null);
  EXPECT!(r1 :nullable is not null);
  EXPECT!(t1 :nullable is not null);
  EXPECT!(b1 :nullable is not null);
  EXPECT!(o1 :nullable is not null);

  set f1 := null ~bool~;
  set i1 := null ~int~;
  set l1 := null ~long~;
  set r1 := null ~real~;
  set t1 := null ~text~;
  set b1 := null ~blob~;
  set o1 := null ~object~;

  EXPECT!(f1 is null);
  EXPECT!(i1 is null);
  EXPECT!(l1 is null);
  EXPECT!(r1 is null);
  EXPECT!(t1 is null);
  EXPECT!(b1 is null);
  EXPECT!(o1 is null);
END);

END_SUITE();

-- manually force tracing on by redefining the macros
@echo c, '
#undef cql_error_trace
#define cql_error_trace() run_test_trace_callback(_PROC_, __FILE__, __LINE__)

// we will call this to verify that tracing worked
void run_test_trace_callback(const char *proc, const char *file, int32_t line);
';

-- this table will never actually be created, only declared
-- hence it is a good source of db errors
create table does_not_exist(id int);

proc fails_because_bogus_table()
begin
  try
    declare D cursor for select * from does_not_exist;
  catch
    -- Without tracing this failure code can be seen, the cursor D
    -- will be finalized as part of cleanup and THAT success will be
    -- the sqlite3_errmsg() result.  Tracing lets you see the error as it happens.
    drop table if exists does_not_exist;
    -- now we save the code
    throw;
  end;
end;

-- Called in the test client to verify that we hit tripwires when passing NULL
-- inappropriately for various argument types and at various argument indices.
proc proc_with_notnull_args(
  a text!, b text!, out c text!, out d text!, inout e text!, inout f text!,
  inout g text!, inout h text!, i text!, out j text!, inout k text!, inout l text!,
)
begin
  c := "text";
  d := "text";
  j := "text";
end;

@echo c, '
#undef cql_error_trace
#define cql_error_trace()
';

@emit_enums;

-- parent child test case
proc TestParentChildInit()
begin
  create table test_tasks(
   taskID int!,
   roomID int!
  );

  create table test_rooms (
    roomID int!,
    name text
  );

  insert into test_rooms values (1, "foo"), (2, "bar");
  insert into test_tasks values (100,1), (101,1), (200,2);
end;

[[private]]
proc TestParent()
begin
  SELECT roomID, name FROM test_rooms ORDER BY name;
end;

proc TestChild()
begin
  SELECT roomID, test_tasks.taskID as thisIsATask FROM test_tasks;
end;

proc TestParentChild()
begin
  out union call TestParent() join call TestChild() using (roomID) as test_tasks;
end;
