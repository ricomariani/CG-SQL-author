/*
 * Copyright (c) Joris Garonian and Rico Mariani
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

declare proc printf no check;

@echo c, "extern const sqlite3_api_routines *sqlite3_api;\n";

-- trivial case fixed text output as a result set
proc hello_world()
begin
  select "Hello World!" as `the result`;
end;

-- multi-column result set, with pass through, one row
proc three_int_test(x int, y int, z int)
begin
  select x x, y y, z z;
end;

-- generated result set with a cursor
-- as many rows as you desire
proc many_rows(x int)
begin
  cursor C like (x int!, y int!, z text!);
  let i := 0;
  for i < x; i += 1;
  begin
    fetch C using i x, i*100 y, printf("text_%d", i) z;
    out union C;
  end;
end;

-- first of 3 tests that aim to ensure each arg type can be
-- verified and marshalled correctly.  We use 3 tests
-- because the max number of args is 16 if we are going to
-- use the select contract we are testing here.
proc comprehensive_test1(
  in in__bool__not_null bool!,
  in in__bool__nullable bool,
  in in__real__not_null real!,
  in in__real__nullable real,
  in in__integer__not_null integer!,
  in in__integer__nullable integer,
  in in__long__not_null long!,
  in in__long__nullable long,
  in in__text__not_null text!,
  in in__text__nullable text,
  in in__blob__not_null blob!,
  in in__blob__nullable blob
  -- in in__object__not_null object!
  -- in in__object__nullable object
)
begin
  select "hello1" as `result`;
end;

-- second of 3 tests that aim to ensure each arg type can be
-- verified and marshalled correctly. This one uses
-- inout args for the return type so they are passthrough
proc comprehensive_test2(
  inout inout__bool__not_null bool!,
  inout inout__bool__nullable bool,
  inout inout__real__not_null real!,
  inout inout__real__nullable real,
  inout inout__integer__not_null integer!,
  inout inout__integer__nullable integer,
  inout inout__long__not_null long!,
  inout inout__long__nullable long,
  inout inout__text__not_null text!,
  inout inout__text__nullable text,
  inout inout__blob__not_null blob!,
  inout inout__blob__nullable blob
  -- inout inout__object__not_null object!,
  -- inout inout__object__nullable object,
)
begin
  select "hello2" as `result`;
end;

-- third of 3 tests that aim to ensure each arg type can be
-- verified and marshalled correctly.  This one uses out args
-- to get the return type.
proc comprehensive_test3(
  out out__real__not_null real!,
  out out__real__nullable real,
  out out__bool__not_null bool!,
  out out__bool__nullable bool,
  out out__integer__not_null integer!,
  out out__integer__nullable integer,
  out out__long__not_null long!,
  out out__long__nullable long,
  out out__text__not_null text!,
  out out__text__nullable text,
  -- out out__object__not_null object!,
  -- out out__object__nullable object,
  out out__blob__not_null blob!,
  out out__blob__nullable blob
)
begin
  out__bool__not_null := TRUE;
  out__bool__nullable := TRUE;

  out__real__not_null := 3.5;
  out__real__nullable := 3.5;

  out__integer__not_null := 3;
  out__integer__nullable := 3;

  out__long__not_null := 3L;
  out__long__nullable := 3L;

  out__text__not_null := 'three';
  out__text__nullable := 'three';

  -- out__object__not_null := null ~object~;
  -- out__object__nullable := null ~object~;

  out__blob__not_null := (select CAST("blob" as blob));
  out__blob__nullable := (select CAST("blob" as blob));

  select "hello3" as `result`;
end;

proc result_from_result_set__no_args()
begin
  select "result_set" as `result`;
end;

proc result_from_result_set__with_in_out_inout(
  in in__text__not_null text!,
  inout inout__text__not_null text!,
  out out__text__not_null text!,
)
begin
  inout__text__not_null := "inout_argument";
  out__text__not_null := "out_argument";

  select "result_set" as `result`;
end;

-- verifies that the first inout or out argument is used
-- as the scalar return value
proc result_from_first_inout_or_out_argument__inout(
  in in__text__not_null text!,
  inout inout__text__not_null text!,
  out out__text__not_null text!,
  inout inout__text__not_null_bis text!,
  out out__text__not_null_bis text!,
)
begin
  inout__text__not_null := "inout_argument";
  out__text__not_null := "out_argument";
  inout__text__not_null_bis := "inout_argument";
  out__text__not_null_bis := "out_argument";
end;

-- verifies that the first inout or out argument is used
-- as the scalar return value
proc result_from_first_inout_or_out_argument__out(
  in in__text__not_null text!,
  out out__text__not_null text!,
  inout inout__text__not_null text!,
  out out__text__not_null_bis text!,
  inout inout__text__not_null_bis text!,
)
begin
  out__text__not_null := "out_argument";
  inout__text__not_null := "inout_argument";
  out__text__not_null_bis := "out_argument";
  inout__text__not_null_bis := "inout_argument";
end;

-- simple test that flows an inout text
proc result_from_inout(inout inout__x text!)
begin
  inout__x := "inout_argument";
end;

-- simple test case that fills an out text
proc result_from_out(out out__x text!)
begin
  out__x := "out_argument";
end;

-- return nothing, this will appear as function
-- that returns a nullable int and it's always null
-- it has to return something.
proc result_from_void__null__with_in(in in__x text!)
begin
  /* noop */
end;

-- return nothing, this will appear as function
-- that returns a nullable int and it's always null
-- it has to return something.
proc result_from_void__null__no_args()
begin
  /* noop */
end;

-- these all pass through their argument and return it in a result set
proc in__bool__not_null(in in__x bool!) begin SELECT in__x; end;
proc in__bool__nullable(in in__x bool) begin SELECT in__x; end;
proc in__real__not_null(in in__x real!) begin SELECT in__x; end;
proc in__real__nullable(in in__x real) begin SELECT in__x; end;
proc in__integer__not_null(in in__x integer!) begin SELECT in__x; end;
proc in__integer__nullable(in in__x integer) begin SELECT in__x; end;
proc in__long__not_null(in in__x long!) begin SELECT in__x; end;
proc in__long__nullable(in in__x long) begin SELECT in__x; end;
proc in__text__not_null(in in__x text!) begin SELECT in__x; end;
proc in__text__nullable(in in__x text) begin SELECT in__x; end;
proc in__blob__not_null(in in__x blob!) begin SELECT in__x; end;
proc in__blob__nullable(in in__x blob) begin SELECT in__x; end;
-- proc in__object__not_null(inout in__x integer!) begin SELECT in__x; end;
-- proc in__object__nullable(inout in__x integer) begin SELECT in__x; end;

-- these all leave their inout argument unchanged and it is their result
proc inout__bool__not_null(inout inout__x bool!) begin /* noop */ end;
proc inout__bool__nullable(inout inout__x bool) begin /* noop */ end;
proc inout__real__not_null(inout inout__x real!) begin /* noop */ end;
proc inout__real__nullable(inout inout__x real) begin /* noop */ end;
proc inout__integer__not_null(inout inout__x integer!) begin /* noop */ end;
proc inout__integer__nullable(inout inout__x integer) begin /* noop */ end;
proc inout__long__not_null(inout inout__x long!) begin /* noop */ end;
proc inout__long__nullable(inout inout__x long) begin /* noop */ end;
proc inout__text__not_null(inout inout__x text!) begin /* noop */ end;
proc inout__text__nullable(inout inout__x text) begin /* noop */ end;
proc inout__blob__not_null(inout inout__x blob!) begin /* noop */ end;
proc inout__blob__nullable(inout inout__x blob) begin /* noop */ end;
-- proc inout__object__not_null(inout inout__x integer!) begin /* noop */ end;
-- proc inout__object__nullable(inout inout__x integer) begin /* noop */ end;

-- these all return some constant value, it's null whenever it's allowed to be
proc out__bool__not_null(out out__x bool!) begin out__x := TRUE; end;
proc out__bool__nullable(out out__x bool) begin out__x := NULL; end;
proc out__real__not_null(out out__x real!) begin out__x := 3.14; end;
proc out__real__nullable(out out__x real) begin out__x := NULL; end;
proc out__integer__not_null(out out__x integer!) begin out__x := 1234; end;
proc out__integer__nullable(out out__x integer) begin out__x := NULL; end;
proc out__long__not_null(out out__x long!) begin out__x := 1234567890123456789; end;
proc out__long__nullable(out out__x long) begin out__x := NULL; end;
proc out__text__not_null(out out__x text!) begin out__x := "HW"; end;
proc out__text__nullable(out out__x text) begin out__x := NULL; end;
proc out__blob__not_null(out out__x blob!) begin out__x := (select CAST("blob" as blob)); end;
proc out__blob__nullable(out out__x blob) begin out__x := NULL; end;
-- proc out__object__not_null(out out__x integer!) begin out__x := 9876; end;
-- proc out__object__nullable(out out__x integer) begin out__x := NULL; end;

proc fib(n int!)
begin
  -- starting condition so that we get two 1s to start the sequence easily
  let a := 0;
  let b := 1;
  let i := 1;

  -- this is the shape of the output row we will create
  cursor result like (i int!, val int!);

  for n > 0; n -= 1; i += 1;
  begin
     -- emit 1 based index and the current fibonacci number
     fetch result using i as i, b as val;
     out union result;

     -- compute the next and shift it down
     let c := a + b;
     a := b;
     b := c;
  end;
end;

proc sql_stuff()
begin
  create table if not exists foo(x int, y int);
  delete from foo;
  insert into foo values (1,1), (2,4), (3, 9);
  select * from foo;
end;
