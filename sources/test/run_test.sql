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
function get_outstanding_refs() int!;
declare start_refs int!;
declare end_refs int!;
declare proc printf no check;
declare proc exit no check;

@MACRO(stmt_list) EXPECT!(pred! expr)
begin
  error_check(pred!, @text(pred!), @MACRO_LINE);
end;

-- storage for the expectation check
var expected bool @sensitive;

@MACRO(stmt_list) EXPECT_EQ!(a! expr, b! expr)
begin
  -- it's important to evaluate the expressions exactly once
  -- because there may be side-effects
  let @tmp(a) := a!;
  let @tmp(b) := b!;
  expected := @tmp(a) IS @tmp(b);
  error_check(expected, @text(a!, " == ", b!), @MACRO_LINE);
  if not expected then
    printf("left: %s\n", @tmp(a):fmt);
    printf("right: %s\n", @tmp(b):fmt);
  end if;
end;

@MACRO(stmt_list) EXPECT_NE!(a! expr, b! expr)
begin
  -- it's important to evaluate the expressions exactly once
  -- because there may be side-effects
  let @tmp(a) := a!;
  let @tmp(b) := b!;
  expected := @tmp(a) IS NOT @tmp(b);
  error_check(expected, @text(a!, " != ", b!), @MACRO_LINE);
  if not expected then
    printf("left: %s\n", @tmp(a):fmt);
    printf("right: %s\n", @tmp(b):fmt);
  end if;
end;

-- use this for both normal eval and SQLite eval this is where we expect CQL to
-- give us the same result as SQLite we do this by evaluating the predicate
-- normally and also wrapped in a (select x).  This is a valuable control.
@MACRO(stmt_list) EXPECT_SQL_TOO!(pred! expr)
begin
  -- this tests the pipeline syntax for statement list macros
  -- there's no reason to write it this way other than
  -- because it's an interesting test. This could obviously
  -- be EXPECT!(pred!) etc.
  pred!:EXPECT!;

  -- verify that SQLite gives the same answer
  (select pred!):EXPECT!;
end;

@MACRO(stmt_list) TEST!(name! expr, body! stmt_list)
begin
  proc @id("test_", name!)()
  begin
    try
      tests := tests + 1;
      declare starting_fails int!;
      starting_fails := fails;
      body!;
    catch
      printf("%s had an unexpected CQL exception (usually a db error)\n", @text(name!));
      fails := fails + 1;
      throw;
    end;
    if starting_fails != fails then
      printf("%s failed.\n", @text(name!));
    else
      tests_passed := tests_passed + 1;
    end if;
  end;

  -- this loose goes into the global proc and invokes the test
  start_refs := get_outstanding_refs();
  @id("test_", name!)();
  end_refs := get_outstanding_refs();
  if start_refs != end_refs then
    printf("Test %s unbalanced refs.", @text(name!));
    printf("  Starting refs %d, ending refs %d.\n", start_refs, end_refs);
    fails := fails + 1;
  end if;
end;

-- this isn't used anymore but it still makes a good compile-time test
@ifdef __rt__lua
  -- This test case is suppressed in Lua, this is done
  -- because the Lua runtime is missing some blob features
  @macro(stmt_list) TEST_C_ONLY!(name! expr, body! stmt_list)
  begin
    printf("Skipping test %s in Lua\n", @text(name!));
  end;

@else

  @macro(stmt_list) TEST_C_ONLY!(name! expr, body! stmt_list)
  begin
    TEST!(name!, body!);
  end;

@endif

-- this isn't used anymore but it still makes a good compile-time test
@ifdef modern_test
  -- This test case is suppressed in Lua, this is done
  -- because the Lua runtime is missing some blob features
  @macro(stmt_list) TEST_MODERN_ONLY!(name! expr, body! stmt_list)
  begin
    TEST!(name!, body!);
  end;

@else

  @macro(stmt_list) TEST_MODERN_ONLY!(name! expr, body! stmt_list)
  begin
    if 0 then end;
  end;

@endif

@MACRO(stmt_list) BEGIN_SUITE!()
begin
  -- we need these constants in the tests
  -- these let us use constants without
  -- actually using constants

  let zero := 0;
  let one := 1;
  let two := 2;
end;

@MACRO(stmt_list) END_SUITE!()
begin
  end_suite();
end;

proc error_check(passed bool @sensitive, message text, line int!)
begin
  expectations += 1;
  if passed is not true then
    printf("test: %s: FAIL on line %d\n", message, line);
    fails += 1;
  end if;
end;

proc end_suite()
begin
  printf("%d tests executed. %d passed, %d failed.  %d expectations failed of %d.\n",
    tests, tests_passed, tests - tests_passed, fails, expectations);
  exit(fails);
end;

-- Use these macros to enable this verbose error tracking in this file

@macro(stmt_list) ENABLE_CQL_ERROR_TRACE_FOR_C!()
begin
  @echo c, '
#undef cql_error_trace
#define cql_error_trace() fprintf(stderr, "Error at %s:%d in %s: %d %s\n", __FILE__, __LINE__, _PROC_, _rc_, sqlite3_errmsg(_db_))
';
end;

@macro(stmt_list) DISABLE_CQL_ERROR_TRACE_FOR_C!()
begin
  @echo c, '
#undef cql_error_trace
#define cql_error_trace()
';
end;

const group blob_types (
  CQL_BLOB_TYPE_BOOL   = 0,
  CQL_BLOB_TYPE_INT32  = 1,
  CQL_BLOB_TYPE_INT64  = 2,
  CQL_BLOB_TYPE_FLOAT  = 3,
  CQL_BLOB_TYPE_STRING = 4,
  CQL_BLOB_TYPE_BLOB   = 5
);

-- These are normally auto-generated so they don't need
-- a declaration, however, here we are going to call them
-- directly for test purposes so we make some kind of approximate
-- declaration.  We'll make it perfect by adding explicit casts.
-- Note that these are configurable so the compiler can't literally
-- pre-declare them for you.  You tell it what you are going to do.

declare select function bgetkey_type(b blob) long;
declare select function bgetval_type(b blob) long;
declare select function bgetkey(b blob, iarg int) long;
declare select function bgetval(b blob, iarg long) long;
declare select function bcreateval no check blob;
declare select function bcreatekey no check blob;
declare select function bupdateval no check blob;
declare select function bupdatekey no check blob;

-- some test helpers we will need
function create_truncated_blob(b blob!, truncated_size int!) create blob!;
function blob_from_string(str text @sensitive) create blob!;
function string_from_blob(b blob @sensitive) create text!;
declare procedure _cql_init_extensions() using transaction;

-- we will use these constants in various tests
enum floats real (
  one = 1.0,
  two = 2.0
);

enum longs long (
  one = 1,
  big = 0x100000000,
  neg = -1
);

-- creates the backing table for the backed table tests
-- this is a generic table with blob key and value as is normal
proc make_schema()
begin
  [[backing_table]]
  create table backing(
    `the key` blob primary key,
    `the value` blob!
  );
end;

-- having declared the above we can make as many backed tables as we like
[[backed_by=backing]]
create table backed (
  id int primary key,
  `value one` int!,
  `value two` int!
);

[[backed_by=backing]]
create table backed2 (
  id int primary key,
  `value one` int
);

-- begin the run with the schema we need and the initialize the extensions
-- _cql_init_extensions is a test helper defined in either the C or the Lua
-- test helpers code.  As it sounds the main job is to declare Sqlite extensions
-- that we can then call.
call make_schema();
call _cql_init_extensions();

BEGIN_SUITE!();

TEST!(vers,
begin
  printf("SQLite Version: %s\n", (select sqlite_version()));
end);

TEST!(arithmetic,
begin
  EXPECT_SQL_TOO!((1 + 2) * 3 == 9);
  EXPECT_SQL_TOO!(1 + 2 * 3 == 7);
  EXPECT_SQL_TOO!(6 / 3 == 2);
  EXPECT_SQL_TOO!(7 - 5 == 2);
  EXPECT_SQL_TOO!(6 % 5 == 1);
  EXPECT_SQL_TOO!(5 / 2.5 == 2);
  EXPECT_SQL_TOO!(-(1 + 3) == -4);
  EXPECT_SQL_TOO!(-1 + 3 == 2);
  EXPECT_SQL_TOO!(1 + -3 == -2);
  EXPECT_SQL_TOO!(longs.neg == -1);
  EXPECT_SQL_TOO!(-longs.neg == 1);
  EXPECT_SQL_TOO!(- -longs.neg == -1);
  EXPECT_SQL_TOO!(-3 / 2 == -1);
  EXPECT_SQL_TOO!(3 / -2 == -1);
  EXPECT_SQL_TOO!(-3 / -2 == 1);
  EXPECT_SQL_TOO!(-3 % 2 == -1);
  EXPECT_SQL_TOO!(3 % -2 == 1);
  EXPECT_SQL_TOO!(-3 % -2 == -1);
end);

-- we will examine these to make sure the side effect functions are getting call
-- the correct number of times
declare side_effect_0_count int!;
declare side_effect_1_count int!;
declare side_effect_null_count int!;

-- for sure returns 0 and counts the number of times it was called
proc side_effect_0(out result int)
begin
  result := 0;
  side_effect_0_count += 1;
end;

-- for sure returns 1 and counts the number of times it was called
proc side_effect_1(out result int)
begin
  result := 1;
  side_effect_1_count += 1;
end;

-- for sure returns null and counts the number of times it was called
proc side_effect_null(out result int)
begin
  result := null;
  side_effect_null_count += 1;
end;

proc reset_counts()
begin
  side_effect_0_count := 0;
  side_effect_1_count := 0;
  side_effect_null_count := 0;
end;

TEST!(logical_operations,
begin
  -- first the truth table, note that we verify that we get the same answer
  -- from the code gen as we would from asking SQLite.
  EXPECT_SQL_TOO!((null and 0) = 0);
  EXPECT_SQL_TOO!((null and 0) = 0);
  EXPECT_SQL_TOO!((0 and null) = 0);
  EXPECT_SQL_TOO!((1 and null) is null);
  EXPECT_SQL_TOO!((null and 1) is null);
  EXPECT_SQL_TOO!((null or 1) = 1);
  EXPECT_SQL_TOO!((1 or null) = 1);
  EXPECT_SQL_TOO!((0 or null) is null);
  EXPECT_SQL_TOO!((null or 0) is null);
  EXPECT_SQL_TOO!((0 or 1) and (1 or 0));
  EXPECT_SQL_TOO!(not 1 + 2 = 0);
  EXPECT_SQL_TOO!((not 1) + 2 = 2);
  EXPECT_SQL_TOO!(null + null is null);
  EXPECT_SQL_TOO!((null between null and null) is null);

  -- the purpose of all this business is to ensure that the expressions that are
  -- evaluated are the ones that are supposed to be evaluated.  We do this by
  -- putting functions with side-effects into the and/or expressions and then
  -- verifying that they were called the right number of times.  We have to do
  -- this for null and true/false with both "and" and "or".  Given the number of
  -- times this code was broken in the project, these tests are considered
  -- indispensable.

  EXPECT_EQ!(side_effect_0() and side_effect_0(), 0);
  EXPECT_EQ!(side_effect_0_count, 1);
  reset_counts();

  EXPECT_EQ!(side_effect_0() and side_effect_1(), 0);
  EXPECT_EQ!(side_effect_0_count, 1);
  EXPECT_EQ!(side_effect_1_count, 0);
  reset_counts();

  EXPECT_EQ!(side_effect_0() and side_effect_null(), 0);
  EXPECT_EQ!(side_effect_0_count, 1);
  EXPECT_EQ!(side_effect_null_count, 0);
  reset_counts();

  EXPECT_EQ!(side_effect_1() and side_effect_0(), 0);
  EXPECT_EQ!(side_effect_0_count, 1);
  EXPECT_EQ!(side_effect_1_count, 1);
  reset_counts();

  EXPECT_EQ!(side_effect_1() and side_effect_1(), 1);
  EXPECT_EQ!(side_effect_1_count, 2);
  reset_counts();

  EXPECT_EQ!((side_effect_1() and side_effect_null()), null);
  EXPECT_EQ!(side_effect_1_count, 1);
  EXPECT_EQ!(side_effect_null_count, 1);
  reset_counts();

  EXPECT_EQ!((side_effect_null() and side_effect_0()), 0);
  EXPECT_EQ!(side_effect_null_count, 1);
  EXPECT_EQ!(side_effect_0_count, 1);
  reset_counts();

  EXPECT_EQ!((side_effect_null() and side_effect_1()), null);
  EXPECT_EQ!(side_effect_null_count, 1);
  EXPECT_EQ!(side_effect_1_count, 1);
  reset_counts();

  EXPECT_EQ!((side_effect_null() and side_effect_null()), null);
  EXPECT_EQ!(side_effect_null_count, 2);
  reset_counts();

  EXPECT_EQ!((side_effect_0() or side_effect_0()), 0);
  EXPECT_EQ!(side_effect_0_count, 2);
  EXPECT_EQ!(side_effect_1_count, 0);
  reset_counts();

  EXPECT_EQ!((side_effect_0() or side_effect_1()), 1);
  EXPECT_EQ!(side_effect_0_count, 1);
  EXPECT_EQ!(side_effect_1_count, 1);
  reset_counts();

  EXPECT_EQ!((side_effect_0() or side_effect_null()), null);
  EXPECT_EQ!(side_effect_0_count, 1);
  EXPECT_EQ!(side_effect_null_count, 1);
  reset_counts();

  EXPECT_EQ!((side_effect_1() or side_effect_0()), 1);
  EXPECT_EQ!(side_effect_0_count, 0);
  EXPECT_EQ!(side_effect_1_count, 1);
  reset_counts();

  EXPECT_EQ!((side_effect_1() or side_effect_1()), 1);
  EXPECT_EQ!(side_effect_1_count, 1);
  reset_counts();

  EXPECT_EQ!((side_effect_1() or side_effect_null()), 1);
  EXPECT_EQ!(side_effect_null_count, 0);
  EXPECT_EQ!(side_effect_1_count, 1);
  reset_counts();

  EXPECT_EQ!((side_effect_null() or side_effect_0()), null);
  EXPECT_EQ!(side_effect_0_count, 1);
  EXPECT_EQ!(side_effect_null_count, 1);
  reset_counts();

  EXPECT_EQ!((side_effect_null() or side_effect_1()), 1);
  EXPECT_EQ!(side_effect_null_count, 1);
  EXPECT_EQ!(side_effect_1_count, 1);
  reset_counts();

  EXPECT_EQ!((side_effect_null() or side_effect_null()), null);
  EXPECT_EQ!(side_effect_null_count, 2);
  reset_counts();

  -- even though this looks like all non nulls we do not eval side_effect_1 we
  -- can't use the simple && form of code-gen because there is statement output
  -- required to evaluate the coalesce.

  EXPECT_EQ!((0 and coalesce(side_effect_1(), 1)), 0);
  EXPECT_EQ!(side_effect_1_count, 0);
  reset_counts();

  -- no short circuit this time

  EXPECT_EQ!((1 and coalesce(side_effect_1(), 1)), 1);
  EXPECT_EQ!(side_effect_1_count, 1);
  reset_counts();

  -- short circuit "or"

  EXPECT_EQ!((1 or coalesce(side_effect_1(), 1)), 1);
  EXPECT_EQ!(side_effect_1_count, 0);
  reset_counts();

  -- no short circuit "or"

  EXPECT_EQ!((0 or coalesce(side_effect_1(), 1)), 1);
  EXPECT_EQ!(side_effect_1_count, 1);
  reset_counts();

  -- This is the same as not (0 < 0) rather than (not 0) < 0
  -- do not move not around in the code gen or you will break stuff
  -- I have broken this many times now. Do not change this expectation
  -- it will save your life...
  EXPECT_SQL_TOO!(not 0 < 0);
end);

-- logical and short-circuit verify 1/0 not evaluated
TEST!(local_operations_early_out,
begin
  EXPECT_SQL_TOO!(not (0 and 1/zero));
  EXPECT_SQL_TOO!(1 or 1 / zero);
end);

-- assorted between combinations
TEST!(between_operations,
begin
  EXPECT_SQL_TOO!(1 between 0 and 2);
  EXPECT_SQL_TOO!(not 3 between 0 and 2);
  EXPECT_SQL_TOO!(not 3 between 0 and 2);
  EXPECT_SQL_TOO!(null between 0 and 2 is null);
  EXPECT_SQL_TOO!(1 between null and 2 is null);
  EXPECT_SQL_TOO!(1 between 0 and null is null);

  EXPECT_EQ!((-1 between side_effect_0() and side_effect_1()), 0);
  EXPECT_EQ!(side_effect_0_count, 1);
  EXPECT_EQ!(side_effect_1_count, 0);
  reset_counts();

  EXPECT_EQ!((0 between side_effect_0() and side_effect_1()), 1);
  EXPECT_EQ!(side_effect_0_count, 1);
  EXPECT_EQ!(side_effect_1_count, 1);
  reset_counts();

  EXPECT_EQ!((2 between side_effect_0() and side_effect_1()), 0);
  EXPECT_EQ!(side_effect_0_count, 1);
  EXPECT_EQ!(side_effect_1_count, 1);
  reset_counts();

  EXPECT_EQ!((-1 not between side_effect_0() and side_effect_1()), 1);
  EXPECT_EQ!(side_effect_0_count, 1);
  EXPECT_EQ!(side_effect_1_count, 0);
  reset_counts();

  EXPECT_EQ!((0 not between side_effect_0() and side_effect_1()), 0);
  EXPECT_EQ!(side_effect_0_count, 1);
  EXPECT_EQ!(side_effect_1_count, 1);
  reset_counts();

  EXPECT_EQ!((2 not between side_effect_0() and side_effect_1()), 1);
  EXPECT_EQ!(side_effect_0_count, 1);
  EXPECT_EQ!(side_effect_1_count, 1);
  reset_counts();
end);

-- assorted not between combinations
TEST!(not_between_operations,
begin
  EXPECT_SQL_TOO!(3 not between 0 and 2);
  EXPECT_SQL_TOO!(not 1 not between 0 and 2);
  EXPECT_SQL_TOO!(not 1 not between 0 and 2);
  EXPECT_SQL_TOO!((not 1) not between 0 and 2 = 0);
  EXPECT_SQL_TOO!(1 not between 2 and 0);
  EXPECT_SQL_TOO!(0 = (not 7 not between 5 and 6));
  EXPECT_SQL_TOO!(1 = (not 7) not between 5 and 6);
  EXPECT_SQL_TOO!(null not between 0 and 2 is null);
  EXPECT_SQL_TOO!(1 not between null and 2 is null);
  EXPECT_SQL_TOO!(1 not between 0 and null is null);
end);

-- assorted comparisons
TEST!(numeric_comparisons,
begin
  EXPECT_SQL_TOO!(0 = zero);
  EXPECT_SQL_TOO!(1 = one);
  EXPECT_SQL_TOO!(2 = two);
  EXPECT_SQL_TOO!(not two = zero);
  EXPECT_SQL_TOO!(two <> zero);
  EXPECT_SQL_TOO!(not zero <> 0);
  EXPECT_SQL_TOO!(not zero == two);
  EXPECT_SQL_TOO!((not two) == 0);
  EXPECT_SQL_TOO!((not two) <> 1);
  EXPECT_SQL_TOO!(one > zero);
  EXPECT_SQL_TOO!(zero < one);
  EXPECT_SQL_TOO!(one >= zero);
  EXPECT_SQL_TOO!(zero <= one);
  EXPECT_SQL_TOO!(one >= 1);
  EXPECT_SQL_TOO!(one <= 1);
end);

TEST!(simple_functions,
begin
  EXPECT_SQL_TOO!(abs(-2) = 2);
  EXPECT_SQL_TOO!(abs(2) = 2);
  EXPECT_SQL_TOO!(abs(-2.0) = 2);
  EXPECT_SQL_TOO!(abs(2.0) = 2);

  let t := 3L;
  EXPECT_SQL_TOO!(abs(t) = t);
  EXPECT_SQL_TOO!(abs(-t) = t);

  t := -4;
  EXPECT_SQL_TOO!(abs(t) = -t);
  EXPECT_SQL_TOO!(abs(-t) = -t);

  EXPECT_EQ!(sign(5), 1);
  EXPECT_EQ!(sign(0.1), 1);
  EXPECT_EQ!(sign(7L), 1);
  EXPECT_EQ!(sign(-5), -1);
  EXPECT_EQ!(sign(-0.1), -1);
  EXPECT_EQ!(sign(-7L), -1);
  EXPECT_EQ!(sign(0), 0);
  EXPECT_EQ!(sign(0.0), 0);
  EXPECT_EQ!(sign(0L), 0);
end);

-- verify that out parameter is set in proc call
proc echo ( in arg1 int!, out arg2 int!)
begin
  arg2 := arg1;
end;

TEST!(out_arguments,
begin
  declare scratch int!;
  echo(12, scratch);
  EXPECT_SQL_TOO!(scratch == 12);
end);

-- test simple recursive function
proc fib (in arg int!, out result int!)
begin
  if arg <= 2 then
    result := 1;
  else
    declare t int!;
    call fib(arg - 1,  result);
    call fib(arg - 2,  t);
    result := t + result;
  end if;
end;

TEST!(simple_recursion,
begin
  EXPECT_EQ!(fib(1), 1);
  EXPECT_EQ!(fib(2), 1);
  EXPECT_EQ!(fib(3), 2);
  EXPECT_EQ!(fib(4), 3);
  EXPECT_EQ!(fib(5), 5);
  EXPECT_EQ!(fib(6), 8);
end);

-- test elementary cursor on select with no tables, still round trips through sqlite
TEST!(cursor_basics,
begin
  declare col1 int;
  declare col2 real!;
  declare basic_cursor cursor for select 1, 2.5;
  fetch basic_cursor into col1, col2;
  EXPECT!(basic_cursor);
  EXPECT_EQ!(col1, 1);
  EXPECT_EQ!(col2, 2.5);
  fetch basic_cursor into col1, col2;
  EXPECT!(not basic_cursor);
end);

-- the most expensive way to swap two variables ever :)
TEST!(exchange_with_cursor,
begin
  let arg1 := 7;
  let arg2 := 11;
  declare exchange_cursor cursor for select arg2, arg1;
  fetch exchange_cursor into arg1, arg2;
  EXPECT!(exchange_cursor);
  EXPECT_EQ!(arg1, 11);
  EXPECT_EQ!(arg2, 7);
end);

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
  insert into mixed values (1, "a name", 12, 1, 5.0, null);
  insert into mixed values (1, "a name", 12, 1, 5.0, null);
  insert into mixed values (2, "another name", 14, 3, 7.0, cast("blob2" as blob));
  insert into mixed values (2, "another name", 14, 3, 7.0, cast("blob2" as blob));
  insert into mixed values (1, "a name", 12, 1, 5.0, cast("blob1" as blob));
  insert into mixed values (1, null, 12, 1, 5.0, null);
end;

proc load_mixed_dupe_identities()
begin
  delete from mixed;
  insert into mixed values (1, "a name", 12, 1, 5.0, null);
  insert into mixed values (1, "another name", 12, 1, 5.0, null);
  insert into mixed values (1, "another name", 12, 0, 5.0, null);
  insert into mixed values (1, "another name", 12, 0, 5.0, cast("blob1" as blob));
  insert into mixed values (1, "another name", 14, 0, 7.0, cast("blob1" as blob));
end;

proc load_mixed_with_nulls()
begin
  load_mixed();
  insert into mixed values (3, null, null, null, null, null);
  insert into mixed values (4, "last name", 16, 0, 9.0, cast("blob3" as blob));
end;

proc update_mixed(id_ int!, name_ text, code_ long int, bl_ blob)
begin
  update mixed set code = code_, bl = bl_ where id = id_;
end;

-- test read back of two rows
TEST!(read_mixed,
begin
  declare id_ int!;
  declare name_ text;
  declare code_ long int;
  declare flag_ bool;
  declare rate_ real;
  declare bl_ blob;

  load_mixed();

  declare read_cursor cursor for select * from mixed;

  fetch read_cursor into id_, name_, code_, flag_, rate_, bl_;
  EXPECT!(read_cursor);
  EXPECT_EQ!(id_, 1);
  EXPECT_EQ!(name_, "a name");
  EXPECT_EQ!(code_, 12);
  EXPECT_EQ!(flag_, 1);
  EXPECT_EQ!(rate_, 5);
  EXPECT_EQ!(string_from_blob(bl_), "blob1");

  fetch read_cursor into id_, name_, code_, flag_, rate_, bl_;
  EXPECT!(read_cursor);
  EXPECT_EQ!(id_, 2);
  EXPECT_EQ!(name_, "another name");
  EXPECT_EQ!(code_, 14);
  EXPECT_EQ!(flag_, 1);
  EXPECT_EQ!(rate_, 7);
  EXPECT_EQ!(string_from_blob(bl_), "blob2");

  fetch read_cursor into id_, name_, code_, flag_, rate_, bl_;
  EXPECT!(not read_cursor);
  close read_cursor;
end);

-- now attempt a mutation
TEST!(mutate_mixed,
begin
  declare new_code long;
  declare code_ long;
  new_code := 88;
  declare id_ int;
  id_ := 2;  -- either works

  load_mixed();

  update mixed set code = new_code where id = id_;
  declare updated_cursor cursor for select code from mixed where id = id_;
  fetch updated_cursor into code_;
  close updated_cursor;
  EXPECT_EQ!(code_, new_code);
end);

TEST!(nested_select_expressions,
begin
  -- use nested expression select
  let temp_1 := (select zero * 5 + one * 11);
  EXPECT_EQ!(temp_1, 11);

  load_mixed();

  temp_1 := (select id from mixed where id > 1 order by id limit 1);
  EXPECT_EQ!(temp_1, 2);

  temp_1 := (select count(*) from mixed);
  EXPECT_EQ!(temp_1, 2);

  let temp_2 := (select avg(id) from mixed);
  EXPECT_EQ!(temp_2, 1.5);

  EXPECT_EQ!((select longs.neg), -1);
  EXPECT_EQ!((select -longs.neg), 1);
  EXPECT_EQ!((select - -longs.neg), -1);
end);

proc make_bools()
begin
  select true x
  union all
  select false x;
end;

TEST!(bool_round_trip,
begin
  declare b bool;

  -- coerce from integer
  b := (select 0);
  EXPECT!(not b);

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
  EXPECT!(not C2.x);
  fetch C2;
  EXPECT!(not C2);
end);

-- complex delete pattern

proc delete_one_from_mixed(out _id int!)
begin
  _id := (select id from mixed order by id limit 1);
  delete from mixed where id = _id;
end;

TEST!(delete_several,
begin
  load_mixed();
  EXPECT_EQ!(2, (select count(*) from mixed));

  declare id_ int!;
  delete_one_from_mixed(id_);
  EXPECT_EQ!(1, id_);
  EXPECT_EQ!(0, (select count(*) from mixed where id = id_));
  EXPECT_EQ!(1, (select count(*) from mixed where id != id_));

  delete_one_from_mixed(id_);
  EXPECT_EQ!(2, id_);
  EXPECT_EQ!(0, (select count(*) from mixed));
end);

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
begin
  declare a_string text!;
  string_copy("Hello", a_string);
  declare result bool!;
  string_equal(a_string, "Hello", result);
  EXPECT!(result);
end);

-- try out some string comparisons
TEST!(string_comparisons,
begin
  let t1 := "a";
  let t2 := "b";
  let t3 := "a";

  EXPECT_SQL_TOO!("a" == "a");
  EXPECT_SQL_TOO!("a" is "a");
  EXPECT_SQL_TOO!("a" != "b");
  EXPECT_SQL_TOO!("a" is not "b");
  EXPECT_SQL_TOO!(t1 < t2);
  EXPECT_SQL_TOO!(t2 > t1);
  EXPECT_SQL_TOO!(t1 <= t2);
  EXPECT_SQL_TOO!(t2 >= t1);
  EXPECT_SQL_TOO!(t1 <= t3);
  EXPECT_SQL_TOO!(t3 >= t1);
  EXPECT_SQL_TOO!(t1 == t3);
  EXPECT_SQL_TOO!(t1 != t2);
end);

-- string comparison nullability checks
TEST!(string_comparisons_nullability,
begin
  declare null_ text;
  let x := "x";
  EXPECT_SQL_TOO!((nullable(x) < nullable(x)) is not null);
  EXPECT_SQL_TOO!((nullable(x) > nullable("x")) is not null);
  EXPECT_SQL_TOO!((null_ > x) is null);
  EXPECT_SQL_TOO!((x > null_) is null);
  EXPECT_SQL_TOO!((null_ > null_) is null);
  EXPECT_SQL_TOO!((null_ == null_) is null);
end);

-- string is null and is not null tests
TEST!(string_is_null_or_not,
begin
  declare null_ text;
  let x := "x";
  let y := nullable("y");

  EXPECT_SQL_TOO!(null_ is null);
  EXPECT_SQL_TOO!(nullable(x) is not null);
  EXPECT_SQL_TOO!(y is not null);
  EXPECT_SQL_TOO!(not (null_ is not null));
  EXPECT_SQL_TOO!(not (nullable(x) is null));
  EXPECT_SQL_TOO!(not (y is null));
end);

-- binding tests for not null types
TEST!(bind_not_nullables,
begin
  let b := true;
  let i := 2;
  let l := 3L;
  let r := 4.5;
  let t := "foo";

  EXPECT_EQ!(b, (select b)); -- binding not null bool
  EXPECT_EQ!(i, (select i)); -- binding not null int
  EXPECT_EQ!(l, (select l)); -- binding not null long
  EXPECT_EQ!(r, (select r)); -- binding not null real
  EXPECT_EQ!(t, (select t)); -- binding not null text

  EXPECT_NE!(b, (select not b)); -- binding not null bool
  EXPECT_NE!(i, (select 1 + i)); -- binding not null int
  EXPECT_NE!(l, (select 1 + l)); -- binding not null long
  EXPECT_NE!(r, (select 1 + r)); -- binding not null real
end);

-- binding tests for nullable types
TEST!(bind_nullables_not_null,
begin
  let b := true:nullable;
  let i := 2:nullable;
  let l := 3L:nullable;
  let r := 4.5:nullable;
  let t := "foo":nullable;

  EXPECT_EQ!(b, (select b)); -- binding nullable not null bool
  EXPECT_EQ!(i, (select i)); -- binding nullable not null int
  EXPECT_EQ!(l, (select l)); -- binding nullable not null long
  EXPECT_EQ!(r, (select r)); -- binding nullable not null real
  EXPECT_EQ!(t, (select t)); -- binding nullable not null text

  EXPECT_NE!(b, (select not b)); -- binding nullable not null bool
  EXPECT_NE!(i, (select 1 + i)); -- binding nullable not null int
  EXPECT_NE!(l, (select 1 + l)); -- binding nullable not null long
  EXPECT_NE!(r, (select 1 + r)); -- binding nullable not null real
end);

-- binding tests for nullable types values null
TEST!(bind_nullables_null,
begin
  declare b bool;
  declare i int;
  declare l long;
  declare r real;
  declare t text;

  EXPECT_EQ!((select b), null); -- binding null bool
  EXPECT_EQ!((select i), null); -- binding null int
  EXPECT_EQ!((select l), null); -- binding null long
  EXPECT_EQ!((select r), null); -- binding null real
  EXPECT_EQ!((select t), null); -- binding null text
end);

TEST!(loop_fetch,
begin
  declare id_ int!;
  declare name_ text;
  declare code_ long int;
  declare flag_  bool;
  declare rate_ real;
  declare bl_ blob;
  declare count, sum int!;

  load_mixed();

  declare read_cursor cursor for select * from mixed;

  count := 0;
  sum := 0;
  loop fetch read_cursor into id_, name_, code_, flag_, rate_, bl_
  begin
    count += 1;
    sum := sum + id_;
  end;

  EXPECT_EQ!(count, 2);  -- there should be two rows
  EXPECT_EQ!(sum , 3);   -- some math along the way
end);

proc load_more_mixed()
begin
  delete from mixed;
  insert into mixed values
    (1, "a name", 12, 1, 5.0, null),
    (2, "some name", 14, 3, 7.0, null),
    (3, "yet another name", 15, 3, 17.4, null),
    (4, "some name", 19, 4, 9.1, null),
    (5, "what name", 21, 8, 12.3, null);
end;

TEST!(loop_control_flow,
begin
  load_more_mixed();

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

  EXPECT_EQ!(count, 3); -- there should be three rows tested
  EXPECT_EQ!(C.id , 4);  -- the match goes with id #4
end);

-- basic test of while loop plus leave and continue
TEST!(while_control_flow,
begin
  let i := 0;
  let sum := 0;
  while i < 5
  begin
    i += 1;
    sum += i;
  end;

  EXPECT_EQ!(i, 5);  -- loop ended on time
  EXPECT_EQ!(sum, 15); -- correct sum computed: 1 + 2 + 3 + 4 + 5

  i := 0;
  sum := 0;
  while i < 5
  begin
    i += 1;
    if i == 2 continue;

    if i == 4 leave;
    sum += i;
  end;

  EXPECT_EQ!(i, 4);  -- loop ended on time
  EXPECT_EQ!(sum, 4);  -- correct sum computed: 1 + 3
end);

-- same test but the control variable is nullable making the expression nullable
TEST!(while_control_flow_with_nullables,
begin
  let i := 0;
  let sum := 0;
  while i < 5
  begin
    i += 1;
    sum += i;
  end;

  EXPECT_EQ!(i, 5); -- loop ended on time
  EXPECT_EQ!(sum, 15);  -- correct sum computed: 1 + 2 + 3 + 4 + 5
end);

-- like predicate test
TEST!(like_predicate,
begin
  EXPECT_SQL_TOO!("this is a test" like "%is a%");
  EXPECT_SQL_TOO!(not ("this is a test" like "is a"));

  declare txt text;
  EXPECT_SQL_TOO!(("" like txt) is null);
  EXPECT_SQL_TOO!((txt like "%") is null);
  EXPECT_SQL_TOO!((txt like txt) is null);
end);

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
begin
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
end);

-- the catch block should not run if no errors
TEST!(throw_and_not_catch,
begin
  declare did_catch int!;
  try
    did_catch := 0;
  catch
    did_catch := 1;
  end;
  EXPECT_EQ!(did_catch, 0); -- catch did not run
end);

TEST!(cql_throw,
begin
   let result := -1;
   try
     cql_throw(12345);
   catch
     result := @rc;
   end;
   EXPECT_EQ!(result, 12345);
end);

proc case_tester1(value int!, out result int)
begin
  result := case value
    when 1 then 100
    when 2 then 200
    when 3 then 300
    else 400
  end;
end;

proc case_tester2(value int!, out result int)
begin
  result := case value
    when 1 then 100
    when 2 then 200
    when 3 then 300
  end;
end;

TEST!(simple_case_test,
begin
  declare result int;

  case_tester1(1, result);
  EXPECT_EQ!(result, 100);
  case_tester1(2, result);
  EXPECT_EQ!(result, 200);
  case_tester1(3, result);
  EXPECT_EQ!(result, 300);
  case_tester1(5, result);
  EXPECT_EQ!(result, 400);

  case_tester2(1, result);
  EXPECT_EQ!(result, 100);
  case_tester2(2, result);
  EXPECT_EQ!(result, 200);
  case_tester2(3, result);
  EXPECT_EQ!(result, 300);
  case_tester2(5, result);
  EXPECT_EQ!(result, null);
end);

proc string_case_tester1(value text, out result text)
begin
  result := case value
    when "1" then "100"
    when "2" then "200"
    when "3" then "300"
  end;
end;

TEST!(string_case_test,
begin
  let result := string_case_tester1("1");
  EXPECT_EQ!(result, "100");

  result := string_case_tester1("2");
  EXPECT_EQ!(result, "200");

  result := string_case_tester1("3");
  EXPECT_EQ!(result, "300");

  result := string_case_tester1("5");
  EXPECT_EQ!(result, null);
end);

proc in_tester1(value int!, out result bool!)
begin
  result := value in (1, 2, 3);
end;

TEST!(in_test_not_null,
begin
  declare result bool!;
  in_tester1(1, result);
  EXPECT!(result);
  in_tester1(2, result);
  EXPECT!(result);
  in_tester1(3, result);
  EXPECT!(result);
  in_tester1(4, result);
  EXPECT!(not result);
end);

proc in_tester2(value int, out result bool)
begin
  declare two int;
  two := 2;
  result := value in (1, two, 3);
end;

TEST!(in_test_nullables,
begin
  declare result bool;
  in_tester2(1, result);
  EXPECT!(result);
  in_tester2(2, result);
  EXPECT!(result);
  in_tester2(3, result);
  EXPECT!(result);
  in_tester2(4, result);
  EXPECT!(not result);
  in_tester2(null, result);
  EXPECT_EQ!(result, null);
end);

proc nullables_case_tester(value int, out result int!)
begin
  -- this is a very weird way to get a bool
  result := case 1 when value then 1 else 0 end;
end;

TEST!(nullable_when_test,
begin
  declare result int!;
  nullables_case_tester(1, result);
  EXPECT_EQ!(result, 1);
  nullables_case_tester(0, result);
  EXPECT_EQ!(result, 0);
end);

proc nullables_case_tester2(value int, out result int!)
begin
  -- this is a very weird way to get a bool
  result := case when value then 1 else 0 end;
end;

TEST!(nullable_when_pred_test,
begin
  declare result int!;
  nullables_case_tester(1, result);
  EXPECT_EQ!(result, 1);
  nullables_case_tester(0, result);
  EXPECT_EQ!(result, 0);
  nullables_case_tester(null, result);
  EXPECT_EQ!(result, 0);
end);

proc in_string_tester(value text, out result bool)
begin
  result := value in ("this", "that");
end;

TEST!(string_in_test,
begin
  declare result bool;
  in_string_tester("this", result);
  EXPECT!(result);
  in_string_tester("that", result);
  EXPECT!(result);
  in_string_tester("at", result);
  EXPECT!(not result);
  in_string_tester(null, result);
  EXPECT_EQ!(result, null);
end);

TEST!(string_between_test,
begin
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
end);

TEST!(string_not_between_test,
begin
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
end);

proc maybe_commit(do_commit bool!)
begin
  load_mixed();
  begin transaction;
  delete from mixed where id = 1;
  EXPECT_EQ!(1, (select count(*) from mixed)); -- delete successful
  if do_commit then
    commit transaction;
  else
    rollback transaction;
  end if;
end;

TEST!(transaction_mechanics,
begin
  maybe_commit(1);
  EXPECT_EQ!(1, (select count(*) from mixed)); -- commit successful
  maybe_commit(0);
  EXPECT_EQ!(2, (select count(*) from mixed)); -- rollback successful
end);

[[identity=(id, code, bl)]]
[[generate_copy]]
proc get_mixed(lim int!)
begin
  select * from mixed limit lim;
end;

[[generate_copy]]
proc get_one_from_mixed(id_ int!)
begin
  cursor C for select * from mixed where id = id_;
  fetch C;
  out C;
end;

TEST!(proc_loop_fetch,
begin
  load_mixed();

  declare read_cursor cursor for call get_mixed(200);

  let count := 0;
  loop fetch read_cursor
  begin
    count += 1;
  end;

  EXPECT_EQ!(count, 2); -- there should be two rows
end);

proc savepoint_maybe_commit(do_commit bool!, out result int!)
begin
  load_mixed();
  savepoint foo;
  delete from mixed where id = 1;
  EXPECT_EQ!(1, (select count(*) from mixed));  -- delete successful
  if do_commit then
    -- this is a commit
    release savepoint foo;
  else
    -- this is a rollback
    rollback transaction to savepoint foo;
  end if;
  result := (select count(*) from mixed);
end;

TEST!(savepoint_mechanics,
begin
  -- savepoint commit successful (1 row deleted)
  EXPECT_EQ!(1, savepoint_maybe_commit(true));

  -- savepoint rollback successful (no rows deleted)
  EXPECT_EQ!(2, savepoint_maybe_commit(false));
end);

TEST!(exists_test,
begin
  load_mixed();
  EXPECT!((select EXISTS(select * from mixed)));  -- exists found rows
  delete from mixed;
  EXPECT!((select not EXISTS(select * from mixed)));  -- not exists found no rows
end);

proc bulk_load_mixed(rows_ int!)
begin
  delete from mixed;

  let i := 0;
  for i < rows_; i += 1;
  begin
    insert into mixed values (i, "a name", 12, 1, 5.0, cast(i as blob));
  end;
end;

TEST!(complex_nested_selects,
begin
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
    EXPECT_EQ!(count_, case id_ when 1 then 3 when 2 then 2 when 3 then 1 else 0 end);
  end;
end);

TEST!(proc_loop_auto_fetch,
begin
  declare count, sum int!;

  load_mixed();

  declare read_cursor cursor for call get_mixed(200);

  count := 0;
  sum := 0;
  loop fetch read_cursor
  begin
    count += 1;
    sum := sum + read_cursor.id;
  end;

  EXPECT_EQ!(count, 2);  -- there should be two rows
  EXPECT_EQ!(sum , 3);  -- id checksum
end);

TEST!(coalesce,
begin
  let i := null ~int~;
  EXPECT_SQL_TOO!(coalesce(i, i, 2) == 2); -- grab the not null last value
  EXPECT_SQL_TOO!(ifnull(i, 2) == 2); -- grab the not null last value

  i := nullable(3);
  EXPECT_SQL_TOO!(coalesce(i, i, 2) == 3); -- grab the not null first value
  EXPECT_SQL_TOO!(ifnull(i, 2) == 3); -- grab the not null first value
end);

TEST!(printf_expression,
begin
  EXPECT_EQ!(printf("%d and %d", 12, 7), "12 and 7"); -- loose printf ok
  EXPECT_EQ!((select printf("%d and %d", 12, 7)), "12 and 7"); -- sql printf ok
end);

TEST!(case_with_null,
begin
  let x := null ~int~;
  x := case x when 0 then 1 else 2 end;
  EXPECT_EQ!(x, 2); --null only matches the else
end);

TEST!(group_concat,
begin
  create table conc_test(id int, name text);
  insert into conc_test values (1,"x");
  insert into conc_test values (1,"y");
  insert into conc_test values (2,"z");
  cursor C for select id, group_concat(name) as vals from conc_test group by id;
  fetch C;
  EXPECT_EQ!(C.id, 1);
  EXPECT_EQ!(C.vals, "x,y");
  fetch C;
  EXPECT_EQ!(C.id, 2);
  EXPECT_EQ!(C.vals, "z");
end);

TEST!(strftime,
begin
  var _null text;

  -- sql strftime ok
  EXPECT_EQ!((select strftime("%s", "1970-01-01T00:00:03")), "3");

 -- strftime null format ok
  EXPECT_EQ!((select strftime(_null, "1970-01-01T00:00:03")), null);

  -- strftime null timestring ok
  EXPECT_EQ!((select strftime("%s", _null)), null);

 -- strftime null timestring ok
  EXPECT_EQ!((select strftime("%s", "1970-01-01T00:00:03", "+1 day")), "86403");

 -- strftime with multiple modifiers on now ok
  EXPECT_NE!((select strftime("%W", "now", "+1 month", "start of month", "-3 minutes", "weekday 4")), null);
end);

TEST!(cast_expr,
begin
  EXPECT_EQ!((select cast(1.3 as int)), 1); -- cast expression
end);

TEST!(type_check_,
begin
  let int_val := type_check(1 as int!);
  EXPECT_EQ!(int_val, 1);

  let int_cast_val := type_check(1 ~int<foo>~ as int<foo> not null);
  EXPECT_EQ!(int_cast_val, 1);
end);

TEST!(union_all_test,
begin
  cursor C for
    select 1 as A, 2 as B
    union all
    select 3 as A, 4 as B;
  fetch C;
  EXPECT_EQ!(C.A, 1);
  EXPECT_EQ!(C.B, 2);
  fetch C;
  EXPECT_EQ!(C.A, 3);
  EXPECT_EQ!(C.B, 4);
end);

TEST!(union_test,
begin
  cursor C for
    select 1 as A, 2 as B
    union
    select 1 as A, 2 as B;
  fetch C;
  EXPECT_EQ!(C.A, 1);
  EXPECT_EQ!(C.B, 2);
  fetch C;
  EXPECT!(not C); -- no more rows
end);

TEST!(union_test_with_nullable,
begin
  cursor C for
    select nullable(121) as A, 212 as B
    union
    select nullable(121) as A, 212 as B;
  fetch C;
  EXPECT_EQ!(C.A, 121);
  EXPECT_EQ!(C.B, 212);
  fetch C;
  EXPECT!(not C);
end);

TEST!(with_test,
begin
  cursor C for
    with X(`A A`,B) as ( select 1,2)
    select * from X;

  fetch C;
  EXPECT_EQ!(C.`A A`, 1);
  EXPECT_EQ!(C.B, 2);
  fetch C;
  EXPECT!(not C);
end);

TEST!(with_recursive_test,
begin
cursor C for
  with recursive
    c1(current) as (
      select 1
      union all
      select current + 1 from c1
      limit 5
    ),
    c2(current) as (
      select 6
      union all
      select current + 1 from c2
      limit 5
    )
  select current as X from c1
  union all
  select current as X from c2;

  declare i int!;
  i := 1;

  loop fetch C
  begin
    EXPECT_EQ!(C.X, i); -- iterating over the recursive result
    i += 1;
  end;
  EXPECT_EQ!(i, 11); -- 10 results matched, 11th did not match
end);

proc out_int(out int1 int, out int2 int!)
begin
  declare C1 cursor for select 1;
  fetch C1 into int1;
  declare C2 cursor for select 2;
  fetch C2 into int2;
end;

TEST!(fetch_output_param,
begin
  declare out call out_int(int1, int2);
  EXPECT_EQ!(int1, 1); -- bind output nullable
  EXPECT_EQ!(int2, 2); -- bind output not nullable
end);

function run_test_math(int1 int!, out int2 int) int!;
function string_create() create text;
function string_ref_count(str text) int!;

TEST!(external_functions,
begin
  declare int_out int;

  let int_result := run_test_math(100, int_out);
  EXPECT_EQ!(int_out, 500);
  EXPECT_EQ!(int_result, 700);

  let text_result := string_create();

  EXPECT!(text_result like "%Hello%");
end);

TEST!(rev_appl_operator,
begin
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
end);

function set_create() create object!;
function set_add(_set object!, _key text!) bool!;
function set_contains(_set object!, _key text!) bool!;

TEST!(external_set,
begin
  -- stress the create and copy semantics
  declare _set object!;
  _set := set_create();
  declare _set2 object!;
  _set2 := set_create();
  _set := _set2; -- this is a copy

  EXPECT_NE!(nullable(_set), null);  -- successful create
  EXPECT!(not set_contains(_set, "something")); -- initially empty
  EXPECT!(set_add(_set, "something")); -- successful addition
  EXPECT!(set_contains(_set, "something")); -- key added
  EXPECT!(not set_add(_set, "something")); -- duplicate addition
end);

TEST!(object_not_null,
begin
  declare _setNN object!;
  declare _set object;
  _set := nullable(set_create());
  _setNN := ifnull_crash(_set);
  EXPECT_EQ!(_set, _setNN); -- should be the same pointer
end);

TEST!(dummy_values,
begin
  delete from mixed;
  let i := 0;
  for i < 20; i += 1;
  begin
    insert into mixed (bl) values (cast(i as blob)) @dummy_seed(i) @dummy_nullables @dummy_defaults;
  end;

  cursor C for select * from mixed;
  i := 0;
  for i < 20; i += 1;
  begin
    fetch C;
    EXPECT_EQ!(C.id, i);
    EXPECT_EQ!(C.name, printf("name_%d", i));
    EXPECT_EQ!(C.code, i);
    EXPECT_EQ!(not C.flag, not i);
    EXPECT_EQ!(C.rate, i);
  end;
end);

TEST!(blob_basics,
begin
  let s := "a string";
  let b := blob_from_string(s);
  let s2 := string_from_blob(b);
  EXPECT_EQ!(s, s2); -- blob conversion failed
  EXPECT_EQ!(b, blob_from_string("a string"));
  EXPECT_EQ!(b, blob_from_string("a string"));
  EXPECT!(b <> blob_from_string("a strings"));
  EXPECT_NE!(b, blob_from_string("a strings"));

  declare b_null blob;
  b_null := null;
  declare s_null text;
  s_null := null;
  EXPECT_EQ!(b_null, b_null);
  EXPECT_EQ!(s_null, s_null);
  EXPECT_NE!(b_null, b);
  EXPECT_NE!(s_null, s);
  EXPECT_EQ!(b_null, null);
  EXPECT_EQ!(s_null, null);
end);

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
  blob_table_maker();

  let i := 0;
  let count := 20;

  for i < count; i += 1;
  begin
    let s := printf("nullable blob %d", i);
    let b1 := blob_from_string(s);
    s := printf("not nullable blob %d", i);
    let b2 := blob_from_string(s);
    insert into blob_table(id, b1, b2) values (i, b1, b2);
  end;
end;

TEST!(blob_dummy_defaults,
begin
  cursor C like blob_table;
  fetch C() from values() @dummy_seed(5) @dummy_nullables;
  let s1 := string_from_blob(C.b1);
  let s2 := string_from_blob(C.b2);
  EXPECT_EQ!(s1, "b1_5");
  EXPECT_EQ!(s2, "b2_5");
end);

TEST!(blob_data_manipulate,
begin
  load_blobs();

  cursor C for select * from blob_table order by id;
  let i := 0;
  let count := 20;

  loop fetch C
  begin
    declare s1, s2 text;
    EXPECT_EQ!(i, C.id);

    s1 := string_from_blob(c.b1);
    EXPECT_EQ!(s1, printf("nullable blob %d", i)); -- nullable blob failed to round trip

    s2 := string_from_blob(c.b2);
    EXPECT_EQ!(s2, printf("not nullable blob %d", i)); -- not nullable blob failed to round trip

    i += 1;
  end;

  EXPECT_EQ!(i, count); -- wrong number of rows
end);

proc get_blob_table()
begin
  select * from blob_table;
end;

proc load_sparse_blobs()
begin
  blob_table_maker();

  declare s text!;
  declare b1 blob;
  declare b2 blob!;

  let i := 0;
  let count := 20;

  for i < count; i += 1;
  begin
    s := printf("nullable blob %d", i);
    b1 := case when i % 2 == 0 then blob_from_string(s) else null end;
    s := printf("not nullable blob %d", i);
    b2 := blob_from_string(s);
    insert into blob_table(id, b1, b2) values (i, b1, b2);
  end;
end;

TEST!(blob_data_manipulate_nullables,
begin
  cursor C for select * from blob_table order by id;
  let i := 0;
  let count := 20;

  load_sparse_blobs();

  loop fetch C
  begin
    declare s1, s2 text;
    s1 := string_from_blob(C.b1);
    EXPECT_EQ!(i, C.id);
    if i % 2 == 0 then
      s1 := string_from_blob(C.b1);
      EXPECT_EQ!(s1, printf("nullable blob %d", i)); -- nullable blob failed to round trip
    else
      EXPECT_EQ!(C.b1, null);
    end if;
    s2 := string_from_blob(C.b2);
    EXPECT_EQ!(s2, printf("not nullable blob %d", i)); -- not nullable blob failed to round trip
    i += 1;
  end;

  EXPECT_EQ!(i, count); -- wrong number of rows
end);

proc row_getter(x int!, y real!, z text)
begin
  cursor C for select x X, y Y, z Z;
  fetch C;
  out C;
end;

TEST!(data_reader,
begin
  cursor C fetch from call row_getter(1, 2.5, "something");
  EXPECT_EQ!(C.X, 1);
  EXPECT_EQ!(C.Y, 2.5);
  EXPECT_EQ!(C.Z, "something");
end);

-- test simple recursive function -- using func syntax!
proc fib2 (in arg int!, out result int!)
begin
  if arg <= 2 then
    result := 1;
  else
    result := fib2(arg - 1) + fib2(arg - 2);
  end if;
end;

TEST!(recurse_with_proc,
begin
  EXPECT_EQ!(fib2(1), 1);
  EXPECT_EQ!(fib2(2), 1);
  EXPECT_EQ!(fib2(3), 2);
  EXPECT_EQ!(fib2(4), 3);
  EXPECT_EQ!(fib2(5), 5);
  EXPECT_EQ!(fib2(6), 8);
end);

-- test simple recursive function -- using func syntax!
proc fib3 (in arg int!, out result int!)
begin
  if arg <= 2 then
    result := (select 1); -- for this to be a dml proc
  else
    result := fib3(arg - 1) + fib3(arg - 2);
  end if;
end;

TEST!(recurse_with_dml_proc,
begin
  -- we force all the error handling code to run with this flavor
  EXPECT_EQ!(fib3(1), 1);
  EXPECT_EQ!(fib3(2), 1);
  EXPECT_EQ!(fib3(3), 2);
  EXPECT_EQ!(fib3(4), 3);
  EXPECT_EQ!(fib3(5), 5);
  EXPECT_EQ!(fib3(6), 8);
end);

TEST!(row_id_test,
begin
  load_mixed();
  cursor C for select rowid from mixed;
  declare r int!;
  r := 1;

  loop fetch C
  begin
    EXPECT_EQ!(C.rowid, r);
    r := r + 1;
  end;
end);

TEST!(bind_and_fetch_all_types,
begin
  let i := 10;
  let l := 1234567890156789L;
  let r := 1234.45;
  let b := 1;
  let s := "string";
  let bl := blob_from_string("blob text");

  EXPECT_EQ!(13 * i, (select 13 * i));
  EXPECT_EQ!(13 * l, (select 13 * l));
  EXPECT_EQ!(13 * r, (select 13 * r));
  EXPECT_EQ!(not b, (select not b));
  EXPECT_EQ!(printf("foo %s", s), (select printf("foo %s", s)));
  EXPECT_EQ!("blob text", string_from_blob((select bl)));
end);

TEST!(bind_and_fetch_all_types_nullable,
begin
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

  EXPECT_EQ!(13 * i, (select 13 * i));
  EXPECT_EQ!(13 * l, (select 13 * l));
  EXPECT_EQ!(13 * r, (select 13 * r));
  EXPECT_EQ!(not b, (select not b));
  EXPECT_EQ!(printf("foo %s", s), (select printf("foo %s", s)));
  EXPECT_EQ!("blob text", string_from_blob((select bl)));
end);

TEST!(fetch_all_types_cursor,
begin
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

  cursor C for select i * 13 i, l * 13 l, r * 13 r, not b b, printf("foo %s",s) s, bl bl;
  fetch C;
  EXPECT_EQ!(13 * i, C.i);
  EXPECT_EQ!(13 * l, C.l);
  EXPECT_EQ!(13 * r, C.r);
  EXPECT_EQ!(not b, C.b);
  EXPECT_EQ!(printf("foo %s", s), C.s);
  EXPECT_EQ!("blob text", string_from_blob(C.bl));

  fetch C;
  EXPECT!(not C);
  EXPECT_EQ!(C.i,  0);
  EXPECT_EQ!(C.l,  0);
  EXPECT_EQ!(C.r,  0);
  EXPECT_EQ!(C.b,  0);
  EXPECT_EQ!(nullable(C.s), null); -- even though s is not null, it is null... sigh
  EXPECT_EQ!(nullable(c.bl), null); -- even though bl is not null, it is null... sigh
end);

TEST!(fetch_all_types_cursor_nullable,
begin
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

  cursor C for select i * 13 i, l * 13 l, r * 13 r, not b b, printf("foo %s",s) s, bl bl;
  fetch C;
  EXPECT!(C);
  EXPECT_EQ!(13 * i, C.i);
  EXPECT_EQ!(13 * l, C.l);
  EXPECT_EQ!(13 * r, C.r);
  EXPECT_EQ!(not b, C.b);
  EXPECT_EQ!(printf("foo %s", s), C.s);
  EXPECT_EQ!("blob text", string_from_blob(C.bl));

  fetch C;
  EXPECT!(not C);
  EXPECT_EQ!(C.i, null);
  EXPECT_EQ!(C.l, null);
  EXPECT_EQ!(C.r, null);
  EXPECT_EQ!(C.b, null);
  EXPECT_EQ!(nullable(C.s), null);
  EXPECT_EQ!(nullable(c.bl), null);
end);

TEST!(concat_pri,
begin
  -- concat is weaker than ~
  EXPECT_EQ!('-22', (select ~1||2));
  EXPECT_EQ!('-22', (select (~1)||2));

  -- if the order was otherwise we'd get a different result...
  -- a semantic error actually
  EXPECT_EQ!(-13, (select ~CAST(1||2 as INTEGER)));

  --- negation is stronger than CONCAT
  EXPECT_EQ!('01', (select -0||1));
  EXPECT_EQ!('01', (select (-0)||1));

  -- if the order was otherwise we'd get a different result...
  -- a semantic error actually
  EXPECT_EQ!(-1, (select -CAST(0||1 as INTEGER)));
end);

-- Test precedence of multiply with (* / %) with add (+ -)
TEST!(multiply_pri,
begin
  EXPECT_SQL_TOO!(1 + 2 * 3 == 7);
  EXPECT_SQL_TOO!(1 + 2 * 3 + 4 * 5 == 27);
  EXPECT_SQL_TOO!(1 + 2 / 2 == 2);
  EXPECT_SQL_TOO!(1 + 2 / 2 * 4 == 5);
  EXPECT_SQL_TOO!(1 + 2 / 2 * 4 == 5);
  EXPECT_SQL_TOO!(1 * 2 + 3 == 5);
  EXPECT_SQL_TOO!(1 * 2 + 6 / 3 == 4);
  EXPECT_SQL_TOO!(1 * 2 + 6 / 3 == 4);
  EXPECT_SQL_TOO!(2 * 3 * 4 + 3 / 3 == 25);
  EXPECT_SQL_TOO!(-5 * 5 == -25);
  EXPECT_SQL_TOO!(5 - 5 * 5 == -20);
  EXPECT_SQL_TOO!(4 + 5 * 5 == 29);
  EXPECT_SQL_TOO!(4 * 5 + 5 == 25);
  EXPECT_SQL_TOO!(4 * 4 - 1 == 15);
  EXPECT_SQL_TOO!(10 - 4 * 2 == 2);
  EXPECT_SQL_TOO!(25 % 3 / 2 == 0);
  EXPECT_SQL_TOO!(25 / 5 % 2 == 1);
  EXPECT_SQL_TOO!(25 * 5 % 2 == 1);
  EXPECT_SQL_TOO!(25 * 5 % 4 % 2 == 1);
  EXPECT_SQL_TOO!(25 - 5 % 2 == 24);
  EXPECT_SQL_TOO!(15 % 3 - 2 == -2);
  EXPECT_SQL_TOO!(15 - 30 % 4 == 13);
  EXPECT_SQL_TOO!(15 - 30 / 2 == 0);
  EXPECT_SQL_TOO!(15 / 5 - 3 == 0);
  EXPECT_SQL_TOO!(15 * 5 - 3 == 72);
  EXPECT_SQL_TOO!(5 * 5 - 3 == 22);
  EXPECT_SQL_TOO!(25 + 5 % 2 == 26);
  EXPECT_SQL_TOO!(15 % 3 + 2 == 2);
  EXPECT_SQL_TOO!(15 + 30 % 4 == 17);
  EXPECT_SQL_TOO!(15 + 30 / 2 == 30);
  EXPECT_SQL_TOO!(15 / 5 + 3 == 6);
  EXPECT_SQL_TOO!(15 * 5 + 3 == 78);
  EXPECT_SQL_TOO!(5 * 5 + 3 == 28);
  EXPECT_SQL_TOO!(5 * 12 / 3 == 20);
  EXPECT_SQL_TOO!(5 * 12 / 3 % 7 == 6);
  EXPECT_SQL_TOO!(9 % 12 / 3 * 7 == 21);
end);

-- Test precedence of binary (<< >> & |) with add ( +  -)
TEST!(shift_pri,
begin
  EXPECT_SQL_TOO!(10<<1 + 1 == 40);
  EXPECT_SQL_TOO!(1 + 10<<1 == 22);
  EXPECT_SQL_TOO!(10<<1 - 1 == 10);
  EXPECT_SQL_TOO!(10<<4 - 1 == 80);
  EXPECT_SQL_TOO!(10 - 1<<1 == 18);

  EXPECT_SQL_TOO!(10>>3 - 1 == 2);
  EXPECT_SQL_TOO!(11 - 1>>1 == 5);
  EXPECT_SQL_TOO!(10>>1 + 1 == 2);
  EXPECT_SQL_TOO!(1 + 10>>1 == 5);

  EXPECT_SQL_TOO!(10&1 + 1 == 2);
  EXPECT_SQL_TOO!(1 + 10&1 == 1);
  EXPECT_SQL_TOO!(1 + 10&7 == 3);
  EXPECT_SQL_TOO!(10 - 1&7 == 1);
  EXPECT_SQL_TOO!(10 - 4&7 == 6);

  EXPECT_SQL_TOO!(10|1 + 1 == 10);
  EXPECT_SQL_TOO!(10|4 == 14);
  EXPECT_SQL_TOO!(1 + 10|4 == 15);
  EXPECT_SQL_TOO!(10 - 1|7 == 15);
  EXPECT_SQL_TOO!(10 - 3|7 == 7);

  EXPECT_SQL_TOO!(6&4 == 4);
  EXPECT_SQL_TOO!(6&4|12 == 12);
  EXPECT_SQL_TOO!(6&4|12|2 == 14);
  EXPECT_SQL_TOO!(6&4|12|2|2 == 14);
  EXPECT_SQL_TOO!(6&4|12|2|2<<3 == 112);
  EXPECT_SQL_TOO!(6&4|12|2|2<<3>>3<<2 == 56);
end);

-- Test precedence of inequality (< <= > >=) with binary (<< >> & |)
TEST!(inequality_pri,
begin
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
end);

-- Test precedence of equality (= == != <> like glob match in not in IS_NOT_NULL IS_NULL) with binary (< <= > >=)
TEST!(equality_pri,
begin
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

  -- glob must be inside a select statement so it also cannot be tested
  -- match can only be in a select statement, no test necessary

  -- Test is_not and is
  EXPECT_SQL_TOO!(nullable(1) + nullable(1) is null == 0);
  EXPECT_SQL_TOO!(nullable(1) + nullable(1) is not null == 1);
  EXPECT_SQL_TOO!(nullable(1) + nullable(1) is null + 1 == 0); -- Evaluated as: (1 + 1) is (null + 1) == 0;
  EXPECT_SQL_TOO!(nullable(1) + nullable(1) is not null);
  EXPECT_SQL_TOO!((nullable(1) + nullable(1) is not null) + 1 == 2);
  EXPECT_SQL_TOO!(1 + 1 is not null + 1 == 1);
  EXPECT_SQL_TOO!(1 + null is null);
  EXPECT_SQL_TOO!(null + 1 is null);
  EXPECT_SQL_TOO!(null * 1 is null);
  EXPECT_SQL_TOO!(null * 0 is null);
  EXPECT_SQL_TOO!(0 * null * 0 is null);
  EXPECT_SQL_TOO!(null > 0 is null);
  EXPECT_SQL_TOO!(null >= 1 is null);
  EXPECT_SQL_TOO!(null < 2 is null);
  EXPECT_SQL_TOO!(null <= 3 is null);
  EXPECT_SQL_TOO!(1 + null == 3 is null);
  EXPECT_SQL_TOO!(1 + null != 3 is null);
  EXPECT_SQL_TOO!(1 + null <> 3 is null);
  EXPECT_SQL_TOO!(1 = null * 1 + 1 is null);
  EXPECT_SQL_TOO!(1 = null * -1 + 1 is null);
  EXPECT_SQL_TOO!(1 + null = 3 - 1 = 1 is null);
  EXPECT_SQL_TOO!(1 + null = 3 - 1 <> 0 is null);
  EXPECT_SQL_TOO!(1 + null == 3 - 1 <> 0 is null);
  EXPECT_SQL_TOO!(1 + null = 3 - 1 <> 30 is null);
  EXPECT_SQL_TOO!(1 + null == 3 - 1 <> 30 is null);
  EXPECT_SQL_TOO!((null is not null) == 0);
  EXPECT_SQL_TOO!(nullable(1) + nullable(1) is not null);
  EXPECT_SQL_TOO!(null_ == 3 is null);
  EXPECT_SQL_TOO!(((null_ == 3) is null) == 1);
  EXPECT_SQL_TOO!((null_ == 3 is null) == 1);
  EXPECT_SQL_TOO!((null_ == 3 is null) == 1);
  EXPECT_SQL_TOO!(nullable(null_ == 3 is null) is not null);
  EXPECT_SQL_TOO!((1 + null == 3 is not null) == 0);
  EXPECT_SQL_TOO!((1 + null = 3 - 1 <> 0 is not null) == 0);
  EXPECT_SQL_TOO!((1 + null == 3 - 1 <> 0 is not null) == 0);
  EXPECT_SQL_TOO!((1 + null = 3 - 1 <> 30 is not null) == 0);

  -- Basic is tests, all non null
  EXPECT_SQL_TOO!(2 * 3 is 4 + 2);
  EXPECT_SQL_TOO!(2 * 3 is 4 + 2);
  EXPECT_SQL_TOO!(10 - 4 * 2 is 2);
  EXPECT_SQL_TOO!(25 % 3 / 2 is 0);
  EXPECT_SQL_TOO!(25 / 5 % 2 is 1);
  EXPECT_SQL_TOO!(25 * 5 % 2 is 1);
  EXPECT_SQL_TOO!(25 * 5 % 4 % 2 is 1);
  EXPECT_SQL_TOO!(25 - 5 % 2 is 24);
  EXPECT_SQL_TOO!(15 % 3 - 2 is -2);
  EXPECT_SQL_TOO!(15 - 30 % 4 is 13);
  EXPECT_SQL_TOO!(15 - 30 / 2 is 0);
  EXPECT_SQL_TOO!(15 / 5 - 3 is 0);
  EXPECT_SQL_TOO!(15 * 5 - 3 is 72);
  EXPECT_SQL_TOO!(5 * 5 - 3 is 22);
  EXPECT_SQL_TOO!(25 + 5 % 2 is 26);
  EXPECT_SQL_TOO!(15 % 3 + 2 is 2);
  EXPECT_SQL_TOO!(15 + 30 % 4 is 17);
  EXPECT_SQL_TOO!(15 + 30 / 2 is 30);
  EXPECT_SQL_TOO!(15 / 5 + 3 is 6);
  EXPECT_SQL_TOO!(15 * 5 + 3 is 78);
  EXPECT_SQL_TOO!(5 * 5 + 3 is 28);
  EXPECT_SQL_TOO!(5 * 12 / 3 is 20);
  EXPECT_SQL_TOO!(5 * 12 / 3 % 7 is 6);
  EXPECT_SQL_TOO!(9 % 12 / 3 * 7 is 21);

  -- is tests with null
  EXPECT_SQL_TOO!(1 is 1 == 1 is 1 == 1);
  EXPECT_SQL_TOO!(5 > 6 is 2 < 1);
  EXPECT_SQL_TOO!(5 <= 6 is 2 > 1);
  EXPECT_SQL_TOO!(5 == 5 is 2 > 1);
  EXPECT_SQL_TOO!("1" is "2" == 0);
  EXPECT_SQL_TOO!(nullable("1") is null == 0);
  EXPECT_SQL_TOO!(null is "1" == 0);
  EXPECT_SQL_TOO!(null is null);
  EXPECT_SQL_TOO!(null_ == 0 is null);
  EXPECT_SQL_TOO!(null is null == 1 != 0);
  EXPECT_SQL_TOO!(null is null = 1 <> 0);
  EXPECT_SQL_TOO!(null_ == null_ is null);
  EXPECT_SQL_TOO!(null is (null_ == 0));
  EXPECT_SQL_TOO!(null is not null == 0);
  EXPECT_SQL_TOO!((null is not null) == 0);
  EXPECT_SQL_TOO!(nullable(5) > nullable(2) is not null);
  EXPECT_SQL_TOO!(null is not 2 < 3);
  EXPECT_SQL_TOO!(nullable(null is 2 < 3) is not null);
  EXPECT_SQL_TOO!(null is null + 1);
  EXPECT_SQL_TOO!(null is 1 + null);
  EXPECT_SQL_TOO!(null is 1 << null);

  -- Test in
  EXPECT_SQL_TOO!(3 in (1, 2) == 0);
  EXPECT_SQL_TOO!(3 + 2 in (1, 5));
  EXPECT_SQL_TOO!(3 / 3 in (1, 2));
  EXPECT_SQL_TOO!(3 / 3 in (1, 2) in (1));
  EXPECT_SQL_TOO!(1 in (null, 1));
  EXPECT!(not (1 in (null, 5)));
  EXPECT!((select null is (not (1 in (null, 5))))); -- known sqlite and CQL in difference for null
  EXPECT_SQL_TOO!(null is (null in (1)));

  -- Test not in
  EXPECT_SQL_TOO!(3 not in (1, 2) == 1);
  EXPECT_SQL_TOO!(1 not in (1, 2) == 0);
  EXPECT_SQL_TOO!(3 + 1 not in (1, 5));
  EXPECT_SQL_TOO!(3 / 1 not in (1, 2));
  EXPECT_SQL_TOO!(3 / 1 not in (1, 2) not in (0));
  EXPECT_SQL_TOO!(not (1 not in (null, 1)));
  EXPECT!(1 not in (null, 5));
  EXPECT!((select null is (1 not in (null, 5))));  -- known sqlite and CQL in difference for null
  EXPECT_SQL_TOO!(null is (null not in (1)));

  declare x text;
  x := null;

  EXPECT_SQL_TOO!((x in ("foo", "goo")) is null);
  EXPECT_SQL_TOO!((x not in ("foo", "goo")) is null);

  -- Test is true and is false
  EXPECT_SQL_TOO!(1 is true);
  EXPECT_SQL_TOO!(0 is false);
  EXPECT_SQL_TOO!(not 0 is true);
  EXPECT_SQL_TOO!(not 1 is false);
  EXPECT_SQL_TOO!(not null is false);
  EXPECT_SQL_TOO!(not null is true);

  -- Test is not true and is not false
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
  -- is an operator.  In SQLite the way it works is that if the right operator of "is" happens
  -- to the the literal "true" then you get "is true" behavior.
  -- This is wrong.  And hard to emulate.   CQL forces it the normal way with parens.
  -- SQLite will see "not ((false is true) < false)";
  --
  -- This may be fixed in future SQLites, but even if that happens the below will still pass.
  --
  EXPECT_SQL_TOO!(not(false is true < false));
end);

TEST!(between_pri,
begin
  -- between is the same as = but binds left to right

  EXPECT_SQL_TOO!(0 == (1=2 between 2 and 2));
  EXPECT_SQL_TOO!(1 == (1=(2 between 2 and 2)));
  EXPECT_SQL_TOO!(0 == ((1=2) between 2 and 2));

  let four := 4;

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
end);

-- and tests with = == != <> is is_not in not in
TEST!(and_pri,
begin
  declare null_ int;

  EXPECT_SQL_TOO!(3 + 3 and 5);
  EXPECT_SQL_TOO!((3 + 3 and 0) == 0);
  EXPECT_SQL_TOO!((null and true) is null);
  EXPECT_SQL_TOO!((null and true = null_) is null);
  EXPECT_SQL_TOO!(not (null and nullable(true) is null));
  EXPECT_SQL_TOO!((null and false) == 0);
  EXPECT_SQL_TOO!(not (null and false));
  EXPECT_SQL_TOO!(1 and false == false);
  EXPECT_SQL_TOO!(1 and false = false);
  EXPECT_SQL_TOO!(1 and true != false);
  EXPECT_SQL_TOO!(1 and true <> false);
  EXPECT_SQL_TOO!(5 is 5 and 2 is 2);
  EXPECT_SQL_TOO!(nullable(5) is not null and 2 is 2);
  EXPECT_SQL_TOO!(nullable(5) is not null and 2 is 2);
  EXPECT_SQL_TOO!(5 and false + 1);
  EXPECT_SQL_TOO!(5 and false * 1 + 1);
  EXPECT_SQL_TOO!(5 and false >> 4 >= -1);
  EXPECT_SQL_TOO!(5 and false | 4 & 12);
  EXPECT_SQL_TOO!(5 and 6 / 3);
  EXPECT_SQL_TOO!((5 and 25 % 5) == false);
  EXPECT_SQL_TOO!(5 and false in (0));
  EXPECT_SQL_TOO!(5 and true not in (false));
  EXPECT_SQL_TOO!(not(5 and false not in (false)));
end);

-- Test and with or
TEST!(or_pri,
begin
  -- The following tests show that if and and or were evaluated from
  -- left to right, then the output would be different
  EXPECT_SQL_TOO!((0 or 1 or 1 and 0 or 0) != ((((0 or 1) or 1) and 0) or 0));
  EXPECT_SQL_TOO!((1 or 1 and 0 and 1 and 0) != ((((1 or 1) and 0) and 1) and 0));
  EXPECT_SQL_TOO!((0 or 1 or 1 and 0 and 1) != ((((0 or 1) or 1) and 0) and 1));
  EXPECT_SQL_TOO!((1 or 1 or 1 and 0 and 0) != ((((1 or 1) or 1) and 0) and 0));
  EXPECT_SQL_TOO!((1 or 1 or 1 and 0 or 0) != ((((1 or 1) or 1) and 0) or 0));
  EXPECT_SQL_TOO!((1 and 1 and 1 or 1 and 0) != ((((1 and 1) and 1) or 1) and 0));
  EXPECT_SQL_TOO!((1 or 0 and 0 and 1 or 0) != ((((1 or 0) and 0) and 1) or 0));
  EXPECT_SQL_TOO!((1 and 1 or 0 and 0 and 1) != ((((1 and 1) or 0) and 0) and 1));
  EXPECT_SQL_TOO!((1 or 0 or 0 or 0 and 0) != ((((1 or 0) or 0) or 0) and 0));
  EXPECT_SQL_TOO!((1 or 0 and 0 or 1 and 0) != ((((1 or 0) and 0) or 1) and 0));
  EXPECT_SQL_TOO!((1 or 1 and 1 and 1 and 0) != ((((1 or 1) and 1) and 1) and 0));
  EXPECT_SQL_TOO!((0 and 0 or 1 or 0 and 0) != ((((0 and 0) or 1) or 0) and 0));
  EXPECT_SQL_TOO!((0 or 1 or 1 and 0 and 0) != ((((0 or 1) or 1) and 0) and 0));
  EXPECT_SQL_TOO!((1 and 1 and 1 or 0 and 0) != ((((1 and 1) and 1) or 0) and 0));
  EXPECT_SQL_TOO!((1 or 1 or 1 and 0 and 1) != ((((1 or 1) or 1) and 0) and 1));
  EXPECT_SQL_TOO!((1 or 0 or 0 or 0 and 0) != ((((1 or 0) or 0) or 0) and 0));
end);

-- Take some priority tests and replace constants with nullable variables
TEST!(nullable_test,
begin
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
  EXPECT_SQL_TOO!(x1 + x2 * x3 + x4 * x5 == temp0);
  EXPECT_SQL_TOO!(x1 + x2 / x2 == x2);
  EXPECT_SQL_TOO!(x1 + x2 / x2 * x4 == x5);
  EXPECT_SQL_TOO!(x1 + x2 / x2 * x4 == x5);
  EXPECT_SQL_TOO!(x1 * x2 + x3 == x5);
  EXPECT_SQL_TOO!(x1 * x2 + x6 / x3 == x4);
  EXPECT_SQL_TOO!(x1 * x2 + x6 / x3 == x4);
  temp0 := nullable(25);
  EXPECT_SQL_TOO!(x2 * x3 * x4 + x3 / x3 == temp0);
  temp0 := nullable(-25);
  EXPECT_SQL_TOO!(-x5 * x5 == temp0);
  temp0 := nullable(-20);
  EXPECT_SQL_TOO!(x5 - x5 * x5 == temp0);
  temp0 := nullable(29);
  EXPECT_SQL_TOO!(x4 + x5 * x5 == temp0);
  temp0 := nullable(25);
  EXPECT_SQL_TOO!(x4 * x5 + x5 == temp0);
  temp0 := nullable(15);
  EXPECT_SQL_TOO!(x4 * x4 - x1 == temp0);
  temp0 := nullable(10);
  EXPECT_SQL_TOO!(10 - x4 * x2 == x2);

  temp0 := nullable(10);

  let temp1 := nullable(40);
  EXPECT_SQL_TOO!(temp0<<x1 + x1 == temp1);
  temp1 := nullable(22);
  EXPECT_SQL_TOO!(x1 + temp0<<x1 == temp1);
  EXPECT_SQL_TOO!(temp0<<x1 - x1 == temp0);
  temp1 := nullable(80);
  EXPECT_SQL_TOO!(temp0<<x4 - x1 == temp1);
  temp1 := nullable(18);
  EXPECT_SQL_TOO!(temp0 - x1<<x1 == temp1);

  EXPECT_SQL_TOO!(temp0>>x3 - x1 == x2);
  temp1 := nullable(11);
  EXPECT_SQL_TOO!(temp1 - x1>>x1 == x5);
  EXPECT_SQL_TOO!(temp0>>x1 + x1 == x2);
  EXPECT_SQL_TOO!(x1 + temp0>>x1 == x5);

  EXPECT_SQL_TOO!(temp0&x1 + x1 == x2);
  EXPECT_SQL_TOO!(x1 + temp0&x1 == x1);
  EXPECT_SQL_TOO!(x1 + temp0&x7 == x3);
  EXPECT_SQL_TOO!(temp0 - x1&x7 == x1);
  EXPECT_SQL_TOO!(temp0 - x4&x7 == x6);

  EXPECT_SQL_TOO!(temp0|x1 + x1 == temp0);
  temp1 := nullable(14);
  EXPECT_SQL_TOO!(temp0|x4 == temp1);
  temp1 := nullable(15);
  EXPECT_SQL_TOO!(x1 + temp0|x4 == temp1);
  EXPECT_SQL_TOO!(temp0 - x1|x7 == temp1);
  EXPECT_SQL_TOO!(temp0 - x3|x7 == x7);

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
  temp_null := null;

  EXPECT_SQL_TOO!(x1 + x1 is null == x0);
  EXPECT_SQL_TOO!(x1 + x1 is not null == x1);
  EXPECT_SQL_TOO!(x1 + x1 is null + x1 == x0);
  EXPECT_SQL_TOO!(x1 + x1 is not null);
  EXPECT_SQL_TOO!((x1 + x1 is not null) + x1 == x2);
  EXPECT_SQL_TOO!(x1 + x1 is not null + x1 == x1);
  EXPECT_SQL_TOO!(x1 + null is null);
  EXPECT_SQL_TOO!(null + x1 is null);
  EXPECT_SQL_TOO!(null * x1 is null);
  EXPECT_SQL_TOO!(null * x0 is null);
  EXPECT_SQL_TOO!(x0 * null * x0 is null);
  EXPECT_SQL_TOO!(null > x0 is null);
  EXPECT_SQL_TOO!(null >= x1 is null);
  EXPECT_SQL_TOO!(null < x2 is null);
  EXPECT_SQL_TOO!(null <= x3 is null);
  EXPECT_SQL_TOO!(x1 + null == x3 is null);
  EXPECT_SQL_TOO!(x1 + null != x3 is null);
  EXPECT_SQL_TOO!(x1 + null <> x3 is null);
  EXPECT_SQL_TOO!(x1 = temp_null * x1 + x1 is temp_null);
  EXPECT_SQL_TOO!(x1 = temp_null * -x1 + x1 is temp_null);
  EXPECT_SQL_TOO!(x1 + temp_null = x3 - x1 = x1 is temp_null);
  EXPECT_SQL_TOO!(x1 + temp_null = x3 - x1 <> x0 is temp_null);
  EXPECT_SQL_TOO!(x1 + temp_null == x3 - x1 <> x0 is temp_null);
  EXPECT_SQL_TOO!(x1 + temp_null = x3 - x1 <> temp1 is temp_null);
  EXPECT_SQL_TOO!(x1 + temp_null == x3 - x1 <> temp1 is temp_null);
  EXPECT_SQL_TOO!((temp_null is not temp_null) == x0);
  EXPECT_SQL_TOO!(x1 + x1 is not temp_null);
  EXPECT_SQL_TOO!(temp_null == x3 is temp_null);
  EXPECT_SQL_TOO!(((temp_null == x3) is temp_null) == x1);
  EXPECT_SQL_TOO!((temp_null == x3 is temp_null) == x1);
  EXPECT_SQL_TOO!((temp_null == x3 is temp_null) == x1);
  EXPECT_SQL_TOO!((temp_null == x3 is temp_null) is not temp_null);
  EXPECT_SQL_TOO!((x1 + temp_null == x3 is not temp_null) == x0);
  EXPECT_SQL_TOO!((x1 + temp_null = x3 - x1 <> x0 is not temp_null) == x0);
  EXPECT_SQL_TOO!((x1 + temp_null == x3 - x1 <> x0 is not temp_null) == x0);
  EXPECT_SQL_TOO!((x1 + temp_null = x3 - x1 <> temp1 is not temp_null) == x0);

  temp0 := nullable(25);

  EXPECT_SQL_TOO!(x2 * x3 is x4 + x2);
  EXPECT_SQL_TOO!(x2 * x3 is x4 + x2);
  temp1 := nullable(10);
  EXPECT_SQL_TOO!(temp1 - x4 * x2 is x2);
  EXPECT_SQL_TOO!(temp0 % x3 / x2 is x0);
  EXPECT_SQL_TOO!(temp0 / x5 % x2 is x1);
  EXPECT_SQL_TOO!(temp0 * x5 % x2 is x1);
  EXPECT_SQL_TOO!(temp0 * x5 % x4 % x2 is x1);
  temp1 := nullable(24);
  EXPECT_SQL_TOO!(temp0 - x5 % x2 is temp1);
  temp1 := nullable(15);
  EXPECT_SQL_TOO!(temp1 % x3 - x2 is -x2);
  temp2 := nullable(30);
  let temp3 := nullable(13);
  EXPECT_SQL_TOO!(temp1 - temp2 % x4 is temp3);
  EXPECT_SQL_TOO!(temp1 - temp2 / x2 is x0);
  EXPECT_SQL_TOO!(temp1 / x5 - x3 is x0);
  temp3 := nullable(72);
  EXPECT_SQL_TOO!(temp1 * x5 - x3 is temp3);
  temp3 := nullable(22);
  EXPECT_SQL_TOO!(x5 * x5 - x3 is temp3);
  temp3 := 26;
  EXPECT_SQL_TOO!(temp0 + x5 % x2 is temp3);
  EXPECT_SQL_TOO!(temp1 % x3 + x2 is x2);
  temp1 := nullable(17);
  temp2 := nullable(30);
  temp3 := nullable(15);
  EXPECT_SQL_TOO!(temp3 + temp2 % x4 is temp1);
  temp1 := nullable(30);
  EXPECT_SQL_TOO!(temp3 + temp1 / x2 is temp1);
  EXPECT_SQL_TOO!(temp3 / x5 + x3 is x6);
  temp1 := nullable(78);
  EXPECT_SQL_TOO!(temp3 * x5 + x3 is temp1);
  temp1 := nullable(28);
  EXPECT_SQL_TOO!(x5 * x5 + x3 is temp1);
  temp1 := nullable(20);
  temp2 := nullable(12);
  EXPECT_SQL_TOO!(x5 * temp2 / x3 is temp1);
  EXPECT_SQL_TOO!(x5 * temp2 / x3 % x7 is x6);
  temp1 := nullable(21);
  temp2 := nullable(12);
  EXPECT_SQL_TOO!(x9 % temp2 / x3 * x7 is temp1);

  EXPECT_SQL_TOO!(x1 is x1 == x1 is x1 == x1);
  EXPECT_SQL_TOO!(x5 > x6 is x2 < x1);
  EXPECT_SQL_TOO!(x5 <= x6 is x2 > x1);
  EXPECT_SQL_TOO!(x5 == x5 is x2 > x1);
  EXPECT_SQL_TOO!(null is null);
  EXPECT_SQL_TOO!(temp_null == x0 is null);
  EXPECT_SQL_TOO!(null is null == x1 != x0);
  EXPECT_SQL_TOO!(null is null = x1 <> x0);
  EXPECT_SQL_TOO!(temp_null == temp_null is null);
  EXPECT_SQL_TOO!(null is (temp_null == x0));
  EXPECT_SQL_TOO!(null is not null == x0);
  EXPECT_SQL_TOO!((null is not null) == x0);
  EXPECT_SQL_TOO!(x5 > x2 is not null);
  EXPECT_SQL_TOO!(null is not x2 < x3);
  EXPECT_SQL_TOO!(null is null + x1);
  EXPECT_SQL_TOO!(null is x1 + null);
  EXPECT_SQL_TOO!(null is x1 << null);

  let one := nullable("1");
  let two := nullable("2");
  EXPECT_SQL_TOO!(one is two == x0);
  EXPECT_SQL_TOO!(one is null == x0);
  EXPECT_SQL_TOO!(null is one == x0);

  -- Test in
  EXPECT_SQL_TOO!(x3 in (x1, x2) == x0);
  EXPECT_SQL_TOO!(x3 + x2 in (x1, x5));
  EXPECT_SQL_TOO!(x3 / x3 in (x1, x2));
  EXPECT_SQL_TOO!(x3 / x3 in (x1, x2) in (x1));
  EXPECT_SQL_TOO!(x1 in (null, x1));
  EXPECT!(not (x1 in (null, x5))); -- known difference between CQL and SQLite in
  EXPECT_SQL_TOO!(null is (null in (x1)));

  -- Test not in
  EXPECT_SQL_TOO!(x1 not in (x1, x2) == x0);
  EXPECT_SQL_TOO!(x3 not in (x1, x2) == x1);
  EXPECT_SQL_TOO!(x3 + x2 not in (x1, x2));
  EXPECT_SQL_TOO!(x3 / x1 not in (x1, x2));
  EXPECT_SQL_TOO!(x3 / x1 not in (x1, x2) in (x1));
  EXPECT_SQL_TOO!(not (x1 not in (null, x1)));
  EXPECT!(x1 not in (null, x5)); -- known difference between CQL and SQLite in
  EXPECT_SQL_TOO!(null is (null not in (x1)));

  declare x text;
  x := null;
  EXPECT_SQL_TOO!((x in ("foo", "goo")) is null);
  EXPECT_SQL_TOO!((x not in ("foo", "goo")) is null);

  EXPECT_SQL_TOO!(x3 + x3 and x5);
  EXPECT_SQL_TOO!((x3 + x3 and x0) == x0);
  EXPECT_SQL_TOO!((null and x1) is null);
  EXPECT_SQL_TOO!((null and x1 = temp_null) is null);
  EXPECT_SQL_TOO!(not (null and x1 is null));
  EXPECT_SQL_TOO!((null and x0) == x0);
  EXPECT_SQL_TOO!(not (null and x0));
  EXPECT_SQL_TOO!(x1 and x0 == x0);
  EXPECT_SQL_TOO!(x1 and x0 = x0);
  EXPECT_SQL_TOO!(x1 and x1 != x0);
  EXPECT_SQL_TOO!(x1 and x1 <> x0);
  EXPECT_SQL_TOO!(x5 is x5 and x2 is x2);
  EXPECT_SQL_TOO!(x5 is not null and x2 is x2);
  EXPECT_SQL_TOO!(x5 is not null and x2 is x2);
  EXPECT_SQL_TOO!(x5 and x0 + x1);
  EXPECT_SQL_TOO!(x5 and x0 * x1 + x1);
  EXPECT_SQL_TOO!(x5 and x0 >> x4 >= -x1);
  temp1 := nullable(12);
  EXPECT_SQL_TOO!(x5 and x0 | x4 & temp1);
  EXPECT_SQL_TOO!(x5 and x6 / x3);
  temp1 := nullable(25);
  EXPECT_SQL_TOO!((x5 and temp1 % x5) == x0);
  EXPECT_SQL_TOO!(x5 and x0 in (x0));

  EXPECT_SQL_TOO!((x0 or x1 or x1 and x0 or x0) != ((((x0 or x1) or x1) and x0) or x0));
  EXPECT_SQL_TOO!((x1 or x1 and x0 and x1 and x0) != ((((x1 or x1) and x0) and x1) and x0));
  EXPECT_SQL_TOO!((x0 or x1 or x1 and x0 and x1) != ((((x0 or x1) or x1) and x0) and x1));
  EXPECT_SQL_TOO!((x1 or x1 or x1 and x0 and x0) != ((((x1 or x1) or x1) and x0) and x0));
  EXPECT_SQL_TOO!((x1 or x1 or x1 and x0 or x0) != ((((x1 or x1) or x1) and x0) or x0));
  EXPECT_SQL_TOO!((x1 and x1 and x1 or x1 and x0) != ((((x1 and x1) and x1) or x1) and x0));
  EXPECT_SQL_TOO!((x1 or x0 and x0 and x1 or x0) != ((((x1 or x0) and x0) and x1) or x0));
  EXPECT_SQL_TOO!((x1 and x1 or x0 and x0 and x1) != ((((x1 and x1) or x0) and x0) and x1));
  EXPECT_SQL_TOO!((x1 or x0 or x0 or x0 and x0) != ((((x1 or x0) or x0) or x0) and x0));
  EXPECT_SQL_TOO!((x1 or x0 and x0 or x1 and x0) != ((((x1 or x0) and x0) or x1) and x0));
  EXPECT_SQL_TOO!((x1 or x1 and x1 and x1 and x0) != ((((x1 or x1) and x1) and x1) and x0));
  EXPECT_SQL_TOO!((x0 and x0 or x1 or x0 and x0) != ((((x0 and x0) or x1) or x0) and x0));
  EXPECT_SQL_TOO!((x0 or x1 or x1 and x0 and x0) != ((((x0 or x1) or x1) and x0) and x0));
  EXPECT_SQL_TOO!((x1 and x1 and x1 or x0 and x0) != ((((x1 and x1) and x1) or x0) and x0));
  EXPECT_SQL_TOO!((x1 or x1 or x1 and x0 and x1) != ((((x1 or x1) or x1) and x0) and x1));
  EXPECT_SQL_TOO!((x1 or x0 or x0 or x0 and x0) != ((((x1 or x0) or x0) or x0) and x0));
end);

[[vault_sensitive]]
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
    false, 0, 0, 0.0, "0", "0" ~blob~,
    true, 1, 1, 1.1, "1", "1" ~blob~
  );

  select * from all_types_encoded_table;
end;

[[vault_sensitive=(context, (b0, i0, l0, d0, s0, bl0, b1, i1, l1, d1, s1, bl1))]]
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
    false, 0, 0, 0.0, "0", cast("0" as blob),
    true, 1, 1, 1.1, "1", cast("1" as blob), "cxt"
  );

  select * from all_types_encoded_with_context_table;
end;

[[vault_sensitive]]
proc load_encoded_cursor()
begin
  cursor C for select * from all_types_encoded_table;
  fetch C;
  out C;
end;

[[vault_sensitive]]
proc out_union_dml()
begin
  declare x cursor for select * from all_types_encoded_table;
  fetch x;
  out union x;
end;

[[vault_sensitive]]
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

[[vault_sensitive]]
proc load_decoded_out_union()
begin
  cursor C for call out_union_dml();
  fetch C;
  out C;
end;

[[vault_sensitive]]
proc load_decoded_multi_out_union()
begin
  cursor C for call out_union_dml();
  fetch C;
  out union C;

  declare C1 cursor for call out_union_not_dml();
  fetch C1;
  out union C1;
end;

[[vault_sensitive=(z, (y))]]
proc out_union_dml_with_encode_context()
begin
  create table some_type_encoded_table(x int, y text @sensitive, z text);
  insert into some_type_encoded_table using 66 x, 'abc' y, 'xyz' z;
  declare x cursor for select * from some_type_encoded_table;
  fetch x;
  out union x;
end;

TEST!(decoded_value_with_encode_context,
begin
  cursor C for call out_union_dml_with_encode_context();
  fetch C;

  EXPECT_EQ!(C.x, 66);
  EXPECT_EQ!(C.y, 'abc');
  EXPECT_EQ!(C.z, 'xyz');
end);

TEST!(encoded_values,
begin
  cursor C for call load_encoded_table();
  fetch C;
  EXPECT_EQ!(C.b0, 0);
  EXPECT_EQ!(C.i0, 0);
  EXPECT_EQ!(C.l0, 0);
  EXPECT_EQ!(C.d0, 0.0);
  EXPECT_EQ!(C.s0, "0");
  EXPECT_EQ!(string_from_blob(C.bl0), "0");
  EXPECT_EQ!(C.b1, 1);
  EXPECT_EQ!(C.i1, 1);
  EXPECT_EQ!(C.l1, 1);
  EXPECT_EQ!(C.d1, 1.1);
  EXPECT_EQ!(C.s1, "1");
  EXPECT_EQ!(string_from_blob(C.bl1), "1");

  declare C1 cursor for call out_union_dml();
  fetch C1;
  EXPECT_EQ!(cql_cursor_diff_val(C, C1), null);

  declare C2 cursor for call out_union_not_dml();
  fetch C2;
  EXPECT_EQ!(cql_cursor_diff_val(C, C2), null);

  declare C3 cursor fetch from call load_decoded_out_union();
  EXPECT_EQ!(cql_cursor_diff_val(C, C3), null);
end);

TEST!(encoded_null_values,
begin
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

  EXPECT_EQ!(C.b0, null);
  EXPECT_EQ!(C.i0, null);
  EXPECT_EQ!(C.l0, null);
  EXPECT_EQ!(C.d0, null);
  EXPECT_EQ!(C.s0, null);
  EXPECT_EQ!(C.bl0, null);
end);

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
begin
  let s := set_create();
  declare D cursor for call emit_object_result_set(s);
  fetch D;
  EXPECT!(D);
  EXPECT_EQ!(D.o, s);

  fetch D;
  EXPECT!(D);
  EXPECT_EQ!(D.o, null);

  declare E cursor for call emit_object_result_set_not_null(s);
  fetch E;
  EXPECT!(E);
  EXPECT_EQ!(E.o, s);
end);

[[vault_sensitive=(y)]]
proc load_some_encoded_field()
begin
  create table some_encoded_field_table(x int, y text @sensitive);
  insert into some_encoded_field_table using 66 x, 'bogus' y;

  cursor C for select * from some_encoded_field_table;
  fetch C;
  out C;
end;

TEST!(read_partially_vault_cursor,
begin
  cursor C fetch from call load_some_encoded_field();

  EXPECT_EQ!(C.x, 66);
  EXPECT_EQ!(C.y, 'bogus');
end);

[[vault_sensitive=(z, (y))]]
proc load_some_encoded_field_with_encode_context()
begin
  create table some_encoded_field_context_table(x int, y text @sensitive, z text);
  insert into some_encoded_field_context_table using 66 x, 'bogus' y, 'context' z;

  cursor C for select * from some_encoded_field_context_table;
  fetch C;
  out C;
end;

TEST!(read_partially_encode_with_encode_context_cursor,
begin
  cursor C fetch from call load_some_encoded_field_with_encode_context();

  EXPECT_EQ!(C.x, 66);
  EXPECT_EQ!(C.y, 'bogus');
  EXPECT_EQ!(C.z, 'context');
end);

[[emit_setters]]
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

-- This helper proc will be called by the client producing its one-row result
-- it has no DB pointer and that exercises and important case in the auto drop logic
-- where info.db is null.  There can be no auto drop tables here.
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
  for i < stop; i += 1;
  begin
    fetch C(v, vsq, junk) from values (i, i * i, printf("%d", i));
    out union C;
  end;

  -- if the start was -1 then force an error, this ensures full cleanup
  -- do this after we have produced rows to make it hard
  if start == -1 then
    drop table dummy_table;
  end if;
end;

-- we need this helper to get a row set out with type "object", all it does is call the above proc
-- we just need the cast that it does really, but there's no way to code that cast in CQL.

declare proc some_integers_fetch(out rs object!, start int!, stop int!) using transaction;

-- these are the helper functions we will be using to read the row set, they are defined and registered elsewhere
-- See the "call cql_init_extensions();" above for registration.

declare select function rscount(rs long) long;
declare select function rscol(rs long, row int!, col int!) long;

-- This test is is going to create a row set using a stored proc, then
-- using the helper proc some_integers_fetch() get access to the result set pointer
-- rather than the sqlite statement.  Then it iterates over the result set as though
-- that result set were a virtual table.  The point of all of this is to test
-- the virtual-table-like construct that we have created and in so doing
-- test the runtime binding facilities needed by ptr(x)

TEST!(row_set_reading,
begin
  declare start, stop, cur int!;
  start := 10;
  stop := 20;
  declare rs object!;
  some_integers_fetch(rs, start, stop);

  -- use a nullable version too to exercise both kinds of binding
  declare rs1 object;
  rs1 := rs;

  cursor C for
    with recursive
    C(i) as (select 0 i union all select i + 1 i from C limit rscount(ptr(rs))),
    V(v,vsq) as (select rscol(ptr(rs), C.i, 0), rscol(ptr(rs1), C.i, 1) from C)
    select * from V;

  cur := start;
  loop fetch C
  begin
    EXPECT_EQ!(C.v, cur);
    EXPECT_EQ!(C.v * C.v, C.vsq);
    cur := cur + 1;
  end;
end);

TEST!(row_set_reading_language_support,
begin
  declare cur int!;
  cur := 7;
  cursor C for call some_integers(7, 12);
  loop fetch C
  begin
    EXPECT_EQ!(C.v, cur);
    EXPECT_EQ!(c.vsq, cur * cur);
    cur := cur + 1;
  end;
end);

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

TEST!(read_all_types_row_set,
begin
  cursor C for call all_types_union();
  fetch C;
  EXPECT!(C);

  EXPECT_EQ!(C.b0, null);
  EXPECT_EQ!(C.i0, null);
  EXPECT_EQ!(C.l0, null);
  EXPECT_EQ!(C.d0, null);
  EXPECT_EQ!(C.s0, null);
  EXPECT_EQ!(C.bl0, null);
  EXPECT_EQ!(C.b1, 0);
  EXPECT_EQ!(C.i1, 0);
  EXPECT_EQ!(C.l1, 0);
  EXPECT_EQ!(C.d1, 0);
  EXPECT_EQ!(C.s1, "s1_0");
  EXPECT_EQ!(C.bl1, blob_from_string("bl1_0"));

  fetch C;
  EXPECT!(C);

  EXPECT_EQ!(C.b0, 1);
  EXPECT_EQ!(C.i0, 1);
  EXPECT_EQ!(C.l0, 1);
  EXPECT_EQ!(C.d0, 1);
  EXPECT_EQ!(C.s0, "s0_1");
  EXPECT_EQ!(C.bl0, blob_from_string("bl0_1"));
  EXPECT_EQ!(C.b1, 1);
  EXPECT_EQ!(C.i1, 1);
  EXPECT_EQ!(C.l1, 1);
  EXPECT_EQ!(C.d1, 1);
  EXPECT_EQ!(C.s1, "s1_1");
  EXPECT_EQ!(C.bl1, blob_from_string("bl1_1"));

  fetch C;
  EXPECT!(not C);
end);

TEST!(read_all_types_auto_fetcher,
begin
  -- we want to force the auto fetcher to be called, so we capture the result set
  -- rather than cursor over it.  Then we cursor over the captured result set

  let result_set := load_all_types_table();
  cursor C for result_set;
  fetch C;
  EXPECT!(C);

  EXPECT_EQ!(C.b0, null);
  EXPECT_EQ!(C.i0, null);
  EXPECT_EQ!(C.l0, null);
  EXPECT_EQ!(C.d0, null);
  EXPECT_EQ!(C.s0, null);
  EXPECT_EQ!(C.bl0, null);
  EXPECT_EQ!(C.b1, 0);
  EXPECT_EQ!(C.i1, 0);
  EXPECT_EQ!(C.l1, 0);
  EXPECT_EQ!(C.d1, 0);
  EXPECT_EQ!(C.s1, "s1_0");
  EXPECT_EQ!(string_from_blob(C.bl1), "bl1_0");

  fetch C;
  EXPECT!(C);

  EXPECT_EQ!(C.b0, 1);
  EXPECT_EQ!(C.i0, 1);
  EXPECT_EQ!(C.l0, 1);
  EXPECT_EQ!(C.d0, 1);
  EXPECT_EQ!(C.s0, "s0_1");
  EXPECT_EQ!(string_from_blob(C.bl0), "bl0_1");
  EXPECT_EQ!(C.b1, 1);
  EXPECT_EQ!(C.i1, 1);
  EXPECT_EQ!(C.l1, 1);
  EXPECT_EQ!(C.d1, 1);
  EXPECT_EQ!(C.s1, "s1_1");
  EXPECT_EQ!(string_from_blob(C.bl1), "bl1_1");
  EXPECT_EQ!(cql_get_blob_size(C.bl1), 5);

  fetch C;
  EXPECT!(not C);
end);

TEST!(row_set_via_union_failed,
begin
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
end);

TEST!(boxing_cursors,
begin
  let i := 0;
  for i < 5; i += 1;
  begin
    cursor C for
      with data(x,y) as (values (1,2), (3,4), (5,6))
      select * from data;

    declare box object<C cursor>;
    set box from cursor C;
    declare D cursor for box;

    fetch C;
    EXPECT_EQ!(C.x, 1);
    EXPECT_EQ!(C.y, 2);

    fetch D;
    -- C did not change
    EXPECT_EQ!(C.x, 1);
    EXPECT_EQ!(C.y, 2);
    EXPECT_EQ!(D.x, 3);
    EXPECT_EQ!(D.y, 4);

    fetch C;
    -- C advanced D values held
    EXPECT_EQ!(C.x, 5);
    EXPECT_EQ!(C.y, 6);
    EXPECT_EQ!(D.x, 3);
    EXPECT_EQ!(D.y, 4);
  end;
end);

proc a_few_rows()
begin
  with data(x,y) as (values (1,2), (3,4), (5,6))
  select * from data;
end;

TEST!(boxing_from_call,
begin
  let i := 0;
  for i < 5; i += 1;
  begin
    cursor C for call a_few_rows();

    declare box object<C cursor>;
    set box from cursor C;
    declare D cursor for box;

    fetch C;
    EXPECT_EQ!(C.x, 1);
    EXPECT_EQ!(C.y, 2);

    fetch D;
    -- C did not change
    EXPECT_EQ!(C.x, 1);
    EXPECT_EQ!(C.y, 2);
    EXPECT_EQ!(D.x, 3);
    EXPECT_EQ!(D.y, 4);

    fetch C;
    -- C advanced D values held
    EXPECT_EQ!(C.x, 5);
    EXPECT_EQ!(C.y, 6);
    EXPECT_EQ!(D.x, 3);
    EXPECT_EQ!(D.y, 4);
  end;
end);

@enforce_normal cast;

TEST!(numeric_casts,
begin
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
  EXPECT_EQ!(b, 1);
  i := cast(1.9 as int);
  EXPECT_EQ!(i, 1);
  l := cast(12.9 as long);
  EXPECT_EQ!(l, 12);
  r := cast(12 as real);
  EXPECT_EQ!(r, 12.0);

  -- null cases
  EXPECT_EQ!(cast(b0 as bool), null);
  EXPECT_EQ!(cast(b0 as int), null);
  EXPECT_EQ!(cast(b0 as long), null);
  EXPECT_EQ!(cast(b0 as real), null);

  -- force conversion (nullable)
  declare x real;
  x := 7.5;
  b0 := cast(x as bool);
  EXPECT_EQ!(b0, 1);
  x := 1.9;
  i0 := cast(x as int);
  EXPECT_EQ!(i0, 1);
  x := 12.9;
  l0 := cast(x as long);
  EXPECT_EQ!(l0, 12);
  x := 12.0;
  r0 := cast(x as real);
  EXPECT_EQ!(r0, 12.0);
  l := 12;
  r0 := cast(l as real);
  EXPECT_EQ!(r0, 12.0);
end);

@enforce_strict cast;

proc dummy(seed int!, i int!, r real!, b bool!)
begin
  EXPECT_EQ!(seed, i);
  EXPECT_EQ!(seed, r);
  EXPECT_EQ!(not seed, not b);
end;

TEST!(cursor_args,
begin
  declare args cursor like dummy arguments;
  fetch args() from values() @dummy_seed(12);
  dummy(from args);
end);

declare proc cql_exec_internal(sql text!) using TRANSACTION;
create table something(id int, name text, data blob);

TEST!(exec_internal,
begin
  cql_exec_internal("create table something(id integer, name text, data blob);");
  declare bl1 blob;
  bl1 := blob_from_string('z');
  declare bl2 blob;
  bl2 := blob_from_string('w');
  insert into something using 1 id, 'x' name, bl1 data;
  insert into something using 2 id, 'y' name, bl2 data;
  cursor C for select * from something;
  declare D cursor like C;
  fetch C;
  fetch D using 1 id, 'x' name, bl1 data;
  EXPECT_EQ!(cql_cursor_diff_val(C,D), null);
  fetch C;
  fetch D using 2 id, 'y' name, bl2 data;
  EXPECT_EQ!(cql_cursor_diff_val(C,D), null);
end);

TEST!(const_folding1,
begin
  EXPECT_EQ!(const(1 + 1), 2);
  EXPECT_EQ!(const(1.0 + 1), 2.0);
  EXPECT_EQ!(const(1.0 + 1), floats.two);
  EXPECT_EQ!(const(floats.one + 1), 2.0);
  EXPECT_EQ!(const(floats.one + 1), floats.two);
  EXPECT_EQ!(const(1 + 1L), 2L);
  EXPECT_EQ!(const(1 + (1==1) ), 2);
  EXPECT_EQ!(const(1.0 + 1L), 2.0);
  EXPECT_EQ!(const(1.0 + (1 == 1)), 2.0);
  EXPECT_EQ!(const((1==1) + 1L), 2L);

  EXPECT_EQ!(2, const(1 + 1));
  EXPECT_EQ!(2.0, const(1.0 + 1));
  EXPECT_EQ!(2L, const(1 + 1L));
  EXPECT_EQ!(2, const(1 + (1==1)));

  EXPECT_EQ!(const(1 - 1), 0);
  EXPECT_EQ!(const(1.0 - 1), 0.0);
  EXPECT_EQ!(const(1 - 1L), 0L);
  EXPECT_EQ!(const(1 - (1==1)), 0);

  EXPECT_EQ!(const(3 * 2), 6);
  EXPECT_EQ!(const(3.0 * 2), 6.0);
  EXPECT_EQ!(const(3 * 2L), 6L);
  EXPECT_EQ!(const(3 * (1==1)), 3);

  EXPECT_EQ!(const(3 / 1), 3);
  EXPECT_EQ!(const(3.0 / 1), 3.0);
  EXPECT_EQ!(const(3 / 1L), 3L);
  EXPECT_EQ!(const(3 / (1==1)), 3);

  EXPECT_EQ!(const(3 % 1), 0);
  EXPECT_EQ!(const(3 % 1L), 0L);
  EXPECT_EQ!(const(3 % (1==1)), 0);

  EXPECT_EQ!(const(8 | 1), 9);
  EXPECT_EQ!(const(8 | 1L), 9L);
  EXPECT_EQ!(const(8 | (1==1)), 9);

  EXPECT_EQ!(const(7 & 4), 4);
  EXPECT_EQ!(const(7 & 4L), 4L);
  EXPECT_EQ!(const(7 & (1==1)), 1);

  EXPECT_EQ!(const(16 << 1), 32);
  EXPECT_EQ!(const(16 << 1L), 32L);
  EXPECT_EQ!(const(16 << (1==1)), 32);

  EXPECT_EQ!(const(16 >> 1), 8);
  EXPECT_EQ!(const(16 >> 1L), 8L);
  EXPECT_EQ!(const(16 >> (1==1)), 8);

  EXPECT_EQ!(const(null), null);

  EXPECT_EQ!(const( 1 or 1 / 0), 1);
  EXPECT_EQ!(const( 0 or null), null);
  EXPECT_EQ!(const( 0 or 0), 0);
  EXPECT_EQ!(const( 0 or 1), 1);
  EXPECT_EQ!(const( null or null), null);
  EXPECT_EQ!(const( null or 0), null);
  EXPECT_EQ!(const( null or 1), 1);

  EXPECT_EQ!(const( 0 and 1 / 0), 0);
  EXPECT_EQ!(const( 1 and null), null);
  EXPECT_EQ!(const( 1 and 0), 0);
  EXPECT_EQ!(const( 1 and 1), 1);
  EXPECT_EQ!(const( null and null), null);
  EXPECT_EQ!(const( null and 0), 0);
  EXPECT_EQ!(const( null and 1), null);
end);

TEST!(const_folding2,
begin
/* note that in the below we often do not use EXPECT_EQ because the point of the
 * relevant tests is to test the const equality or inequality.  So the comparisons
 * need to be part of the const expression itself.
 */

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
end);

TEST!(const_folding3,
begin
  EXPECT_EQ!((null + null), null);
  EXPECT_EQ!((null - null), null);
  EXPECT_EQ!((null * null), null);
  EXPECT_EQ!((null / null), null);
  EXPECT_EQ!((null % null), null);
  EXPECT_EQ!((null | null), null);
  EXPECT_EQ!((null & null), null);
  EXPECT_EQ!((null << null), null);
  EXPECT_EQ!((null >> null), null);

  EXPECT_EQ!(const(null + null), null);
  EXPECT_EQ!(const(null - null), null);
  EXPECT_EQ!(const(null * null), null);
  EXPECT_EQ!(const(null / null), null);
  EXPECT_EQ!(const(null % null), null);
  EXPECT_EQ!(const(null | null), null);
  EXPECT_EQ!(const(null & null), null);
  EXPECT_EQ!(const(null << null), null);
  EXPECT_EQ!(const(null >> null), null);

  EXPECT!(const((null + null) is null));
  EXPECT!(const((null - null) is null));EXPECT!(const((null * null) is null));
  EXPECT!(const((null / null) is null));
  EXPECT!(const((null % null) is null));
  EXPECT!(const((null | null) is null));
  EXPECT!(const((null & null) is null));
  EXPECT!(const((null << null) is null));
  EXPECT!(const((null >> null) is null));

  EXPECT_EQ!(const(null is not null), 0);
  EXPECT!(const(null is not 1));
  EXPECT!(const((1 or null) is not null));

  EXPECT!(const(1 is 1));
  EXPECT!(const(1L is 1L));
  EXPECT!(const(1.0 is 1.0));
  EXPECT!(const((1==1) is (2==2)));

  EXPECT_EQ!(const(cast(3.2 as int)), 3);
  EXPECT_EQ!(const(cast(3.2 as long)), 3L);
  EXPECT_EQ!(const(cast(3.2 as bool)), 1);
  EXPECT_EQ!(const(cast(0.0 as bool)), 0);
  EXPECT_EQ!(const(cast(null + 0 as bool)), null);
  EXPECT_EQ!(const(cast(3L as real)), 3.0);
  EXPECT_EQ!(const(cast(3L as int)), 3);
  EXPECT_EQ!(const(cast(3L as bool)), 1);
  EXPECT_EQ!(const(cast(0L as bool)), 0);

  EXPECT_EQ!(const(not 0), 1);
  EXPECT_EQ!(const(not 1), 0);
  EXPECT_EQ!(const(not 2), 0);
  EXPECT_EQ!(const(not 0L), 1);
  EXPECT_EQ!(const(not 1L), 0);
  EXPECT_EQ!(const(not 2L), 0);
  EXPECT_EQ!(const(not 2.0), 0);
  EXPECT_EQ!(const(not 0.0), 1);
  EXPECT_EQ!(const(not not 2), 1);
  EXPECT_EQ!(const(not null), null);

  EXPECT_EQ!(const(~0), -1);
  EXPECT_EQ!(const(~0L), -1L);
  EXPECT_EQ!(const(~ ~0L), 0L);
  EXPECT_EQ!(const(~null), null);
  EXPECT_EQ!(const(~(0==0)), -2);
  EXPECT_EQ!(const(~(0==1)), -1);

  EXPECT_EQ!(const(-1), -1);
  EXPECT_EQ!(const(-2), -2);
  EXPECT_EQ!(const(-1.0), -1.0);
  EXPECT_EQ!(const(-2.0), -2.0);
  EXPECT_EQ!(const((0 + -2)), -2);
  EXPECT_EQ!(const(-(1 + 1)), -2);
  EXPECT_EQ!(const(-1L), -1L);
  EXPECT_EQ!(const(- -1L), 1L);
  EXPECT_EQ!(const(-null), null);
  EXPECT_EQ!(const(-(0==0)), -1);
  EXPECT_EQ!(const(-(0==1)), 0);

end);

TEST!(const_folding4,
begin
  -- IIF gets rewritten to case/when so we use that here for convenience
  EXPECT_EQ!(const(iif(1, 3, 5)), 3);
  EXPECT_EQ!(const(iif(0, 3, 5)), 5);
  EXPECT_EQ!(const(iif(1L, 3, 5)), 3);
  EXPECT_EQ!(const(iif(0L, 3, 5)), 5);
  EXPECT_EQ!(const(iif(1.0, 3, 5)), 3);
  EXPECT_EQ!(const(iif(0.0, 3, 5)), 5);
  EXPECT_EQ!(const(iif((1==1), 3, 5)), 3);
  EXPECT_EQ!(const(iif((1==0), 3, 5)), 5);

  EXPECT_EQ!(const(case 1 when 2 then 20 else 10 end), 10);
  EXPECT_EQ!(const(case 2 when 2 then 20 else 10 end), 20);
  EXPECT_EQ!(const(case 2 when 1 then 10 when 2 then 20 else 40 end), 20);
  EXPECT_EQ!(const(case 1 when 1 then 10 when 2 then 20 else 40 end), 10);
  EXPECT_EQ!(const(case 5 when 1 then 10 when 2 then 20 else 40 end), 40);
  EXPECT_EQ!(const(case null when 1 then 10 when 2 then 20 else 40 end), 40);

  EXPECT_EQ!(const(case 1.0 when 2 then 20 else 10 end), 10);
  EXPECT_EQ!(const(case 2.0 when 2 then 20 else 10 end), 20);
  EXPECT_EQ!(const(case 2.0 when 1 then 10 when 2 then 20 else 40 end), 20);
  EXPECT_EQ!(const(case 1.0 when 1 then 10 when 2 then 20 else 40 end), 10);
  EXPECT_EQ!(const(case 5.0 when 1 then 10 when 2 then 20 else 40 end), 40);

  EXPECT_EQ!(const(case 1L when 2 then 20 else 10 end), 10);
  EXPECT_EQ!(const(case 2L when 2 then 20 else 10 end), 20);
  EXPECT_EQ!(const(case 2L when 1 then 10 when 2 then 20 else 40 end), 20);
  EXPECT_EQ!(const(case 1L when 1 then 10 when 2 then 20 else 40 end), 10);
  EXPECT_EQ!(const(case 5L when 1 then 10 when 2 then 20 else 40 end), 40);

  EXPECT_EQ!(const(case (1==1) when (1==1) then 10 else 20 end), 10);
  EXPECT_EQ!(const(case (1==0) when (1==1) then 10 else 20 end), 20);
  EXPECT_EQ!(const(case (1==1) when (0==1) then 10 else 20 end), 20);
  EXPECT_EQ!(const(case (1==0) when (0==1) then 10 else 20 end), 10);

  EXPECT_EQ!(const(case 5L when 1 then 10 when 2 then 20 end), null);

  EXPECT_EQ!(const(0x10), 16);
  EXPECT_EQ!(const(0x10 + 0xf), 31);
  EXPECT_EQ!(const(0x100100100), 0x100100100);
  EXPECT_EQ!(const(0x100100100L), 0x100100100);
  EXPECT_EQ!(const(0x100100100), 0x100100100L);
  EXPECT_EQ!(const(0x100100100L), 0x100100100L);
end);

TEST!(long_literals,
begin
  declare x long!;
  declare z long;

  x := 1L;
  EXPECT_EQ!(x, 1);

  x := 10000000000;
  EXPECT_EQ!(x, 10000000000);
  EXPECT_NE!(x, const(cast(10000000000L as int)));
  EXPECT!(x > 0x7fffffff);

  x := 10000000000L;
  EXPECT_EQ!(x, 10000000000L);
  EXPECT_NE!(x, const(cast(10000000000L as int)));
  EXPECT!(x > 0x7fffffff);

  x := 0x1000000000L;
  EXPECT_EQ!(x, 0x1000000000L);
  EXPECT_NE!(x, const(cast(0x10000000000L as int)));
  EXPECT!(x > 0x7fffffff);

  x := 0x1000000000;
  EXPECT_EQ!(x, 0x1000000000L);
  EXPECT_NE!(x, const(cast(0x10000000000L as int)));
  EXPECT!(x > 0x7fffffff);

  x := const(0x1000000000);
  EXPECT_EQ!(x, 0x1000000000L);
  EXPECT_NE!(x, const(cast(0x1000000000L as int)));
  EXPECT!(x > 0x7fffffff);

  x := 1000L * 1000 * 1000 * 1000;
  EXPECT_EQ!(x, 1000000000000);
  EXPECT_NE!(x, const(cast(1000000000000 as int)));
  x := const(1000L * 1000 * 1000 * 1000);

  z := 1L;
  EXPECT_EQ!(z, 1);

  z := 10000000000;
  EXPECT_EQ!(z, 10000000000);
  EXPECT_NE!(z, const(cast(10000000000L as int)));
  EXPECT!(z > 0x7fffffff);

  z := 10000000000L;
  EXPECT_EQ!(z, 10000000000L);
  EXPECT_NE!(z, const(cast(10000000000L as int)));
  EXPECT!(z > 0x7fffffff);

  z := 0x1000000000L;
  EXPECT_EQ!(z, 0x1000000000L);
  EXPECT_NE!(z, const(cast(0x1000000000L as int)));
  EXPECT!(z > 0x7fffffff);

  z := 0x1000000000;
  EXPECT_EQ!(z, 0x1000000000L);
  EXPECT_NE!(z, const(cast(0x1000000000L as int)));
  EXPECT!(z > 0x7fffffff);

  z := const(0x1000000000);
  EXPECT_EQ!(z, 0x1000000000L);
  EXPECT_NE!(z, const(cast(0x1000000000L as int)));
  EXPECT!(z > 0x7fffffff);

  z := 1000L * 1000 * 1000 * 1000;
  EXPECT_EQ!(z, 1000000000000);
  EXPECT_NE!(z, const(cast(1000000000000 as int)));
  z := const(1000L * 1000 * 1000 * 1000);
end);

proc no_statement_really(x int)
begin
  if x then
    select 1 x;
  end if;
end;

TEST!(null_statement,
begin
  cursor C for call no_statement_really(0);
  let x := 0;
  loop fetch C
  begin
    x := x + 1;
  end;
  EXPECT_EQ!(x, 0);
end);

TEST!(if_nothing_forms,
begin
  create table t_data (
    id int,
    v int,
    t text);

  declare t1 text;
  t1 := (select t from t_data if nothing then "nothing");
  EXPECT_EQ!(t1, "nothing");

  declare `value one` int;
  set `value one` := (select v from t_data if nothing then -1);
  EXPECT_EQ!(`value one`, -1);

  insert into t_data values(1, 2, null);
  t1 := (select t from t_data if nothing then "nothing");
  EXPECT_EQ!(t1, null);

  set `value one` := (select v from t_data if nothing then -1);
  EXPECT_EQ!(`value one`, 2);

  t1 := (select t from t_data if nothing or null then "still nothing");
  EXPECT_EQ!(t1, "still nothing");

  insert into t_data values(2, null, "x");
  set `value one` := (select v from t_data where id == 2 if nothing or null then -1);
  EXPECT_EQ!(`value one`, -1);

  let caught := 0;
  try
    t1 := (select t from t_data if nothing or null then throw);
  catch
    caught := 1;
  end;

  EXPECT_EQ!(caught, 1);

  try
    t1 := (select t from t_data where 0 if nothing or null then throw);
  catch
    caught := 2;
  end;

  EXPECT_EQ!(caught, 2);

  try
    let id_out := (select id from t_data limit 1 if nothing or null then throw);
  catch
    caught := 3;
  end;

  EXPECT_EQ!(id_out, 1);
  EXPECT_EQ!(caught, 2);

end);

proc simple_select()
begin
  select 1 x;
end;

TEST!(call_in_loop,
begin
  let i := 1;
  for i <= 5; i += 1;
  begin
    cursor C for call simple_select();
    fetch C;
    EXPECT_EQ!(C.x, 1);
  end;
end);

TEST!(call_in_loop_boxed,
begin
  let i := 1;
  for i <= 5; i += 1;
  begin
    cursor C for call simple_select();
    declare box object<C cursor>;
    set box from cursor C;
    declare D cursor for box;
    fetch D;
    EXPECT_EQ!(D.x, 1);
  end;
end);

proc out_union_helper()
begin
  cursor C like select 1 x;
  fetch C using 1 x;
  out union C;
end;

TEST!(call_out_union_in_loop,
begin
  let i := 1;
  for i <= 5; i += 1;
  begin
    cursor C for call out_union_helper();
    fetch C;
    EXPECT_EQ!(C.x, 1);
  end;
end);

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
begin
  cursor C for call simple_select();
  EXPECT_EQ!(@rc, 0);
end);

TEST!(rc_simple_insert_and_select,
begin
  create table simple_rc_table(id int, foo text);

  simple_insert();
  EXPECT_EQ!(@rc, 0);

  select_if_nothing(1);
  EXPECT_EQ!(@rc, 0);

  select_if_nothing(2);
  EXPECT_EQ!(@rc, 0);

  try
    call select_if_nothing_throw(2);
  catch
    EXPECT_NE!(@rc, 0);
  end;
end);

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
begin
  cursor C for call out_union_nil_result();
  fetch C;
  EXPECT!(not C); -- cursor empty but not null

  declare D cursor for call out_union_nil_result_dml();
  fetch D;
  EXPECT!(not D); -- cursor empty but not null
end);

TEST!(nested_rc_values,
begin
  let e0 := @rc;
  EXPECT_EQ!(e0, 0); -- SQLITE_OK
  try
    -- force duplicate table error
    create table foo(id int primary key);
    create table foo(id int primary key);
  catch
    let e1 := @rc;
    EXPECT_EQ!(e1, 1); -- SQLITE_ERROR
    try
      let e2 := @rc;
      EXPECT_EQ!(e2, 1); -- SQLITE_ERROR
      -- force constraint error
      insert into foo using 1 id;
      insert into foo using 1 id;
    catch
      let e3 := @rc;
      EXPECT_EQ!(e3, 19); -- SQLITE_CONSTRAINT
    end;
    let e4 := @rc;
    EXPECT_EQ!(e4, 1); -- back to SQLITE_ERROR
  end;
  let e7 := @rc;
  EXPECT_EQ!(e7, 0); -- back to SQLITE_OK
end);

TEST!(at_proc,
BEGIN
  EXPECT_EQ!(@proc, "test_at_proc");
END);

-- facet helper functions, used by the schema upgrade system
declare facet_data TYPE OBJECT<facet_data>;
declare func cql_facets_create() create facet_data!;
declare func cql_facet_add(facets facet_data, facet text!, crc LONG not null) BOOL not null;
declare func cql_facet_find(facets facet_data, facet text!) LONG not null;

TEST!(facet_helpers,
begin
  let facets := cql_facets_create();

  -- add some facets
  let i := 0;
  for i < 1000; i += 1;
  begin
    EXPECT!(cql_facet_add(facets, printf('fake facet %d', i), i * i));
  end;

  -- all duplicates, all the adds should return false
  i := 0;
  for i < 1000; i += 1;
  begin
    EXPECT!(not cql_facet_add(facets, printf('fake facet %d', i), i * i));
  end;

  -- we should be able to find all of these
  i := 0;
  for i < 1000; i += 1;
  begin
    EXPECT_EQ!(i * i, cql_facet_find(facets, printf('fake facet %d', i)));
  end;

  -- we should be able to find none of these
  i := 0;
  for i < 1000; i += 1;
  begin
    EXPECT_EQ!(-1, cql_facet_find(facets, printf('fake_facet %d', i)));
  end;

  -- NOTE the test infra is counting refs so that if we fail
  -- to clean up the test fails; no expectation is required
end);

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
-- something like t1 + t2 + t3 + t4 + t5 + t6 with no sharing
-- naturally, the reason this is here is because this was once wrong.
TEST!(verify_temp_non_reuse,
begin
  EXPECT_EQ!(f(1) + f(2) + f(4) + f(8) + f(16) + f(32), 63);
  EXPECT_EQ!(fn(1) + fn(2) + fn(4) + fn(8) + fn(16) + fn(32), 63);
  EXPECT_EQ!(f(1) + fn(2) + f(4) + fn(8) + f(16) + fn(32), 63);
  EXPECT_EQ!(fn(1) + f(2) + fn(4) + f(8) + fn(16) + f(32), 63);

  EXPECT_EQ!(fnn(1) + fnn(2) + fnn(4) + fnn(8) + fnn(16) + fnn(32), 63);
  EXPECT_EQ!(fn(1) + fnn(2) + fn(4) + fnn(8) + fn(16) + fnn(32), 63);
  EXPECT_EQ!(f(1) + fn(2) + fnn(4) + fn(8) + fnn(16) + fn(32), 63);
  EXPECT_EQ!(fn(1) + fnn(2) + fn(4) + f(8) + fnn(16) + f(32), 63);
end);

TEST!(compressible_batch,
begin
  -- nest the batch so that it doesn't conflict with the macro proc preamble
  IF 1 then
    drop table if exists foo;
    create table goo(id int);
    insert into goo values (1), (2), (3);
  end IF;
  EXPECT_EQ!((select sum(id) from goo), 6);
  drop table goo;
end);

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

TEST!(out_union_ref_counts,
begin
  cursor C for call get_row();
  fetch C;
  EXPECT!(C);
  EXPECT_EQ!(C.facet, 'x');
  fetch C;
  EXPECT!(not C);

  declare D cursor for call get_row_thrice();
  fetch D;
  EXPECT!(D);
  EXPECT_EQ!(D.facet, 'x');
  fetch D;
  EXPECT!(not D);
end);

[[shared_fragment]]
proc f1(pattern text)
begin
  with source(*) like (select 1 id, "x" t)
  select * from source where t like pattern;
end;

[[shared_fragment]]
proc f2(pattern text, id_start int!, id_end int!, lim int!)
begin
  with
  source(*) like f1,
  data(*) as (call f1(pattern) using source as source)
  select * from data where data.id between id_start and id_end
  limit lim;
end;

[[private]]
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
begin
  cursor C for call shared_consumer();
  fetch C;
  EXPECT_EQ!(C.id, 1100);
  EXPECT_EQ!(C.t, 'x_x');
  fetch C;
  EXPECT_EQ!(C.id, 4500);
  EXPECT_EQ!(C.t, 'y_y');
  fetch C;
  EXPECT!(not C);
end);

[[shared_fragment]]
proc select_nothing_user(flag bool!)
begin
  if flag then
    select flag as anything;
  else
    select nothing;
  end if;
end;

TEST!(select_nothing,
begin
  declare X cursor for select * from (call select_nothing_user(true));
  fetch X;
  EXPECT!(X);
  fetch X;
  EXPECT!(not X);

  declare Y cursor for select * from (call select_nothing_user(false));
  fetch Y;
  EXPECT!(not Y);
end);

[[shared_fragment]]
proc get_values()
begin
  select 1 id, 'x' t
  union all
  select 2 id, 'y' t;
end;

create table x(id int, t text);

TEST!(shared_exec,
begin
  drop table if exists x;
  create table x(id int, t text);
  with
    (call get_values())
  insert into x select * from get_values;

  cursor C for select * from x;
  fetch C;
  EXPECT_EQ!(C.id, 1);
  EXPECT_EQ!(C.t, 'x');
  fetch C;
  EXPECT_EQ!(C.id, 2);
  EXPECT_EQ!(C.t, 'y');
  fetch C;
  EXPECT!(not C);

  drop table x;
end);

[[shared_fragment]]
proc conditional_values_base(x_ int)
begin
  if x_ == 2 then
    select x_ id, 'y' t;
  else
    select x_ id, 'u' t
    union all
    select x_ + 1 id, 'v' t;
  end if;
end;

[[shared_fragment]]
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
begin
  cursor C for
    with some_cte(*) as (call conditional_values(1))
    select * from some_cte;

  fetch C;

  EXPECT_EQ!(C.id, 1);
  EXPECT_EQ!(C.t, 'x');
  fetch C;
  EXPECT!(not C);

  declare D cursor for
    with some_cte(*) as (call conditional_values(2))
  select * from some_cte;

  fetch D;
  EXPECT_EQ!(D.id, 2);
  EXPECT_EQ!(D.t, 'y');
  fetch D;
  EXPECT!(not D);

  declare E cursor for
    with some_cte(*) as (call conditional_values(3))
  select * from some_cte;

  fetch E;
  EXPECT_EQ!(E.id, 3);
  EXPECT_EQ!(E.t, 'u');
  fetch E;
  EXPECT_EQ!(E.id, 4);
  EXPECT_EQ!(E.t, 'v');
  fetch E;
  EXPECT!(not E);
end);

TEST!(conditional_fragment_no_with,
begin
  cursor C for select * from (call conditional_values(1));

  fetch C;
  EXPECT_EQ!(C.id, 1);
  EXPECT_EQ!(C.t, 'x');
  fetch C;
  EXPECT!(not C);

  declare D cursor for select * from (call conditional_values(2));

  fetch D;
  EXPECT_EQ!(D.id, 2);
  EXPECT_EQ!(D.t, 'y');
  fetch D;
  EXPECT!(not D);

  declare E cursor for select * from (call conditional_values(3));

  fetch E;
  EXPECT_EQ!(E.id, 3);
  EXPECT_EQ!(E.t, 'u');
  fetch E;
  EXPECT_EQ!(E.id, 4);
  EXPECT_EQ!(E.t, 'v');
  fetch E;
  EXPECT!(not E);
end);

[[shared_fragment]]
proc skip_not_nulls(a_ int!, b_ bool!, c_ long!, d_ real!, e_ text!, f_ blob!, g_ object!)
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

TEST!(skip_not_nulls,
begin
  declare _set object!;
  _set := set_create();
  declare _bl blob!;
  _bl := blob_from_string('hi');

  cursor C for
    with some_cte(*) as (call skip_not_nulls(123, false, 1L, 2.3, 'x', _bl, _set))
    select * from some_cte;

  fetch C;
  EXPECT_EQ!(C.result, 123);
  fetch C;
  EXPECT!(not C);
end);

[[shared_fragment]]
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
begin
  declare _set object!;
  _set := set_create();
  declare _bl blob!;
  _bl := blob_from_string('hi');

  cursor C for
    with some_cte(*) as (call skip_nullables(456, false, 1L, 2.3, 'x', _bl, _set))
    select * from some_cte;

  fetch C;
  EXPECT_EQ!(C.result, 456);
  fetch C;
  EXPECT!(not C);
end);

[[shared_fragment]]
proc abs_func(x int!)
begin
  select case
    when x < 0 then x * -1
    else x
  end x;
end;

[[shared_fragment]]
proc max_func(x int!, y int!)
begin
  select case when x <= y then y else x end result;
end;

[[shared_fragment]]
proc ten()
begin
  select 10 ten;
end;

[[shared_fragment]]
proc numbers(lim int!)
begin
  with N(x) as (
    select 1 x
    union all
    select x + 1 x from N
    limit lim)
  select x from N;
end;

TEST!(inline_proc,
begin
  cursor C for
    select
      abs_func(x - ten()) s1,
      abs(x - 10) s2,
      max_func(x - ten(), abs_func(x - ten())) m1,
      max(x - 10, abs(x - 10)) m2
    from
      (call numbers(20));

  loop fetch C
  begin
    EXPECT_EQ!(C.s1, C.s2);
    EXPECT_EQ!(C.m1, C.m2);
  end;
end);

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
begin
  make_xy();
  insert into xy values (1,2), (2,3);

  cursor C for
    with T(*) as (call transformer() using xy as source)
    select T.* from T;

  fetch C;
  EXPECT!(C);
  EXPECT_EQ!(C.x, 2);
  EXPECT_EQ!(C.y, 22);
  fetch C;
  EXPECT!(C);
  EXPECT_EQ!(C.x, 3);
  EXPECT_EQ!(C.y, 23);
  fetch C;
  EXPECT!(not C);
end);

declare proc all_types_nullable() (
  t bool,
  f bool,
  i int,
  l long,
  r real,
  bl blob,
  str text
);

declare proc all_types_not_null() (
  `bool 1 not null` bool!,
  `bool 2 not null` bool!,
  i_nn int!,
  l_nn long!,
  r_nn real!,
  bl_nn blob!,
  str_nn text!
);

[[blob_storage]]
create table storage_not_null(
  like all_types_not_null
);

[[blob_storage]]
create table storage_nullable(
  like all_types_nullable
);

[[blob_storage]]
create table storage_both(
  like all_types_not_null,
  like all_types_nullable
);

[[blob_storage]]
create table storage_with_extras(
  like all_types_not_null,
  x int!
);

[[blob_storage]]
create table storage_one_int(
  x int!
);

[[blob_storage]]
create table storage_one_long(
  x long!
);

[[blob_storage]]
create table storage_one_real(
  data real!
);

TEST!(blob_serialization,
begin
  @echo lua, "cql_disable_tracing = true\n";

  let a_blob := blob_from_string("a blob");
  let b_blob := blob_from_string("b blob");
  declare cursor_both cursor like storage_both;
  fetch cursor_both using
      false f, true t, 22 i, 33L l, 3.14 r, a_blob bl, "text" str,
      false `bool 2 not null`, true `bool 1 not null`, 88 i_nn, 66L l_nn, 6.28 r_nn, b_blob bl_nn, "text2" str_nn;

  -- note: using Cursor_both and cursor_both ensures code gen is canonicalizing the name
  declare blob_both blob<storage_both>;
  blob_both := Cursor_both:to_blob;

  declare test_cursor_both cursor like cursor_both;
  test_cursor_both:from_blob(blob_both);

  EXPECT!(test_cursor_both);
  EXPECT_EQ!(test_cursor_both.`bool 1 not null`, cursor_both.`bool 1 not null`);
  EXPECT_EQ!(test_cursor_both.`bool 2 not null`, cursor_both.`bool 2 not null`);
  EXPECT_EQ!(test_cursor_both.i_nn, cursor_both.i_nn);
  EXPECT_EQ!(test_cursor_both.l_nn, cursor_both.l_nn);
  EXPECT_EQ!(test_cursor_both.r_nn, cursor_both.r_nn);
  EXPECT_EQ!(test_cursor_both.bl_nn, cursor_both.bl_nn);
  EXPECT_EQ!(test_cursor_both.str_nn, cursor_both.str_nn);
  EXPECT_EQ!(test_cursor_both.t, cursor_both.t);
  EXPECT_EQ!(test_cursor_both.f, cursor_both.f);
  EXPECT_EQ!(test_cursor_both.i, cursor_both.i);
  EXPECT_EQ!(test_cursor_both.l, cursor_both.l);
  EXPECT_EQ!(test_cursor_both.r, cursor_both.r);
  EXPECT_EQ!(test_cursor_both.bl, cursor_both.bl);
  EXPECT_EQ!(test_cursor_both.str, cursor_both.str);

  cursor cursor_not_nulls  like storage_not_null;
  fetch cursor_not_nulls from cursor_both(like cursor_not_nulls);
  let blob_not_nulls := cursor_not_nulls:to_blob;
  declare test_cursor_not_nulls cursor like cursor_not_nulls;
  test_cursor_not_nulls:from_blob(blob_not_nulls);

  EXPECT!(test_cursor_not_nulls);
  EXPECT_EQ!(test_cursor_not_nulls.`bool 1 not null`, cursor_both.`bool 1 not null`);
  EXPECT_EQ!(test_cursor_not_nulls.`bool 2 not null`, cursor_both.`bool 2 not null`);
  EXPECT_EQ!(test_cursor_not_nulls.i_nn, cursor_both.i_nn);
  EXPECT_EQ!(test_cursor_not_nulls.l_nn, cursor_both.l_nn);
  EXPECT_EQ!(test_cursor_not_nulls.r_nn, cursor_both.r_nn);
  EXPECT_EQ!(test_cursor_not_nulls.bl_nn, cursor_both.bl_nn);
  EXPECT_EQ!(test_cursor_not_nulls.str_nn, cursor_both.str_nn);

  -- deserializing should not screw up the reference counts
  blob_not_nulls := cursor_not_nulls:to_blob;
  blob_not_nulls := cursor_not_nulls:to_blob;
  blob_not_nulls := cursor_not_nulls:to_blob;

  -- The next tests verify various things with blobs that are
  -- not directly the right type so we're cheesing the type system.
  -- We need to be able to handle different version sources
  -- as well as assorted corruptions without crashing hence
  -- we pass in blobs of dubious pedigree.

  -- There are missing nullable columns at the end
  -- this is ok and it is our versioning strategy.
  declare any_blob blob;
  let stash_both := blob_both;
  let stash_not_nulls := blob_not_nulls;
  any_blob := blob_not_nulls;
  blob_both := any_blob;
  test_cursor_both:from_blob(blob_both);

  EXPECT!(test_cursor_both);
  EXPECT_EQ!(test_cursor_both.`bool 1 not null`, cursor_both.`bool 1 not null`);
  EXPECT_EQ!(test_cursor_both.`bool 2 not null`, cursor_both.`bool 2 not null`);
  EXPECT_EQ!(test_cursor_both.i_nn, cursor_both.i_nn);
  EXPECT_EQ!(test_cursor_both.l_nn, cursor_both.l_nn);
  EXPECT_EQ!(test_cursor_both.r_nn, cursor_both.r_nn);
  EXPECT_EQ!(test_cursor_both.bl_nn, cursor_both.bl_nn);
  EXPECT_EQ!(test_cursor_both.str_nn, cursor_both.str_nn);
  EXPECT_EQ!(test_cursor_both.t, null);
  EXPECT_EQ!(test_cursor_both.f, null);
  EXPECT_EQ!(test_cursor_both.i, null);
  EXPECT_EQ!(test_cursor_both.l, null);
  EXPECT_EQ!(test_cursor_both.r, null);
  EXPECT_EQ!(test_cursor_both.bl, null);
  EXPECT_EQ!(test_cursor_both.str, null);

  blob_both := null;

  -- null blob, throws exception
  let caught := false;
  try
    test_cursor_both:from_blob(blob_both);
  catch
    EXPECT!(not test_cursor_both);
    caught := true;
  end;
  EXPECT!(caught);

  -- big blob will have too many fields...
  caught := false;
  any_blob := stash_both;
  blob_not_nulls := any_blob;
  test_cursor_not_nulls:from_blob(blob_not_nulls);

  -- we still expect to be able to read the fields we know without error
  EXPECT!(test_cursor_not_nulls);
  EXPECT_EQ!(test_cursor_not_nulls.`bool 1 not null`, cursor_both.`bool 1 not null`);
  EXPECT_EQ!(test_cursor_not_nulls.`bool 2 not null`, cursor_both.`bool 2 not null`);
  EXPECT_EQ!(test_cursor_not_nulls.i_nn, cursor_both.i_nn);
  EXPECT_EQ!(test_cursor_not_nulls.l_nn, cursor_both.l_nn);
  EXPECT_EQ!(test_cursor_not_nulls.r_nn, cursor_both.r_nn);
  EXPECT_EQ!(test_cursor_not_nulls.bl_nn, cursor_both.bl_nn);
  EXPECT_EQ!(test_cursor_not_nulls.str_nn, cursor_both.str_nn);

  -- we're missing fields and they aren't nullable, this will make errors
  declare cursor_with_extras cursor like storage_with_extras;
  caught := false;
  any_blob := stash_not_nulls;
  declare blob_with_extras blob<storage_with_extras>;
  blob_with_extras := any_blob;
  try
    cursor_with_extras:from_blob(blob_with_extras);
  catch
    EXPECT!(not cursor_with_extras);
    caught := true;
  end;
  EXPECT!(caught);

  -- attempting to read from an empty cursor will throw
  EXPECT!(not cursor_with_extras);
  caught := false;
  try
    blob_with_extras := cursor_with_extras:to_blob;
  catch
    EXPECT!(not cursor_with_extras);
    caught := true;
  end;
  EXPECT!(caught);

  -- the types are all wrong but they are simply not null values of the same types
  -- we can safely decode that
  declare blob_nullables blob<storage_nullable>;
  any_blob := stash_not_nulls;
  blob_nullables := any_blob;
  declare cursor_nullables cursor like storage_nullable;
  cursor_nullables:from_blob(blob_nullables);

  -- note that we read the not null versions of the fields
  EXPECT!(cursor_nullables);
  EXPECT_EQ!(cursor_nullables.t, cursor_both.`bool 1 not null`);
  EXPECT_EQ!(cursor_nullables.f, cursor_both.`bool 2 not null`);
  EXPECT_EQ!(cursor_nullables.i, cursor_both.i_nn);
  EXPECT_EQ!(cursor_nullables.l, cursor_both.l_nn);
  EXPECT_EQ!(cursor_nullables.r, cursor_both.r_nn);
  EXPECT_EQ!(cursor_nullables.bl, cursor_both.bl_nn);
  EXPECT_EQ!(cursor_nullables.str, cursor_both.str_nn);

  -- now blob_nullables really does have nullable types
  blob_nullables := cursor_nullables:to_blob;
  any_blob := blob_nullables;
  blob_not_nulls := any_blob;

  -- we can't read possibly null types into not null types
  caught := false;
  try
    test_cursor_not_nulls:from_blob(blob_not_nulls);
  catch
    EXPECT!(not test_cursor_not_nulls);
    caught := true;
  end;
  EXPECT!(caught);

  -- set up a totally different stored blob
  declare cursor_other cursor like storage_one_int;
  fetch cursor_other using 5 x;
  declare blob_other blob<storage_one_int>;
  cursor_other:to_blob(blob_other);
  declare test_cursor_other cursor like cursor_other;
  test_cursor_other:from_blob(blob_other);
  EXPECT!(test_cursor_other);
  EXPECT_EQ!(test_cursor_other.x, cursor_other.x);

  any_blob := blob_other;
  blob_nullables := any_blob;

  -- the types in this blob do not match the cursor we're going to use it with
  caught := false;
  try
    cursor_nullables:from_blob(blob_nullables);
  catch
    EXPECT!(not cursor_nullables);
    caught := true;
  end;
  EXPECT!(caught);
  @echo lua, "cql_disable_tracing = false\n";
end);

TEST!(blob_serialization_null_cases,
begin
  @echo lua, "cql_disable_tracing = true\n";

  declare cursor_nulls cursor like storage_nullable;
  fetch cursor_nulls using
    null f, null t, null i, null l, null r, null bl, null str;

  let blob_nulls := cursor_nulls:to_blob;
  declare test_cursor cursor like cursor_nulls;
  test_cursor:from_blob(blob_nulls);

  EXPECT!(test_cursor);
  EXPECT_EQ!(test_cursor.t, null);
  EXPECT_EQ!(test_cursor.f, null);
  EXPECT_EQ!(test_cursor.i, null);
  EXPECT_EQ!(test_cursor.l, null);
  EXPECT_EQ!(test_cursor.r, null);
  EXPECT_EQ!(test_cursor.bl, null);
  EXPECT_EQ!(test_cursor.str, null);

  @echo lua, "cql_disable_tracing = false\n";
end);

TEST!(corrupt_blob_deserialization,
begin
  @echo lua, "cql_disable_tracing = true\n";

  let a_blob := blob_from_string("a blob");
  let b_blob := blob_from_string("b blob");
  declare cursor_both cursor like storage_both;
  fetch cursor_both using
      false f, true t, 22 i, 33L l, 3.14 r, a_blob bl, "text" str,
      false `bool 2 not null`, true `bool 1 not null`, 88 i_nn, 66L l_nn, 6.28 r_nn, b_blob bl_nn, "text2" str_nn;

  let blob_both := cursor_both:to_blob;

  -- sanity check the decode of the full blob
  declare test_cursor_both cursor like cursor_both;
  test_cursor_both:from_blob(blob_both);

  -- sanity check the blob size of the full encoding
  let full_size := cql_get_blob_size(blob_both);
  EXPECT!(full_size > 50);
  EXPECT!(full_size < 100);

  -- try truncated blobs of every size
  let i := 0;
  for i < full_size; i += 1;
  begin
    declare blob_broken  blob<storage_both>;
    blob_broken := create_truncated_blob(blob_both, i);
    -- the types in this blob do not match the cursor we're going to use it with
    let caught := false;
    try
      -- this is gonna fail
      cursor_both:from_blob(blob_broken);
    catch
      EXPECT!(not cursor_both);
      caught := true;
    end;
    EXPECT!(caught);
  end;

  @echo lua, "cql_disable_tracing = false\n";
end);

TEST!(bogus_var_int,
begin
  @echo lua, "cql_disable_tracing = true\n";

  let control_blob := (select X'490001');  -- one byte zigzag encoding of -1
  declare test_blob blob<storage_one_int>;
  test_blob := control_blob;
  cursor C like storage_one_int;

  -- correctly encoded control case
  C:from_blob(test_blob);
  EXPECT!(C);
  EXPECT_EQ!(C.x, -1);

  -- this int has 6 bytes, 5 is the most you can need
  let bogus_int := (select X'4900818181818100');

  test_blob := bogus_int;

  let caught := false;
  try
    -- this is gonna fail
    C:from_blob(test_blob);
  catch
    EXPECT!(not C);
    caught := true;
  end;
  EXPECT!(caught);

  @echo lua, "cql_disable_tracing = false\n";
end);

TEST!(bogus_var_long,
begin
  @echo lua, "cql_disable_tracing = true\n";

  let control_blob := (select X'4C0001');  -- one byte zigzag encoding of -1
  declare test_blob blob<storage_one_long>;
  test_blob := control_blob;
  cursor C like storage_one_long;

  -- correctly encoded control case
  C:from_blob(test_blob);
  EXPECT!(C);
  EXPECT_EQ!(C.x, -1);

  -- this long has 11 bytes, 10 is the most you can need
  let bogus_long := (select X'4C008181818181818181818100');

  test_blob := bogus_long;

  let caught := false;
  try
    -- this is gonna fail
    C:from_blob(test_blob);
  catch
    EXPECT!(not C);
    caught := true;
  end;
  EXPECT!(caught);
  @echo lua, "cql_disable_tracing = false\n";
end);

proc round_trip_int(value int!)
begin
  cursor C like storage_one_int;
  cursor D like C;

  fetch C using value x;
  EXPECT_EQ!(C.x, value);
  let int_blob := C:to_blob;
  D:from_blob(int_blob);
  EXPECT_EQ!(C.x, D.x);
end;

proc round_trip_long(value long!)
begin
  cursor C like storage_one_long;
  cursor D like C;

  fetch C using value x;
  EXPECT_EQ!(C.x, value);
  let int_blob := C:to_blob;
  D:from_blob(int_blob);
  EXPECT_EQ!(C.x, D.x);
end;

[[blob_storage]]
create table base_blob(
  f1 bool,
  f2 int,
  f3 long,
  f4 real,
  f5 text,
  f6 blob,
  g1 bool,
  g2 int,
  g3 long,
  g4 real,
  g5 text,
  g6 blob,
  h1 bool!,
  h2 int!,
  h3 long!,
  h4 real!,
  h5 text!,
  h6 blob!
);

[[blob_storage]]
create table extended_blob (
 like base_blob,
  i1 bool,
  i2 int,
  i3 long,
  i4 real,
  i5 text,
  i6 blob
);


TEST!(blob_storage_binary_compat,
begin
  cursor base_cursor like base_blob;
  cursor ext_cursor like extended_blob;

  let a_blob := (select "first blob" ~blob~);
  let b_blob := (select "second blob" ~blob~);

  fetch ext_cursor using
    null f1,
    null f2,
    null f3,
    null f4,
    null f5,
    null f6,
    true g1,
    1 g2,
    2000000000L g3,
    3.25 g4,
    "a string" g5,
    a_blob g6,
    false h1,
    500 h2,
    4000000000000L h3,
    9.75 h4,
    "a second string" h5,
    b_blob h6,
    null i1,
    null i2,
    null i3,
    null i4,
    "an unused string" i5,
    null i6;

  let b := ext_cursor:to_blob;

  let actual_hex := hex(b);
  let expected_hex :=
     "66696C64736266696C64736246494C44534266696C64736200C00F090280D0AC"
     "F30E0000000000000A406120737472696E670014666972737420626C6F62E807"
     "8080A2A9EAE801000000000080234061207365636F6E6420737472696E670016"
     "7365636F6E6420626C6F62616E20756E7573656420737472696E6700";

  -- this is true on all platforms!
  EXPECT_EQ!(actual_hex, expected_hex);

  -- type alias so we can try fetching from the future
  let b2 := b ~blob<base_blob>~;

  -- the fetched values are the same as the originals
  -- up to the fields that are present
  base_cursor:from_blob(b2);
  let base_text := cql_cursor_format(base_cursor);
  let ext_text := cql_cursor_format(ext_cursor);
  EXPECT_EQ!(substr(ext_text, 1, length(base_text)), base_text);

  let expected_cursor_value :=
    "f1:null|f2:null|f3:null|f4:null|f5:null|f6:null|"
    "g1:true|g2:1|g3:2000000000|g4:3.25|g5:a string|g6:length 10 blob|"
    "h1:false|h2:500|h3:4000000000000|h4:9.75|h5:a second string|h6:length 11 blob|"
    "i1:null|i2:null|i3:null|i4:null|i5:an unused string|i6:null";

  EXPECT_EQ!(ext_text, expected_cursor_value);

  -- for debugging
  -- printf("%s\n", ext_text);
  -- printf("%s\n", base_text);
end);


[[blob_storage]]
create table small_blob_table(x int, y int);

TEST!(blob_function_pattern,
begin
  cursor C like small_blob_table;

  fetch C from values(12, 25);
  let s1 := printf("%s\n", C:format);
  let b1 := cql_cursor_to_blob(C);
  cql_cursor_from_blob(C, b1);
  let s2 := printf("%s\n", C:format);

  -- use short forms also

  let b2 := C:to_blob;
  C:from_blob(b2);
  let s3 := printf("%s\n", C:format);

  let h1 := hex(b1);
  let h2 := hex(b2);

  EXPECT_EQ!(s1, s2);
  EXPECT_EQ!(s2, s3);
  EXPECT_EQ!(h1, h2);
end);

const group long_constants (
  long_const_1 = -9223372036854775807L,
  long_const_2 = -9223372036854775808L,
  long_const_3 = -9223372036854775808
);

@emit_constants long_constants;

TEST!(verify_long_constant_forms,
begin
  let reference := long_const_1  - 1;

  EXPECT_SQL_TOO!(reference = -9223372036854775808L);
  EXPECT_SQL_TOO!(reference = -9223372036854775808);
  EXPECT_SQL_TOO!(reference = const(-9223372036854775808L));
  EXPECT_SQL_TOO!(reference = const(-9223372036854775808));
  EXPECT_SQL_TOO!(reference = long_const_2);
  EXPECT_SQL_TOO!(reference = long_const_3);

  let x := -9223372036854775808L;
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

  declare z real!;
  z := 9223372036854775807;

  -- this verifies that z was stored as a double
  -- hence adding 0.0 will make no difference
  EXPECT_SQL_TOO!(z - 1 == z + 0.0 - 1);

  -- ensure division does not convert to float
  EXPECT_EQ!(9223372036854775807 - 9223372036854775807 / 2 * 2, 1);
  EXPECT_EQ!(const(9223372036854775807 - 9223372036854775807 / 2 * 2), 1);
  EXPECT_EQ!(9223372036854775807 >> 1, 9223372036854775807 / 2);
  EXPECT_EQ!(const(9223372036854775807 >> 1), 9223372036854775807 / 2);

  cursor C for
    select 9223372036854775807 v
    union all
    select 9223372036854775807.0 v;

  -- this verifies that if we mean to fetch a float we get a float
  -- even if the value in the select is a long
  fetch C;
  EXPECT_EQ!(z, C.v);
  fetch C;
  EXPECT_EQ!(z, C.v);
end);

TEST!(serialization_tricky_values,
begin
  round_trip_int(0);
  round_trip_int(1);
  round_trip_int(-1);
  round_trip_int(129);
  round_trip_int(32769);
  round_trip_int(-129);
  round_trip_int(-32769);
  round_trip_int(0x7fffffff);
  round_trip_int(-214783648);

  round_trip_long(0);
  round_trip_long(1);
  round_trip_long(-1);
  round_trip_long(129);
  round_trip_long(32769);
  round_trip_long(-129);
  round_trip_long(-32769);
  round_trip_long(0x7fffffffL);
  round_trip_long(-214783648L);
  round_trip_long(0x7fffffffffffffffL);  -- max int64
  round_trip_long(0x8000000000000000L);  -- min int64

  -- these are actually testing constant handling rather than
  -- the blob but this is a convenient way to ensure that it was
  -- all on the up and up.  Especially since we already confirmed
  -- above that it works in hex.
  round_trip_long(-9223372036854775808L); -- min int64 in decimal
  round_trip_long(-9223372036854775808);  -- min int64 in decimal
  round_trip_long(9223372036854775807L);  -- max int64 in decimal
  round_trip_long(9223372036854775807);   -- max int64 in decimal
end);

declare proc rand_reset();
function corrupt_blob_with_invalid_shenanigans(b blob!) create blob!;

TEST!(clobber_blobs,
begin
  -- the point of the test is to ensure that we don't fault or get sanitizer failures
  -- or leak memory when dealing with broken blobs.  Some of the blobs
  -- may still be valid since we corrupt them randomly.  But this will
  -- help us to be sure that nothing horrible happens if you corrupt blobs

  @echo lua, "cql_disable_tracing = true\n";

  -- we're going to make a good blob with various data in it and then clobber it
  let a_blob := blob_from_string("a blob");
  let b_blob := blob_from_string("b blob");
  declare cursor_both cursor like storage_both;
  fetch cursor_both using
      false f, true t, 22 i, 33L l, 3.14 r, a_blob bl, "text" str,
      false `bool 2 not null`, true `bool 1 not null`, 88 i_nn, 66L l_nn, 6.28 r_nn, b_blob bl_nn, "text2" str_nn;

  -- storage both means nullable types and not null types
  let my_blob := cursor_both:to_blob;

  -- sanity check the decode of the full blob
  declare test_cursor_both cursor like storage_both;
  test_cursor_both:from_blob(my_blob);

  rand_reset();

  let good := 0;
  let bad := 0;

  -- if this test fails you can use this count to set a breakpoint
  -- on the attempt that crashed, check out this value in the debugger
  let attempt := 0;

  let i := 1;
  for i <= 100; i += 1;
  begin
    -- refresh the blob from the cursor, it's good now (again)
    my_blob := cursor_both:to_blob;

    -- same buffer will be smashed 10 times
    let j := 0;
    while j < 10
    begin
      j += 1;

      -- invoke da smasher
      my_blob := corrupt_blob_with_invalid_shenanigans(my_blob);

      try
        -- almost certainly going to get an error, that's fine, but no seg violation, no leaks, etc.
        -- each attempt will be more smashed, there are 100 trails with 10 smashes each
        -- each smash clobbers 20 bytes of the blob

        test_cursor_both:from_blob(my_blob);
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
  @echo lua,  "cql_disable_tracing = false\n";
end);

proc change_arg(x text)
begin
  x := 'hi';
end;

TEST!(arg_mutation,
begin
  change_arg(null);
end);

declare proc many_types() (
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

function cql_cursor_hash(C cursor) long!;

TEST!(cursor_hash,
begin
  cursor C like many_types;
  declare D cursor like C;

  -- empty cursor hashes to nothing
  EXPECT_EQ!(0, cql_cursor_hash(C));

  let i := 0;
  for i < 5; i += 1;
  begin
    -- no explicit values, all dummy
    fetch C() from values () @dummy_seed(i);
    fetch D() from values () @dummy_seed(i);

    let hash0 := cql_cursor_hash(C);
    let hash1 := cql_cursor_hash(C);
    let hash2 := cql_cursor_hash(D);

    EXPECT_EQ!(hash0, hash1);  -- control for sanity
    EXPECT_EQ!(hash1, hash2);  -- equivalent data -> same hash (note different string, same text)

    fetch C() from values () @dummy_seed(i) @dummy_nullables;
    fetch D() from values () @dummy_seed(i) @dummy_nullables;
    cursor X like C;
    fetch X from D;

    hash0 := cql_cursor_hash(C);
    hash1 := cql_cursor_hash(C); -- hashing the same thing should always be the same
    hash2 := cql_cursor_hash(D);

    EXPECT_EQ!(hash0, hash1);  -- control for sanity
    EXPECT_EQ!(hash1, hash2);  -- equivalent data -> same hash (note different string same text)

    -- hash different with different bool (not null version)
    fetch D from X;
    update cursor D using not C.b as b;

    hash2 := cql_cursor_hash(D);
    EXPECT_NE!(hash1, hash2);  -- now different

    -- hash different with different int (not null version)
    fetch D from X;

    update cursor D using C.i + 1 as i;

    hash2 := cql_cursor_hash(D);
    EXPECT_NE!(hash1, hash2);  -- now different

    -- hash different with different long (not null version)
    fetch D from X;
    update cursor D using C.l + 1 as l;

    hash2 := cql_cursor_hash(D);
    EXPECT_NE!(hash1, hash2);  -- now different

    -- hash different with different real (not null version)
    fetch D from X;
    update cursor D using C.r + 1 as r;

    hash2 := cql_cursor_hash(D);
    EXPECT_NE!(hash1, hash2);  -- now different

    -- hash different with different text (not null version)
    fetch D from X;
    update cursor D using "different" as t;

    hash2 := cql_cursor_hash(D);
    EXPECT_NE!(hash1, hash2);  -- now different

    -- hash different with different bool
    fetch D from X;
    update cursor D using not C.b as b0;

    hash2 := cql_cursor_hash(D);
    EXPECT_NE!(hash1, hash2);  -- now different

    -- hash different with different int
    fetch D from X;
    update cursor D using C.i + 1 as i0;

    hash2 := cql_cursor_hash(D);
    EXPECT_NE!(hash1, hash2);  -- now different

    -- hash different with different long
    fetch D from X;
    update cursor D using C.l + 1 as l0;

    hash2 := cql_cursor_hash(D);
    EXPECT_NE!(hash1, hash2);  -- now different

    -- hash different with different real
    fetch D from X;
    update cursor D using C.r + 1 as r0;

    hash2 := cql_cursor_hash(D);
    EXPECT_NE!(hash1, hash2);  -- now different

    -- hash different with different string
    fetch D from X;
    update cursor D using"different" as t0;

    hash2 := cql_cursor_hash(D);
    EXPECT_NE!(hash1, hash2);  -- now different

    -- hash different with null bool
    fetch D from X;
    update cursor D using null as b0;

    hash2 := cql_cursor_hash(D);
    EXPECT_NE!(hash1, hash2);  -- now different

    -- has different with null int
    fetch D from X;
    update cursor D using null as i0;

    hash2 := cql_cursor_hash(D);
    EXPECT_NE!(hash1, hash2);  -- now different

    -- hash different with null long
    fetch D from X;
    update cursor D using null as l0;

    hash2 := cql_cursor_hash(D);
    EXPECT_NE!(hash1, hash2);  -- now different

    -- has different with null real
    fetch D from X;
    update cursor D using null as r0;

    hash2 := cql_cursor_hash(D);
    EXPECT_NE!(hash1, hash2);  -- now different


    -- hash different with null text
    fetch D from X;
    update cursor D using null as t0;

    hash2 := cql_cursor_hash(D);
    EXPECT_NE!(hash1, hash2);  -- now different
  end;
end);

TEST!(cursor_equal,
begin
  cursor C like many_types;
  declare D cursor like C;

  -- empty cursor hashes to nothing
  EXPECT!(cql_cursors_equal(C, D));

  -- one cursor empty
  fetch C() from values () @dummy_seed(0);
  EXPECT!(not cql_cursors_equal(C, D));
  EXPECT!(not cql_cursors_equal(D, C));

  let i := 0;
  for i < 5; i += 1;
  begin
    -- no explicit values, all dummy
    fetch C() from values () @dummy_seed(i);
    fetch D() from values () @dummy_seed(i);
    cursor X like C;
    fetch X from D;

    EXPECT!(cql_cursors_equal(C, C)); -- control for sanity
    EXPECT!(cql_cursors_equal(C, D)); -- control for sanity

    fetch C() from values () @dummy_seed(i) @dummy_nullables;
    fetch D() from values () @dummy_seed(i) @dummy_nullables;

    EXPECT!(cql_cursors_equal(C, C)); -- control for sanity
    EXPECT!(cql_cursors_equal(C, D)); -- control for sanity

    -- values different with different bool (not null version)
    fetch D from X;
    update cursor D using not C.b as b;

    EXPECT!(not cql_cursors_equal(C, D));

    -- values different with different int (not null version)
    fetch D from X;
    update cursor D using C.i + 1 as i;

    EXPECT!(not cql_cursors_equal(C, D));

    -- values different with different long (not null version)
    fetch D from X;
    update cursor D using C.l + 1 as l;

    EXPECT!(not cql_cursors_equal(C, D));

    -- values different with different real (not null version)
    fetch D from X;
    update cursor D using C.r + 1 as r;

    EXPECT!(not cql_cursors_equal(C, D));

    -- values different with different text (not null version)
    fetch D from X;
    update cursor D using "different" as t;

    EXPECT!(not cql_cursors_equal(C, D));

    -- values different with different bool
    fetch D from X;
    update cursor D using not C.b as b0;

    EXPECT!(not cql_cursors_equal(C, D));

    -- values different with different int
    fetch D from X;
    update cursor D using C.i + 1 as i0;

    EXPECT!(not cql_cursors_equal(C, D));

    -- values different with different long
    fetch D from X;
    update cursor D using C.l + 1 as l0;

    EXPECT!(not cql_cursors_equal(C, D));

    -- values different with different real
    fetch D from X;
    update cursor D using C.r + 1 as r0;

    EXPECT!(not cql_cursors_equal(C, D));

    -- values different with different string
    fetch D from X;
    update cursor D using "different" as t0;

    EXPECT!(not cql_cursors_equal(C, D));

    -- values different with null bool
    fetch D from X;
    update cursor D using null as b0;

    EXPECT!(not cql_cursors_equal(C, D));

    -- values different with null int
    fetch D from X;
    update cursor D using null as i0;

    EXPECT!(not cql_cursors_equal(C, D));

    -- values different with null long
    fetch D from X;
    update cursor D using null as l0;

    EXPECT!(not cql_cursors_equal(C, D));

    -- values different with null real
    fetch D from X;
    update cursor D using null as r0;

    EXPECT!(not cql_cursors_equal(C, D));

    -- values different with null text
    fetch D from X;
    update cursor D using null as t0;

    EXPECT!(not cql_cursors_equal(C, D));
  end;

  -- different number of columns
  declare E cursor like select 1 x;
  EXPECT!(not cql_cursors_equal(C, E));

  -- different types (same offset)
  declare F cursor like select 1L x;
  EXPECT!(not cql_cursors_equal(E, F));

  -- different offsets (this is checked before types)
  declare G cursor like select 1L x, 1L y;
  declare H cursor like select 1 x, 1 y;
  EXPECT!(not cql_cursors_equal(G, H));
end);

TEST!(cursor_diff_index,
begin
  let o1 := 1:box;
  let o2 := 2:box;

  cursor C like (
    a bool!, b int!, c long!, d real!, e text!, f blob!, g object!,
    i bool,  j int,  k long,  l real,  m text,  n blob,  o object);

  cursor D like C;
  cursor X like C;

  -- empty cursors match
  EXPECT_EQ!(C:diff_index(D), -1);

  fetch C(g,o) from values(o1, o2) @dummy_seed(0) @dummy_nullables;

  -- this indicates that one is null and one is not
  EXPECT_EQ!(C:diff_index(D), -2);

  -- all different values
  fetch X(g,o) from values(o2, o1) @dummy_seed(1) @dummy_nullables;

  fetch D from C;
  EXPECT_EQ!(C:diff_index(D), -1);

  fetch C from D;
  update cursor C using X.a a;
  EXPECT_EQ!(C:diff_index(D), 0);

  fetch C from D;
  update cursor C using X.b b;
  EXPECT_EQ!(C:diff_index(D), 1);

  fetch C from D;
  update cursor C using X.c c;
  EXPECT_EQ!(C:diff_index(D), 2);

  fetch C from D;
  update cursor C using X.d d;
  EXPECT_EQ!(C:diff_index(D), 3);

  fetch C from D;
  update cursor C using X.e e;
  EXPECT_EQ!(C:diff_index(D), 4);

  fetch C from D;
  update cursor C using X.f f;
  EXPECT_EQ!(C:diff_index(D), 5);

  fetch C from D;
  update cursor C using X.g g;
  EXPECT_EQ!(C:diff_index(D), 6);

  fetch C from D;
  update cursor C using null i;
  EXPECT_EQ!(C:diff_index(D), 7);

  fetch C from D;
  update cursor C using null j;
  EXPECT_EQ!(C:diff_index(D), 8);

  fetch C from D;
  update cursor C using null k;
  EXPECT_EQ!(C:diff_index(D), 9);

  fetch C from D;
  update cursor C using null l;
  EXPECT_EQ!(C:diff_index(D), 10);

  fetch C from D;
  update cursor C using null m;
  EXPECT_EQ!(C:diff_index(D), 11);

  fetch C from D;
  update cursor C using null n;
  EXPECT_EQ!(C:diff_index(D), 12);

  fetch C from D;
  update cursor C using null o;
  EXPECT_EQ!(C:diff_index(D), 13);

  fetch C(g) from values(o1) @dummy_seed(0);
  fetch D(g) from values(o1) @dummy_seed(0);
  EXPECT_EQ!(C.i, null);
  EXPECT_EQ!(D.i, null);
  EXPECT_EQ!(C:diff_index(D), -1);
end);

TEST!(cursor_diff_col,
begin
  let o1 := 1:box;
  let o2 := 2:box;
  cursor C like (
    a bool!, b int!, c long!, d real!, e text!, f blob!, g object!,
    i bool,  j int,  k long,  l real,  m text,  n blob,  o object);
  cursor D like C;
  cursor X like C;

  fetch C(g,o) from values(o1, o2) @dummy_seed(0) @dummy_nullables;

  -- all different values
  fetch X(g,o) from values(o2, o1) @dummy_seed(1) @dummy_nullables;

  -- one has a row and the other doesn't
  EXPECT_EQ!(C:diff_col(D), "_has_row_");

  fetch D from C;
  EXPECT_EQ!(cql_cursor_diff_col(C,D), null);

  fetch C from D;
  update cursor C using X.a a;
  EXPECT_EQ!(cql_cursor_diff_col(C,D), "a");

  fetch C from D;
  update cursor C using X.b b;
  EXPECT_EQ!(cql_cursor_diff_col(C,D), "b");

  fetch C from D;
  update cursor C using X.c c;
  EXPECT_EQ!(cql_cursor_diff_col(C,D), "c");

  fetch C from D;
  update cursor C using X.d d;
  EXPECT_EQ!(cql_cursor_diff_col(C,D), "d");

  fetch C from D;
  update cursor C using X.e e;
  EXPECT_EQ!(cql_cursor_diff_col(C,D), "e");

  fetch C from D;
  update cursor C using X.f f;
  EXPECT_EQ!(cql_cursor_diff_col(C,D), "f");

  fetch C from D;
  update cursor C using X.g g;
  EXPECT_EQ!(cql_cursor_diff_col(C,D), "g");

  fetch C from D;
  update cursor C using null i;
  EXPECT_EQ!(cql_cursor_diff_col(C,D), "i");

  fetch C from D;
  update cursor C using null j;
  EXPECT_EQ!(cql_cursor_diff_col(C,D), "j");

  fetch C from D;
  update cursor C using null k;
  EXPECT_EQ!(cql_cursor_diff_col(C,D), "k");

  fetch C from D;
  update cursor C using null l;
  EXPECT_EQ!(cql_cursor_diff_col(C,D), "l");

  fetch C from D;
  update cursor C using null m;
  EXPECT_EQ!(cql_cursor_diff_col(C,D), "m");

  fetch C from D;
  update cursor C using null n;
  EXPECT_EQ!(cql_cursor_diff_col(C,D), "n");

  fetch C from D;
  update cursor C using null o;
  EXPECT_EQ!(cql_cursor_diff_col(C,D), "o");

  fetch C(g) from values(o1) @dummy_seed(0);
  fetch D(g) from values(o1) @dummy_seed(0);
  EXPECT_EQ!(C.i, null);
  EXPECT_EQ!(D.i, null);
  EXPECT_EQ!(cql_cursor_diff_col(C,D), null);
end);

TEST!(cursor_diff_val,
begin
  let o1 := 1:box;
  let o2 := 2:box;
  cursor C like (
    a bool!, b int!, c long!, d real!, e text!, f blob!, g object!,
    i bool,  j int,  k long,  l real,  m text,  n blob,  o object);
  cursor D like C;
  cursor X like C;

  fetch C(g,o) from values(o1, o2) @dummy_seed(0) @dummy_nullables;
  EXPECT_EQ!(C:diff_val(D), "column:_has_row_ c1:true c2:false");

  -- all different values
  fetch X(g,o) from values(o2, o1) @dummy_seed(1) @dummy_nullables;

  fetch D from C;
  EXPECT_EQ!(cql_cursor_diff_val(C,D), null);

  fetch C from D;
  update cursor C using X.a a;
  EXPECT_EQ!(cql_cursor_diff_val(C,D), "column:a c1:true c2:false");

  fetch C from D;
  update cursor C using X.b b;
  EXPECT_EQ!(cql_cursor_diff_val(C,D), "column:b c1:1 c2:0");

  fetch C from D;
  update cursor C using X.c c;
  EXPECT_EQ!(cql_cursor_diff_val(C,D), "column:c c1:1 c2:0");

  fetch C from D;
  update cursor C using X.d d;
  let diff := cql_cursor_diff_val(C,D);
  EXPECT!(diff == "column:d c1:1 c2:0" or diff == "column:d c1:1.0 c2:0.0");

  fetch C from D;
  update cursor C using X.e e;
  EXPECT_EQ!(cql_cursor_diff_val(C,D), "column:e c1:e_1 c2:e_0");

  fetch C from D;
  update cursor C using X.f f;
  EXPECT_EQ!(cql_cursor_diff_val(C,D), "column:f c1:length 3 blob c2:length 3 blob");

  fetch C from D;
  update cursor C using X.g g;
  EXPECT_EQ!(cql_cursor_diff_val(C,D), "column:g c1:generic object c2:generic object");

  fetch C from D;
  update cursor C using null i;
  EXPECT_EQ!(cql_cursor_diff_val(C,D), "column:i c1:null c2:false");

  fetch C from D;
  update cursor C using null j;
  EXPECT_EQ!(cql_cursor_diff_val(C,D), "column:j c1:null c2:0");

  fetch C from D;
  update cursor C using null k;
  EXPECT_EQ!(cql_cursor_diff_val(C,D), "column:k c1:null c2:0");

  fetch C from D;
  update cursor C using null l;
  set diff := cql_cursor_diff_val(C,D);
  EXPECT!(diff == "column:l c1:null c2:0" or diff == "column:l c1:null c2:0.0");

  fetch C from D;
  update cursor C using null m;
  EXPECT_EQ!(cql_cursor_diff_val(C,D), "column:m c1:null c2:m_0");

  fetch C from D;
  update cursor C using null n;
  EXPECT_EQ!(cql_cursor_diff_val(C,D), "column:n c1:null c2:length 3 blob");

  fetch C from D;
  update cursor C using null o;
  EXPECT_EQ!(cql_cursor_diff_val(C,D), "column:o c1:null c2:generic object");

  fetch C(g) from values(o1) @dummy_seed(0);
  fetch D(g) from values(o1) @dummy_seed(0);
  EXPECT_EQ!(C.i, null);
  EXPECT_EQ!(D.i, null);
  EXPECT_EQ!(cql_cursor_diff_val(C,D), null);
end);

declare PROC get_rows(result object!) out union (x INT!, y text!, z BOOL);

TEST!(child_results,
begin
  let p := cql_partition_create();

  declare v cursor like (x int!, y text!, z bool);
  declare k cursor like v(x, y);

  -- empty cursors, not added to partition
  let added := cql_partition_cursor(p, k, v);
  EXPECT!(not added);

  let i := 0;
  for i < 10; i += 1;
  begin
    fetch v() from values() @dummy_seed(i) @dummy_nullables;
    fetch k from v(like k);
    added := cql_partition_cursor(p, k, v);
    EXPECT!(added);

    if i % 3 == 0 then
      added := cql_partition_cursor(p, k, v);
      EXPECT!(added);
    end if;

    if i % 6 == 0 then
      added := cql_partition_cursor(p, k, v);
      EXPECT!(added);
    end if;
  end;

  i := -2;
  for i < 12; i += 1;
  begin
    /* don't join #6 to force cleanup */
    if i != 6 then
      fetch k() from values() @dummy_seed(i) @dummy_nullables;
      declare rs1 object<get_rows set>;
      rs1 := cql_extract_partition(p, k);
      let rs2 := cql_extract_partition(p, k);

      -- if we ask for the same key more than once, we should get the exact same result
      -- this is object identity we are checking here (i.e. it's the same pointer!)
      EXPECT_EQ!(rs1, rs2);

      cursor C for rs1;

      let row_count := 0;
      loop fetch C
      begin
        EXPECT_EQ!(C.x, i);
        EXPECT_EQ!(C.y, printf("y_%d", i));
        EXPECT_EQ!(C.z, not not i);
        row_count := row_count + 1;
      end;

      switch i
        when -2, -1, 10, 11
          then EXPECT_EQ!(row_count, 0);
        when 1, 2, 4, 5, 7, 8
          then EXPECT_EQ!(row_count, 1);
        when 3, 9
          then EXPECT_EQ!(row_count, 2);
        when 0
          then EXPECT_EQ!(row_count, 3);
      end;
    end if;
  end;
end);

proc ch1()
begin
  let base := 500;
  cursor C like (k1 int, k2 text, v1 bool, v2 text, v3 real);
  declare K cursor like C(k1,k2);

  let i := 0;
  for i < 10; i += 1;
  begin
    -- note that 1/3 of parents do not have this child
    if i % 3 != 2 then
      fetch K() from values() @dummy_seed(base + i) @dummy_nullables;
      fetch C(like K) from values(from K) @dummy_seed(base + i * 2) @dummy_nullables;
      out union C;
      fetch C(like K) from values(from K) @dummy_seed(base + i * 2 + 1) @dummy_nullables;
      out union C;
    end if;
  end;
end;

proc ch2()
begin
  let base := 1000;
  cursor C like (k3 integer, k4 text, v1 bool, v2 text, v3 real);
  declare K cursor like C(k3, k4);

  let i := 0;
  for i < 10; i += 1;
  begin
    -- note that 1/3 of parents do not have this child
    if i % 3 != 1 then
      fetch K() from values() @dummy_seed(base + i) @dummy_nullables;
      fetch C(like K) from values(from K) @dummy_seed(base + i * 2) @dummy_nullables;
      out union C;
      fetch C(like K) from values(from K) @dummy_seed(base + i * 2 + 1) @dummy_nullables;
      out union C;
    end if;
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
  cursor C like (k1 int, k2 text, k3 int, k4 text, v1 bool, v2 text, v3 real);
  declare D cursor like C;
  let i := 0;
  for i < 10; i += 1;
  begin
    fetch C() from values() @dummy_seed(i) @dummy_nullables;

    -- ch1 keys are +500
    fetch D() from values() @dummy_seed(i + 500) @dummy_nullables;
    update cursor C using D.k1 k1, D.k2 k2;

    -- ch2 keys are +1000
    fetch D() from values() @dummy_seed(i + 1000) @dummy_nullables;
    update cursor C using D.k3 k3, D.k4 k4;

    out union C;
  end;
end;

proc parent_child()
begin
  out union call parent() join
    call ch1() using (k1, k2) AS ch1 and
    call ch2() using (k3, k4) AS ch2;
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
    EXPECT_EQ!(P.k1, i + 500);
    EXPECT_EQ!(P.k2, printf("k2_%d", i + 500));
    EXPECT_EQ!(P.k3, i + 1000);
    EXPECT_EQ!(P.k4, printf("k4_%d", i + 1000));
    EXPECT_EQ!(P.k4, printf("k4_%d", i + 1000));
    EXPECT_EQ!(P.v1, not not i);
    EXPECT_EQ!(P.v2, printf("v2_%d", i));
    EXPECT_EQ!(P.v3, i);

    let count_rows := 0;
    declare C1 cursor for P.ch1;
    loop fetch C1
    begin
      EXPECT_EQ!(P.k1, C1.k1);
      EXPECT_EQ!(P.k2, C1.k2);
      EXPECT_EQ!(C1.v1, not not 500 + i * 2 + count_rows);
      EXPECT_EQ!(C1.v2, printf("v2_%d", 500 + i * 2 + count_rows));
      EXPECT_EQ!(C1.v3, 500 + i * 2 + count_rows);
      count_rows := count_rows + 1;
    end;

    EXPECT_EQ!(count_rows, case when i % 3 == 2 then 0 else 2 end);

    count_rows := 0;
    declare C2 cursor for P.ch2;
    loop fetch C2
    begin
      EXPECT_EQ!(P.k3, C2.k3);
      EXPECT_EQ!(P.k4, C2.k4);
      EXPECT_EQ!(C2.v1, not not 1000 + i * 2 + count_rows);
      EXPECT_EQ!(C2.v2, printf("v2_%d", 1000 + i * 2 + count_rows));
      EXPECT_EQ!(C2.v3, 1000 + i * 2 + count_rows);
      count_rows := count_rows + 1;
    end;

    EXPECT_EQ!(count_rows, case when i % 3 == 1 then 0 else 2 end);

    i += 1;
  end;
end;

TEST!(parent_child_results,
begin
  let results := parent_child();
  verify_parent_child_results(results);

  let alt_results := parent_child_simple_pattern();
  declare r object;
  r := alt_results;

  -- shape compatible, cast away ch1/ch2 vs. ch1_filter/ch2_filter
  -- this verifies that the manually created parent/child result is the same
  verify_parent_child_results(r);
end);

TEST!(string_dictionary,
begin
  let i := 1;
  for i <= 512; i *= 2;
  begin
    let dict := cql_string_dictionary_create();

    let j := 0;
    for j < i; j += 2;
    begin
      -- set to bogus original value
      let added := dict:add(printf("%d", j), "0");
      EXPECT!(added);

      let zero_val := dict:find(printf("%d", j));
      EXPECT_EQ!(zero_val, "0");

      -- replace
      added := dict:add(printf("%d", j), printf("%d", j * 100));
      EXPECT!(not added);
    end;

    j := 0;
    for j < i; j += 1;
    begin
      let result := dict:find(printf("%d", j));
      EXPECT_EQ!(result, case when j % 2 then null else printf("%d", j * 100) end);
    end;
  end;

  -- test null lookup, always fails
  EXPECT_EQ!(dict:find(null), null);
end);

TEST!(long_dictionary,
begin
  let i := 1;
  for i <= 512; i *= 2;
  begin
    let dict := cql_long_dictionary_create();

    let j := 0;
    for j < i; j += 2;
    begin
      -- set to bogus original value
      let added := dict:add(printf("%d", j), 0);
      EXPECT!(added);

      let zero_val := dict:find(printf("%d", j));
      EXPECT_EQ!(zero_val, 0);

      -- replace
      added := dict:add(printf("%d", j), j * 100);
      EXPECT!(not added);
    end;

    j := 0;
    for j < i; j += 1;
    begin
      let result := dict[printf("%d", j)];
      EXPECT_EQ!(result, case when j % 2 then null else j * 100 end);
    end;
  end;

  -- test null lookup, always fails
  EXPECT_EQ!(dict:find(null), null);
end);

TEST!(real_dictionary,
begin
  let i := 1;
  for i <= 512; i *= 2;
  begin
    let dict := cql_real_dictionary_create();

    let j := 0;
    for j < i; j += 2;
    begin
      -- set to bogus original value
      let added := dict:add(printf("%d", j), 0);
      EXPECT!(added);

      let zero_val := dict:find(printf("%d", j));
      EXPECT_EQ!(zero_val, 0);

      -- replace
      added := dict:add(printf("%d", j), j * 100.5);
      EXPECT!(not added);
    end;

    j := 0;
    for j < i; j += 1;
    begin
      let result := dict[printf("%d", j)];
      EXPECT_EQ!(result, case when j % 2 then null else j * 100.5 end);
      j += 1;
    end;
  end;

  -- test null lookup, always fails
  EXPECT_EQ!(dict:find(null), null);
end);

create proc blob_for_real(x real!, out result blob<storage_one_real>!)
begin
  declare C cursor like storage_one_real;
  fetch C from values(x);
  result := C:to_blob;
end;

TEST!(blob_dictionary,
begin
  let zero := blob_for_real(0);
  cursor C like storage_one_real;

  let i := 1;
  for i <= 512; i *= 2;
  begin
    let dict := cql_blob_dictionary_create();

    let j := 0;
    for j < i; j += 2;
    begin
      -- set to bogus original value
      let added := dict:add(printf("%d", j), zero);
      EXPECT!(added);

      let zero_val := dict:find(printf("%d", j)) ~blob<storage_one_real>~ :ifnull_throw;
      fetch C from values (1);  -- not zero, just to be sure the value changes
      C:from_blob(zero_val);
      EXPECT_EQ!(C.data, 0);

      -- replace
      let b := blob_for_real(j * 100.5);
      added := dict:add(printf("%d", j), b);
      EXPECT!(not added);
    end;

    j := 0;
    for j < i; j += 1;
    begin
      let result := dict[printf("%d", j)] ~blob<storage_one_real>~;

      if j % 2 then
        EXPECT_EQ!(result, null);
      else
        C:from_blob(result);
        EXPECT_EQ!(C.data, j * 100.5);
      end if;
    end;
  end;

  -- test null lookup, always fails
  EXPECT_EQ!(dict:find(null), null);
end);


declare func _cql_contains_column_def(haystack text, needle text) BOOL not null;

-- _cql_contains_column_def is used by the schema upgrade logic to find string matches the indicate a column is present
-- it's the same as this expression: haystack glob printf('*[) ]%s*', needle)
-- any null arguments yield a false result
TEST!(cql_contains_column_def,
begin
  -- trivial cases all fail, the "needle" has to be reasonable to even have a chance to match
  EXPECT!(not _cql_contains_column_def(null, 'x'));
  EXPECT!(not _cql_contains_column_def('x', null));
  EXPECT!(not _cql_contains_column_def('', 'bar'));
  EXPECT!(not _cql_contains_column_def('foo', ''));

  EXPECT!(_cql_contains_column_def("create table foo(x integer)", "x integer"));
  EXPECT!(not _cql_contains_column_def("create table foo(xx integer)", "x integer"));
  EXPECT!(_cql_contains_column_def("create table foo(id integer, x integer)", "x integer"));
  EXPECT!(not _cql_contains_column_def("create table foo(id integer, xx integer)", "x integer"));

  -- it's expecting normalized text so non-canonical matches don't count
  EXPECT!(not _cql_contains_column_def("create table foo(id integer, x Integer)", "x integer"));

  -- column name at the start isn't a match, there has to be a space or paren
  EXPECT!(not _cql_contains_column_def("x integer", "x integer"));
end);

-- cql utilities for making a basic string list
-- this is not a very functional list but schema helpers might need
-- generic lists of strings so we offer these based on bytebuf

TEST!(cql_string_list,
begin
  -- this version does not use any of the pipeline shortcuts
  -- in case there are bugs with that transform this test would pass
  let list := cql_string_list_create();
  EXPECT_EQ!(0, cql_string_list_count(list));
  cql_string_list_add(list, "hello");
  cql_string_list_add(list, "goodbye");
  EXPECT_EQ!(2, cql_string_list_count(list));
  EXPECT_EQ!("hello", cql_string_list_get_at(list, 0));
  EXPECT_EQ!("goodbye", cql_string_list_get_at(list, 1));
end);

TEST!(cql_string_list_as_array,
begin
  -- this version uses the better notation which should
  -- compile into the same code as the above
  let list := cql_string_list_create();
  EXPECT_EQ!(0, list.count);
  list:add("hello"):add("goodbye");
  EXPECT_EQ!(2, list.count);
  EXPECT_EQ!("hello", list[0]);
  EXPECT_EQ!("goodbye", list[1]);

  -- use the setter, too
  list[0] := "salut";
  EXPECT_EQ!(2, list.count);
  EXPECT_EQ!("salut", list[0]);
  EXPECT_EQ!("goodbye", list[1]);
end);

TEST!(cql_blob_list,
begin
  -- this version uses the better notation which should
  -- compile into the same code as the above
  let list := cql_blob_list_create();
  EXPECT_EQ!(0, list.count);
  list:add(blob_from_string("hello")):add(blob_from_string("goodbye"));
  EXPECT_EQ!(2, list.count);
  EXPECT_EQ!("hello", string_from_blob(list[0]));
  EXPECT_EQ!("goodbye", string_from_blob(list[1]));

  -- use the setter, too
  list[0] := blob_from_string("salut");
  EXPECT_EQ!(2, list.count);
  EXPECT_EQ!("salut", string_from_blob(list[0]));
  EXPECT_EQ!("goodbye", string_from_blob(list[1]));
end);

TEST!(cql_object_list,
begin
  -- this version uses the better notation which should
  -- compile into the same code as the above
  let list := cql_object_list_create();
  EXPECT_EQ!(0, list.count);
  list:add("hello":box):add("goodbye":box);
  EXPECT_EQ!(2, list.count);
  EXPECT_EQ!("hello", list[0] ~object<cql_box>~ :to_text);
  EXPECT_EQ!("goodbye", list[1] ~object<cql_box>~ :to_text);

  -- use the setter, too
  list[0] := "salut":box;
  EXPECT_EQ!(2, list.count);
  EXPECT_EQ!("salut", list[0] ~object<cql_box>~ :to_text);
  EXPECT_EQ!("goodbye", list[1] ~object<cql_box>~: to_text);
end);

TEST!(cql_long_list,
begin
  let list := cql_long_list_create();
  EXPECT_EQ!(0, list.count);
  list:add(10):add(20);
  EXPECT_EQ!(2, list.count);
  EXPECT_EQ!(10, list[0]);
  EXPECT_EQ!(20, list[1]);

  -- use the setter, too
  list[0] := 100;
  EXPECT_EQ!(2, list.count);
  EXPECT_EQ!(100, list[0]);
  EXPECT_EQ!(20, list[1]);

  -- test some growth
  list := cql_long_list_create();
  let i := 0;
  for i < 1024; i += 1;
  begin
    list:add(i * 3);
  end;

  i := 0;
  for i < 1024; i += 1;
  begin
    EXPECT_EQ!(list[i], i * 3);
  end;
end);

TEST!(cql_real_list,
begin
  let list := cql_real_list_create();
  EXPECT_EQ!(0, list.count);
  list:add(10.5):add(20.5);
  EXPECT_EQ!(2, list.count);
  EXPECT_EQ!(10.5, list[0]);
  EXPECT_EQ!(20.5, list[1]);

  -- use the setter, too
  list[0] := 100.25;
  EXPECT_EQ!(2, list.count);
  EXPECT_EQ!(100.25, list[0]);
  EXPECT_EQ!(20.5, list[1]);

  -- test some growth
  list := cql_real_list_create();
  let i := 0;
  for i < 1024; i += 1;
  begin
    list:add(i * 3.5);
  end;

  i := 0;
  for i < 1024; i += 1;
  begin
    EXPECT_EQ!(list[i], i * 3.5);
  end;
end);

TEST!(cursor_formatting,
begin
  cursor C like (a_bool bool, an_int int, a_long long, a_real real, a_string text, a_blob blob);
  -- load all nulls
  fetch C() from values ();

  let s1 := C:format;
  EXPECT_EQ!(s1, "a_bool:null|an_int:null|a_long:null|a_real:null|a_string:null|a_blob:null");

  -- nullable values not null
  fetch C(a_blob, a_real) from values ((select cast('xyzzy' as blob)), 3.5) @dummy_seed(1) @dummy_nullables;
  let s2 := C:format;
  EXPECT_EQ!(s2, "a_bool:true|an_int:1|a_long:1|a_real:3.5|a_string:a_string_1|a_blob:length 5 blob");

  declare D cursor like (a_bool bool!, an_int int!, a_long long!, a_real real!, a_string text!, a_blob blob!);

  -- not null values
  fetch D(a_blob, a_real) from values ((select cast('xyzzy' as blob)), 3.5) @dummy_seed(1);
  let s3 := cql_cursor_format(D);
  EXPECT_EQ!(s3, "a_bool:true|an_int:1|a_long:1|a_real:3.5|a_string:a_string_1|a_blob:length 5 blob");

  -- test single column formatting
  -- we don't exercise all the types because it uses the same code as the above
  -- so we only have to exercise the entry point
  let s4 := D:format_col(3);
  EXPECT_EQ!(s4, "3.5");
end);

TEST!(primitive_formatting,
begin
  EXPECT_EQ!(null:fmt, "null");
  EXPECT_EQ!(1:fmt, "1");
  EXPECT_EQ!(true:fmt, "true");
  EXPECT_EQ!(2L:fmt, "2");
  EXPECT_EQ!(2.5:fmt, "2.5");
  EXPECT_EQ!("foo":fmt, "foo");
  EXPECT_EQ!(1:box:fmt, "generic object");
  EXPECT_EQ!(cql_blob_from_int("foo", 52):fmt, "length 5 blob");
end);

TEST!(compressed_strings,
begin
  let x := "hello hello hello hello";
  let y := cql_compressed("hello hello hello hello");
  EXPECT_EQ!(x, y);

  let empty1 := "";
  let empty2 := cql_compressed("");
  EXPECT_EQ!(empty1, empty2);
end);

-- external implementation will test the exact value passed
declare proc take_bool_not_null(x bool!, y bool!);
declare proc take_bool(x bool, y bool);

TEST!(normalize_bool_on_call,
begin
  take_bool(10, true);
  take_bool(0, false);

  take_bool_not_null(10, true);
  take_bool_not_null(0, false);
end);

@op blob : call key as bgetkey;

TEST!(blob_key_funcs,
begin
  let b := (select bcreatekey(112233, 1234, CQL_BLOB_TYPE_INT32, 5678, CQL_BLOB_TYPE_INT32));
  EXPECT_EQ!(112233, (select bgetkey_type(b)));
  EXPECT_EQ!(1234, (select b:key(0)));
  EXPECT_EQ!(5678, (select b:key(1)));

  b := (select bupdatekey(b, 1, 3456));
  EXPECT_EQ!(1234, (select b:key(0)));
  EXPECT_EQ!(3456, (select b:key(1)));

  b := (select bupdatekey(b, 0, 2345));
  EXPECT_EQ!(2345, (select b:key(0)));
  EXPECT_EQ!(3456, (select b:key(1)));

  -- note that CQL thinks that we are going to be returning a integer value from bgetkey here
  -- ad hoc calls to these functions aren't the normal way they are used
  b := (select bcreatekey(112234, 2, CQL_BLOB_TYPE_BOOL, 5.5, CQL_BLOB_TYPE_FLOAT));
  EXPECT_EQ!(112234, (select bgetkey_type(b)));
  EXPECT_EQ!((select b:key(0)), 1);
  EXPECT_EQ!((select b:key(1) ~real~), 5.5);

  b := (select bupdatekey(b, 0, 0));
  EXPECT_EQ!((select b:key(0)), 0);

  b := (select bupdatekey(b, 0, 1, 1, 3.25));
  EXPECT_EQ!((select b:key(0)), 1);
  EXPECT_EQ!((select b:key(1) ~real~), 3.25);

  -- note that CQL thinks that we are going to be returning a integer value from bgetkey here
  -- ad hoc calls to these functions aren't the normal way they are used
  b := (select bcreatekey(112235, 0x12345678912L, CQL_BLOB_TYPE_INT64, 0x87654321876L, CQL_BLOB_TYPE_INT64));
  EXPECT_EQ!(112235, (select bgetkey_type(b)));
  EXPECT_EQ!((select b:key(0)), 0x12345678912L);
  EXPECT_EQ!((select b:key(1)), 0x87654321876L);

  b := (select bupdatekey(b, 0, 0xabcdef01234));
  EXPECT_EQ!((select b:key(0)), 0xabcdef01234);

  -- cheese the return type with casts to work around the fixed type of bgetkey
  b := (select bcreatekey(112236,  x'313233', CQL_BLOB_TYPE_BLOB, 'hello', CQL_BLOB_TYPE_STRING));
  EXPECT_EQ!(112236, (select bgetkey_type(b)));
  EXPECT!((select b:key(0) ~blob~ == x'313233'));
  EXPECT_EQ!((select b:key(1) ~text~), 'hello');

  b := (select bupdatekey(b, 0, x'4546474849'));
  EXPECT!((select b:key(0) ~blob~ == x'4546474849'));

  b := (select bupdatekey(b, 0, x'fe'));
  EXPECT!((select b:key(0) ~blob~ == x'fe'));

  b := (select bupdatekey(b, 0, x''));
  EXPECT!((select b:key(0) ~blob~ == x''));

  b := (select bupdatekey(b, 1, 'garbonzo'));
  EXPECT_EQ!((select b:key(1) ~text~), 'garbonzo');
  EXPECT!((select b:key(0) ~blob~ == x''));

  b := (select bupdatekey(b, 0, x'4546474849', 1, 'h'));
  EXPECT!((select b:key(0) ~blob~ == x'4546474849'));
  EXPECT_EQ!((select b:key(1) ~text~), 'h');
end);

TEST!(blob_createkey_func_errors,
begin
  -- not enough args
  EXPECT_EQ!((select bcreatekey(112233)), null);

  -- args have the wrong parity (it should be pairs)
  EXPECT_EQ!((select bcreatekey(112233, 1)), null);

  -- the first arg should be an int64
  EXPECT_EQ!((select bcreatekey('112233', 1, 1)), null);

  -- the arg type should be a small integer
  EXPECT_EQ!((select bcreatekey(112233, 1, 'error')), null);

  -- the arg type should be a small integer
  EXPECT_EQ!((select bcreatekey(112233, 1000, 99)), null);

  -- the value doesn't match the blob type -- int32
  EXPECT_EQ!((select bcreatekey(112233, 'xxx', CQL_BLOB_TYPE_BOOL)), null);

  -- the value doesn't match the blob type -- int32
  EXPECT_EQ!((select bcreatekey(112233, 'xxx', CQL_BLOB_TYPE_INT32)), null);

  -- the value doesn't match the blob type -- int64
  EXPECT_EQ!((select bcreatekey(112233, 'xxx', CQL_BLOB_TYPE_INT64)), null);

  -- the value doesn't match the blob type -- float
  EXPECT_EQ!((select bcreatekey(112233, 'xxx', CQL_BLOB_TYPE_FLOAT)), null);

  -- the value doesn't match the blob type -- string
  EXPECT_EQ!((select bcreatekey(112233, 1, CQL_BLOB_TYPE_STRING)), null);

  -- the value doesn't match the blob type -- blob
  EXPECT_EQ!((select bcreatekey(112233, 1, CQL_BLOB_TYPE_BLOB)), null);
end);

TEST!(blob_getkey_func_errors,
begin
  -- a test blob
  let b := (select bcreatekey(112235, 0x12345678912L, CQL_BLOB_TYPE_INT64, 0x87654321876L, CQL_BLOB_TYPE_INT64));

  -- second arg is too big  only (0, 1) are valid
  EXPECT_EQ!((select b:key(2)), null);

  -- second arg is negative
  EXPECT_EQ!((select b:key(-1)), null);

  -- the blob isn't a real encoded blob
  EXPECT_EQ!((select bgetkey(x'0000000000000000000000000000', 0)), null);

  -- the blob isn't a real encoded blob
  EXPECT_EQ!((select bgetkey_type(x'0000000000000000000000000000')), null);
end);

TEST!(blob_updatekey_func_errors,
begin
  -- a test blob
  let b := (select bcreatekey(
    112235,
    false, CQL_BLOB_TYPE_BOOL,
    0x12345678912L, CQL_BLOB_TYPE_INT64,
    1.5, CQL_BLOB_TYPE_FLOAT,
    'abc', CQL_BLOB_TYPE_STRING,
    x'4546474849', CQL_BLOB_TYPE_BLOB
    ));

  -- not enough args
  EXPECT_EQ!((select bupdatekey(112233)), null);

  -- args have the wrong parity (it should be pairs)
  EXPECT_EQ!((select bupdatekey(112233, 1)), null);

  -- the first arg should be a blob
  EXPECT_EQ!((select bupdatekey(1234, 1, 1)), null);

  -- the first arg should be a blob in the standard format
  EXPECT_EQ!((select bupdatekey(x'0000000000000000000000000000', 1, 1)), null);

  -- the column index should be a small integer
  EXPECT_EQ!((select bupdatekey(b, 'error', 1)), null);

  -- the column index must be in range
  EXPECT_EQ!((select bupdatekey(b, 5, 1234)), null);

  -- the column index must be in range
  EXPECT_EQ!((select bupdatekey(b, -1, 1234)), null);

  -- the value doesn't match the blob type
  EXPECT_EQ!((select bupdatekey(b, 0, 'xxx')), null);
  EXPECT_EQ!((select bupdatekey(b, 1, 'xxx')), null);
  EXPECT_EQ!((select bupdatekey(b, 2, 'xxx')), null);
  EXPECT_EQ!((select bupdatekey(b, 3, 5.0)), null);
  EXPECT_EQ!((select bupdatekey(b, 4, 5.0)), null);

  -- can't update the same field twice (setting bool to false twice)
  EXPECT_EQ!((select bupdatekey(b, 0, 0, 0, 0)), null);
end);

@op blob : call val as bgetval;

TEST!(blob_val_funcs,
begin
  let k1 := 123412341234;
  let k2 := 123412341235;
  let b := (select bcreateval(112233, k1, 1234, CQL_BLOB_TYPE_INT32, k2, 5678, CQL_BLOB_TYPE_INT32));

  EXPECT_EQ!(112233, (select bgetval_type(b)));
  EXPECT_EQ!(1234, (select b:val(k1)));
  EXPECT_EQ!(5678, (select b:val(k2)));

  b := (select bupdateval(b, k2, 3456, CQL_BLOB_TYPE_INT32));

  EXPECT_NE!(b, null);
  EXPECT_EQ!((select bgetval_type(b)), 112233);
  EXPECT_NE!((select b:val(k1)), null);
  EXPECT_NE!((select b:val(k2)), null);

  EXPECT_EQ!(1234, (select b:val(k1)));
  EXPECT_EQ!(3456, (select b:val(k2)));

  b := (select bupdateval(b, k1, 2345, CQL_BLOB_TYPE_INT32));
  EXPECT_EQ!(2345, (select b:val(k1)));
  EXPECT_EQ!(3456, (select b:val(k2)));

  -- note that CQL thinks that we are going to be returning a integer value from bgetkey here
  -- ad hoc calls to these functions aren't the normal way they are used
  b := (select bcreateval(112234, k1, 2, CQL_BLOB_TYPE_BOOL, k2, 5.5, CQL_BLOB_TYPE_FLOAT));
  EXPECT_EQ!(112234, (select bgetval_type(b)));
  EXPECT_EQ!((select b:val(k1)), 1);
  EXPECT_EQ!((select b:val(k2) ~real~), 5.5);

  b := (select bupdateval(b, k1, 0, CQL_BLOB_TYPE_BOOL));
  EXPECT_EQ!((select b:val(k1)), 0);

  b := (select bupdateval(b, k1, 1, CQL_BLOB_TYPE_BOOL, k2, 3.25, CQL_BLOB_TYPE_FLOAT));
  EXPECT_EQ!((select b:val(k1)), 1);
  EXPECT_EQ!((select b:val(k2) ~real~), 3.25);

  -- note that CQL thinks that we are going to be returning a integer value from bgetval here
  -- ad hoc calls to these functions aren't the normal way they are used
  b := (select bcreateval(112235, k1, 0x12345678912L, CQL_BLOB_TYPE_INT64, k2, 0x87654321876L, CQL_BLOB_TYPE_INT64));
  EXPECT_EQ!((select bgetval_type(b)), 112235);
  EXPECT_EQ!((select b:val(k1)), 0x12345678912L);
  EXPECT_EQ!((select b:val(k2)), 0x87654321876L);

  b := (select bupdateval(b, k1, 0xabcdef01234, CQL_BLOB_TYPE_INT64));
  EXPECT_EQ!((select b:val(k1)), 0xabcdef01234);

  -- cheese the return type with casts to work around the fixed type of bgetval
  b := (select bcreateval(112236,  k1, x'313233', CQL_BLOB_TYPE_BLOB, k2, 'hello', CQL_BLOB_TYPE_STRING));
  EXPECT_EQ!(112236, (select bgetval_type(b)));
  EXPECT!((select b:val(k1) ~blob~ == x'313233'));
  EXPECT_EQ!((select b:val(k2) ~text~), 'hello');

  b := (select bupdateval(b, k1, x'4546474849', CQL_BLOB_TYPE_BLOB));
  EXPECT!((select b:val(k1) ~blob~ == x'4546474849'));

  b := (select bupdateval(b, k1, x'fe', CQL_BLOB_TYPE_BLOB));
  EXPECT!((select b:val(k1) ~blob~ == x'fe'));

  b := (select bupdateval(b, k1, x'', CQL_BLOB_TYPE_BLOB));
  EXPECT!((select b:val(k1) ~blob~ == x''));

  b := (select bupdateval(b, k2, 'garbonzo', CQL_BLOB_TYPE_STRING));
  EXPECT_EQ!((select b:val(k2) ~text~), 'garbonzo');
  EXPECT!((select b:val(k1) ~blob~ == x''));

  b := (select bupdateval(b, k1, x'4546474849', CQL_BLOB_TYPE_BLOB, k2, 'h', CQL_BLOB_TYPE_STRING));
  EXPECT!((select b:val(k1) ~blob~ == x'4546474849'));
  EXPECT_EQ!((select b:val(k2) ~text~), 'h');

  b := (select bcreateval(112234, k1, null, CQL_BLOB_TYPE_BOOL, k2, 5.5, CQL_BLOB_TYPE_FLOAT));
  EXPECT_EQ!(112234, (select bgetval_type(b)));
  EXPECT_EQ!((select b:val(k1)), null);  /* missing column */
  EXPECT_EQ!((select b:val(k2) ~real~), 5.5);
end);

TEST!(blob_createval_func_errors,
begin
  let k1 := 123412341234;

  -- not enough args
  EXPECT_EQ!((select bcreateval()), null);

  -- args have the wrong parity (it should be triples)
  EXPECT_EQ!((select bcreateval(112233, 1)), null);

  -- the first arg should be an int64
  EXPECT_EQ!((select bcreateval('112233', 1, 1, 1)), null);

  -- the field id should be an integer
  EXPECT_EQ!((select bcreateval(112233, 'error', 1, CQL_BLOB_TYPE_BOOL)), null);

  -- the arg type should be a small integer
  EXPECT_EQ!((select bcreateval(112233, k1, 1, 'error')), null);

  -- the field id type should be a small integer
  EXPECT_EQ!((select bcreateval(112233, 'k1', 1, CQL_BLOB_TYPE_BOOL)), null);

  -- the arg type should be a small integer
  EXPECT_EQ!((select bcreateval(112233, k1, 1000, 99)), null);

  -- the value doesn't match the blob type -- int32
  EXPECT_EQ!((select bcreateval(112233, k1, 'xxx', CQL_BLOB_TYPE_BOOL)), null);

  -- the value doesn't match the blob type -- int32
  EXPECT_EQ!((select bcreateval(112233, k1, 'xxx', CQL_BLOB_TYPE_INT32)), null);

  -- the value doesn't match the blob type -- int64
  EXPECT_EQ!((select bcreateval(112233, k1, 'xxx', CQL_BLOB_TYPE_INT64)), null);

  -- the value doesn't match the blob type -- float
  EXPECT_EQ!((select bcreateval(112233, k1, 'xxx', CQL_BLOB_TYPE_FLOAT)), null);

  -- the value doesn't match the blob type -- string
  EXPECT_EQ!((select bcreateval(112233, k1, 1, CQL_BLOB_TYPE_STRING)), null);

  -- the value doesn't match the blob type -- blob
  EXPECT_EQ!((select bcreateval(112233, k1, 1, CQL_BLOB_TYPE_BLOB)), null);
end);

TEST!(blob_getval_func_errors,
begin
  let k1 := 123412341234;
  let k2 := 123412341235;
  let b := (select bcreateval(112233, k1, 1234, CQL_BLOB_TYPE_INT32, k2, 5678, CQL_BLOB_TYPE_INT32));

  -- second arg is is not a valid key
  EXPECT_EQ!((select b:val(1111)), null);
end);

TEST!(blob_updateval_null_cases,
begin
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

  EXPECT_EQ!((select bgetval_type(b)), 112235);
  EXPECT_EQ!((select b:val(k1) ~bool~), false);
  EXPECT_EQ!((select b:val(k2)), 0x12345678912L);
  EXPECT_EQ!((select b:val(k3) ~real~), 1.5);
  EXPECT_EQ!((select b:val(k4) ~text~), 'abc');
  EXPECT!((select b:val(k5) ~blob~ == x'4546474849'));
  EXPECT_EQ!((select b:val(k6)), null);

  -- adding a new field id adds a field...
  b := (select bupdateval(b, k6, 1.1, CQL_BLOB_TYPE_FLOAT));
  EXPECT_EQ!((select bgetval_type(b)), 112235);
  EXPECT_EQ!((select b:val(k6) ~real~), 1.1);
  EXPECT_EQ!((select b:val(k1) ~bool~), false);
  EXPECT_EQ!((select b:val(k2)), 0x12345678912L);
  EXPECT_EQ!((select b:val(k3) ~real~), 1.5);
  EXPECT_EQ!((select b:val(k4) ~text~), 'abc');
  EXPECT!((select b:val(k5) ~blob~ == x'4546474849'));

  -- remove the field k6
  b := (select bupdateval(b, k6, null, CQL_BLOB_TYPE_FLOAT));

  EXPECT_EQ!((select bgetval_type(b)), 112235);
  EXPECT_EQ!((select b:val(k6)), null);
  EXPECT_EQ!((select b:val(k1) ~bool~), false);
  EXPECT_EQ!((select b:val(k2)), 0x12345678912L);
  EXPECT_EQ!((select b:val(k3) ~real~), 1.5);
  EXPECT_EQ!((select b:val(k4) ~text~), 'abc');
  EXPECT!((select b:val(k5) ~blob~ == x'4546474849'));

  -- remove the field k6 again (removing a not present field)
  b := (select bupdateval(b, k6, null, CQL_BLOB_TYPE_FLOAT));
  EXPECT_EQ!((select bgetval_type(b)), 112235);
  EXPECT_EQ!((select b:val(k6)), null);
  EXPECT_EQ!((select b:val(k1) ~bool~), false);
  EXPECT_EQ!((select b:val(k2)), 0x12345678912L);
  EXPECT_EQ!((select b:val(k3) ~real~), 1.5);
  EXPECT_EQ!((select b:val(k4) ~text~), 'abc');
  EXPECT!((select b:val(k5) ~blob~ == x'4546474849'));

  -- remove several fields
  b := (select bupdateval(
    b,
    k1, null, CQL_BLOB_TYPE_BOOL,
    k2, 0x12345678912L, CQL_BLOB_TYPE_INT64,
    k3, null, CQL_BLOB_TYPE_FLOAT,
    k4, 'abc', CQL_BLOB_TYPE_STRING,
    k5, null, CQL_BLOB_TYPE_BLOB
    ));

  EXPECT_EQ!((select bgetval_type(b)), 112235);
  EXPECT_EQ!((select b:val(k1)), null);
  EXPECT_EQ!((select b:val(k3)), null);
  EXPECT_EQ!((select b:val(k5)), null);
  EXPECT_EQ!((select b:val(k6)), null);
  EXPECT_EQ!((select b:val(k2)), 0x12345678912L);
  EXPECT_EQ!((select b:val(k4) ~text~), 'abc');

  -- remove all remaining fields
  b := (select bupdateval(
    b,
    k1, null, CQL_BLOB_TYPE_BOOL,
    k2, null, CQL_BLOB_TYPE_INT64,
    k4, null, CQL_BLOB_TYPE_STRING
    ));

  EXPECT_EQ!((select bgetval_type(b)), 112235);
  EXPECT_EQ!((select b:val(k1)), null);
  EXPECT_EQ!((select b:val(k2)), null);
  EXPECT_EQ!((select b:val(k3)), null);
  EXPECT_EQ!((select b:val(k4)), null);
  EXPECT_EQ!((select b:val(k5)), null);
  EXPECT_EQ!((select b:val(k6)), null);

  -- put some fields back
  b := (select bupdateval(
    b,
    k2, 0x12345678912L, CQL_BLOB_TYPE_INT64,
    k4, 'abc', CQL_BLOB_TYPE_STRING
    ));

  EXPECT_EQ!((select bgetval_type(b)), 112235);
  EXPECT_EQ!((select b:val(k1)), null);
  EXPECT_EQ!((select b:val(k3)), null);
  EXPECT_EQ!((select b:val(k5)), null);
  EXPECT_EQ!((select b:val(k6)), null);
  EXPECT_EQ!((select b:val(k2)), 0x12345678912L);
  EXPECT_EQ!((select b:val(k4) ~text~), 'abc');

  -- the blob isn't a real encoded blob
  EXPECT_EQ!((select bgetval(x'0000000000000000000000000000', k1)), null);

  -- the blob isn't a real encoded blob
  EXPECT_EQ!((select bgetval_type(x'0000000000000000000000000000')), null);
end);

TEST!(blob_updateval_func_errors,
begin
  -- a test blob
  let k1 := 123412341234;
  let k2 := 123412341235;
  let k3 := 123412341236;
  let k4 := 123412341237;
  let k5 := 123412341238;
  let k6 := 123412341239;

  let b := (select bcreateval(
    112235,
    k1, false, CQL_BLOB_TYPE_BOOL,
    k2, 0x12345678912L, CQL_BLOB_TYPE_INT64,
    k3, 1.5, CQL_BLOB_TYPE_FLOAT,
    k4, 'abc', CQL_BLOB_TYPE_STRING,
    k5, x'4546474849', CQL_BLOB_TYPE_BLOB
    ));

  -- not enough args
  EXPECT_EQ!((select bupdateval(112233)), null);

  -- args have the wrong parity (it should be pairs)
  EXPECT_EQ!((select bupdateval(112233, 1)), null);

  -- the first arg should be a blo)b
  EXPECT_EQ!((select bupdateval(1234, k1, 1, CQL_BLOB_TYPE_BOOL)), null);

  -- the column index should be a small integer
  EXPECT_EQ!((select bupdateval(b, 'error', 1, CQL_BLOB_TYPE_BOOL)), null);

  -- duplicate field id is an error
  EXPECT_EQ!((select bupdateval(b, k1, 1, CQL_BLOB_TYPE_BOOL, k1, 1, CQL_BLOB_TYPE_BOOL)), null);

    -- the value doesn't match the blob type
  EXPECT_EQ!((select bupdateval(b, k1, 'xxx', CQL_BLOB_TYPE_BOOL)), null);
  EXPECT_EQ!((select bupdateval(b, k2, 'xxx', CQL_BLOB_TYPE_INT64)), null);
  EXPECT_EQ!((select bupdateval(b, k3, 'xxx', CQL_BLOB_TYPE_FLOAT)), null);
  EXPECT_EQ!((select bupdateval(b, k4, 5.0, CQL_BLOB_TYPE_STRING)), null);
  EXPECT_EQ!((select bupdateval(b, k5, 5.0, CQL_BLOB_TYPE_BLOB)), null);

  -- adding a new column but the types are not compatible
  EXPECT_EQ!((select bupdateval(b, k1, 1, CQL_BLOB_TYPE_BOOL, k6, 'xxx', CQL_BLOB_TYPE_BOOL)), null);

  -- the first arg should be a blob in the standard format
  EXPECT_EQ!((select bupdateval(x'0000000000000000000000000000', k1, 0, CQL_BLOB_TYPE_BOOL)), null);
end);

TEST!(backed_tables,
begin
  -- seed some data
  insert into backed values (1, 100, 101), (2, 200, 201);

  -- validate count and the math of the columns
  let r := 0;
  cursor C for select * from backed;
  loop fetch C
  begin
    EXPECT_EQ!(C.`value one`, 100 * C.id);
    EXPECT_EQ!(C.`value two`, 100 * C.id + 1);
    r := r + 1;
  end;
  EXPECT_EQ!(r, 2);

  -- update some keys and values
  update backed set id=3, `value one`=300, `value two`=301 where id = 2;
  update backed set id=4, `value one`=400, `value two`=401 where `value one` = 100;

  -- reverify it still makes sense
  r := 0;
  declare D cursor for select * from backed;
  loop fetch D
  begin
    EXPECT_EQ!(D.`value one`, 100 * D.id);
    EXPECT_EQ!(D.`value two`, 100 * D.id + 1);
    r := r + 1;
  end;
  EXPECT_EQ!(r, 2);

  -- delete one row
  delete from backed where `value two` = 401;

  -- validate again, use aggregate functions and nested select alternatives
  EXPECT_EQ!(1, (select count(*) from backed));
  EXPECT_EQ!(300, (select `value one` from backed where id = 3));

  -- update using the values already in the table
  update backed set id = id + 1, `value one` = `value one` + 100, `value two` = backed.`value two` + 100;

  EXPECT_EQ!(400, (select `value one` from backed where id = 4));

  -- another swizzle using values to update keys and keys to update values
  update backed set id = (`value one` + 100) / 100, `value one` = (id + 1) * 100, `value two` = `value two` + 100;

  EXPECT_EQ!(500, (select `value one` from backed where id = 5));

  -- insert a row with only key and no value
  insert into backed2(id) values(1);
  EXPECT_EQ!(1, (select id from backed2));
end);

[[backed_by=backing]]
create table backed_table_with_defaults(
  pk1 int default 1000,
  pk2 int default 2000,
  x int default 3000,
  y int default 4000,
  z text default "foo",
  constraint pk primary key (pk1, pk2)
);

TEST!(backed_tables_default_values,
begin
  insert into backed_table_with_defaults(pk1, x) values (1, 100), (2, 200);

  cursor C for select * from backed_table_with_defaults;

  -- verify default values inserted
  fetch C;
  EXPECT!(C);
  EXPECT_EQ!(C.pk1, 1);
  EXPECT_EQ!(C.pk2, 2000);
  EXPECT_EQ!(C.x, 100);
  EXPECT_EQ!(C.y, 4000);

  -- and second row
  fetch C;
  EXPECT!(C);
  EXPECT_EQ!(C.pk1, 2);
  EXPECT_EQ!(C.pk2, 2000);
  EXPECT_EQ!(C.x, 200);
  EXPECT_EQ!(C.y, 4000);

  -- and no third row
  fetch C;
  EXPECT!(not C);
end);

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
begin
  load_mixed_backed();

  cursor C for select * from mixed_backed;
  fetch C;
  EXPECT!(C);
  EXPECT_EQ!(C.id, 1);
  EXPECT_EQ!(C.name, "a name");
  EXPECT_EQ!(C.code, 12);
  EXPECT_EQ!(C.flag, 1);
  EXPECT_EQ!(C.rate, 5);
  EXPECT_EQ!(string_from_blob(C.bl), "blob1");

  fetch C;
  EXPECT!(C);
  EXPECT_EQ!(C.id, 2);
  EXPECT_EQ!(C.name, "another name");
  EXPECT_EQ!(C.code, 14);
  EXPECT_EQ!(C.flag, 1);
  EXPECT_EQ!(C.rate, 7);
  EXPECT_EQ!(string_from_blob(C.bl), "blob2");

  fetch C;
  EXPECT!(not C);
end);

-- now attempt a mutation
TEST!(mutate_mixed_backed,
begin
  declare new_code long;
  declare code_ long;
  new_code := 88;
  declare id_ int;
  id_ := 2;  -- either works

  load_mixed_backed();

  update mixed_backed set code = new_code where id = id_;
  declare updated_cursor cursor for select code from mixed_backed where id = id_;
  fetch updated_cursor into code_;
  close updated_cursor;
  EXPECT_EQ!(code_, new_code);
end);

[[backed_by=backing]]
create table compound_backed(
  id1 text,
  id2 text,
  val real,
  primary key (id1, id2)
);

@macro(stmt_list) insert_basic_data!(tab! expr)
begin
  insert into @ID(tab!) values('foo', 'bar', 1);
  insert into @ID(tab!) values('goo', 'bar', 2);
  insert into @ID(tab!) values('foo', 'stew', 3);
end;

 -- We're going to make sure that the key blob stays in canonical form
 -- no matter how we update it.  This is a bit tricky for variable fields
 -- which have to stay in a fixed order so this test exercises that.
TEST!(mutate_compound_backed_key,
begin
  insert_basic_data!(compound_backed);

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
  EXPECT_EQ!(C.id1, 'zoo');
  EXPECT_EQ!(C.id2, 'bar');
  EXPECT_EQ!(C.val, 1);

  fetch C;
  EXPECT!(C);
  EXPECT_EQ!(C.id1, 'foo');
  EXPECT_EQ!(C.id2, 'bar');
  EXPECT_EQ!(C.val, 2);

  fetch C;
  EXPECT!(C);
  EXPECT_EQ!(C.id1, 'foo');
  EXPECT_EQ!(C.id2, 'stew');
  EXPECT_EQ!(C.val, 3);

  fetch C;
  EXPECT!(not C);
end);

-- This a bogus proc but it makes an interesting test it can be called directly
-- or using proc as func and we need both for this test.  The purpose is to
-- make sure that we can handle expression statements and rewrite them as
-- CALL statements and do so with an observable side-effect.
var a_global int!;
proc mutator(new_val int!, out result int!)
begin
  result := new_val + 1;
  a_global := result;
end;

-- verify that we can create expression statementsd we use "mutator" to ensure
-- that the code ran because it has an observable side effect
TEST!(expr_stmt_rewrite,
begin
  a_global := 0;

  -- not a top level call
  case when 1 then mutator(1) end;
  EXPECT_EQ!(a_global, 2);
  -- not a top level call
  case when 1 then mutator(100) end;
  EXPECT_EQ!(a_global, 101);

  -- same thing but this time we rewrite as a CALL statement
  var result int!;
  mutator(2, result);
  EXPECT_EQ!(a_global, 3);
  EXPECT_EQ!(result, 3);

  -- pipeline syntax call, the last one is the proc form so it needs all the
  -- args we can actually do better on this by adding special logic to allow
  -- proc_as_func at the top level if the arg count is ok for that not yet
  -- implemented though
  20:mutator():mutator(result);
  EXPECT_EQ!(result, 22);
  EXPECT_EQ!(a_global, 22);
end);


-- handling box tests generically,  box the value and unbox it
@MACRO(stmt_list) box_test!(x! expr, t! expr, type_val! expr)
begin
  -- make nullable variable and hold the given value to test
  let @tmp(val) := nullable(x!);

  -- now box and unbox
  let @tmp(box) := @tmp(val):box;
  let @tmp(unboxed) := @tmp(box):@id('to_', t!);
  EXPECT_EQ!(@tmp(unboxed), @tmp(val));
  EXPECT_EQ!(@tmp(box):cql_box_get_type, type_val!);

  -- test null value of the correct type (e.g. nullable bool)
  @tmp(val) := null;

  -- now box and unbox a value that happens to be null
  @tmp(box) := @tmp(val):box;
  @tmp(unboxed) := @tmp(box):@id('to_', t!);
  EXPECT_EQ!(@tmp(unboxed), null);
end;

-- normal boxing validation for the various types
-- the box_test! macro does the work, box and unbox
-- and expect the same result.
TEST!(boxing_normal,
begin
  let bl := (select 'a blob' ~blob~);

  box_test!(5, 'int', CQL_DATA_TYPE_INT32);
  box_test!(7.5, 'real', CQL_DATA_TYPE_DOUBLE);
  box_test!(true, 'bool', CQL_DATA_TYPE_BOOL);
  box_test!(1000L, 'long', CQL_DATA_TYPE_INT64);
  box_test!('abcde', 'text', CQL_DATA_TYPE_STRING);
  box_test!(bl, 'blob', CQL_DATA_TYPE_BLOB);
  box_test!(5:box, 'object', CQL_DATA_TYPE_OBJECT);
end);

-- unboxing validation, unbox incorrect type
TEST!(unboxing_incorrect_types,
begin
  -- now we store the wrong kind of stuff in the boxed object
  -- all the unboxing operations should fail.

  let box_bool := 5:box;   -- not a boxed bool
  let box_int := 5.0:box;  -- etc.
  let box_long := 5:box;
  let box_real := 5:box;
  let box_text := 5:box;
  let box_blob := 5:box;
  let box_object := 5:box;

  -- they all have the wrong thing in them
  EXPECT_EQ!(box_int:cql_unbox_int, null);
  EXPECT_EQ!(box_bool:cql_unbox_bool, null);
  EXPECT_EQ!(box_real:cql_unbox_real, null);
  EXPECT_EQ!(box_long:cql_unbox_long, null);
  EXPECT_EQ!(box_text:cql_unbox_text, null);
  EXPECT_EQ!(box_blob:cql_unbox_blob, null);
  EXPECT_EQ!(box_object:cql_unbox_object, null);
end);

-- unboxing validation: attempt to unbox nil
TEST!(unboxing_from_nil,
begin
  -- try to recover from nil, these should all fail
  -- we need a null object that is of the right type
  var _nil object<cql_box>;

  EXPECT_EQ!(_nil:to_bool, null);
  EXPECT_EQ!(_nil:to_int, null);
  EXPECT_EQ!(_nil:to_long, null);
  EXPECT_EQ!(_nil:to_real, null);
  EXPECT_EQ!(_nil:to_text, null);
  EXPECT_EQ!(_nil:to_blob, null);
  EXPECT_EQ!(_nil:to_object, null);
  EXPECT_EQ!(_nil:type, CQL_DATA_TYPE_NULL);
end);

TEST!(object_dictionary,
begin
  let d := cql_object_dictionary_create();
  d:add("foo", 101:box);
  let v := d:find("foo")~object<cql_box>~:ifnull_throw:to_int;
  EXPECT_EQ!(v, 101);
end);

-- Verify cursor field access for not nullables, by field number.
-- The verifications include:
-- 1. field count and types are correct
-- 2. field names are correct
-- 3. field values are correct
-- 4. out of bound indexes return null
-- 5. negative indexes return null
TEST!(cursor_accessors_notnull,
begin
  cursor C for select
    true a,
    1 b,
    2L c,
    3.0 d,
    "foo" e,
    "bar" ~blob~ f;
  fetch C;

  -- field count and types correct
  EXPECT_EQ!(6, C:count);
  EXPECT_EQ!(CQL_DATA_TYPE_BOOL | CQL_DATA_TYPE_NOT_NULL, C:type(0));
  EXPECT_EQ!(CQL_DATA_TYPE_INT32 | CQL_DATA_TYPE_NOT_NULL, C:type(1));
  EXPECT_EQ!(CQL_DATA_TYPE_INT64 | CQL_DATA_TYPE_NOT_NULL, C:type(2));
  EXPECT_EQ!(CQL_DATA_TYPE_DOUBLE | CQL_DATA_TYPE_NOT_NULL, C:type(3));
  EXPECT_EQ!(CQL_DATA_TYPE_STRING | CQL_DATA_TYPE_NOT_NULL, C:type(4));
  EXPECT_EQ!(CQL_DATA_TYPE_BLOB | CQL_DATA_TYPE_NOT_NULL, C:type(5));

  -- field names
  EXPECT_EQ!(C:name(-1), null);
  EXPECT_EQ!(C:name(0), "a");
  EXPECT_EQ!(C:name(1), "b");
  EXPECT_EQ!(C:name(2), "c");
  EXPECT_EQ!(C:name(3), "d");
  EXPECT_EQ!(C:name(4), "e");
  EXPECT_EQ!(C:name(5), "f");
  EXPECT_EQ!(C:name(6), null);

  -- expected values
  EXPECT_EQ!(-1, C:type(-1));
  EXPECT_EQ!(-1, C:type(C:count));
  EXPECT_EQ!(true, C:get_bool(0));
  EXPECT_EQ!(1, C:get_int(1));
  EXPECT_EQ!(2L, C:get_long(2));
  EXPECT_EQ!(3.0, C:get_real(3));
  EXPECT_EQ!("foo", C:get_text(4));
  EXPECT_NE!(C:get_blob(5), null);
end);

-- try reading out all the nullable types from a cursor, these are all
-- th eleagal fields except for object, handled without using SQL in
-- the next test case
TEST!(cursor_accessors_nullable,
begin
  cursor C for select
    true:nullable a,
    1:nullable b,
    2L:nullable c,
    3.0:nullable d,
    "foo":nullable e,
    "bar" ~blob~:nullable f;
  fetch C;

  EXPECT_EQ!(6, C:count);
  EXPECT_EQ!(CQL_DATA_TYPE_BOOL, C:type(0));
  EXPECT_EQ!(CQL_DATA_TYPE_INT32, C:type(1));
  EXPECT_EQ!(CQL_DATA_TYPE_INT64, C:type(2));
  EXPECT_EQ!(CQL_DATA_TYPE_DOUBLE, C:type(3));
  EXPECT_EQ!(CQL_DATA_TYPE_STRING, C:type(4));
  EXPECT_EQ!(CQL_DATA_TYPE_BLOB, C:type(5));

  EXPECT_EQ!(true, C:get_bool(0));
  EXPECT_EQ!(1, C:get_int(1));
  EXPECT_EQ!(2L, C:get_long(2));
  EXPECT_EQ!(3.0, C:get_real(3));
  EXPECT_EQ!("foo", C:get_text(4));
  EXPECT_NE!(C:get_blob(5), null);
end);

-- test reading object fields out of a cursor, we use a
-- boxed int as our test case
TEST!(cursor_accessors_object,
begin
  let v := 1:box;
  cursor C like (obj object<cql_box>);
  fetch C from values(v);
  EXPECT_NE!(C:get_object(0), null);
  EXPECT_EQ!(C:get_object(-1), null);
  EXPECT_EQ!(C:get_object(1), null);
end);

-- verify that we can cast anything to null
TEST!(null_casting,
begin
  let f1 := null ~bool~;
  let i1 := null ~int~;
  let l1 := null ~long~;
  let r1 := null ~real~;
  let t1 := null ~text~;
  let b1 := null ~blob~;
  let o1 := null ~object~;

  -- sanity check null initialization
  EXPECT_EQ!(f1, null);
  EXPECT_EQ!(i1, null);
  EXPECT_EQ!(l1, null);
  EXPECT_EQ!(r1, null);
  EXPECT_EQ!(t1, null);
  EXPECT_EQ!(b1, null);
  EXPECT_EQ!(o1, null);

  -- make everything not null again, this sets us up for the
  -- test we actually want to do
  f1 := true;
  i1 := 1;
  l1 := 1;
  r1 := 1;
  t1 := "dummy";
  b1 := randomblob(1);
  o1 := b1:box;

  -- we need the :nullable to avoid the warning that these are
  -- provably not null, we want to make sure that the compiler
  -- doesn't complain about the casts.
  EXPECT_NE!(f1 :nullable, null);
  EXPECT_NE!(i1 :nullable, null);
  EXPECT_NE!(l1 :nullable, null);
  EXPECT_NE!(r1 :nullable, null);
  EXPECT_NE!(t1 :nullable, null);
  EXPECT_NE!(b1 :nullable, null);
  EXPECT_NE!(o1 :nullable, null);

  -- casing only supported limited values, one is null
  -- the point of this is to verify that we can cast null to anything
  set f1 := null ~bool~;
  set i1 := null ~int~;
  set l1 := null ~long~;
  set r1 := null ~real~;
  set t1 := null ~text~;
  set b1 := null ~blob~;
  set o1 := null ~object~;

  EXPECT_EQ!(f1, null);
  EXPECT_EQ!(i1, null);
  EXPECT_EQ!(l1, null);
  EXPECT_EQ!(r1, null);
  EXPECT_EQ!(t1, null);
  EXPECT_EQ!(b1, null);
  EXPECT_EQ!(o1, null);
end);

-- autodrop test case, ensure we fetch using the result set helper
[[autodrop=(temp_table_one, temp_table_two, temp_table_three)]]
proc read_three_tables_and_autodrop()
begin
  init_temp_tables();

  select * from temp_table_one
  union all
  select * from temp_table_two
  union all
  select * from temp_table_three;
end;

TEST!(verify_autodrops,
begin
  -- note we do not use for CALL -- we want to materialize the result set
  -- autodrop happens after fetch results, in the bad old days there was
  -- no way to do this from inside CQL
  declare C cursor for read_three_tables_and_autodrop();
  declare D cursor for read_three_tables_and_autodrop();
  fetch C;
  fetch D;
  while C and D
  begin
    EXPECT_EQ!(C.id, D.id);
    fetch C;
    fetch D;
  end;
  EXPECT!(not C);
  EXPECT!(not D);
end);

proc make_json_backed_schema()
begin
  [[backing_table]]
  [[json]]
  create table json_backing(
    k blob primary key,
    v blob
  );
end;

[[backed_by=json_backing]]
create table my_data(
 id int! primary key,
 name text!,
 age int!
);

proc insert_data_into_json()
begin
  make_json_backed_schema();
  let i := 1;
  for i <= 15; i += 1;
  begin
    insert into my_data() values() @dummy_seed(i);
  end;

  update my_data set name = 'modified' where id = 5;
  delete from my_data where id = 11;
  update my_data set id = 1234 where id = 6;
end;

-- verify that we can cast anything to null
TEST_MODERN_ONLY!(verify_json_backing,
begin
  insert_data_into_json();

  cursor C for select @columns(like my_data) from my_data order by rowid;
  cursor D like my_data;

  let i := 0;
  loop fetch C
  begin
     i += 1;
     if i == 11 then i += 1; end; -- these were moved
     EXPECT_NE!(C.id, 11);  -- this was deleted
     fetch D() from values() @dummy_seed(i);

     -- adjust for expected updates
     if i == 5 then
       update cursor D using 'modified' name;
     else if i == 6 then
       update cursor D using 1234 id;
     end if;

     if not cql_cursors_equal(C, D) then
       printf("cursors differ at %s\n", C:diff_val(D));
       EXPECT!(cql_cursors_equal(C,D));
     end;
  end;
  EXPECT_EQ!(i, 15);
end);

TEST_MODERN_ONLY!(verify_backing_store,
begin
  cursor C for select k ~text~ k, v ~text~ v from json_backing order by rowid;
  let i := 0;
  loop fetch C
  begin
     i += 1;
     if i == 1 then
        let code := (select C.k ->> ~long~ 0);
     end;
     if i == 11 then i += 1; end;
     let name := case when i  == 5 then "modified" else printf("name_%d", i) end;
     let j := json_object('name', name, "age", i);
     EXPECT_EQ!(j, C.v);
     EXPECT_EQ!(code, (select C.k ->>  ~long~ 0));
     let x := case when i == 6 then 1234 else i end;
     let y := (select C.k ->>  ~long~ 1);
     EXPECT_NE!(y, 11);
     EXPECT_EQ!(x, y);
     -- printf("%d %s %s\n", i, C.k, C.v); for debugging
  end;
  -- we should be at the last row and done
  EXPECT_EQ!(i, 15);
end);


proc make_jsonb_backed_schema()
begin
  [[backing_table]]
  [[jsonb]]
  create table `a backing table`(
    `the key` blob primary key,
    `the value` blob
  );
end;

[[backed_by=`a backing table`]]
create table `a table`(
  `col 1` int primary key,
  `col 2` int
);

TEST_MODERN_ONLY!(verify_returning,
begin
  make_jsonb_backed_schema();

  cursor C for
  with data(a, b) as (values
    (1, 1),
    (2, 4),
    (3, 9),
    (4, 16)
  )
  insert into `a table`(`col 1`, `col 2`)
    select * from data
    returning *;

  let i := 0;
  loop fetch C
  begin
    i += 1;
    EXPECT_EQ!(C.`col 1` * C.`col 1`, C.`col 2`);
  end;
  EXPECT_EQ!(i, 4);

  cursor D for
    delete from `a table` where `col 1` in (2, 3)
    returning *;

  fetch D;
  EXPECT_EQ!(D.`col 1`, 2);
  EXPECT_EQ!(D.`col 2`, 4);
  fetch D;
  EXPECT_EQ!(D.`col 1`, 3);
  EXPECT_EQ!(D.`col 2`, 9);
  fetch D;
  EXPECT!(not D);

  cursor E for select * from `a table`;
  i := 0;
  loop fetch E
  begin
    i += 1;
    EXPECT_EQ!(E.`col 1` * E.`col 1`, E.`col 2`);
  end;
  EXPECT_EQ!(i, 2);

  cursor F for
    update `a table` set `col 2` = `col 1` * 1000
    where `col 1` = 4
    returning *;

  fetch F;
  EXPECT_EQ!(F.`col 1`, 4);
  EXPECT_EQ!(F.`col 2`, 4000);
  fetch F;
  EXPECT!(not F);

  -- force the excluded rewrite to work also
  cursor G for
    insert into `a table`(`col 1`, `col 2`) values (1, 1), (5, 25)
    on conflict(`col 1`)
    do update set `col 2` = 1000 where excluded.`col 1` <= 4
    returning *;

  fetch G;
  EXPECT_EQ!(G.`col 1`, 1);
  EXPECT_EQ!(G.`col 2`, 1000);

  fetch G;
  EXPECT_EQ!(G.`col 1`, 5);
  EXPECT_EQ!(G.`col 2`, 25);
  fetch G;
  EXPECT!(not G);
end);


proc make_qname_backed_schema()
begin
  [[backing_table]]
  create table `backing table 2`(
    `the key` blob primary key,
    `the value` blob
  );
end;

[[backed_by=`backing table 2`]]
create table `table 2`(
  `col 1` int primary key,
  `col 2` int
);

TEST!(verify_backed_qnames,
begin
  make_qname_backed_schema();

  with data(a, b) as (values
    (1, 1),
    (2, 4),
    (3, 9),
    (4, 16)
  )
  insert into `table 2`(`col 1`, `col 2`)
    select * from data;

  cursor C for select * from `table 2`;

  let i := 0;
  loop fetch C
  begin
    i += 1;
    EXPECT_EQ!(C.`col 1` * C.`col 1`, C.`col 2`);
  end;
  EXPECT_EQ!(i, 4);

    delete from `table 2` where `col 1` in (2, 3);

  cursor D for select * from `table 2`;

  fetch D;
  EXPECT_EQ!(D.`col 1`, 1);
  EXPECT_EQ!(D.`col 2`, 1);
  fetch D;
  EXPECT_EQ!(D.`col 1`, 4);
  EXPECT_EQ!(D.`col 2`, 16);
  fetch D;
  EXPECT!(not D);

  update `table 2` set `col 2` = `col 1` * 1000
  where `col 1` = 4;

  cursor F for select * from `table 2`;

  fetch F;
  EXPECT_EQ!(F.`col 1`, 1);
  EXPECT_EQ!(F.`col 2`, 1);
  fetch F;
  EXPECT_EQ!(F.`col 1`, 4);
  EXPECT_EQ!(F.`col 2`, 4000);
  fetch F;
  EXPECT!(not F);

  -- force the excluded rewrite to work also
  insert into `table 2`(`col 1`, `col 2`) values (1, 1), (4, 100), (3, 9), (3, 9), (3, 11), (5, 25)
  on conflict(`col 1`) where `col 2` != 9
  do update set `col 2` = excluded.`col 1`*123
  where excluded.`col 1` < 4;

  cursor G for select * from `table 2` order by `col 1`;

  fetch G;
  EXPECT_EQ!(G.`col 1`, 1);
  EXPECT_EQ!(G.`col 2`, 123);

  fetch G;
  EXPECT_EQ!(G.`col 1`, 3);
  EXPECT_EQ!(G.`col 2`, 3*123);

  fetch G;
  EXPECT_EQ!(G.`col 1`, 4);
  EXPECT_EQ!(G.`col 2`, 4000);

  fetch G;
  EXPECT_EQ!(G.`col 1`, 5);
  EXPECT_EQ!(G.`col 2`, 25);
  fetch G;

  EXPECT!(not G);
end);

TEST!(for_loop,
begin
  let t1 := 0;
  let i := 0;

  for i <= 5; i+= 1;
  begin
    t1 += i;
  end;

  EXPECT_EQ!(t1, 1+2+3+4+5);

  let j := nullable(0);
  let t2 := j;
  for j <= 6; j += 1;
  begin
    if j == 3 continue;
    if j == 5 leave;
    t2 += j;
  end;

  EXPECT_EQ!(t2, 1+2+4);

end);

[[blob_storage]]
create table my_blob
(
    x int,
    y int,
    z text
);

proc control_blob(out control blob!)
begin
  -- the hex for the test blob we use
  control :=
    (select x'05000000230000002E00000039000000440000004F000000696973000700007A5F3000696973000702027A5F3100696973000704047A5F3200696973000706067A5F3300696973000708087A5F3400');
end;

TEST!(make_blob_stream,
begin
  let builder := cql_blob_list_create();
  cursor C like my_blob;
  let i := 0;
  for i < 5; i := i + 1;
  begin
    fetch C() from values () @dummy_seed(i) @dummy_nullables;
    let b := cql_cursor_to_blob(C);
    cql_blob_list_add(builder, b);
  end;

  b := cql_make_blob_stream(builder);
  let control := control_blob();
  EXPECT_EQ!(hex(b), hex(control));

  let num := cql_blob_stream_count(b);
  EXPECT_EQ!(num, 5);

  i := 0;
  for i < num; i := i + 1;
  begin
    cql_cursor_from_blob_stream(C, b, i);
    EXPECT_EQ!(c.x, i);
    EXPECT_EQ!(c.y, i);
    EXPECT_EQ!(c.z, printf("z_%d", i));
  end;
end);

TEST!(blob_stream_fixed_blob,
begin
  -- We revalidate based on a fixed blob, the format must be invariant across all output types
  -- and versions.  E.g. the lua build must produce the same blob
  let b := control_blob();
  let num := cql_blob_stream_count(b);
  EXPECT_EQ!(num, 5);

  cursor C like my_blob;
  let i := 0;
  for i < num; i := i + 1;
  begin
    cql_cursor_from_blob_stream(C, b, i);
    EXPECT_EQ!(c.x, i);
    EXPECT_EQ!(c.y, i);
    EXPECT_EQ!(c.z, printf("z_%d", i));
  end;
end);

TEST!(blob_stream_empty,
begin
  let b := (select x'00');
  let hit := false;
  cursor C like my_blob;
  try
    cql_cursor_from_blob_stream(C, b, 0);
  catch
    hit := true;
  end;
  -- no row
  EXPECT_EQ!(hit, true);
  EXPECT_EQ!(c, false);
end);

TEST!(blob_stream_invalid_offsets__,
begin
  let b := (select x'05000000FF00000000000000');
  let hit := 0;
  cursor C like my_blob;
  try
    -- the offset of the first blob is too big
    cql_cursor_from_blob_stream(C, b, 0);
  catch
    hit := 1;
  end;
  EXPECT_EQ!(hit, 1);
  EXPECT_EQ!(C, false);

  hit := 0;
  try
    -- the start offset of the 2nd blob (index 0) is too big
    cql_cursor_from_blob_stream(C, b, 1);
  catch
    hit := 1;
  end;
  EXPECT_EQ!(hit, 1);
  EXPECT_EQ!(C, false);

  hit := 0;
  try
    -- the count claims to be 5 but there are not enough offsets
    cql_cursor_from_blob_stream(C, b, 3);
  catch
    hit := 1;
  end;
  EXPECT_EQ!(hit, 1);
  EXPECT_EQ!(C, false);

  -- invalid index
  hit := false;
  try
    cql_cursor_from_blob_stream(C, b, -1);
  catch
    hit := true;
  end;
  EXPECT_EQ!(hit, true);
  EXPECT_EQ!(C, false);
end);

END_SUITE();

-- manually force tracing on by redefining the macros
-- in Lua we have tracing on by default so we don't a separate test
-- there is trace output already
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

-- Called in the test client to verify that we hit tripwires when passing null
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

-- parent child test case, this code is exercised from run_test_client.c
-- Lua has no such test case at this time, though in fairness this test
-- is trivial for Lua because "everything in an object".  The code is
-- in an ifdef as a reminder that it is not a Lua test case.

@ifndef __rt__lua

-- make our schema and add a few dummy rows
proc TestParentChildInit()
begin
  create table test_rooms (
    roomID int! primary key,
    name text
  );

  -- fk is here just to make the relationship clear, it is not required
  -- to have a foreign key in the child table for the parent/child
  -- relationship to work in the test case.
  create table test_tasks(
   taskID int!,
   roomID int! references test_rooms(roomID)
  );

  insert into test_rooms values (1, "foo"), (2, "bar");
  insert into test_tasks values (100,1), (101,1), (200,2);
end;

[[private]]
proc TestParent()
begin
  select roomID, name from test_rooms order by name;
end;

proc TestChild()
begin
  select roomID, test_tasks.taskID as thisIsATask from test_tasks;
end;

-- create the parent/child result set using the sugar, this does a "manual" hash join
-- from the parent result set to the child result set and then makes the result
-- with a nested result set in it.
proc TestParentChild()
begin
  out union call TestParent() join call TestChild() using (roomID) as test_tasks;
end;

@endif
