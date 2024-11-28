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

proc comprehensive_test(
  in in__bool__not_null bool not null,
  in in__bool__nullable bool,
  in in__real__not_null real not null,
  in in__real__nullable real,
  in in__integer__not_null integer not null,
  in in__integer__nullable integer,
  in in__long__not_null long not null,
  in in__long__nullable long,
  in in__text__not_null text not null,
  in in__text__nullable text,
  -- in in__object__not_null object not null,
  -- in in__object__nullable object,
  in in__blob__not_null blob not null,
  in in__blob__nullable blob,
  inout inout__bool__not_null bool not null,
  inout inout__bool__nullable bool,
  inout inout__real__not_null real not null,
  inout inout__real__nullable real,
  inout inout__integer__not_null integer not null,
  inout inout__integer__nullable integer,
  inout inout__long__not_null long not null,
  inout inout__long__nullable long,
  inout inout__text__not_null text not null,
  inout inout__text__nullable text,
  -- inout inout__object__not_null object not null,
  -- inout inout__object__nullable object,
  inout inout__blob__not_null blob not null,
  inout inout__blob__nullable blob,
  out out__real__not_null real not null,
  out out__real__nullable real,
  out out__bool__not_null bool not null,
  out out__bool__nullable bool,
  out out__integer__not_null integer not null,
  out out__integer__nullable integer,
  out out__long__not_null long not null,
  out out__long__nullable long,
  out out__text__not_null text not null,
  out out__text__nullable text,
  -- out out__object__not_null object not null,
  -- out out__object__nullable object,
  out out__blob__not_null blob not null,
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

  select "hello" as `result`;
end;

proc result_from_result_set__no_args()
begin
  select "result_set" as `result`;
end;

proc result_from_result_set__with_in_out_inout(
  in in__text__not_null text not null,
  inout inout__text__not_null text not null,
  out out__text__not_null text not null,
)
begin
  inout__text__not_null := "inout_argument";
  out__text__not_null := "out_argument";

  select "result_set" as `result`;
end;

proc result_from_first_inout_or_out_argument__inout(
  in in__text__not_null text not null,
  inout inout__text__not_null text not null,
  out out__text__not_null text not null,
  inout inout__text__not_null_bis text not null,
  out out__text__not_null_bis text not null,
)
begin
  inout__text__not_null := "inout_argument";
  out__text__not_null := "out_argument";
  inout__text__not_null_bis := "inout_argument";
  out__text__not_null_bis := "out_argument";
end;

proc result_from_first_inout_or_out_argument__out(
  in in__text__not_null text not null,
  out out__text__not_null text not null,
  inout inout__text__not_null text not null,
  out out__text__not_null_bis text not null,
  inout inout__text__not_null_bis text not null,
)
begin
  out__text__not_null := "out_argument";
  inout__text__not_null := "inout_argument";
  out__text__not_null_bis := "out_argument";
  inout__text__not_null_bis := "inout_argument";
end;

proc result_from_inout(inout inout__text__not_null text not null) begin inout__text__not_null := "inout_argument"; end;
proc result_from_out(out out__text__not_null text not null) begin out__text__not_null := "out_argument"; end;
proc result_from_void__null__with_in(in in__text__not_null text not null) begin /* noop */ end;
proc result_from_void__null__no_args() begin /* noop */ end;

proc in__bool__not_null(in in__x bool not null)          begin SELECT in__x; end;
proc in__bool__nullable(in in__x bool /*null*/)          begin SELECT in__x; end;
proc in__real__not_null(in in__x real not null)          begin SELECT in__x; end;
proc in__real__nullable(in in__x real /*null*/)          begin SELECT in__x; end;
proc in__integer__not_null(in in__x integer not null)    begin SELECT in__x; end;
proc in__integer__nullable(in in__x integer /*null*/)    begin SELECT in__x; end;
proc in__long__not_null(in in__x long not null)          begin SELECT in__x; end;
proc in__long__nullable(in in__x long /*null*/)          begin SELECT in__x; end;
proc in__text__not_null(in in__x text not null)          begin SELECT in__x; end;
proc in__text__nullable(in in__x text /*null*/)          begin SELECT in__x; end;
proc in__blob__not_null(in in__x blob not null)          begin SELECT in__x; end;
proc in__blob__nullable(in in__x blob /*null*/)          begin SELECT in__x; end;
-- proc in__object__not_null(inout in__x integer not null)  begin SELECT x; end;
-- proc in__object__nullable(inout in__x integer /*null*/)  begin SELECT x; end;

proc inout__bool__not_null(inout inout__x bool not null)       begin /* noop */ end;
proc inout__bool__nullable(inout inout__x bool /*null*/)       begin /* noop */ end;
proc inout__real__not_null(inout inout__x real not null)       begin /* noop */ end;
proc inout__real__nullable(inout inout__x real /*null*/)       begin /* noop */ end;
proc inout__integer__not_null(inout inout__x integer not null) begin /* noop */ end;
proc inout__integer__nullable(inout inout__x integer /*null*/) begin /* noop */ end;
proc inout__long__not_null(inout inout__x long not null)       begin /* noop */ end;
proc inout__long__nullable(inout inout__x long /*null*/)       begin /* noop */ end;
proc inout__text__not_null(inout inout__x text not null)       begin /* noop */ end;
proc inout__text__nullable(inout inout__x text /*null*/)       begin /* noop */ end;
proc inout__blob__not_null(inout inout__x blob not null)       begin /* noop */ end;
proc inout__blob__nullable(inout inout__x blob /*null*/)       begin /* noop */ end;
-- proc inout__object__not_null(inout inout__x integer not null)  begin /* noop */ end;
-- proc inout__object__nullable(inout inout__x integer /*null*/)  begin /* noop */ end;

proc out__bool__not_null(out out__x bool not null)       begin out__x := TRUE; end;
proc out__bool__nullable(out out__x bool /*null*/)       begin out__x := NULL; end;
proc out__real__not_null(out out__x real not null)       begin out__x := 3.14; end;
proc out__real__nullable(out out__x real /*null*/)       begin out__x := NULL; end;
proc out__integer__not_null(out out__x integer not null) begin out__x := 1234; end;
proc out__integer__nullable(out out__x integer /*null*/) begin out__x := NULL; end;
proc out__long__not_null(out out__x long not null)       begin out__x := 1234567890123456789; end;
proc out__long__nullable(out out__x long /*null*/)       begin out__x := NULL; end;
proc out__text__not_null(out out__x text not null)       begin out__x := "HW"; end;
proc out__text__nullable(out out__x text /*null*/)       begin out__x := NULL; end;
proc out__blob__not_null(out out__x blob not null)       begin set out__x := (select CAST("blob" as blob)); end;
proc out__blob__nullable(out out__x blob /*null*/)       begin out__x := NULL; end;
-- proc out__object__not_null(out out__x integer not null)  begin out__x := 1 end;
-- proc out__object__nullable(out out__x integer /*null*/)  begin out__x := NULL end;
