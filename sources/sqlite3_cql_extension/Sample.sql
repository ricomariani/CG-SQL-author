/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

declare proc printf no check;

proc hello_world()
begin
  select "Hello World !" as result;
end;

proc three_int_test(x int, y int, z int)
begin
  select x x, y y, z z;
end;

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

proc result_from_inout(inout inout__x text!) begin
  inout__x := "inout_argument";
end;

proc result_from_out(out out__x text!) begin
  out__x := "out_argument";
end;

proc result_from_void__null__with_in(in in__x text!) begin
  /* noop */
end;

proc result_from_void__null__no_args() begin
  /* noop */
end;

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
